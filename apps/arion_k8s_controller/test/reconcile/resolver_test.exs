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

defmodule Arion.K8sController.Reconcile.ResolverTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Ir
  alias Arion.K8sController.Reconcile.{Resolver, Translator}

  test "claims GatewayClasses matching the controller name" do
    snap = Fixtures.snapshot([Fixtures.gateway_class(name: "arion")])

    %Ir.Graph{classes: [class]} = Resolver.resolve(snap, Fixtures.controller_name())

    assert class.name == "arion"
    assert class.invalid_params == nil
    assert class.generation == 1
  end

  test "ignores GatewayClasses owned by another controller" do
    snap = Fixtures.snapshot([Fixtures.gateway_class(controller_name: "other.io/controller")])

    assert %Ir.Graph{classes: []} = Resolver.resolve(snap, Fixtures.controller_name())
  end

  test "allowedRoutes namespace selector controls cross-namespace route attachment" do
    gateway =
      Fixtures.gateway(
        listeners: [
          %{
            "name" => "http",
            "port" => 80,
            "protocol" => "HTTP",
            "allowedRoutes" => %{
              "namespaces" => %{
                "from" => "Selector",
                "selector" => %{"matchLabels" => %{"team" => "payments"}}
              }
            }
          }
        ]
      )

    route =
      Fixtures.http_route(
        namespace: "payments",
        parent_refs: [%{"name" => "demo", "namespace" => "default"}]
      )

    snap =
      Fixtures.snapshot([
        Fixtures.gateway_class(),
        Fixtures.namespace(name: "payments", labels: %{"team" => "payments"}),
        gateway,
        Fixtures.service(namespace: "payments"),
        route
      ])

    %Ir.Graph{routes: [resolved], gateways: [resolved_gateway]} =
      Resolver.resolve(snap, Fixtures.controller_name())

    assert hd(resolved.parents).accepted?
    assert resolved_gateway.listeners |> hd() |> Map.get(:attached_routes) |> length() == 1
  end

  test "allowedRoutes namespace selector rejects non-matching namespaces" do
    gateway =
      Fixtures.gateway(
        listeners: [
          %{
            "name" => "http",
            "port" => 80,
            "protocol" => "HTTP",
            "allowedRoutes" => %{
              "namespaces" => %{
                "from" => "Selector",
                "selector" => %{"matchLabels" => %{"team" => "payments"}}
              }
            }
          }
        ]
      )

    route =
      Fixtures.http_route(
        namespace: "search",
        parent_refs: [%{"name" => "demo", "namespace" => "default"}]
      )

    snap =
      Fixtures.snapshot([
        Fixtures.gateway_class(),
        Fixtures.namespace(name: "search", labels: %{"team" => "search"}),
        gateway,
        Fixtures.service(namespace: "search"),
        route
      ])

    %Ir.Graph{routes: [resolved], gateways: [resolved_gateway]} =
      Resolver.resolve(snap, Fixtures.controller_name())

    parent = hd(resolved.parents)
    refute parent.accepted?
    assert parent.accepted_reason == "NotAllowedByListeners"
    assert resolved_gateway.listeners |> hd() |> Map.get(:attached_routes) == []
  end

  test "only a Gateway parentRef attaches a route to a Gateway" do
    for {ref, attached} <- [
          {%{"group" => "", "kind" => "Service"}, 0},
          {%{"kind" => "ListenerSet"}, 0},
          {%{"group" => "example.com", "kind" => "Gateway"}, 0},
          {%{"group" => "gateway.networking.k8s.io", "kind" => "Gateway"}, 1},
          {%{}, 1}
        ] do
      ref = Map.put(ref, "name", "demo")

      snap =
        Fixtures.snapshot([
          Fixtures.gateway_class(),
          Fixtures.gateway(),
          Fixtures.service(),
          Fixtures.http_route(parent_refs: [ref])
        ])

      %Ir.Graph{routes: [route], gateways: [gateway]} =
        Resolver.resolve(snap, Fixtures.controller_name())

      assert length(route.parents) == attached, inspect(ref)
      assert length(hd(gateway.listeners).attached_routes) == attached, inspect(ref)
    end
  end

  test "TLSRoutes attach to a TLS Terminate listener by hostname intersection" do
    listener = %{
      "name" => "tls",
      "port" => 443,
      "protocol" => "TLS",
      "hostname" => "*.example.com",
      "tls" => %{"mode" => "Terminate", "certificateRefs" => [%{"name" => "app-cert"}]}
    }

    snap =
      Fixtures.snapshot([
        Fixtures.gateway_class(),
        Fixtures.gateway(listeners: [listener]),
        Fixtures.tls_secret(name: "app-cert"),
        Fixtures.tls_route(name: "match", hostnames: ["a.example.com", "a.example.net"]),
        Fixtures.tls_route(name: "apex", hostnames: ["example.com"]),
        Fixtures.http_route(hostnames: ["b.example.com"])
      ])

    graph = Resolver.resolve(snap, Fixtures.controller_name())
    [%{listeners: [resolved]}] = graph.gateways

    assert %{protocol: :tls_terminate, resolved_reason: "ResolvedRefs"} = resolved
    assert [%{sds_name: "secret:default/app-cert"}] = resolved.tls.certificates
    assert [%{name: "match", domains: ["a.example.com"]}] = resolved.attached_routes

    assert Map.new(graph.routes, fn %{name: name, parents: [parent]} ->
             {name, parent.accepted_reason}
           end) == %{
             "match" => "Accepted",
             "apex" => "NoMatchingListenerHostname",
             "app" => "NotAllowedByListeners"
           }
  end

  test "a wildcard HTTPS listener overlaps a sibling without a hostname" do
    https = fn name, hostname ->
      %{
        "name" => name,
        "port" => 443,
        "protocol" => "HTTPS",
        "tls" => %{"mode" => "Terminate", "certificateRefs" => [%{"name" => "app-cert"}]}
      }
      |> then(&if hostname, do: Map.put(&1, "hostname", hostname), else: &1)
    end

    snap =
      Fixtures.snapshot([
        Fixtures.gateway_class(),
        Fixtures.gateway(listeners: [https.("wildcard", "*.example.com"), https.("all", nil)]),
        Fixtures.tls_secret(name: "app-cert")
      ])

    %Ir.Graph{gateways: [%{listeners: listeners}]} =
      Resolver.resolve(snap, Fixtures.controller_name())

    assert Enum.map(listeners, &{&1.name, &1.overlapping_tls?, &1.conflict}) == [
             {"wildcard", true, nil},
             {"all", true, nil}
           ]
  end

  test "a GatewayClass parametersRef must name an ArionGatewayParameters in a namespace" do
    ref = %{
      "group" => "arion.io",
      "kind" => "ArionGatewayParameters",
      "name" => "arion-params",
      "namespace" => "default"
    }

    for {params_ref, reason} <- [
          {%{ref | "kind" => "ConfigMap"},
           "parametersRef kind must be arion.io/ArionGatewayParameters"},
          {Map.delete(ref, "namespace"), "parametersRef must have a namespace"},
          {%{ref | "name" => "missing"}, "ArionGatewayParameters default/missing not found"},
          {ref, nil}
        ] do
      snap =
        Fixtures.snapshot([
          Fixtures.gateway_class(params_ref: params_ref),
          Fixtures.gateway(),
          Fixtures.service(),
          Fixtures.http_route(),
          Fixtures.gateway_params()
        ])

      graph = Resolver.resolve(snap, Fixtures.controller_name())
      %Ir.Graph{classes: [class], gateways: [gateway]} = graph

      assert class.invalid_params == reason, inspect(params_ref)

      assert gateway.invalid_params == (reason && "GatewayClass arion: #{reason}"),
             inspect(params_ref)

      # A Gateway of a rejected class is not translated either.
      assert Map.has_key?(Translator.translate(graph), "gateway/default/demo") == is_nil(reason)
    end
  end
end
