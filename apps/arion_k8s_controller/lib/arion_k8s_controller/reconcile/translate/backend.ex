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

defmodule Arion.K8sController.Reconcile.Translate.Backend do
  @moduledoc """
  Turns resolved backends into Arion EDS clusters with their endpoint
  assignments, and backendRefs into weighted cluster pairs.
  """

  alias Arion.ControlPlane.Helpers.{Cluster, Endpoint}
  alias Arion.K8sController.Ir

  # Must never name a translated cluster: requests routed to it have to fail.
  @invalid_cluster "arion.invalid-backend"

  def invalid_cluster, do: @invalid_cluster

  @doc """
  Positive-weight `{cluster, weight}` pairs, or `[]` when no resolved backend
  carries weight. Unresolved backends keep their combined share under
  `invalid_cluster/0`.
  """
  def weighted_clusters(backends) do
    {resolved, unresolved} =
      backends |> Enum.filter(&(&1.weight > 0)) |> Enum.split_with(& &1.resolved?)

    pairs = Enum.map(resolved, &{&1.cluster_name, &1.weight})
    invalid_weight = Enum.sum_by(unresolved, & &1.weight)

    cond do
      resolved == [] -> []
      invalid_weight == 0 -> pairs
      true -> pairs ++ [{@invalid_cluster, invalid_weight}]
    end
  end

  @doc """
  True for a routable InferencePool backend, whose endpoint picker chooses the
  upstream. A weight-0 pool receives no traffic, so it must not pick endpoints.
  """
  def inference?(%Ir.Backend{inference?: true, resolved?: true, epp: epp, weight: weight})
      when not is_nil(epp) and weight > 0,
      do: true

  def inference?(_backend), do: false

  @doc """
  The backend's EDS cluster, speaking its `protocol`. Not `Cluster.eds/2`: the
  proxy rejects eds_cluster_config; its EDS always comes over ADS.
  """
  def eds_cluster(%Ir.Backend{cluster_name: name, protocol: protocol}) do
    name |> Cluster.new(discovery: :eds) |> maybe_http2(protocol)
  end

  # The proxy rejects an assignment without endpoints, so such a cluster gets none.
  def to_load_assignment(%Ir.Backend{resolved?: true, endpoints: [_ | _]} = backend) do
    lb_endpoints = for {address, port} <- backend.endpoints, do: Endpoint.lb(address, port)
    Endpoint.assignment(backend.cluster_name, lb_endpoints)
  end

  def to_load_assignment(_backend), do: nil

  defp maybe_http2(cluster, :http1), do: cluster

  defp maybe_http2(cluster, :http2),
    do: Cluster.put_http_protocol_options(cluster, Cluster.http2_options())
end
