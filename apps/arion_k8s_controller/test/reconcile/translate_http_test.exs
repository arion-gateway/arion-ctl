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

defmodule Arion.K8sController.Reconcile.Translate.HttpTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.{Fixtures, Ir}
  alias Arion.K8sController.Reconcile.Translate.Http

  defp entry(rules, opts \\ []) do
    %Ir.Attachment{
      namespace: "default",
      name: Keyword.get(opts, :name, "app"),
      creation_ts: Keyword.get(opts, :creation_ts, "2026-01-01T00:00:00Z"),
      domains: Keyword.get(opts, :domains, ["app.example.com"]),
      rules: rules
    }
  end

  defp backend(name, weight \\ 1) do
    %Ir.Backend{
      cluster_name: name,
      port: 80,
      weight: weight,
      resolved?: true
    }
  end

  defp rule(match, opts \\ []) do
    %Ir.Rule{
      matches: [match],
      filters: Keyword.get(opts, :filters, []),
      backends: Keyword.get(opts, :backends, [backend("c1")]),
      timeouts: Keyword.get(opts, :timeouts, %{}),
      retry: Keyword.get(opts, :retry)
    }
  end

  defp invalid_backend(name, weight \\ 1), do: %{backend(name, weight) | resolved?: false}

  defp route_config(entries), do: Fixtures.route_config(entries)

  defp only_route(rule) do
    route_config([entry([rule])]).virtual_hosts |> hd() |> Map.get(:routes) |> hd()
  end

  defp root_rule(opts), do: rule(%{"path" => %{"type" => "PathPrefix", "value" => "/"}}, opts)

  defp route_action(opts) do
    {:route, action} = only_route(root_rule(opts)).action
    action
  end

  defp ms(ms),
    do: %Google.Protobuf.Duration{seconds: div(ms, 1000), nanos: rem(ms, 1000) * 1_000_000}

  test "one VirtualHost per hostname, carrying the route's domains" do
    rc =
      route_config([
        entry([rule(%{"path" => %{"type" => "PathPrefix", "value" => "/"}})])
      ])

    assert [vh] = rc.virtual_hosts
    assert vh.domains == ["app.example.com"]
    assert [route] = vh.routes
    assert {:prefix, "/"} = route.match.path_specifier
  end

  test "without routes or matching hostnames, every request gets 404" do
    for entries <- [[], [entry([root_rule([])], domains: [])]] do
      assert [vh] = route_config(entries).virtual_hosts
      assert vh.domains == ["*"]
      assert [%{match: %{path_specifier: {:prefix, "/"}}} = route] = vh.routes
      assert {:direct_response, %{status: 404}} = route.action
    end
  end

  test "routes are ordered by precedence (exact before prefix)" do
    prefix = rule(%{"path" => %{"type" => "PathPrefix", "value" => "/"}})
    exact = rule(%{"path" => %{"type" => "Exact", "value" => "/health"}})

    rc = route_config([entry([prefix, exact])])
    [vh] = rc.virtual_hosts

    assert [%{path_specifier: {:path, "/health"}}, %{path_specifier: {:prefix, "/"}}] =
             Enum.map(vh.routes, & &1.match)
  end

  test "non-root PathPrefix uses path separated prefix semantics" do
    r = rule(%{"path" => %{"type" => "PathPrefix", "value" => "/v2"}})
    rc = route_config([entry([r])])
    [vh] = rc.virtual_hosts
    [route] = vh.routes

    assert {:path_separated_prefix, "/v2"} = route.match.path_specifier
  end

  test "a PathPrefix trailing slash is dropped" do
    r = rule(%{"path" => %{"type" => "PathPrefix", "value" => "/match/prefix/"}})

    assert {:path_separated_prefix, "/match/prefix"} = only_route(r).match.path_specifier
  end

  test "weighted backends become weighted clusters" do
    r =
      rule(%{"path" => %{"type" => "PathPrefix", "value" => "/"}},
        backends: [backend("a", 80), backend("b", 20)]
      )

    rc = route_config([entry([r])])
    [vh] = rc.virtual_hosts
    [route] = vh.routes

    assert {:route, action} = route.action
    assert {:weighted_clusters, wc} = action.cluster_specifier
    assert Enum.map(wc.clusters, &{&1.name, &1.weight.value}) == [{"a", 80}, {"b", 20}]
  end

  test "RequestHeaderModifier set becomes a request header override" do
    filters = [{:request_header_modifier, %{"set" => [%{"name" => "x-env", "value" => "prod"}]}}]

    r = rule(%{"path" => %{"type" => "PathPrefix", "value" => "/"}}, filters: filters)
    rc = route_config([entry([r])])
    [vh] = rc.virtual_hosts
    [route] = vh.routes

    assert [%{header: %{key: "x-env", value: "prod"}, append_action: :OVERWRITE_IF_EXISTS_OR_ADD}] =
             route.request_headers_to_add
  end

  test "request timeout is applied to the route action" do
    r =
      rule(%{"path" => %{"type" => "PathPrefix", "value" => "/"}},
        timeouts: %{"request" => "30s"}
      )

    rc = route_config([entry([r])])
    [vh] = rc.virtual_hosts
    [route] = vh.routes

    assert {:route, action} = route.action
    assert action.timeout.seconds == 30
  end

  test "GEP-2257 durations parse to milliseconds" do
    assert Http.parse_duration_ms("500ms") == 500
    assert Http.parse_duration_ms("1h") == 3_600_000
    assert Http.parse_duration_ms("1m30s") == 90_000
    assert Http.parse_duration_ms("30s1h500ms") == 3_630_500
    assert Http.parse_duration_ms("1s1s") == 2_000
    assert Http.parse_duration_ms("0s") == 0

    for invalid <- ["0", "1.5s", "1d", "-1s", "100000s", "1h1m1s1ms1h", "", nil] do
      assert Http.parse_duration_ms(invalid) == nil
    end
  end

  test "request timeout keeps sub-second and compound values, and 0s disables it" do
    assert route_action(timeouts: %{"request" => "500ms"}).timeout == ms(500)
    assert route_action(timeouts: %{"request" => "1m30s"}).timeout == ms(90_000)
    assert route_action(timeouts: %{"request" => "0s"}).timeout == ms(0)
    assert route_action(timeouts: %{"request" => "1d"}).timeout == route_action([]).timeout
  end

  test "without a retry, backendRequest bounds the route timeout" do
    assert route_action(timeouts: %{"backendRequest" => "500ms"}).timeout == ms(500)

    assert route_action(timeouts: %{"request" => "10s", "backendRequest" => "500ms"}).timeout ==
             ms(500)

    assert route_action(timeouts: %{"request" => "0s", "backendRequest" => "500ms"}).timeout ==
             ms(500)

    assert route_action(timeouts: %{"request" => "1s", "backendRequest" => "2s"}).timeout ==
             ms(1000)

    assert route_action(timeouts: %{"request" => "10s", "backendRequest" => "0s"}).timeout ==
             ms(10_000)

    assert route_action(timeouts: %{"backendRequest" => "500ms"}).retry_policy == nil
  end

  test "with a retry, backendRequest is the per-try timeout" do
    retry = %{"attempts" => 2, "codes" => [503]}

    action =
      route_action(timeouts: %{"request" => "10s", "backendRequest" => "500ms"}, retry: retry)

    assert action.timeout == ms(10_000)
    assert action.retry_policy.per_try_timeout == ms(500)

    action = route_action(timeouts: %{"backendRequest" => "0s"}, retry: retry)
    assert action.retry_policy.per_try_timeout == nil
  end

  test "retry backoff is the base interval with no per-try timeout or max interval" do
    policy = route_action(retry: %{"codes" => [503], "backoff" => "500ms"}).retry_policy

    assert policy.per_try_timeout == nil
    assert policy.retry_back_off.base_interval == ms(500)
    assert policy.retry_back_off.max_interval == nil

    assert route_action(retry: %{"backoff" => "30s"}).retry_policy.retry_back_off.base_interval ==
             ms(30_000)

    assert route_action(retry: %{"backoff" => "0s"}).retry_policy.retry_back_off.base_interval ==
             ms(1000)
  end

  test "timeouts, retries and rewrites keep a direct response or redirect action" do
    rewrite =
      {:url_rewrite,
       %{"path" => %{"type" => "ReplacePrefixMatch", "replacePrefixMatch" => "/v2"}}}

    redirect = {:request_redirect, %{"scheme" => "https"}}
    opts = [timeouts: %{"request" => "1s"}, retry: %{"attempts" => 2}]

    direct = root_rule([backends: [invalid_backend("x")], filters: [rewrite]] ++ opts)
    assert {:direct_response, %{status: 500}} = only_route(direct).action

    assert {:redirect, _} = only_route(root_rule([filters: [redirect]] ++ opts)).action
  end

  test "zero-weight backends get no weighted cluster entry" do
    action = route_action(backends: [backend("a", 70), backend("b", 30), backend("c", 0)])

    assert {:weighted_clusters, wc} = action.cluster_specifier
    assert Enum.map(wc.clusters, &{&1.name, &1.weight.value}) == [{"a", 70}, {"b", 30}]

    assert route_action(backends: [backend("a", 1), backend("b", 0)]).cluster_specifier ==
             {:cluster, "a"}
  end

  test "unresolved backends keep their share on a cluster that returns 500" do
    backends = [backend("a", 50), invalid_backend("x", 30), invalid_backend("y", 20)]
    action = route_action(backends: backends)

    assert {:weighted_clusters, wc} = action.cluster_specifier

    assert Enum.map(wc.clusters, &{&1.name, &1.weight.value}) ==
             [{"a", 50}, {"arion.invalid-backend", 50}]

    assert action.cluster_not_found_response_code == :INTERNAL_SERVER_ERROR
  end

  test "rules without a resolved, weighted backend return 500 directly" do
    for backends <- [[], [invalid_backend("x")], [backend("a", 0), invalid_backend("x")]] do
      assert {:direct_response, %{status: 500}} = only_route(root_rule(backends: backends)).action
    end
  end
end
