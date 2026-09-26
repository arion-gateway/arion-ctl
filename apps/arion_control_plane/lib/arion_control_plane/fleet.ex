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

defmodule Arion.ControlPlane.Fleet do
  @moduledoc """
  The resource cache and subscribed streams of one fleet: the resources a proxy
  selects with its xDS `node.cluster`. One process per fleet, registered in
  `Arion.ControlPlane.Registry` under `Arion.ControlPlane.FleetSupervisor`.

  Processes start on demand through `Arion.ControlPlane.Service.ensure/1` and
  stop through `Arion.ControlPlane.Service.retire/1`. A retired process exits
  normally and is not restarted; a crashed one is, empty. Until its owner
  publishes again it refuses subscriptions, so a proxy reconnecting with the
  resources it holds is not told to remove them.
  """

  use GenServer, restart: :transient

  require Logger

  alias Arion.ControlPlane.AdsServer.StreamHandler
  alias Arion.ControlPlane.ResourceCache
  alias Arion.ControlPlane.Xds.ResourceTypes

  # Dependency order: a resource is published after what it refers to and
  # removed before it.
  @order [
    :secret,
    :cluster,
    :load_assignment,
    :listener,
    :route,
    :mcp_tool,
    :mcp_dynamic_server,
    :mcp_toolkit,
    :mcp_openapi_source
  ]

  defstruct [:name, :cache, subscribers: %{}, published?: false, retired?: false]

  def start_link(name), do: GenServer.start_link(__MODULE__, name, name: via(name))

  @doc "`:via` tuple addressing the process for `name` through the Registry."
  def via(name), do: {:via, Registry, {Arion.ControlPlane.Registry, name}}

  @impl true
  def init(name), do: {:ok, %__MODULE__{name: name, cache: ResourceCache.new()}}

  @impl true
  def handle_call({:replace, cache}, _from, state), do: {:reply, :ok, replace(state, cache)}

  # Unregistered before exiting, so ensure/1 starts a fresh process from here on.
  # A subscribe queued behind this call is dropped; its StreamHandler monitors
  # this pid and ends the stream, so the proxy resubscribes.
  def handle_call(:retire, _from, state) do
    state = replace(state, ResourceCache.new())

    if subscribed?(state) do
      {:reply, :kept, %{state | retired?: true}}
    else
      {:stop, :normal, :stopped, unregister(state)}
    end
  end

  def handle_call(:resources, _from, state) do
    {:reply, ResourceCache.resources(state.cache), state}
  end

  def handle_call(:acks, _from, state) do
    clients = state.subscribers |> Map.values() |> Enum.reduce(MapSet.new(), &MapSet.union/2)
    {:reply, Map.new(clients, &{&1, StreamHandler.acks(&1)}), state}
  end

  # Every subscription is a fleet-wide wildcard for its kind: the names a request
  # subscribes to or unsubscribes from are ignored, as is a repeated subscription.
  @impl true
  def handle_cast({:subscribe, client, type_url, initial_versions}, state) do
    case discovery_kind(type_url, state) do
      {:ok, kind} -> {:noreply, subscribe(state, kind, client, initial_versions)}
      :error -> {:noreply, state}
    end
  end

  def handle_cast({:push, kind, %ResourceCache.Entry{} = entry}, state) do
    cache = put_in(state.cache, [kind, entry.wire.name], entry)
    publish(state.subscribers, kind, [entry])

    if kind == :cluster,
      do: publish(state.subscribers, :load_assignment, reassigned(cache, [entry], []))

    {:noreply, %{state | cache: cache, published?: true, retired?: false}}
  end

  def handle_cast({:drop, kind, name}, state) do
    if ResourceCache.get(state.cache, kind, name),
      do: unpublish(state.subscribers, kind, [name])

    {:noreply, %{state | cache: ResourceCache.remove(state.cache, kind, name)}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subscribers =
      Map.new(state.subscribers, fn {kind, pids} -> {kind, MapSet.delete(pids, pid)} end)

    state = %{state | subscribers: subscribers}

    if state.retired? and not subscribed?(state),
      do: {:stop, :normal, unregister(state)},
      else: {:noreply, state}
  end

  defp subscribe(%__MODULE__{published?: false} = state, _kind, client, _initial_versions) do
    StreamHandler.unavailable(client, "fleet #{state.name} has nothing published yet")
    state
  end

  defp subscribe(state, kind, client, initial_versions) do
    if subscribed?(state, kind, client) do
      state
    else
      unless subscribed?(state, client), do: Process.monitor(client)
      replay(kind, client, ResourceCache.list(state.cache, kind), initial_versions)
      update_in(state.subscribers[kind], &MapSet.put(&1 || MapSet.new(), client))
    end
  end

  defp replace(%__MODULE__{cache: old, subscribers: subscribers} = state, new) do
    changed = Map.new(@order, &{&1, changed(old, new, &1)})

    changed =
      Map.update!(changed, :load_assignment, &(&1 ++ reassigned(new, changed.cluster, &1)))

    for kind <- @order, do: publish(subscribers, kind, changed[kind])

    for kind <- Enum.reverse(@order) do
      removed =
        for entry <- ResourceCache.list(old, kind),
            ResourceCache.get(new, kind, entry.wire.name) == nil,
            do: entry.wire.name

      unpublish(subscribers, kind, removed)
    end

    %{state | cache: new, published?: true, retired?: false}
  end

  defp changed(old, new, kind) do
    Enum.filter(ResourceCache.list(new, kind), fn entry ->
      case ResourceCache.get(old, kind, entry.wire.name) do
        nil -> true
        previous -> previous.wire.version != entry.wire.version
      end
    end)
  end

  # Arion rebuilds a republished EDS cluster without endpoints, so the cluster's
  # assignment is published again unless it is already being published.
  defp reassigned(cache, clusters, assignments) do
    published = MapSet.new(assignments, & &1.wire.name)

    for cluster <- clusters,
        not MapSet.member?(published, cluster.wire.name),
        entry = ResourceCache.get(cache, :load_assignment, cluster.wire.name),
        do: entry
  end

  # Assignments are always sent: the clusters replayed before them may have
  # dropped their endpoints (see reassigned/3).
  defp replay(kind, client, entries, initial_versions) do
    {current, stale} =
      Enum.split_with(entries, fn entry ->
        kind != :load_assignment and entry.wire.version == initial_versions[entry.wire.name]
      end)

    if stale != [], do: StreamHandler.publish(client, kind, Enum.map(stale, & &1.wire))

    if current != [],
      do:
        StreamHandler.seed_acks(client, kind, Enum.map(current, &{&1.wire.name, &1.wire.version}))

    known = MapSet.new(entries, & &1.wire.name)
    gone = for {name, _version} <- initial_versions, not MapSet.member?(known, name), do: name
    if gone != [], do: StreamHandler.unpublish(client, kind, gone)
  end

  defp publish(_subscribers, _kind, []), do: :ok

  defp publish(subscribers, kind, entries) do
    wires = Enum.map(entries, & &1.wire)
    Enum.each(Map.get(subscribers, kind, []), &StreamHandler.publish(&1, kind, wires))
  end

  defp unpublish(_subscribers, _kind, []), do: :ok

  defp unpublish(subscribers, kind, names),
    do: Enum.each(Map.get(subscribers, kind, []), &StreamHandler.unpublish(&1, kind, names))

  defp discovery_kind(type_url, state) do
    with {:ok, kind} <- ResourceTypes.kind_for_type_url(type_url),
         true <- ResourceTypes.discovery_kind?(kind) do
      {:ok, kind}
    else
      _ ->
        Logger.warning("fleet #{state.name}: subscription to unsupported type #{type_url}")
        :error
    end
  end

  defp subscribed?(state),
    do: Enum.any?(state.subscribers, fn {_, pids} -> MapSet.size(pids) > 0 end)

  defp subscribed?(state, client),
    do: Enum.any?(state.subscribers, fn {_, pids} -> MapSet.member?(pids, client) end)

  defp subscribed?(state, kind, client),
    do: MapSet.member?(Map.get(state.subscribers, kind, MapSet.new()), client)

  defp unregister(state) do
    Registry.unregister(Arion.ControlPlane.Registry, state.name)
    state
  end
end
