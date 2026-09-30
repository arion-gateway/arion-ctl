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

defmodule Arion.K8sController.Reconcile.GrpcTest do
  use ExUnit.Case, async: true

  alias Arion.ControlPlane.Pb.Cluster.Cluster
  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Reconcile.{Resolver, Translator}

  defp resolve(objects),
    do: objects |> Fixtures.snapshot() |> Resolver.resolve(Fixtures.controller_name())

  test "gRPC method match becomes an exact path match on /service/method" do
    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "echo-svc", port: 9000),
        Fixtures.grpc_route()
      ])

    route = Enum.find(graph.routes, &(&1.kind == :grpc))
    [match] = hd(route.rules).matches
    assert match["path"] == %{"type" => "Exact", "value" => "/echo.Echo/Ping"}
  end

  test "a gRPC service-only match is a path-separated prefix on /service" do
    rules = [
      %{
        "matches" => [%{"method" => %{"service" => "echo.Echo"}}],
        "backendRefs" => [%{"name" => "echo-svc", "port" => 9000}]
      }
    ]

    %{gateways: [%{listeners: [listener]}]} =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "echo-svc", port: 9000),
        Fixtures.grpc_route(rules: rules)
      ])

    [%{routes: [route]}] =
      Fixtures.route_config(listener.attached_routes).virtual_hosts

    assert route.match.path_specifier == {:path_separated_prefix, "/echo.Echo"}
  end

  test "gRPC rules rank by service, then method, before the catch-all" do
    rule = fn method, backend ->
      matches = if method, do: %{"matches" => [%{"method" => method}]}, else: %{}
      Map.put(matches, "backendRefs", [%{"name" => backend, "port" => 9000}])
    end

    rules = [
      rule.(nil, "all"),
      rule.(%{"method" => "Ping"}, "method"),
      rule.(%{"service" => "echo.Echo"}, "service"),
      rule.(%{"service" => "echo.Echo", "method" => "Ping"}, "exact")
    ]

    %{gateways: [%{listeners: [listener]}]} =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.grpc_route(rules: rules)
        | for(name <- ~w(all method service exact), do: Fixtures.service(name: name, port: 9000))
      ])

    [%{routes: routes}] =
      Fixtures.route_config(listener.attached_routes).virtual_hosts

    assert for(%{action: {:route, action}} <- routes, do: action.cluster_specifier) == [
             {:cluster, "svc:default/exact:9000/h2"},
             {:cluster, "svc:default/service:9000/h2"},
             {:cluster, "svc:default/method:9000/h2"},
             {:cluster, "svc:default/all:9000/h2"}
           ]
  end

  test "a gRPC regex match on only a service or only a method matches any other side" do
    rules = [
      %{
        "matches" => [
          %{"method" => %{"type" => "RegularExpression", "service" => "echo\\..*"}},
          %{"method" => %{"type" => "RegularExpression", "method" => "Get.*"}}
        ],
        "backendRefs" => [%{"name" => "echo-svc", "port" => 9000}]
      }
    ]

    graph =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "echo-svc", port: 9000),
        Fixtures.grpc_route(rules: rules)
      ])

    [route] = graph.routes

    assert for(match <- hd(route.rules).matches, do: match["path"]["value"]) ==
             ["/echo\\..*/[^/]+", "/[^/]+/Get.*"]
  end

  test "gRPC backend cluster gets HTTP/2 protocol options" do
    resources =
      resolve([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "echo-svc", port: 9000),
        Fixtures.grpc_route()
      ])
      |> Translator.translate()
      |> Map.get("gateway/default/demo")

    assert %{"svc:default/echo-svc:9000/h2" => %Cluster{} = cluster} = resources.cluster

    assert Map.has_key?(
             cluster.typed_extension_protocol_options,
             "envoy.extensions.upstreams.http.v3.HttpProtocolOptions"
           )
  end
end
