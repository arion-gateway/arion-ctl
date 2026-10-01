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

defmodule Arion.K8sController.Runtime do
  @moduledoc """
  Builds the live controller supervision tree.

  Ordering matters: the control plane (fleet supervisor) and the `Store` come
  up before the `Engine`/`StatusWriter`, which come up before the
  `WatchSupervisor` so the first watch events have somewhere to land; the
  `Leader` (without HA) comes last. The control plane starts without its xDS
  server: the `Engine` starts it after its first publish of a fully listed
  store, so a restarted controller never serves empty fleets. In HA mode the
  `Engine` likewise joins the leader election only then, so an unsynced replica
  never leads.
  """

  use Supervisor

  require Logger

  alias Arion.K8sController.{Cluster, Config}
  alias Arion.K8sController.Deployer.Deployer
  alias Arion.K8sController.Kube.{Conn, Gvk, WatchSupervisor}
  alias Arion.K8sController.Reconcile.Engine
  alias Arion.K8sController.Status.StatusWriter
  alias Arion.K8sController.Store
  alias Arion.K8sController.Election.Leader

  def start_link(config), do: Supervisor.start_link(__MODULE__, config, name: __MODULE__)

  @impl true
  def init(config), do: Supervisor.init(children(config), strategy: :rest_for_one)

  @doc """
  Returns child specs for the live controller.

  If Kubernetes connection setup fails, pure pipeline processes still start.
  """
  def children(%Config{} = config) do
    conn =
      case Conn.build(config) do
        {:ok, conn} ->
          conn

        {:error, reason} ->
          Logger.error("arion_k8s_controller: could not build K8s connection: #{inspect(reason)}")
          nil
      end

    cluster_children(config) ++
      control_plane_child() ++
      [
        # Without a connection nothing is listed, so nothing is published or served.
        {Store, kinds: Gvk.all()},
        {StatusWriter, conn: conn},
        {Deployer, conn: conn, config: config},
        {Engine,
         config: config,
         serve: {Arion.ControlPlane, :serve, [[port: config.control_plane_port]]},
         lead: lead(config)}
      ] ++
      leader_children(config) ++
      watch_children(conn)
  end

  defp cluster_children(%Config{leader_election?: true} = config),
    do: [
      {Elixir.Cluster.Supervisor,
       [Cluster.topologies(config), [name: Arion.K8sController.ClusterSupervisor]]}
    ]

  defp cluster_children(_config), do: []

  defp lead(%Config{leader_election?: true}), do: {Leader, :start_candidate, []}
  defp lead(_config), do: nil

  defp leader_children(%Config{leader_election?: true}), do: []
  defp leader_children(_config), do: [{Leader, []}]

  defp control_plane_child do
    if Process.whereis(Arion.ControlPlane.Registry) do
      []
    else
      [
        %{
          id: :arion_control_plane,
          start: {Arion.ControlPlane, :start_link, [[serve?: false]]},
          type: :supervisor
        }
      ]
    end
  end

  defp watch_children(nil), do: []
  defp watch_children(conn), do: [{WatchSupervisor, conn: conn, store: Store}]
end
