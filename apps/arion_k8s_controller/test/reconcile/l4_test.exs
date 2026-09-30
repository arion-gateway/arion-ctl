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

defmodule Arion.K8sController.Reconcile.L4Test do
  use ExUnit.Case, async: true

  alias Arion.ControlPlane.Pb.Filter.TcpProxy
  alias Arion.ControlPlane.Pb.Listener.Listener
  alias Arion.K8sController.{Fixtures, Ir}
  alias Arion.K8sController.Reconcile.{Resolver, Translator}
  alias Arion.K8sController.Reconcile.Translate.L4

  defp translate(objects) do
    objects
    |> Fixtures.snapshot()
    |> Resolver.resolve(Fixtures.controller_name())
    |> Translator.translate()
    |> Map.get("gateway/default/demo")
  end

  defp backend(name, weight, resolved? \\ true),
    do: %Ir.Backend{cluster_name: name, weight: weight, resolved?: resolved?}

  defp tcp_clusters(backends), do: cluster_specifier([%{rules: [%Ir.Rule{backends: backends}]}])

  defp cluster_specifier(attached_routes) do
    listener = L4.tcp("tcp", 5432, attached_routes)
    [%{filters: [%{config_type: {:typed_config, any}}]}] = listener.filter_chains
    TcpProxy.decode(any.value).cluster_specifier
  end

  defp weights({:weighted_clusters, wc}), do: Enum.map(wc.clusters, &{&1.name, &1.weight})

  test "TCPRoute becomes a TCP listener with a tcp_proxy filter and a cluster" do
    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.tcp_gateway(),
        Fixtures.service(name: "db-svc", port: 5432),
        Fixtures.tcp_route()
      ])

    assert Map.has_key?(resources.cluster, "svc:default/db-svc:5432")
    assert %{"default-demo-5432" => %Listener{} = listener} = resources.listener
    assert [chain] = listener.filter_chains
    assert [%{name: "envoy.filters.network.tcp_proxy"}] = chain.filters
  end

  test "TLSRoute becomes an SNI chain on the port's TLS listener" do
    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.tls_passthrough_gateway(),
        Fixtures.service(name: "tls-svc", port: 8443),
        Fixtures.tls_route()
      ])

    assert %{"default-demo-443" => %Listener{} = listener} = resources.listener
    assert [_tls_inspector] = listener.listener_filters
    assert [chain] = listener.filter_chains
    assert chain.filter_chain_match.server_names == ["secure.example.com"]
    assert [%{name: "envoy.filters.network.tcp_proxy"}] = chain.filters
  end

  test "TCP weights drop zero-weight backends" do
    assert tcp_clusters([backend("a", 1), backend("b", 0)]) == {:cluster, "a"}

    assert weights(tcp_clusters([backend("a", 70), backend("b", 30), backend("c", 0)])) ==
             [{"a", 70}, {"b", 30}]
  end

  test "unresolved TCP backends keep their share on a cluster that fails" do
    assert weights(tcp_clusters([backend("a", 1), backend("x", 2, false)])) ==
             [{"a", 1}, {"arion.invalid-backend", 2}]

    assert tcp_clusters([backend("x", 1, false)]) == {:cluster, "arion.invalid-backend"}
  end

  test "a TCP listener without routes proxies to a cluster that fails" do
    assert cluster_specifier([]) == {:cluster, "arion.invalid-backend"}
  end
end
