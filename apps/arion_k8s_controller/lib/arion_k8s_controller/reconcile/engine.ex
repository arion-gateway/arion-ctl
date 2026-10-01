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

defmodule Arion.K8sController.Reconcile.Engine do
  @moduledoc """
  Orchestrates the reconcile pipeline.

  Store pokes, resync ticks and fleet restarts are debounced, then each replica
  computes and publishes deterministic xDS locally:

      snapshot -> Resolver.resolve -> Translator.translate -> Service.replace

  Every translated fleet is replaced with its full translated view.
  `Service.replace` diffs against the live fleet cache, so an unchanged
  recompute publishes nothing and a restarted fleet is repopulated. A Gateway
  fleet that is no longer translated is retired: emptied, and stopped once no
  proxy is subscribed to it.

  The periodic resync makes every watcher list again, converging events a watch
  missed, then recomputes. Only the elected leader writes Kubernetes status and
  provisions data planes. Publishing, status and provisioning wait until the
  Store is synced. The `:serve` MFA (the xDS server) and the `:lead` MFA
  (joining the leader election) are started after the first publish.
  """

  use GenServer
  require Logger

  alias Arion.ControlPlane.Service
  alias Arion.K8sController.Deployer.Deployer
  alias Arion.K8sController.Ir
  alias Arion.K8sController.Kube.WatchSupervisor
  alias Arion.K8sController.Reconcile.{Resolver, Translator}
  alias Arion.K8sController.Status.{Conditions, StatusWriter}
  alias Arion.K8sController.Store

  defstruct [
    :config,
    :store,
    :status_writer,
    :deployer,
    # MFAs started after the first complete publish, then nil.
    :serve,
    :lead,
    leader?: false,
    flush_timer: nil,
    deadline: nil,
    # Fleet process monitor ref => fleet.
    monitors: %{}
  ]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def reconcile_now(server \\ __MODULE__), do: GenServer.call(server, :reconcile_now)

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    Process.send_after(self(), :resync, config.resync_interval_ms)

    {:ok,
     %__MODULE__{
       config: config,
       store: Keyword.get(opts, :store, Store),
       status_writer: Keyword.get(opts, :status_writer, StatusWriter),
       deployer: Keyword.get(opts, :deployer, Deployer),
       serve: Keyword.get(opts, :serve),
       lead: Keyword.get(opts, :lead)
     }}
  end

  @impl true
  def handle_info(:dirty, state), do: {:noreply, schedule_flush(state)}

  def handle_info(:resync, state) do
    Logger.debug("arion_k8s_controller: periodic resync")
    WatchSupervisor.relist()
    Process.send_after(self(), :resync, state.config.resync_interval_ms)
    {:noreply, schedule_flush(state)}
  end

  def handle_info(:flush, state) do
    state = %{state | flush_timer: nil, deadline: nil}
    {:noreply, run_pipeline(state)}
  end

  # The workers learn of the change before the reconcile it schedules reaches them.
  def handle_info({:leadership, :acquired}, state) do
    Logger.info("arion_k8s_controller: leadership acquired")
    signal_leadership(state, :acquired)
    {:noreply, schedule_flush(%{state | leader?: true})}
  end

  def handle_info({:leadership, :lost}, state) do
    Logger.warning("arion_k8s_controller: leadership lost")
    signal_leadership(state, :lost)
    {:noreply, %{state | leader?: false}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if Map.has_key?(state.monitors, ref),
      do: {:noreply, schedule_flush(state)},
      else: {:noreply, state}
  end

  @impl true
  def handle_call(:reconcile_now, _from, state), do: {:reply, :ok, run_pipeline(state)}

  defp schedule_flush(%{flush_timer: nil} = state) do
    deadline = now_ms() + state.config.debounce_max_ms
    timer = Process.send_after(self(), :flush, state.config.debounce_ms)
    %{state | flush_timer: timer, deadline: deadline}
  end

  defp schedule_flush(%{flush_timer: timer, deadline: deadline} = state) do
    # An already fired timer has queued its :flush, which covers this change.
    if Process.cancel_timer(timer) do
      delay = max(0, min(state.config.debounce_ms, deadline - now_ms()))
      %{state | flush_timer: Process.send_after(self(), :flush, delay)}
    else
      state
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp signal_leadership(state, event) do
    Deployer.leadership(state.deployer, event)
    StatusWriter.leadership(state.status_writer, event)
  end

  defp run_pipeline(state), do: if(Store.synced?(state.store), do: reconcile(state), else: state)

  defp reconcile(state) do
    snapshot = Store.snapshot(state.store)
    graph = Resolver.resolve(snapshot, state.config.controller_name)

    state =
      state
      |> publish(Translator.translate(graph))
      |> start(:serve, "xDS server")
      |> start(:lead, "leader election")

    if state.leader? do
      graph
      |> Conditions.compute()
      |> Conditions.changed(snapshot)
      |> then(&StatusWriter.enqueue(state.status_writer, &1))

      Deployer.reconcile(state.deployer, graph, snapshot)
    end

    state
  rescue
    error ->
      Logger.error("arion_k8s_controller: reconcile failed: #{Exception.message(error)}")
      state
  end

  defp publish(state, xds) do
    Enum.each(Map.keys(state.monitors), &Process.demonitor(&1, [:flush]))

    # Only this controller's Gateway fleets are retired: a shared control plane
    # may serve other fleets. Retired fleets are not monitored: one exits
    # normally, and a restarted one would be empty anyway.
    for fleet <- Service.list_fleets(),
        Ir.Gateway.fleet?(fleet),
        not Map.has_key?(xds, fleet),
        do: Service.retire(fleet)

    monitors =
      Map.new(xds, fn {fleet, by_kind} ->
        ref = Process.monitor(Service.ensure(fleet))

        resources =
          for {kind, by_name} <- by_kind, resource <- Map.values(by_name), do: {kind, resource}

        # A fleet that dies during the replace is republished on its DOWN.
        try do
          :ok = Service.replace(fleet, resources)
        catch
          :exit, _ -> :ok
        end

        {ref, fleet}
      end)

    %{state | monitors: monitors}
  end

  # Proxies reconnect listing the resources they hold, so an empty fleet would
  # remove them; an unsynced leader would stall status and provisioning.
  defp start(state, key, what) do
    case Map.fetch!(state, key) do
      nil ->
        state

      {m, f, a} ->
        case apply(m, f, a) do
          :ok ->
            Logger.info("arion_k8s_controller: #{what} started")
            Map.put(state, key, nil)

          # Not raised: the rescue returns the pre-publish state, losing the new monitors.
          {:error, reason} ->
            Logger.error("arion_k8s_controller: #{what} failed to start: #{inspect(reason)}")
            state
        end
    end
  end
end
