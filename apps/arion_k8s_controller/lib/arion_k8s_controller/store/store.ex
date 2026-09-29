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

defmodule Arion.K8sController.Store do
  @moduledoc """
  Central cache of raw watched objects, keyed by `{gvk, namespace, name}`.

  The store only caches events and pokes the Engine; resolving the cross-kind
  graph stays in the reconcile pipeline.

  Each of the `:kinds` must be listed once (`replace_kind/3`) before the store is
  `synced?/1`. The default `[]` is synced from the start.
  """

  use GenServer

  defstruct objects: %{}, by_kind: %{}, engine: nil, unlisted: MapSet.new()

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def upsert(server \\ __MODULE__, gvk, object),
    do: GenServer.cast(server, {:upsert, gvk, object})

  def delete(server \\ __MODULE__, gvk, namespace, name),
    do: GenServer.cast(server, {:delete, gvk, namespace, name})

  @doc """
  Replaces all objects for a GVK with a watcher's list snapshot, deletions included.

  Synchronous: once it returns, the snapshot is in place and any event applied
  afterwards is newer than it.
  """
  def replace_kind(server \\ __MODULE__, gvk, objects),
    do: GenServer.call(server, {:replace_kind, gvk, objects})

  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  def synced?(server \\ __MODULE__), do: GenServer.call(server, :synced?)

  def list(objects, gvk) when is_map(objects),
    do: for({{^gvk, _ns, _name}, obj} <- objects, do: obj)

  def get(objects, gvk, namespace, name) when is_map(objects),
    do: Map.get(objects, {gvk, namespace, name})

  @impl true
  def init(opts) do
    # Pokes tolerate the Engine not being registered yet.
    {:ok,
     %__MODULE__{
       engine: Keyword.get(opts, :engine, Arion.K8sController.Reconcile.Engine),
       unlisted: MapSet.new(Keyword.get(opts, :kinds, []))
     }}
  end

  @impl true
  def handle_cast({:upsert, gvk, object}, state) do
    key = key(gvk, object)

    if Map.get(state.objects, key) == object do
      {:noreply, state}
    else
      {:noreply, state |> put_object(gvk, key, object) |> poke()}
    end
  end

  def handle_cast({:delete, gvk, namespace, name}, state) do
    key = {gvk, namespace, name}

    if Map.has_key?(state.objects, key),
      do: {:noreply, state |> drop_object(gvk, key) |> poke()},
      else: {:noreply, state}
  end

  @impl true
  def handle_call({:replace_kind, gvk, objects}, _from, state) do
    old_keys = Map.get(state.by_kind, gvk, MapSet.new())
    new = Map.new(objects, &{key(gvk, &1), &1})

    state = %{
      state
      | objects: state.objects |> Map.drop(MapSet.to_list(old_keys)) |> Map.merge(new),
        by_kind: Map.put(state.by_kind, gvk, MapSet.new(Map.keys(new))),
        unlisted: MapSet.delete(state.unlisted, gvk)
    }

    {:reply, :ok, poke(state)}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, state.objects, state}
  def handle_call(:synced?, _from, state), do: {:reply, MapSet.size(state.unlisted) == 0, state}

  defp key(gvk, object) do
    meta = Map.get(object, "metadata", %{})
    {gvk, Map.get(meta, "namespace"), Map.fetch!(meta, "name")}
  end

  defp put_object(state, gvk, key, object) do
    %{
      state
      | objects: Map.put(state.objects, key, object),
        by_kind: Map.update(state.by_kind, gvk, MapSet.new([key]), &MapSet.put(&1, key))
    }
  end

  defp drop_object(state, gvk, key) do
    %{
      state
      | objects: Map.delete(state.objects, key),
        by_kind: Map.update(state.by_kind, gvk, MapSet.new(), &MapSet.delete(&1, key))
    }
  end

  defp poke(%{engine: nil} = state), do: state

  defp poke(%{engine: engine} = state) do
    pid = if is_pid(engine), do: engine, else: Process.whereis(engine)
    if pid, do: send(pid, :dirty)
    state
  end
end
