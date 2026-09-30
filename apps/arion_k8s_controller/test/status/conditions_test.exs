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

defmodule Arion.K8sController.Status.ConditionsTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Resolver
  alias Arion.K8sController.Status.Conditions

  defp entries(objects) do
    objects
    |> Fixtures.snapshot()
    |> Resolver.resolve(Fixtures.controller_name())
    |> Conditions.compute("2026-06-30T00:00:00Z")
  end

  defp entry(entries, gvk, name), do: Enum.find(entries, &(&1.gvk == gvk and &1.name == name))

  defp condition(status_map, type),
    do: Enum.find(status_map["conditions"], &(&1["type"] == type))

  test "GatewayClass, Gateway and HTTPRoute get Accepted conditions with observedGeneration" do
    entries =
      entries([
        Fixtures.gateway_class(),
        Fixtures.gateway(generation: 3),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route()
      ])

    gw = entry(entries, Gvk.gateway(), "demo")
    accepted = condition(gw.status, "Accepted")
    assert accepted["status"] == "True"
    assert accepted["observedGeneration"] == 3
    # No data plane provisioned yet, so Programmed is Pending.
    assert condition(gw.status, "Programmed")["status"] == "False"
    assert condition(gw.status, "Programmed")["reason"] == "Pending"

    [listener] = gw.status["listeners"]
    assert listener["attachedRoutes"] == 1

    route = entry(entries, Gvk.http_route(), "app")
    [parent] = route.status["parents"]
    assert parent["controllerName"] == Fixtures.controller_name()
    assert Enum.find(parent["conditions"], &(&1["type"] == "Accepted"))["status"] == "True"

    class = entry(entries, Gvk.gateway_class(), "arion")

    features = Enum.map(class.status["supportedFeatures"], & &1["name"])
    assert features == Enum.sort(features)

    for feature <- [
          "Gateway",
          "HTTPRoute",
          "ReferenceGrant",
          "HTTPRouteBackendProtocolWebSocket",
          "HTTPRouteCORS",
          "HTTPRoutePathRewrite",
          "HTTPRouteSchemeRedirect"
        ] do
      assert feature in features
    end

    refute "HTTPRouteRequestMirror" in features
    refute "HTTPRouteHostRewrite" in features

    # Backend filters are not folded into rules that split traffic, which that feature's test needs.
    refute "HTTPRouteBackendRequestHeaderModification" in features
  end

  defp with_status(objects, entries) do
    for obj <- objects do
      meta = obj["metadata"]

      case entry(entries, Fixtures.gvk(obj), meta["name"]) do
        nil -> obj
        entry -> Map.put(obj, "status", entry.status)
      end
    end
  end

  defp changed(objects, now) do
    snapshot = Fixtures.snapshot(objects)

    snapshot
    |> Resolver.resolve(Fixtures.controller_name())
    |> Conditions.compute(now)
    |> Conditions.changed(snapshot)
  end

  test "only changed statuses are written, and unchanged conditions keep their time" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(),
      Fixtures.service(name: "app-svc"),
      Fixtures.http_route()
    ]

    written = with_status(objects, entries(objects))
    assert changed(written, "2026-07-01T00:00:00Z") == []

    ready = [Fixtures.provisioned_deployment(ready_replicas: 1) | written]
    assert [gw] = changed(ready, "2026-07-01T00:00:00Z")
    [listener] = gw.status["listeners"]

    assert %{"status" => "True", "lastTransitionTime" => "2026-07-01T00:00:00Z"} =
             condition(gw.status, "Programmed")

    assert condition(gw.status, "Accepted")["lastTransitionTime"] == "2026-06-30T00:00:00Z"
    assert condition(listener, "Programmed")["lastTransitionTime"] == "2026-06-30T00:00:00Z"
  end

  test "a ready provisioned data plane makes the Gateway Programmed with addresses" do
    entries =
      entries([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.provisioned_deployment(ready_replicas: 2),
        Fixtures.provisioned_service(
          ingress: [
            %{"ip" => "203.0.113.9"},
            %{"ip" => "2001:db8::10", "hostname" => "lb.example.net"},
            %{"hostname" => "lb.example.net"}
          ]
        )
      ])

    gw = entry(entries, Gvk.gateway(), "demo")
    assert condition(gw.status, "Programmed")["status"] == "True"

    assert gw.status["addresses"] == [
             %{"type" => "IPAddress", "value" => "203.0.113.9"},
             %{"type" => "IPAddress", "value" => "2001:db8::10"},
             %{"type" => "Hostname", "value" => "lb.example.net"}
           ]
  end

  test "cross-namespace backend without a grant reports ResolvedRefs=False RefNotPermitted" do
    route =
      Fixtures.http_route(
        rules: [
          %{
            "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
            "backendRefs" => [%{"name" => "api", "namespace" => "backends", "port" => 9000}]
          }
        ]
      )

    entries =
      entries([Fixtures.gateway_class(), Fixtures.gateway(), route])

    parent = entry(entries, Gvk.http_route(), "app").status["parents"] |> hd()
    resolved = Enum.find(parent["conditions"], &(&1["type"] == "ResolvedRefs"))
    assert resolved["status"] == "False"
    assert resolved["reason"] == "RefNotPermitted"
  end

  test "InferencePool status reports Accepted and ResolvedRefs parents" do
    entries =
      entries([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "llm-epp", port: 9002),
        Fixtures.inference_pool(),
        Fixtures.inference_http_route(parent_refs: [%{"name" => "demo", "sectionName" => "http"}])
      ])

    pool = entry(entries, Gvk.inference_pool(), "llm-pool")
    [parent] = pool.status["parents"]

    # Only the fields the InferencePool status schema keeps.
    assert parent["parentRef"] == %{
             "group" => "gateway.networking.k8s.io",
             "kind" => "Gateway",
             "name" => "demo",
             "namespace" => "default"
           }

    assert condition(parent, "Accepted")["status"] == "True"
    assert condition(parent, "ResolvedRefs")["status"] == "True"
  end

  test "InferencePool status reports ResolvedRefs=False when the endpoint picker is missing" do
    entries =
      entries([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.inference_pool(),
        Fixtures.inference_http_route()
      ])

    pool = entry(entries, Gvk.inference_pool(), "llm-pool")
    [parent] = pool.status["parents"]
    resolved = condition(parent, "ResolvedRefs")

    assert resolved["status"] == "False"
    assert resolved["reason"] == "BackendNotFound"
  end

  test "InferencePool status drops stale parents and keeps other controllers' parents" do
    parent = fn controller, gateway ->
      %{
        "parentRef" => %{"kind" => "Gateway", "namespace" => "default", "name" => gateway},
        "controllerName" => controller,
        "conditions" => []
      }
    end

    stale = parent.(Fixtures.controller_name(), "demo")
    theirs = parent.("example.com/other", "other")

    pool_writes = fn parents, routes ->
      pool = Fixtures.inference_pool()
      pool = if parents, do: Map.put(pool, "status", %{"parents" => parents}), else: pool

      for entry <- changed([Fixtures.gateway_class(), Fixtures.gateway(), pool | routes], "now"),
          entry.gvk == Gvk.inference_pool(),
          do: entry.status["parents"]
    end

    assert pool_writes.([stale, theirs], []) == [[theirs]]
    assert pool_writes.([stale], []) == [[]]
    assert pool_writes.([theirs], []) == []
    assert pool_writes.(nil, []) == []

    assert [[^theirs, ours]] = pool_writes.([theirs], [Fixtures.inference_http_route()])
    assert ours["controllerName"] == Fixtures.controller_name()
  end

  test "route status reports only Arion's Gateways and keeps other controllers' parents" do
    other = "istio.io/gateway-controller"
    theirs = %{"parentRef" => %{"name" => "istio-gw"}, "controllerName" => other}
    stale = %{"parentRef" => %{"name" => "gone"}, "controllerName" => Fixtures.controller_name()}

    route_writes = fn parents, parent_refs ->
      route = Fixtures.http_route(parent_refs: parent_refs)
      route = if parents, do: Map.put(route, "status", %{"parents" => parents}), else: route

      objects = [
        Fixtures.gateway_class(),
        Fixtures.gateway_class(name: "istio", controller_name: other),
        Fixtures.gateway(),
        Fixtures.gateway(name: "istio-gw", class_name: "istio"),
        Fixtures.service(name: "app-svc"),
        route
      ]

      for entry <- changed(objects, "now"),
          entry.gvk == Gvk.http_route(),
          do: entry.status["parents"]
    end

    istio_gw = %{"name" => "istio-gw"}
    assert route_writes.(nil, [istio_gw, %{"name" => "missing"}]) == []
    assert route_writes.([theirs], [istio_gw]) == []
    assert route_writes.([stale, theirs], [istio_gw]) == [[theirs]]

    assert [[^theirs, ours]] = route_writes.([theirs], [istio_gw, %{"name" => "demo"}])
    assert ours["controllerName"] == Fixtures.controller_name()
    assert %{"status" => "True"} = condition(ours, "Accepted")

    # A listener mismatch on Arion's own Gateway is still reported.
    assert [[^theirs, ours]] =
             route_writes.([theirs], [istio_gw, %{"name" => "demo", "sectionName" => "none"}])

    assert %{"status" => "False", "reason" => "NoMatchingParent"} = condition(ours, "Accepted")
  end

  test "a peer that lists other controllers' parents first causes no rewrites" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(),
      Fixtures.service(name: "llm-epp", port: 9002),
      Fixtures.inference_pool(),
      Fixtures.inference_http_route()
    ]

    peer = fn ours ->
      conditions =
        for c <- ours["conditions"], do: %{c | "lastTransitionTime" => "2026-05-01T00:00:00Z"}

      %{ours | "controllerName" => "example.com/peer", "conditions" => conditions}
    end

    written = with_status(objects, entries(objects))
    assert Enum.count(written, &match?(%{"status" => %{"parents" => [_]}}, &1)) == 2

    for order <- [&[&1, peer.(&1)], &[peer.(&1), &1]] do
      shared =
        for obj <- written do
          case obj["status"] do
            %{"parents" => [ours]} -> put_in(obj, ["status", "parents"], order.(ours))
            _ -> obj
          end
        end

      assert changed(shared, "2026-07-01T00:00:00Z") == []
    end
  end

  test "an unsupported (UDP) listener is Accepted=False UnsupportedProtocol" do
    udp_gateway =
      Fixtures.gateway(
        listeners: [
          %{
            "name" => "udp",
            "port" => 53,
            "protocol" => "UDP",
            "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
          }
        ]
      )

    entries = entries([Fixtures.gateway_class(), udp_gateway])
    [listener] = entry(entries, Gvk.gateway(), "demo").status["listeners"]
    accepted = Enum.find(listener["conditions"], &(&1["type"] == "Accepted"))
    assert accepted["status"] == "False"
    assert accepted["reason"] == "UnsupportedProtocol"
  end

  defp https_listener_status(certificate_refs) do
    entries =
      entries([
        Fixtures.gateway_class(),
        Fixtures.https_gateway(certificate_refs: certificate_refs),
        Fixtures.tls_secret(name: "app-cert"),
        Fixtures.tls_secret(name: "app-cert", namespace: "certs"),
        Fixtures.provisioned_deployment(ready_replicas: 1),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route(parent_refs: [%{"name" => "demo", "sectionName" => "https"}])
      ])

    gw = entry(entries, Gvk.gateway(), "demo")
    assert %{"status" => "True", "reason" => "Accepted"} = condition(gw.status, "Accepted")
    assert %{"status" => "True", "reason" => "Programmed"} = condition(gw.status, "Programmed")

    [parent] = entry(entries, Gvk.http_route(), "app").status["parents"]
    assert %{"status" => "True", "reason" => "Accepted"} = condition(parent, "Accepted")

    [listener] = gw.status["listeners"]
    assert listener["attachedRoutes"] == 1
    assert %{"status" => "True", "reason" => "Accepted"} = condition(listener, "Accepted")
    listener
  end

  test "an HTTPS listener without a usable certificate is not Programmed, but its Gateway is" do
    for {ref, reason} <- [
          {%{"name" => "missing-cert"}, "InvalidCertificateRef"},
          {%{"name" => "app-cert", "namespace" => "certs"}, "RefNotPermitted"}
        ] do
      listener = https_listener_status([ref])
      assert %{"status" => "False", "reason" => ^reason} = condition(listener, "ResolvedRefs")
      assert %{"status" => "False", "reason" => "Invalid"} = condition(listener, "Programmed")
    end
  end

  test "an HTTPS listener with a usable and an invalid certificateRef is Programmed" do
    listener =
      https_listener_status([
        %{"name" => "app-cert", "namespace" => "certs"},
        %{"name" => "app-cert"}
      ])

    assert %{"status" => "False", "reason" => "RefNotPermitted"} =
             condition(listener, "ResolvedRefs")

    assert %{"status" => "True", "reason" => "Programmed"} = condition(listener, "Programmed")
  end

  # Mirrors the TLSRoute Terminate listener conformance manifests.
  test "a TLS Terminate listener supports TLSRoute and resolves certificateRefs like HTTPS" do
    for {ref, reason, programmed} <- [
          {%{"name" => "app-cert"}, "ResolvedRefs", "True"},
          {%{"name" => "missing-cert"}, "InvalidCertificateRef", "False"},
          {%{"name" => "app-cert", "namespace" => "certs"}, "RefNotPermitted", "False"}
        ] do
      listener = %{
        "name" => "tls-terminate",
        "port" => 8443,
        "protocol" => "TLS",
        "hostname" => "terminate.example.com",
        "allowedRoutes" => %{
          "namespaces" => %{"from" => "Same"},
          "kinds" => [%{"kind" => "TLSRoute"}]
        },
        "tls" => %{"mode" => "Terminate", "certificateRefs" => [ref]}
      }

      entries =
        entries([
          Fixtures.gateway_class(),
          Fixtures.gateway(listeners: [listener]),
          Fixtures.tls_secret(name: "app-cert"),
          Fixtures.tls_secret(name: "app-cert", namespace: "certs"),
          Fixtures.provisioned_deployment(ready_replicas: 1)
        ])

      gw = entry(entries, Gvk.gateway(), "demo")
      assert %{"status" => "True", "reason" => "Accepted"} = condition(gw.status, "Accepted")
      assert %{"status" => "True", "reason" => "Programmed"} = condition(gw.status, "Programmed")

      [status] = gw.status["listeners"]

      assert status["supportedKinds"] == [
               %{"group" => "gateway.networking.k8s.io", "kind" => "TLSRoute"}
             ]

      assert %{"status" => "True", "reason" => "Accepted"} = condition(status, "Accepted")
      assert condition(status, "ResolvedRefs")["reason"] == reason
      assert condition(status, "Programmed")["status"] == programmed
    end
  end

  test "allowedRoutes kinds the listener's protocol does not support are InvalidRouteKinds" do
    passthrough = %{"mode" => "Passthrough"}

    for {protocol, tls, kinds, supported, reason} <- [
          {"HTTP", nil, [%{"kind" => "InvalidRoute"}], [], "InvalidRouteKinds"},
          {"HTTP", nil, [%{"kind" => "InvalidRoute"}, %{"kind" => "HTTPRoute"}], ["HTTPRoute"],
           "InvalidRouteKinds"},
          {"HTTP", nil, [%{"group" => "example.com", "kind" => "HTTPRoute"}], [],
           "InvalidRouteKinds"},
          {"TLS", passthrough, [%{"kind" => "TCPRoute"}, %{"kind" => "TLSRoute"}], ["TLSRoute"],
           "InvalidRouteKinds"},
          {"HTTP", nil, [%{"group" => "gateway.networking.k8s.io", "kind" => "GRPCRoute"}],
           ["GRPCRoute"], "ResolvedRefs"},
          {"HTTP", nil, [], ["HTTPRoute", "GRPCRoute"], "ResolvedRefs"},
          {"TCP", nil, nil, ["TCPRoute"], "ResolvedRefs"}
        ] do
      listener = %{
        "name" => "l",
        "port" => 80,
        "protocol" => protocol,
        "tls" => tls,
        "allowedRoutes" => %{"kinds" => kinds}
      }

      entries = entries([Fixtures.gateway_class(), Fixtures.gateway(listeners: [listener])])
      [status] = entry(entries, Gvk.gateway(), "demo").status["listeners"]
      name = "#{protocol} #{inspect(kinds)}"

      assert status["supportedKinds"] ==
               Enum.map(supported, &%{"group" => "gateway.networking.k8s.io", "kind" => &1}),
             name

      resolved = condition(status, "ResolvedRefs")
      resolved_status = if reason == "ResolvedRefs", do: "True", else: "False"
      assert {resolved["status"], resolved["reason"]} == {resolved_status, reason}, name
      assert condition(status, "Accepted")["status"] == "True", name
      assert condition(status, "Programmed")["status"] == "True", name
    end
  end

  test "a route of a kind its listener does not support does not attach" do
    listener = %{
      "name" => "http",
      "port" => 80,
      "protocol" => "HTTP",
      "allowedRoutes" => %{"kinds" => [%{"kind" => "TCPRoute"}, %{"kind" => "HTTPRoute"}]}
    }

    entries =
      entries([
        Fixtures.gateway_class(),
        Fixtures.gateway(listeners: [listener]),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route(),
        Fixtures.service(name: "db-svc", port: 5432),
        Fixtures.tcp_route()
      ])

    gw = entry(entries, Gvk.gateway(), "demo")
    assert %{"status" => "True", "reason" => "Accepted"} = condition(gw.status, "Accepted")
    assert [%{"attachedRoutes" => 1}] = gw.status["listeners"]

    [http_parent] = entry(entries, Gvk.http_route(), "app").status["parents"]
    assert %{"status" => "True"} = condition(http_parent, "Accepted")

    [tcp_parent] = entry(entries, Gvk.tcp_route(), "db").status["parents"]

    assert %{"status" => "False", "reason" => "NotAllowedByListeners"} =
             condition(tcp_parent, "Accepted")
  end

  test "a certificateRef reason takes precedence over InvalidRouteKinds" do
    for {ref, reason, programmed} <- [
          {%{"name" => "missing-cert"}, "InvalidCertificateRef", "False"},
          {%{"name" => "app-cert"}, "InvalidRouteKinds", "True"}
        ] do
      gateway =
        [certificate_refs: [ref]]
        |> Fixtures.https_gateway()
        |> put_in(
          ["spec", "listeners", Access.at(0), "allowedRoutes", "kinds"],
          [%{"kind" => "InvalidRoute"}]
        )

      entries =
        entries([Fixtures.gateway_class(), gateway, Fixtures.tls_secret(name: "app-cert")])

      [listener] = entry(entries, Gvk.gateway(), "demo").status["listeners"]
      assert condition(listener, "ResolvedRefs")["reason"] == reason
      assert condition(listener, "Programmed")["status"] == programmed
    end
  end

  test "a Gateway whose parametersRef is unsupported or missing is rejected" do
    for {group, kind, name, rejection} <- [
          {"invalid.io", "InvalidParameters", "invalid",
           "parametersRef kind must be arion.io/ArionGatewayParameters"},
          {"arion.io", "ArionGatewayParameters", "missing",
           "ArionGatewayParameters default/missing not found"},
          {"arion.io", "ArionGatewayParameters", "arion-params", nil}
        ] do
      ref = %{"group" => group, "kind" => kind, "name" => name}
      gateway = put_in(Fixtures.gateway(), ["spec", "infrastructure"], %{"parametersRef" => ref})

      entries =
        entries([
          Fixtures.gateway_class(),
          gateway,
          Fixtures.gateway_params(),
          Fixtures.provisioned_deployment(ready_replicas: 1)
        ])

      gw = entry(entries, Gvk.gateway(), "demo")
      [listener] = gw.status["listeners"]

      if rejection do
        assert %{"status" => "False", "reason" => "InvalidParameters", "message" => ^rejection} =
                 condition(gw.status, "Accepted")

        assert %{"status" => "False", "reason" => "Invalid"} = condition(gw.status, "Programmed")
        assert %{"status" => "False"} = condition(listener, "Programmed")
      else
        assert %{"status" => "True"} = condition(gw.status, "Accepted")
        assert %{"status" => "True"} = condition(gw.status, "Programmed")
        assert %{"status" => "True"} = condition(listener, "Programmed")
      end
    end
  end

  @invalid_listener %{"name" => "invalid", "port" => 1111, "protocol" => "INVALID"}

  test "a Gateway with only unsupported listeners is not Accepted or Programmed" do
    entries =
      entries([
        Fixtures.gateway_class(),
        Fixtures.gateway(listeners: [@invalid_listener]),
        Fixtures.provisioned_deployment(ready_replicas: 1)
      ])

    gw = entry(entries, Gvk.gateway(), "demo")

    assert %{"status" => "False", "reason" => "ListenersNotValid"} =
             condition(gw.status, "Accepted")

    assert %{"status" => "False", "reason" => "Invalid"} = condition(gw.status, "Programmed")

    assert [%{"name" => "invalid", "supportedKinds" => [], "attachedRoutes" => 0} = listener] =
             gw.status["listeners"]

    assert %{"status" => "False", "reason" => "UnsupportedProtocol"} =
             condition(listener, "Accepted")
  end

  test "a Gateway with a supported listener stays Accepted and names the invalid ones" do
    http = %{"name" => "http", "port" => 80, "protocol" => "HTTP"}

    entries =
      entries([
        Fixtures.gateway_class(),
        Fixtures.gateway(listeners: [http, @invalid_listener]),
        Fixtures.provisioned_deployment(ready_replicas: 1)
      ])

    gw = entry(entries, Gvk.gateway(), "demo")

    assert %{
             "status" => "True",
             "reason" => "ListenersNotValid",
             "message" => "Invalid listeners: invalid"
           } = condition(gw.status, "Accepted")

    assert %{"status" => "True", "reason" => "Programmed"} = condition(gw.status, "Programmed")

    [http_status, _invalid] = gw.status["listeners"]
    assert %{"status" => "True", "reason" => "Accepted"} = condition(http_status, "Accepted")
  end

  test "a Gateway whose Service lost its load-balancer address has it cleared" do
    objects = [Fixtures.gateway_class(), Fixtures.gateway(), Fixtures.provisioned_service()]
    written = with_status(objects, entries(objects))

    assert [%{"status" => %{"addresses" => [_]}}] =
             Enum.filter(written, &(&1["kind"] == "Gateway"))

    assert [gw] = changed(Enum.reject(written, &(&1["kind"] == "Service")), "now")
    assert gw.status["addresses"] == []
  end

  test "a GatewayClass with an invalid parametersRef and its Gateways are not accepted" do
    ref = %{"group" => "arion.io", "kind" => "ArionGatewayParameters", "name" => "arion-params"}

    for {params_ref, message} <- [
          {%{ref | "kind" => "ConfigMap"},
           "parametersRef kind must be arion.io/ArionGatewayParameters"},
          {ref, "parametersRef must have a namespace"},
          {Map.put(ref, "namespace", "other"),
           "ArionGatewayParameters other/arion-params not found"},
          {Map.put(ref, "namespace", "default"), nil}
        ] do
      entries =
        entries([
          Fixtures.gateway_class(params_ref: params_ref),
          Fixtures.gateway(),
          Fixtures.gateway_params(),
          Fixtures.provisioned_deployment(ready_replicas: 1)
        ])

      class = entry(entries, Gvk.gateway_class(), "arion")
      gw = entry(entries, Gvk.gateway(), "demo")

      if message do
        gateway_message = "GatewayClass arion: #{message}"

        assert %{"status" => "False", "reason" => "InvalidParameters", "message" => ^message} =
                 condition(class.status, "Accepted")

        assert %{
                 "status" => "False",
                 "reason" => "InvalidParameters",
                 "message" => ^gateway_message
               } =
                 condition(gw.status, "Accepted")

        assert %{"status" => "False", "reason" => "Invalid"} = condition(gw.status, "Programmed")
      else
        assert %{"status" => "True", "reason" => "Accepted"} = condition(class.status, "Accepted")
        assert %{"status" => "True", "reason" => "Accepted"} = condition(gw.status, "Accepted")

        assert %{"status" => "True", "reason" => "Programmed"} =
                 condition(gw.status, "Programmed")
      end
    end
  end
end
