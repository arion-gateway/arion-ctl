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

defmodule Arion.K8sController.Reconcile.Translate.L4 do
  @moduledoc """
  Builds TCP listeners and the SNI chains of TLS listeners from attached L4
  routes.
  """

  alias Arion.ControlPlane.Helpers.{FilterChain, Listener, TcpProxy}
  alias Arion.K8sController.Ir
  alias Arion.K8sController.Reconcile.Translate.{Backend, Tls}

  def tcp(name, port, attached_routes) do
    backends = Enum.flat_map(attached_routes, &Ir.Route.backends/1)
    chain = FilterChain.new(name) |> FilterChain.add_filter(tcp_proxy(name, backends))
    Listener.new(name, Listener.local_address(port)) |> Listener.add_filter_chain(chain)
  end

  @doc """
  One SNI chain per server name of the listener's routes, oldest route first. A
  route without hostnames on a listener without one takes the default chain,
  since the proxy rejects a "*" server name. A Terminate listener's chains
  terminate TLS with its certificate; Passthrough chains forward it unread.
  """
  def sni_chains(name, %Ir.Listener{} = listener) do
    routes =
      Enum.sort_by(listener.attached_routes, &{&1.creation_ts || "", &1.namespace, &1.name})

    for entry <- routes, domain <- entry.domains do
      chain_name = "#{name}-#{listener.name}-#{domain}"

      FilterChain.new(chain_name)
      |> sni(domain)
      |> FilterChain.put_transport_socket(Tls.transport_socket(listener))
      |> FilterChain.add_filter(tcp_proxy(chain_name, Ir.Route.backends(entry)))
    end
  end

  defp sni(chain, "*"), do: chain
  defp sni(chain, domain), do: FilterChain.put_match(chain, FilterChain.server_names([domain]))

  defp tcp_proxy(stat_prefix, backends) do
    case Backend.weighted_clusters(backends) do
      [{cluster, _weight}] -> TcpProxy.filter(cluster, stat_prefix)
      [] -> TcpProxy.filter(Backend.invalid_cluster(), stat_prefix)
      many -> TcpProxy.weighted(many, stat_prefix)
    end
  end
end
