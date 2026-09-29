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

defmodule Arion.K8sController.Reconcile.BackendResolutionTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Reconcile.Resolver

  defp resolve(objects),
    do: objects |> Fixtures.snapshot() |> Resolver.resolve(Fixtures.controller_name())

  defp backend(graph) do
    graph.routes |> hd() |> Map.get(:rules) |> hd() |> Map.get(:backends) |> hd()
  end

  defp parent_reason(graph) do
    graph.routes |> hd() |> Map.get(:parents) |> hd() |> Map.get(:resolved_reason)
  end

  test "same-namespace backend resolves when the Service exists" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route()
      ])

    assert backend(graph).resolved?
  end

  test "cross-namespace backend without a ReferenceGrant is denied" do
    route =
      Fixtures.http_route(
        rules: [
          %{
            "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
            "backendRefs" => [%{"name" => "api", "namespace" => "backends", "port" => 9000}]
          }
        ]
      )

    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "api", namespace: "backends", port: 9000),
        route
      ])

    refute backend(graph).resolved?
    assert backend(graph).reason == :ref_not_permitted
    assert parent_reason(graph) == "RefNotPermitted"
  end

  test "cross-namespace backend is allowed with a matching ReferenceGrant" do
    route =
      Fixtures.http_route(
        rules: [
          %{
            "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
            "backendRefs" => [%{"name" => "api", "namespace" => "backends", "port" => 9000}]
          }
        ]
      )

    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "api", namespace: "backends", port: 9000),
        Fixtures.reference_grant(namespace: "backends", from_namespace: "default"),
        route
      ])

    assert backend(graph).resolved?
  end

  test "a ReferenceGrant naming a Service permits only that Service" do
    rule = fn path, name ->
      %{
        "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => path}}],
        "backendRefs" => [%{"name" => name, "namespace" => "backends", "port" => 8080}]
      }
    end

    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-backend-v1", namespace: "backends"),
        Fixtures.service(name: "app-backend-v2", namespace: "backends"),
        Fixtures.reference_grant(
          to: [%{"group" => "", "kind" => "Service", "name" => "app-backend-v1"}]
        ),
        Fixtures.http_route(rules: [rule.("/v2", "app-backend-v2"), rule.("/", "app-backend-v1")])
      ])

    [v2, v1] = graph.routes |> hd() |> Map.get(:rules) |> Enum.flat_map(& &1.backends)
    assert v1.resolved?
    assert {v2.resolved?, v2.reason} == {false, :ref_not_permitted}
    assert parent_reason(graph) == "RefNotPermitted"
  end

  test "a ReferenceGrant must name the referring kind and the Gateway API group" do
    route =
      Fixtures.http_route(
        rules: [
          %{"backendRefs" => [%{"name" => "api", "namespace" => "backends", "port" => 9000}]}
        ]
      )

    for grant <- [
          Fixtures.reference_grant(from_kind: "Gateway"),
          Fixtures.reference_grant(from_kind: nil),
          Fixtures.reference_grant(from_group: nil)
        ] do
      graph =
        resolve([
          Fixtures.gateway_class(),
          Fixtures.gateway(),
          Fixtures.service(name: "api", namespace: "backends", port: 9000),
          grant,
          route
        ])

      assert backend(graph).reason == :ref_not_permitted
    end
  end

  test "a ReferenceGrant naming an InferencePool permits only that pool" do
    to = &[%{"group" => "inference.networking.k8s.io", "kind" => "InferencePool", "name" => &1}]

    resolve_with = fn grant ->
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "llm-epp", namespace: "backends", port: 9002),
        Fixtures.inference_pool(namespace: "backends"),
        Fixtures.inference_http_route(pool_namespace: "backends"),
        grant
      ])
    end

    assert backend(resolve_with.(Fixtures.reference_grant(to: to.("llm-pool")))).resolved?

    graph = resolve_with.(Fixtures.reference_grant(to: to.("other-pool")))
    assert backend(graph).reason == :ref_not_permitted
    assert parent_reason(graph) == "RefNotPermitted"
  end

  test "InferencePool backend is unresolved when the pool is missing" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.inference_http_route()
      ])

    refute backend(graph).resolved?
    assert backend(graph).inference?
    assert backend(graph).reason == :pool_not_found
    assert parent_reason(graph) == "BackendNotFound"
  end

  test "InferencePool backend is unresolved when the endpoint picker Service is missing" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.inference_pool(),
        Fixtures.inference_http_route()
      ])

    refute backend(graph).resolved?
    assert backend(graph).inference?
    assert backend(graph).reason == :epp_not_found
    assert parent_reason(graph) == "BackendNotFound"
  end

  test "InferencePool endpoint picker port object resolves and backendRef port is ignored" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "llm-epp", port: 9002),
        Fixtures.inference_pool(target_ports: [%{"number" => 3000}]),
        Fixtures.inference_http_route(pool_port: 8888),
        Fixtures.pod()
      ])

    assert backend(graph).resolved?
    assert backend(graph).endpoints == [{"10.1.0.1", 3000}]
    assert backend(graph).epp.port == 9002
  end

  test "a Service port appProtocol of kubernetes.io/h2c makes the backend HTTP/2" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(
          name: "app-svc",
          ports: [%{"port" => 8080, "appProtocol" => "kubernetes.io/h2c"}]
        ),
        Fixtures.http_route()
      ])

    assert backend(graph).protocol == :http2
    assert backend(graph).cluster_name == "svc:default/app-svc:8080/h2"
  end

  test "a Service port without appProtocol stays HTTP/1.1" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route()
      ])

    assert backend(graph).protocol == :http1
    assert backend(graph).cluster_name == "svc:default/app-svc:8080"
  end

  test "a backendRef port the Service does not expose is BackendNotFound" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc", port: 9090),
        Fixtures.endpoint_slice(ports: [%{"name" => "", "port" => 9090}]),
        Fixtures.http_route()
      ])

    assert %{resolved?: false, reason: :port_not_found, cluster_name: nil, endpoints: []} =
             backend(graph)

    assert parent_reason(graph) == "BackendNotFound"
  end

  test "a backendRef port that is only UDP on the Service is UnsupportedProtocol" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc", ports: [%{"port" => 8080, "protocol" => "UDP"}]),
        Fixtures.http_route()
      ])

    assert %{resolved?: false, reason: :unsupported_port_protocol} = backend(graph)
    assert parent_reason(graph) == "UnsupportedProtocol"
  end

  test "a valid port without ready endpoints resolves to an empty backend" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.endpoint_slice(endpoints: [Fixtures.endpoint("10.0.0.1", false)]),
        Fixtures.http_route()
      ])

    assert %{resolved?: true, reason: nil, endpoints: []} = backend(graph)
    assert parent_reason(graph) == "ResolvedRefs"
  end

  test "backendRef filters are kept on the resolved backend" do
    filters = [
      %{
        "type" => "RequestHeaderModifier",
        "requestHeaderModifier" => %{"set" => [%{"name" => "X-Backend", "value" => "one"}]}
      }
    ]

    route =
      Fixtures.http_route(
        rules: [
          %{
            "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
            "backendRefs" => [%{"name" => "app-svc", "port" => 8080, "filters" => filters}]
          }
        ]
      )

    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        route
      ])

    assert [{:request_header_modifier, %{"set" => [%{"name" => "X-Backend"}]}}] =
             backend(graph).filters
  end

  defp first_parent(graph) do
    graph.routes |> hd() |> Map.get(:parents) |> hd()
  end

  defp attached_entries(graph) do
    graph.gateways |> hd() |> Map.get(:listeners) |> hd() |> Map.get(:attached_routes)
  end

  test "a RequestMirror filter rejects the route with UnsupportedValue" do
    route =
      Fixtures.http_route(
        rules: [
          %{
            "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
            "backendRefs" => [%{"name" => "app-svc", "port" => 8080}],
            "filters" => [
              %{
                "type" => "RequestMirror",
                "requestMirror" => %{"backendRef" => %{"name" => "mirror-svc", "port" => 8080}}
              }
            ]
          }
        ]
      )

    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        route
      ])

    parent = first_parent(graph)
    refute parent.accepted?
    assert parent.accepted_reason == "UnsupportedValue"
    assert attached_entries(graph) == []
    assert hd(graph.routes).unsupported == "unsupported filter RequestMirror"
  end

  test "a filter without its configuration or with a malformed path rejects the route" do
    base = [Fixtures.gateway_class(), Fixtures.gateway(), Fixtures.service(name: "app-svc")]

    for {filter, message} <- [
          {%{"type" => "CORS"}, "CORS filter without its configuration"},
          {%{"type" => "RequestHeaderModifier", "requestHeaderModifier" => "x"},
           "RequestHeaderModifier filter without its configuration"},
          {%{"type" => "URLRewrite", "urlRewrite" => %{"path" => %{"type" => "Odd"}}},
           "URLRewrite path is malformed"},
          {%{"nope" => true}, "filter without a type"}
        ] do
      rules = [
        %{"backendRefs" => [%{"name" => "app-svc", "port" => 8080}], "filters" => [filter]}
      ]

      graph = resolve(base ++ [Fixtures.http_route(rules: rules)])

      assert hd(graph.routes).unsupported == message
      assert first_parent(graph).accepted_reason == "UnsupportedValue"
      assert attached_entries(graph) == []
    end
  end

  test "a URLRewrite hostname rejects the route, a path rewrite does not" do
    rewrite_rule = fn rewrite ->
      [
        %{
          "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
          "backendRefs" => [%{"name" => "app-svc", "port" => 8080}],
          "filters" => [%{"type" => "URLRewrite", "urlRewrite" => rewrite}]
        }
      ]
    end

    base = [Fixtures.gateway_class(), Fixtures.gateway(), Fixtures.service(name: "app-svc")]

    hostname =
      resolve(base ++ [Fixtures.http_route(rules: rewrite_rule.(%{"hostname" => "x.example"}))])

    refute first_parent(hostname).accepted?
    assert first_parent(hostname).accepted_reason == "UnsupportedValue"

    path_only =
      resolve(
        base ++
          [
            Fixtures.http_route(
              rules:
                rewrite_rule.(%{
                  "path" => %{"type" => "ReplacePrefixMatch", "replacePrefixMatch" => "/v2"}
                })
            )
          ]
      )

    assert first_parent(path_only).accepted?
  end

  test "backend filters on a weighted rule reject the route" do
    filters = [
      %{
        "type" => "RequestHeaderModifier",
        "requestHeaderModifier" => %{"set" => [%{"name" => "X-B", "value" => "1"}]}
      }
    ]

    weighted = [
      %{"name" => "app-svc", "port" => 8080, "weight" => 1, "filters" => filters},
      %{"name" => "app-svc", "port" => 8080, "weight" => 1}
    ]

    single = [%{"name" => "app-svc", "port" => 8080, "filters" => filters}]

    rule = fn backends ->
      [
        %{
          "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
          "backendRefs" => backends
        }
      ]
    end

    base = [Fixtures.gateway_class(), Fixtures.gateway(), Fixtures.service(name: "app-svc")]

    rejected = resolve(base ++ [Fixtures.http_route(rules: rule.(weighted))])
    refute first_parent(rejected).accepted?
    assert first_parent(rejected).accepted_reason == "UnsupportedValue"

    accepted = resolve(base ++ [Fixtures.http_route(rules: rule.(single))])
    assert first_parent(accepted).accepted?
  end
end
