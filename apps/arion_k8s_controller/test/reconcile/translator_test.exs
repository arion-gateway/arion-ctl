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

defmodule Arion.K8sController.Reconcile.TranslatorTest do
  use ExUnit.Case, async: true

  alias Arion.ControlPlane.Pb.Cluster.Cluster
  alias Arion.ControlPlane.Pb.Filter.HttpConnectionManager
  alias Arion.ControlPlane.Pb.Listener.Listener
  alias Arion.K8sController.{Fixtures, Ir}
  alias Arion.K8sController.Reconcile.{Resolver, Translator}

  defp resolve_translate(objects) do
    objects
    |> Fixtures.snapshot()
    |> Resolver.resolve(Fixtures.controller_name())
    |> Translator.translate()
  end

  defp virtual_hosts(listener) do
    [chain] = listener.filter_chains
    [filter] = chain.filters
    {:typed_config, any} = filter.config_type
    {:route_config, route_config} = HttpConnectionManager.decode(any.value).route_specifier
    route_config.virtual_hosts
  end

  defp redirect(listener) do
    [%{routes: [%{action: {:redirect, redirect}}]}] = virtual_hosts(listener)
    redirect
  end

  test "HTTPRoute → EDS cluster + listener in the per-Gateway namespace" do
    xds =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route()
      ])

    assert %{"gateway/default/demo" => resources} = xds

    assert %{"svc:default/app-svc:8080" => %Cluster{} = cluster} = resources.cluster
    assert cluster.name == "svc:default/app-svc:8080"
    assert cluster.cluster_discovery_type == {:type, :EDS}

    assert %{"default-demo-80" => %Listener{} = listener} = resources.listener
    assert listener.name == "default-demo-80"
    assert [chain] = listener.filter_chains
    assert [_hcm_filter] = chain.filters
  end

  test "the HCM enables the websocket upgrade" do
    xds =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route()
      ])

    %{"gateway/default/demo" => resources} = xds
    %{"default-demo-80" => listener} = resources.listener
    [chain] = listener.filter_chains
    [filter] = chain.filters
    {:typed_config, any} = filter.config_type
    hcm = HttpConnectionManager.decode(any.value)

    assert [upgrade] = hcm.upgrade_configs
    assert upgrade.upgrade_type == "websocket"
    assert upgrade.enabled.value
  end

  test "an h2c Service backend gets HTTP/2 cluster protocol options" do
    xds =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(
          name: "app-svc",
          ports: [%{"port" => 8080, "appProtocol" => "kubernetes.io/h2c"}]
        ),
        Fixtures.http_route()
      ])

    %{"gateway/default/demo" => resources} = xds
    %{"svc:default/app-svc:8080/h2" => cluster} = resources.cluster

    assert Map.has_key?(
             cluster.typed_extension_protocol_options,
             "envoy.extensions.upstreams.http.v3.HttpProtocolOptions"
           )
  end

  test "HTTP and gRPC routes to one Service port get a cluster per protocol" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(),
      Fixtures.service(name: "echo-svc", port: 9000),
      Fixtures.endpoint_slice(service: "echo-svc", ports: [%{"name" => "", "port" => 9000}]),
      Fixtures.http_route(
        hostnames: ["grpc.example.com"],
        rules: [%{"backendRefs" => [%{"name" => "echo-svc", "port" => 9000}]}]
      ),
      Fixtures.grpc_route()
    ]

    resources = resolve_translate(objects)["gateway/default/demo"]

    assert Map.keys(resources.cluster) == [
             "svc:default/echo-svc:9000",
             "svc:default/echo-svc:9000/h2"
           ]

    assert Map.keys(resources.load_assignment) == Map.keys(resources.cluster)
    refute Map.has_key?(resources.cluster["svc:default/echo-svc:9000"], :bogus)
    assert resources.cluster["svc:default/echo-svc:9000"].typed_extension_protocol_options == %{}

    refute resources.cluster["svc:default/echo-svc:9000/h2"].typed_extension_protocol_options ==
             %{}

    [vhost] = virtual_hosts(resources.listener["default-demo-80"])

    assert for(%{action: {:route, action}} <- vhost.routes, do: action.cluster_specifier) == [
             {:cluster, "svc:default/echo-svc:9000/h2"},
             {:cluster, "svc:default/echo-svc:9000"}
           ]

    assert resolve_translate(Enum.reverse(objects)) == resolve_translate(objects)
  end

  test "different resources under one name fail instead of publishing one of them" do
    graph =
      [
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route()
      ]
      |> Fixtures.snapshot()
      |> Resolver.resolve(Fixtures.controller_name())

    [%{listeners: [listener]} = gateway] = graph.gateways
    [backend] = listener.attached_routes |> Enum.flat_map(&Ir.Route.backends/1)
    entry = hd(listener.attached_routes)
    rule = hd(entry.rules)

    rules =
      for address <- ["10.0.0.1", "10.0.0.9"],
          do: %{rule | backends: [%{backend | endpoints: [{address, 8080}]}]}

    listener = %{listener | attached_routes: [%{entry | rules: rules}]}
    graph = %{graph | gateways: [%{gateway | listeners: [listener]}]}

    assert_raise ArgumentError, ~r/conflicting load_assignment resources named/, fn ->
      Translator.translate(graph)
    end
  end

  test "a CORS route adds the chain-level cors filter, others do not" do
    decode_hcm = fn xds ->
      %{"gateway/default/demo" => resources} = xds
      %{"default-demo-80" => listener} = resources.listener
      [chain] = listener.filter_chains
      [filter] = chain.filters
      {:typed_config, any} = filter.config_type
      HttpConnectionManager.decode(any.value)
    end

    cors_route =
      Fixtures.http_route(
        rules: [
          %{
            "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
            "backendRefs" => [%{"name" => "app-svc", "port" => 8080}],
            "filters" => [%{"type" => "CORS", "cors" => %{"allowOrigins" => ["*"]}}]
          }
        ]
      )

    base = [Fixtures.gateway_class(), Fixtures.gateway(), Fixtures.service(name: "app-svc")]

    with_cors = decode_hcm.(resolve_translate(base ++ [cors_route]))

    assert Enum.map(with_cors.http_filters, & &1.name) == [
             "envoy.filters.http.cors",
             "envoy.filters.http.router"
           ]

    without_cors = decode_hcm.(resolve_translate(base ++ [Fixtures.http_route()]))
    assert Enum.map(without_cors.http_filters, & &1.name) == ["envoy.filters.http.router"]
  end

  test "Gateways whose namespace and name join alike keep separate fleets" do
    xds =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(namespace: "default", name: "a-b"),
        Fixtures.gateway(namespace: "default-a", name: "b"),
        Fixtures.http_route(namespace: "default", parent_refs: [%{"name" => "a-b"}])
      ])

    assert %{"gateway/default/a-b" => routed, "gateway/default-a/b" => empty} = xds

    assert [%{routes: [%{name: "default/app"}]}] =
             virtual_hosts(routed.listener["default-a-b-80"])

    assert [%{routes: [%{action: {:direct_response, _}}]}] =
             virtual_hosts(empty.listener["default-a-b-80"])
  end

  test "unresolved backend (no Service) yields no cluster and a direct response" do
    xds =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.http_route()
      ])

    resources = xds["gateway/default/demo"]
    refute Map.has_key?(resources, :cluster)
    assert %{"default-demo-80" => %Listener{}} = resources.listener
  end

  test "route to another controller's class is ignored" do
    xds =
      resolve_translate([
        Fixtures.gateway_class(controller_name: "other.io/ctrl"),
        Fixtures.gateway(),
        Fixtures.service(),
        Fixtures.http_route()
      ])

    assert xds == %{}
  end

  test "a Gateway with a missing parametersRef is not translated" do
    ref = %{"group" => "arion.io", "kind" => "ArionGatewayParameters", "name" => "missing"}

    xds =
      resolve_translate([
        Fixtures.gateway_class(),
        put_in(Fixtures.gateway(), ["spec", "infrastructure"], %{"parametersRef" => ref}),
        Fixtures.service(),
        Fixtures.http_route()
      ])

    assert xds == %{}
  end

  test "a hostname redirect on an HTTP listener keeps http and its non-default port" do
    listener = %{
      "name" => "http",
      "port" => 8080,
      "protocol" => "HTTP",
      "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
    }

    xds =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(listeners: [listener]),
        Fixtures.http_route(
          rules: [
            %{
              "filters" => [
                %{
                  "type" => "RequestRedirect",
                  "requestRedirect" => %{"hostname" => "example.org"}
                }
              ]
            }
          ]
        )
      ])

    redirect = redirect(xds["gateway/default/demo"].listener["default-demo-8080"])
    assert redirect.scheme_rewrite_specifier == {:scheme_redirect, "http"}
    assert redirect.host_redirect == "example.org"
    assert redirect.port_redirect == 8080
  end

  test "a wildcard route hostname narrows to the listener's hostname" do
    listener = %{
      "name" => "http",
      "port" => 80,
      "protocol" => "HTTP",
      "hostname" => "very.specific.com",
      "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
    }

    xds =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(listeners: [listener]),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route(hostnames: ["non.matching.com", "*.specific.com"])
      ])

    assert [vhost] = virtual_hosts(xds["gateway/default/demo"].listener["default-demo-80"])
    assert vhost.domains == ["very.specific.com"]
  end
end
