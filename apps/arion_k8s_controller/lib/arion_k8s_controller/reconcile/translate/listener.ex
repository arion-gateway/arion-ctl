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

defmodule Arion.K8sController.Reconcile.Translate.Listener do
  @moduledoc """
  Builds the HTTP and TLS Envoy listeners for Gateway listeners.

  HTTP listeners on a port share one HCM chain; HTTPS and TLS listeners on a
  port become the SNI chains of one TLS listener.
  """

  alias Arion.ControlPlane.Helpers.{FilterChain, Hcm, Listener, Xds}
  alias Arion.K8sController.Ir
  alias Arion.K8sController.Reconcile.Resolve.Hostname
  alias Arion.K8sController.Reconcile.Translate.{Backend, Http, Inference, L4, Tls}

  def http(name, port, group) do
    config = Http.http_config(name, group, {"http", port})
    chain = FilterChain.new(name) |> FilterChain.add_hcm(hcm(name, config, group))
    Listener.new(name, Listener.local_address(port)) |> Listener.add_filter_chain(chain)
  end

  @doc """
  One TLS listener for a port's HTTPS and TLS listeners, with at most one
  server name per chain. The proxy rejects duplicate matches and fails
  connections that match two chains equally, so a contested name goes to the
  most specific listener hostname, then the oldest route.
  """
  def tls(name, port, listeners) do
    https_group = Enum.filter(listeners, &(&1.protocol == :https))

    chains =
      listeners
      |> Enum.sort_by(&Hostname.rank(&1.hostname))
      |> Enum.flat_map(&tls_chains(name, &1, https_group))
      |> Enum.uniq_by(& &1.filter_chain_match)

    Listener.new(name, Listener.local_address(port))
    |> Listener.add_listener_filter(Listener.tls_inspector())
    |> Listener.put_filter_chains(chains)
  end

  defp tls_chains(name, %Ir.Listener{protocol: :https} = listener, https_group),
    do: [https_chain(name, listener, https_group)]

  defp tls_chains(name, %Ir.Listener{} = listener, _https_group),
    do: L4.sni_chains(name, listener)

  defp https_chain(name, %Ir.Listener{} = listener, https_group) do
    chain_name = "#{name}-#{listener.name}"
    config = Http.https_config(chain_name, listener, https_group, {"https", listener.port})

    FilterChain.new(chain_name)
    |> maybe_sni(listener.hostname)
    |> FilterChain.put_transport_socket(Tls.transport_socket(listener))
    |> FilterChain.add_hcm(hcm(chain_name, config, [listener]))
  end

  defp maybe_sni(chain, nil), do: chain

  defp maybe_sni(chain, hostname),
    do: FilterChain.put_match(chain, FilterChain.server_names([hostname]))

  defp hcm(name, route_config, group) do
    attached_routes = Enum.flat_map(group, & &1.attached_routes)

    Hcm.new(stat_prefix: name)
    |> Hcm.add_upgrade(:websocket)
    |> Hcm.route_config(route_config)
    |> maybe_cors(attached_routes)
    |> maybe_ext_proc(attached_routes)
  end

  # An empty policy matches no origin, so the chain-level filter is inert for
  # routes without their own CORS policy override.
  defp maybe_cors(hcm, attached_routes) do
    if Enum.any?(attached_routes, &route_uses_cors?/1) do
      inert = %Arion.ControlPlane.Pb.Data.Extensions.CorsPolicy{}
      Hcm.add_filter(hcm, Xds.http_filter(Http.cors_filter_name(), :cors_policy, inert))
    else
      hcm
    end
  end

  defp route_uses_cors?(entry),
    do: Enum.any?(entry.rules, fn rule -> Enum.any?(rule.filters, &match?({:cors, _}, &1)) end)

  defp maybe_ext_proc(hcm, attached_routes) do
    backends = Enum.flat_map(attached_routes, &Ir.Route.backends/1)

    case Enum.find(backends, &Backend.inference?/1) do
      nil -> hcm
      backend -> Hcm.add_filter(hcm, Inference.ext_proc_filter(backend.epp.cluster_name))
    end
  end
end
