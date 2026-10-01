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

defmodule Arion.K8sController.Election.Leader do
  @moduledoc """
  Cluster-wide leadership as a BEAM singleton, without Kubernetes Leases.

  Highlander keeps one process alive across the cluster. The leader signals only
  its local Engine, so one replica writes status and provisions while all
  replicas keep serving xDS. A replica's Engine joins the election
  (`start_candidate/0`) after its first complete publish, so an unsynced replica
  never leads.

  Transient split-brain is tolerated because status patches and server-side
  apply converge on the same object state.
  """

  use GenServer

  alias Arion.K8sController.Reconcile.Engine

  defstruct [:engine]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Joins the election for the calling Engine. The candidacy is linked to the
  Engine: each ends the other. Highlander stops the candidate on every
  name conflict a netsplit heal produces, so the restart budget is generous.
  """
  def start_candidate do
    children = [{Highlander, {__MODULE__, engine: self()}}]

    case Supervisor.start_link(children,
           strategy: :one_for_one,
           max_restarts: 20,
           max_seconds: 60
         ) do
      {:ok, _pid} -> :ok
      error -> error
    end
  end

  @impl true
  def init(opts) do
    engine = Keyword.get(opts, :engine, Engine)
    Process.flag(:trap_exit, true)
    signal(engine, :acquired)
    {:ok, %__MODULE__{engine: engine}}
  end

  @impl true
  def terminate(_reason, state) do
    signal(state.engine, :lost)
    :ok
  end

  defp signal(engine, event) do
    pid = if is_pid(engine), do: engine, else: Process.whereis(engine)
    if pid, do: send(pid, {:leadership, event})
  end
end
