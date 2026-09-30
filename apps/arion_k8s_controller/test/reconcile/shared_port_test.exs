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

defmodule Arion.K8sController.Reconcile.SharedPortTest do
  use ExUnit.Case, async: true

  alias Arion.ControlPlane.Pb.Data.Extensions.DownstreamTlsContext
  alias Arion.ControlPlane.Pb.Filter.TcpProxy
  alias Arion.ControlPlane.Pb.Listener.FilterChainMatch
  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.{Resolver, Translator}
  alias Arion.K8sController.Status.Conditions

  defp resolve(objects),
    do: objects |> Fixtures.snapshot() |> Resolver.resolve(Fixtures.controller_name())

  defp translate(objects),
    do: objects |> resolve() |> Translator.translate() |> Map.get("gateway/default/demo")

  defp gateway_status(objects) do
    objects
    |> resolve()
    |> Conditions.compute("2026-06-30T00:00:00Z")
    |> Enum.find(&(&1.gvk == Gvk.gateway()))
    |> Map.fetch!(:status)
  end

  defp listener_status(gateway_status, name),
    do: Enum.find(gateway_status["listeners"], &(&1["name"] == name))

  defp condition(status, type), do: Enum.find(status["conditions"], &(&1["type"] == type))

  defp listener(name, protocol, port, hostname \\ nil) do
    tls =
      case protocol do
        "HTTPS" -> %{"certificateRefs" => [%{"name" => "app-cert"}]}
        "TLS" -> %{"mode" => "Passthrough"}
        _ -> nil
      end

    %{
      "name" => name,
      "protocol" => protocol,
      "port" => port,
      "hostname" => hostname,
      "tls" => tls
    }
  end

  # A TLSRoute to the Service named like the route, so each chain's cluster names its route.
  defp tls_route(name, hostnames, created \\ "2026-01-01T00:00:00Z") do
    Fixtures.tls_route(name: name, hostnames: hostnames)
    |> put_in(["metadata", "creationTimestamp"], created)
    |> put_in(["spec", "rules"], [%{"backendRefs" => [%{"name" => name, "port" => 8443}]}])
  end

  defp services(names), do: Enum.map(names, &Fixtures.service(name: &1, port: 8443))

  defp server_names(%{filter_chain_match: nil}), do: nil
  defp server_names(chain), do: chain.filter_chain_match.server_names

  defp tcp_cluster(chain) do
    [%{name: "envoy.filters.network.tcp_proxy", config_type: {:typed_config, any}}] =
      chain.filters

    {:cluster, cluster} = TcpProxy.decode(any.value).cluster_specifier
    cluster
  end

  # What the proxy would reject or split: two listeners on one port, a listener
  # without chains, equal or "*" matches, SNI without a tls_inspector, and an
  # empty tcp_proxy cluster.
  defp assert_proxy_valid(resources) do
    listeners = Map.values(resources.listener)

    ports =
      Enum.map(listeners, fn %{address: %{address: {:socket_address, a}}} -> a.port_specifier end)

    assert ports == Enum.uniq(ports)

    for listener <- listeners do
      assert listener.filter_chains != []
      matches = Enum.map(listener.filter_chains, &(&1.filter_chain_match || %FilterChainMatch{}))
      assert matches == Enum.uniq(matches)

      names = Enum.flat_map(matches, & &1.server_names)
      refute "*" in names
      listener_filters = Enum.map(listener.listener_filters, & &1.name)
      assert names == [] or "envoy.filters.listener.tls_inspector" in listener_filters

      for chain <- listener.filter_chains,
          %{name: "envoy.filters.network.tcp_proxy", config_type: {:typed_config, any}} <-
            chain.filters do
        refute TcpProxy.decode(any.value).cluster_specifier == {:cluster, ""}
      end
    end

    resources
  end

  test "HTTPS and TLS passthrough listeners on a port share one TLS listener" do
    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(
          listeners: [
            listener("https", "HTTPS", 443, "app.example.com"),
            listener("tls-a", "TLS", 443, "a.example.com"),
            listener("tls-b", "TLS", 443, "b.example.com")
          ]
        ),
        Fixtures.tls_secret(name: "app-cert"),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route(),
        tls_route("a", ["a.example.com"]),
        tls_route("b", ["b.example.com"]) | services(["a", "b"])
      ])
      |> assert_proxy_valid()

    assert [{"default-demo-443", listener}] = Map.to_list(resources.listener)
    assert [%{name: "envoy.filters.listener.tls_inspector"}] = listener.listener_filters
    assert [app, a, b] = listener.filter_chains

    assert Enum.map([app, a, b], &server_names/1) ==
             [["app.example.com"], ["a.example.com"], ["b.example.com"]]

    assert app.transport_socket.name == "envoy.transport_sockets.tls"
    assert [%{name: "envoy.filters.network.http_connection_manager"}] = app.filters
    assert {a.transport_socket, tcp_cluster(a)} == {nil, "svc:default/a:8443"}
    assert {b.transport_socket, tcp_cluster(b)} == {nil, "svc:default/b:8443"}
  end

  test "a more specific listener keeps a server name a catch-all passthrough route claims" do
    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(
          listeners: [
            listener("tls", "TLS", 443),
            listener("https", "HTTPS", 443, "app.example.com")
          ]
        ),
        Fixtures.tls_secret(name: "app-cert"),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route(),
        tls_route("z", ["app.example.com", "z.example.com"]) | services(["z"])
      ])
      |> assert_proxy_valid()

    assert [app, z] = resources.listener["default-demo-443"].filter_chains
    assert server_names(app) == ["app.example.com"]
    assert app.transport_socket.name == "envoy.transport_sockets.tls"
    assert {server_names(z), tcp_cluster(z)} == {["z.example.com"], "svc:default/z:8443"}
  end

  test "an HTTPS listener without a usable certificate leaves its port to passthrough" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(
        listeners: [
          listener("https", "HTTPS", 443, "app.example.com"),
          listener("tls", "TLS", 443, "a.example.com")
        ]
      ),
      Fixtures.service(name: "app-svc"),
      Fixtures.http_route(),
      tls_route("a", ["a.example.com"]) | services(["a"])
    ]

    resources = objects |> translate() |> assert_proxy_valid()
    refute Map.has_key?(resources, :secret)
    assert [chain] = resources.listener["default-demo-443"].filter_chains
    assert {server_names(chain), tcp_cluster(chain)} == {["a.example.com"], "svc:default/a:8443"}

    status = gateway_status(objects)
    https = listener_status(status, "https")
    assert %{"status" => "True", "reason" => "Accepted"} = condition(https, "Accepted")
    assert %{"status" => "False", "reason" => "Invalid"} = condition(https, "Programmed")
    tls = listener_status(status, "tls")
    assert %{"status" => "True", "reason" => "Programmed"} = condition(tls, "Programmed")
  end

  # The snapshot lists "new" before "old", so only creation time can make "old" win.
  test "the oldest TLSRoute keeps a contested server name" do
    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.tls_passthrough_gateway(),
        tls_route("new", ["a.example.com"], "2026-02-01T00:00:00Z"),
        tls_route("old", ["a.example.com"]) | services(["new", "old"])
      ])
      |> assert_proxy_valid()

    assert [chain] = resources.listener["default-demo-443"].filter_chains

    assert {server_names(chain), tcp_cluster(chain)} ==
             {["a.example.com"], "svc:default/old:8443"}
  end

  test "a passthrough route without hostnames takes the default chain" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.tls_passthrough_gateway(),
      tls_route("old", []) | services(["new", "old"])
    ]

    for objects <- [objects, [tls_route("new", [], "2026-02-01T00:00:00Z") | objects]] do
      resources = objects |> translate() |> assert_proxy_valid()
      assert [chain] = resources.listener["default-demo-443"].filter_chains
      assert {server_names(chain), tcp_cluster(chain)} == {nil, "svc:default/old:8443"}
    end
  end

  test "a TLS passthrough port without routes is not bound but stays programmed" do
    objects = [Fixtures.gateway_class(), Fixtures.tls_passthrough_gateway()]
    assert translate(objects) == nil

    tls = objects |> gateway_status() |> listener_status("tls")
    assert %{"status" => "True", "reason" => "Accepted"} = condition(tls, "Accepted")
    assert %{"status" => "True", "reason" => "Programmed"} = condition(tls, "Programmed")

    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(
          listeners: [
            listener("tls", "TLS", 443),
            listener("https", "HTTPS", 443, "app.example.com")
          ]
        ),
        Fixtures.tls_secret(name: "app-cert")
      ])
      |> assert_proxy_valid()

    assert [chain] = resources.listener["default-demo-443"].filter_chains
    assert server_names(chain) == ["app.example.com"]
  end

  test "proxy listeners are named by port, not by Gateway listener" do
    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(
          listeners: [listener("8080", "TCP", 5432), listener("http", "HTTP", 8080)]
        )
      ])
      |> assert_proxy_valid()

    assert Map.keys(resources.listener) == ["default-demo-5432", "default-demo-8080"]
    assert [tcp] = resources.listener["default-demo-5432"].filter_chains
    assert tcp_cluster(tcp) == "arion.invalid-backend"
    assert [http] = resources.listener["default-demo-8080"].filter_chains
    assert [%{name: "envoy.filters.network.http_connection_manager"}] = http.filters
  end

  test "mixed protocols on a port are ProtocolConflict and not translated" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(
        listeners: [
          listener("tcp", "TCP", 80),
          listener("http", "HTTP", 80),
          listener("web", "HTTP", 8080)
        ]
      ),
      Fixtures.provisioned_deployment(ready_replicas: 1),
      Fixtures.service(name: "db-svc", port: 5432),
      Fixtures.tcp_route(),
      Fixtures.service(name: "app-svc"),
      Fixtures.http_route()
    ]

    resources = objects |> translate() |> assert_proxy_valid()
    assert Map.keys(resources.listener) == ["default-demo-8080"]
    assert Map.keys(resources.cluster) == ["svc:default/app-svc:8080"]

    status = gateway_status(objects)

    assert %{
             "status" => "True",
             "reason" => "ListenersNotValid",
             "message" => "Invalid listeners: tcp, http"
           } = condition(status, "Accepted")

    assert %{"status" => "True", "reason" => "Programmed"} = condition(status, "Programmed")

    for name <- ["tcp", "http"] do
      listener = listener_status(status, name)
      assert listener["attachedRoutes"] == 1

      assert %{"status" => "False", "reason" => "ProtocolConflict"} =
               condition(listener, "Accepted")

      assert %{"status" => "True", "reason" => "ProtocolConflict"} =
               condition(listener, "Conflicted")

      assert %{"status" => "True", "reason" => "ResolvedRefs"} =
               condition(listener, "ResolvedRefs")

      assert %{"status" => "False", "reason" => "ProtocolConflict"} =
               condition(listener, "Programmed")
    end

    web = listener_status(status, "web")
    assert %{"status" => "True", "reason" => "Accepted"} = condition(web, "Accepted")
    assert condition(web, "Conflicted") == nil
  end

  test "HTTP and HTTPS on one port conflict, leaving the Gateway without valid listeners" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(
        listeners: [
          listener("http", "HTTP", 443),
          listener("https", "HTTPS", 443, "app.example.com")
        ]
      ),
      Fixtures.tls_secret(name: "app-cert"),
      Fixtures.provisioned_deployment(ready_replicas: 1)
    ]

    assert translate(objects) == nil

    status = gateway_status(objects)

    assert %{"status" => "False", "reason" => "ListenersNotValid"} =
             condition(status, "Accepted")

    assert %{"status" => "False", "reason" => "Invalid"} = condition(status, "Programmed")

    for name <- ["http", "https"] do
      assert %{"status" => "True", "reason" => "ProtocolConflict"} =
               status |> listener_status(name) |> condition("Conflicted")
    end
  end

  test "HTTPS and TLS listeners sharing a hostname are HostnameConflict" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(
        listeners: [
          listener("https-a", "HTTPS", 443, "a.example.com"),
          listener("tls-a", "TLS", 443, "a.example.com"),
          listener("https-b", "HTTPS", 443, "b.example.com")
        ]
      ),
      Fixtures.tls_secret(name: "app-cert")
    ]

    resources = objects |> translate() |> assert_proxy_valid()
    assert [chain] = resources.listener["default-demo-443"].filter_chains
    assert server_names(chain) == ["b.example.com"]

    status = gateway_status(objects)

    for name <- ["https-a", "tls-a"] do
      listener = listener_status(status, name)

      assert %{"status" => "False", "reason" => "HostnameConflict"} =
               condition(listener, "Accepted")

      assert %{"status" => "True", "reason" => "HostnameConflict"} =
               condition(listener, "Conflicted")
    end

    https_b = listener_status(status, "https-b")
    assert %{"status" => "True", "reason" => "Accepted"} = condition(https_b, "Accepted")
    assert condition(https_b, "Conflicted") == nil

    no_hostnames = [
      Fixtures.gateway_class(),
      Fixtures.gateway(listeners: [listener("https", "HTTPS", 443), listener("tls", "TLS", 443)]),
      Fixtures.tls_secret(name: "app-cert")
    ]

    assert translate(no_hostnames) == nil

    for listener <- gateway_status(no_hostnames)["listeners"] do
      assert %{"status" => "True", "reason" => "HostnameConflict"} =
               condition(listener, "Conflicted")
    end
  end

  test "HTTPS listeners whose hostnames overlap on a port get OverlappingTLSConfig" do
    status =
      gateway_status([
        Fixtures.gateway_class(),
        Fixtures.gateway(
          listeners: [
            listener("any", "HTTPS", 443),
            listener("second", "HTTPS", 443, "second.example.org"),
            listener("wildcard", "HTTPS", 8443, "*.example.com"),
            listener("foo", "HTTPS", 8443, "foo.example.com"),
            listener("org", "HTTPS", 8443, "foo.example.org"),
            listener("tls", "TLS", 8443, "*.example.org"),
            listener("other-port", "HTTPS", 9443, "bar.example.com")
          ]
        ),
        Fixtures.tls_secret(name: "app-cert")
      ])

    overlapping =
      for l <- status["listeners"],
          c = condition(l, "OverlappingTLSConfig"),
          do: {l["name"], c["status"], c["reason"]}

    assert overlapping == [
             {"any", "True", "OverlappingHostnames"},
             {"second", "True", "OverlappingHostnames"},
             {"wildcard", "True", "OverlappingHostnames"},
             {"foo", "True", "OverlappingHostnames"}
           ]

    for listener <- status["listeners"] do
      assert %{"status" => "True", "reason" => "Accepted"} = condition(listener, "Accepted")
      assert %{"status" => "True", "reason" => "Programmed"} = condition(listener, "Programmed")
    end
  end

  test "TLS Terminate listeners terminate on SNI chains beside HTTPS and passthrough ones" do
    terminate = fn name, tls ->
      %{listener(name, "TLS", 8443, "#{name}.example.com") | "tls" => tls}
    end

    refs = %{"certificateRefs" => [%{"name" => "app-cert"}]}

    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(
        listeners: [
          listener("https", "HTTPS", 8443, "app.example.com"),
          terminate.("terminate", Map.put(refs, "mode", "Terminate")),
          # The CRD defaults the mode to Terminate.
          terminate.("default", refs),
          terminate.("uncertified", %{"certificateRefs" => [%{"name" => "missing"}]}),
          listener("passthrough", "TLS", 8443, "passthrough.example.com")
        ]
      ),
      Fixtures.tls_secret(name: "app-cert"),
      Fixtures.service(name: "app-svc"),
      Fixtures.http_route(),
      tls_route("t", [
        "terminate.example.com",
        "default.example.com",
        "uncertified.example.com",
        "passthrough.example.com"
      ])
      | services(["t"])
    ]

    resources = objects |> translate() |> assert_proxy_valid()
    assert Map.keys(resources.secret) == ["secret:default/app-cert"]
    assert [app, t, d, p] = resources.listener["default-demo-8443"].filter_chains

    assert Enum.map([app, t, d, p], &server_names/1) == [
             ["app.example.com"],
             ["terminate.example.com"],
             ["default.example.com"],
             ["passthrough.example.com"]
           ]

    assert [%{name: "envoy.filters.network.http_connection_manager"}] = app.filters

    for chain <- [t, d] do
      {:typed_config, any} = chain.transport_socket.config_type
      context = DownstreamTlsContext.decode(any.value).common_tls_context
      assert [%{name: "secret:default/app-cert"}] = context.tls_certificate_sds_secret_configs
      assert tcp_cluster(chain) == "svc:default/t:8443"
    end

    assert {p.transport_socket, tcp_cluster(p)} == {nil, "svc:default/t:8443"}

    status = gateway_status(objects)
    assert %{"status" => "True", "reason" => "Accepted"} = condition(status, "Accepted")

    for name <- ["terminate", "default"] do
      listener = listener_status(status, name)

      assert %{
               "supportedKinds" => [%{"kind" => "TLSRoute"}],
               "attachedRoutes" => 1
             } = listener

      assert %{"status" => "True", "reason" => "Accepted"} = condition(listener, "Accepted")

      assert %{"status" => "True", "reason" => "ResolvedRefs"} =
               condition(listener, "ResolvedRefs")

      assert %{"status" => "True", "reason" => "Programmed"} = condition(listener, "Programmed")
    end

    uncertified = listener_status(status, "uncertified")

    assert %{"status" => "False", "reason" => "InvalidCertificateRef"} =
             condition(uncertified, "ResolvedRefs")

    assert %{"status" => "False", "reason" => "Invalid"} = condition(uncertified, "Programmed")
  end

  test "TLS Terminate and Passthrough listeners sharing a hostname are HostnameConflict" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(
        listeners: [
          %{
            listener("terminate", "TLS", 443, "a.example.com")
            | "tls" => %{"certificateRefs" => [%{"name" => "app-cert"}]}
          },
          listener("passthrough", "TLS", 443, "a.example.com")
        ]
      ),
      Fixtures.tls_secret(name: "app-cert")
    ]

    assert translate(objects) == nil

    for listener <- gateway_status(objects)["listeners"] do
      assert %{"status" => "False", "reason" => "HostnameConflict"} =
               condition(listener, "Accepted")
    end
  end

  test "an unsupported listener never conflicts" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(listeners: [listener("tcp", "TCP", 53), listener("udp", "UDP", 53)])
    ]

    resources = objects |> translate() |> assert_proxy_valid()
    assert Map.keys(resources.listener) == ["default-demo-53"]

    status = gateway_status(objects)

    assert %{"status" => "True", "reason" => "ListenersNotValid"} =
             condition(status, "Accepted")

    tcp = listener_status(status, "tcp")
    assert %{"status" => "True", "reason" => "Accepted"} = condition(tcp, "Accepted")
    assert condition(tcp, "Conflicted") == nil

    assert %{"status" => "False", "reason" => "UnsupportedProtocol"} =
             status |> listener_status("udp") |> condition("Accepted")
  end
end
