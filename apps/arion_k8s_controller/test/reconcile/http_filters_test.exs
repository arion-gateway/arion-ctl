# Copyright 2026 The arion-gateway Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Arion.K8sController.Reconcile.HttpFiltersTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.{Fixtures, Ir}

  defp entry(rule) do
    %Ir.Attachment{
      namespace: "default",
      name: "app",
      creation_ts: "2026-01-01T00:00:00Z",
      domains: ["app.example.com"],
      rules: [rule]
    }
  end

  defp rule(filters, opts \\ []) do
    %Ir.Rule{
      matches: [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
      filters: filters,
      backends: Keyword.get(opts, :backends, []),
      timeouts: %{},
      retry: Keyword.get(opts, :retry)
    }
  end

  defp only_route(rule, listener \\ {"http", 80}) do
    Fixtures.route_config([entry(rule)], listener).virtual_hosts
    |> hd()
    |> Map.get(:routes)
    |> hd()
  end

  defp redirect(fields, listener \\ {"http", 80}) do
    {:redirect, redirect} = only_route(rule([{:request_redirect, fields}]), listener).action
    redirect
  end

  test "RequestRedirect becomes a redirect action" do
    filters = [{:request_redirect, %{"scheme" => "https", "statusCode" => 301}}]
    route = only_route(rule(filters))
    assert {:redirect, redirect} = route.action
    assert redirect.scheme_rewrite_specifier == {:scheme_redirect, "https"}
    assert redirect.response_code == :MOVED_PERMANENTLY
  end

  test "a hostname redirect keeps the listener's scheme" do
    redirect = redirect(%{"hostname" => "example.org"})
    assert redirect.scheme_rewrite_specifier == {:scheme_redirect, "http"}
    assert redirect.host_redirect == "example.org"
    assert redirect.port_redirect == 0
    assert redirect.response_code == :FOUND

    redirect = redirect(%{"hostname" => "example.org", "statusCode" => 301}, {"https", 443})
    assert redirect.scheme_rewrite_specifier == {:scheme_redirect, "https"}
    assert redirect.port_redirect == 0
    assert redirect.response_code == :MOVED_PERMANENTLY
  end

  test "a redirect without hostname or scheme stays relative" do
    redirect = redirect(%{"path" => %{"type" => "ReplaceFullPath", "replaceFullPath" => "/new"}})
    assert redirect.scheme_rewrite_specifier == {:https_redirect, false}
    assert redirect.host_redirect == ""
    assert redirect.port_redirect == 0
    assert redirect.path_rewrite_specifier == {:path_redirect, "/new"}
  end

  test "an empty scheme redirects to a non-default listener port" do
    listener = {"http", 8080}
    host = %{"hostname" => "example.org"}
    path = %{"type" => "ReplaceFullPath", "replaceFullPath" => "/new"}

    assert redirect(host, listener).port_redirect == 8080
    assert redirect(Map.put(host, "scheme", "https"), listener).port_redirect == 0
    assert redirect(Map.put(host, "port", 8443), listener).port_redirect == 8443
    assert redirect(%{"path" => path}, listener).port_redirect == 0
  end

  test "statusCode maps to the redirect response code and defaults to 302" do
    for {code, response_code} <- [
          {301, :MOVED_PERMANENTLY},
          {302, :FOUND},
          {303, :SEE_OTHER},
          {307, :TEMPORARY_REDIRECT},
          {308, :PERMANENT_REDIRECT},
          {nil, :FOUND}
        ] do
      assert redirect(%{"statusCode" => code}).response_code == response_code
    end
  end

  test "URLRewrite ReplacePrefixMatch sets prefix_rewrite on the route action" do
    path = %{"type" => "ReplacePrefixMatch", "replacePrefixMatch" => "/v2"}
    filters = [{:url_rewrite, %{"path" => path}}]

    backend = %Ir.Backend{
      cluster_name: "c1",
      port: 80,
      weight: 1,
      resolved?: true
    }

    route = only_route(rule(filters, backends: [backend]))

    assert {:route, action} = route.action
    assert action.cluster_specifier == {:cluster, "c1"}
    assert action.prefix_rewrite == "/v2"
  end

  test "filters on a single backendRef fold into route-level header mutations" do
    backend_filters = [
      {:request_header_modifier,
       %{"set" => [%{"name" => "X-Backend", "value" => "one"}], "remove" => ["X-Drop"]}},
      {:response_header_modifier, %{"add" => [%{"name" => "X-Resp", "value" => "two"}]}}
    ]

    backend = %Ir.Backend{
      cluster_name: "c1",
      port: 80,
      weight: 1,
      resolved?: true,
      filters: backend_filters
    }

    rule_filter =
      {:request_header_modifier, %{"set" => [%{"name" => "X-Rule", "value" => "first"}]}}

    route = only_route(rule([rule_filter], backends: [backend]))

    assert {:route, _action} = route.action
    assert [rule_set, backend_set] = route.request_headers_to_add
    assert rule_set.header.key == "X-Rule"
    assert backend_set.header.key == "X-Backend"
    assert backend_set.append_action == :OVERWRITE_IF_EXISTS_OR_ADD
    assert route.request_headers_to_remove == ["X-Drop"]
    assert [resp] = route.response_headers_to_add
    assert resp.header.key == "X-Resp"
    assert resp.append_action == :APPEND_IF_EXISTS_OR_ADD
  end

  test "backendRef filters on a weighted rule are not folded" do
    filters = [
      {:request_header_modifier, %{"set" => [%{"name" => "X-Backend", "value" => "one"}]}}
    ]

    backends = [
      %Ir.Backend{cluster_name: "c1", port: 80, weight: 1, resolved?: true, filters: filters},
      %Ir.Backend{cluster_name: "c2", port: 80, weight: 1, resolved?: true}
    ]

    route = only_route(rule([], backends: backends))

    assert {:route, action} = route.action
    assert {:weighted_clusters, _} = action.cluster_specifier
    assert route.request_headers_to_add == []
  end

  test "backendRef filters on a redirect rule are ignored" do
    filters = [
      {:request_header_modifier, %{"set" => [%{"name" => "X-Backend", "value" => "one"}]}}
    ]

    backend = %Ir.Backend{
      cluster_name: "c1",
      port: 80,
      weight: 1,
      resolved?: true,
      filters: filters
    }

    route = only_route(rule([{:request_redirect, %{"scheme" => "https"}}], backends: [backend]))

    assert {:redirect, _} = route.action
    assert route.request_headers_to_add == []
  end

  test "a CORS filter becomes a per-route cors policy override" do
    filter =
      {:cors,
       %{
         "allowOrigins" => ["https://www.foo.com", "https://*.bar.com", "*"],
         "allowMethods" => ["GET", "OPTIONS"],
         "allowHeaders" => ["x-header-1"],
         "exposeHeaders" => ["x-header-2"],
         "allowCredentials" => true,
         "maxAge" => 3600
       }}

    route = only_route(rule([filter]))

    assert %{"envoy.filters.http.cors" => any} = route.typed_per_filter_config
    assert any.type_url == "type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy"

    policy = Arion.ControlPlane.Pb.Data.Extensions.CorsPolicy.decode(any.value)
    assert [exact, wildcard, star] = policy.allow_origin_string_match
    assert exact.match_pattern == {:exact, "https://www.foo.com"}
    assert {:safe_regex, %{regex: "https://.*\\.bar\\.com"}} = wildcard.match_pattern
    assert star.match_pattern == {:exact, "*"}
    assert policy.allow_methods == "GET,OPTIONS"
    assert policy.allow_headers == "x-header-1"
    assert policy.expose_headers == "x-header-2"
    assert policy.max_age == "3600"
    assert policy.allow_credentials == %Google.Protobuf.BoolValue{value: true}
    assert policy.forward_not_matching_preflights == %Google.Protobuf.BoolValue{value: false}
  end

  test "CORS maxAge defaults to 5 and credentials false is omitted" do
    filter = {:cors, %{"allowOrigins" => ["*"], "allowCredentials" => false}}

    route = only_route(rule([filter]))
    %{"envoy.filters.http.cors" => any} = route.typed_per_filter_config
    policy = Arion.ControlPlane.Pb.Data.Extensions.CorsPolicy.decode(any.value)

    assert policy.max_age == "5"
    assert policy.allow_credentials == nil
  end

  test "every accepted filter resolves to a tagged value and translates" do
    set = fn name -> %{"set" => [%{"name" => name, "value" => "1"}]} end

    filters = [
      %{"type" => "RequestHeaderModifier", "requestHeaderModifier" => set.("X-Req")},
      %{"type" => "ResponseHeaderModifier", "responseHeaderModifier" => set.("X-Resp")},
      %{
        "type" => "URLRewrite",
        "urlRewrite" => %{"path" => %{"type" => "ReplaceFullPath", "replaceFullPath" => "/new"}}
      },
      %{"type" => "CORS", "cors" => %{"allowOrigins" => ["*"]}}
    ]

    backend_filter = %{
      "type" => "ResponseHeaderModifier",
      "responseHeaderModifier" => set.("X-B")
    }

    rules = [
      %{
        "backendRefs" => [%{"name" => "app-svc", "port" => 8080, "filters" => [backend_filter]}],
        "filters" => filters
      },
      %{
        "filters" => [
          %{"type" => "RequestRedirect", "requestRedirect" => %{"hostname" => "example.org"}}
        ]
      }
    ]

    %{gateways: [%{listeners: [listener]}], routes: [resolved]} =
      [
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route(rules: rules)
      ]
      |> Fixtures.snapshot()
      |> Arion.K8sController.Reconcile.Resolver.resolve(Fixtures.controller_name())

    assert resolved.unsupported == nil
    [forward, redirect] = resolved.rules

    assert Enum.map(forward.filters, &elem(&1, 0)) ==
             ~w(request_header_modifier response_header_modifier url_rewrite cors)a

    assert [{:response_header_modifier, _}] = hd(forward.backends).filters
    assert [{:request_redirect, _}] = redirect.filters

    [vhost] = Fixtures.route_config(listener.attached_routes).virtual_hosts
    [forwarded, redirected] = vhost.routes
    assert [%{header: %{key: "X-Req"}}] = forwarded.request_headers_to_add
    assert ["X-Resp", "X-B"] = Enum.map(forwarded.response_headers_to_add, & &1.header.key)
    assert {:route, %{regex_rewrite: %{substitution: "/new"}}} = forwarded.action
    assert Map.has_key?(forwarded.typed_per_filter_config, "envoy.filters.http.cors")
    assert {:redirect, %{host_redirect: "example.org"}} = redirected.action
  end

  test "retry maps to a retry policy on the route action" do
    backend = %Ir.Backend{
      cluster_name: "c1",
      port: 80,
      weight: 1,
      resolved?: true
    }

    route = only_route(rule([], backends: [backend], retry: %{"attempts" => 5, "codes" => [503]}))

    assert {:route, action} = route.action
    assert action.retry_policy.num_retries.value == 5
    assert action.retry_policy.retriable_status_codes == [503]
  end
end
