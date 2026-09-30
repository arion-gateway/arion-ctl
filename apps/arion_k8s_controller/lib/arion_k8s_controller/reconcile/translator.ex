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

defmodule Arion.K8sController.Reconcile.Translator do
  @moduledoc """
  Translates a resolved `Ir.Graph` into Arion xDS resources for `Service.replace`.

  Each Gateway becomes its own fleet with clusters, endpoint
  assignments, secrets, and listeners grouped by resource kind/name. Only
  programmed listeners are translated, into one proxy listener per Gateway port.
  """

  alias Arion.ControlPlane.Xds.ResourceTypes
  alias Arion.K8sController.Ir
  alias Arion.K8sController.Reconcile.Translate.{Backend, Inference, L4, Listener, Tls}

  def translate(%Ir.Graph{gateways: gateways}) do
    for gateway <- gateways,
        is_nil(gateway.invalid_params),
        resources = translate_gateway(gateway),
        resources != %{},
        into: %{},
        do: {Ir.Gateway.fleet(gateway), resources}
  end

  defp translate_gateway(%Ir.Gateway{} = gateway) do
    listeners = Enum.filter(gateway.listeners, &Ir.Listener.programmed?/1)

    backends =
      listeners
      |> Enum.flat_map(& &1.attached_routes)
      |> Enum.flat_map(&Ir.Route.backends/1)
      |> Enum.filter(& &1.resolved?)

    assignments = backends |> Enum.map(&Backend.to_load_assignment/1) |> Enum.reject(&is_nil/1)

    %{}
    |> put_kind(:cluster, Enum.flat_map(backends, &clusters/1))
    |> put_kind(:load_assignment, assignments)
    |> put_kind(:secret, Tls.secrets(listeners))
    |> put_kind(:listener, build_listeners(gateway, listeners))
  end

  defp clusters(%Ir.Backend{inference?: true} = backend),
    do: [Inference.pool_cluster(backend), Inference.epp_cluster(backend)]

  defp clusters(%Ir.Backend{} = backend), do: [Backend.eds_cluster(backend)]

  # The proxy splits connections between listeners bound to one port and rejects
  # a listener without filter chains.
  defp build_listeners(gateway, listeners) do
    for {port, group} <- Enum.group_by(listeners, & &1.port),
        listener = build_port_listener(listener_name(gateway, port), port, group),
        listener.filter_chains != [],
        do: listener
  end

  defp build_port_listener(name, port, [%Ir.Listener{protocol: :http} | _] = group),
    do: Listener.http(name, port, group)

  defp build_port_listener(name, port, [%Ir.Listener{protocol: :tcp} | _] = group),
    do: L4.tcp(name, port, Enum.flat_map(group, & &1.attached_routes))

  defp build_port_listener(name, port, group), do: Listener.tls(name, port, group)

  defp put_kind(map, _kind, []), do: map

  # Backends sharing a cluster produce equal resources, which are shared; two
  # different resources under one name would publish an ambiguous configuration.
  defp put_kind(map, kind, resources) do
    by_name =
      Enum.reduce(resources, %{}, fn resource, acc ->
        name = ResourceTypes.resource_name!(resource)

        case acc do
          %{^name => ^resource} -> acc
          %{^name => _other} -> raise ArgumentError, "conflicting #{kind} resources named #{name}"
          _ -> Map.put(acc, name, resource)
        end
      end)

    Map.put(map, kind, by_name)
  end

  defp listener_name(%Ir.Gateway{namespace: ns, name: name}, port), do: "#{ns}-#{name}-#{port}"
end
