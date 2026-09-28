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

defmodule Arion.Ctl.Store do
  @moduledoc """
  Durable desired state. Each change is written to the snapshot before the
  fleets are published, and the fleets are republished whenever one restarts.
  """

  use GenServer

  alias Arion.ControlPlane.Service
  alias Arion.Ctl.Manifest

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def apply(entries), do: GenServer.call(__MODULE__, {:apply, entries}, :infinity)

  def delete(ids), do: GenServer.call(__MODULE__, {:delete, ids}, :infinity)

  def resources, do: GenServer.call(__MODULE__, :resources)

  @impl true
  def init(opts) do
    dir = Keyword.fetch!(opts, :state_dir)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(dir, 0o700),
         {:ok, entries} <- load(Path.join(dir, "state.json")) do
      {:ok, publish(%{dir: dir, entries: Map.new(entries, &{&1.id, &1}), monitors: %{}})}
    else
      {:error, reason} -> {:stop, {:state_restore_failed, reason}}
    end
  end

  @impl true
  def handle_call(:resources, _from, state), do: {:reply, manifests(state.entries), state}

  def handle_call({:apply, entries}, _from, state),
    do: commit(Map.merge(state.entries, Map.new(entries, &{&1.id, &1})), state)

  def handle_call({:delete, ids}, _from, state), do: commit(Map.drop(state.entries, ids), state)

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if Map.has_key?(state.monitors, ref), do: {:noreply, publish(state)}, else: {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Unchanged desired state is neither written nor republished; a crashed fleet
  # is still restored by its DOWN.
  defp commit(entries, %{entries: entries} = state),
    do: {:reply, {:ok, %{resources: map_size(entries)}}, state}

  defp commit(entries, state) do
    bytes = Jason.encode!(%{version: 1, resources: manifests(entries)})

    case write_atomically(Path.join(state.dir, "state.json"), bytes) do
      :ok ->
        {:reply, {:ok, %{resources: map_size(entries)}}, publish(%{state | entries: entries})}

      {:error, reason} ->
        {:reply, {:error, "could not persist desired state: #{:file.format_error(reason)}"},
         state}
    end
  end

  defp write_atomically(path, bytes) do
    temp = path <> ".tmp"

    with {:ok, file} <- :file.open(String.to_charlist(temp), [:write, :binary, :raw]),
         :ok <- write_synced(file, temp, bytes),
         :ok <- File.rename(temp, path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temp)
        {:error, reason}
    end
  end

  defp write_synced(file, temp, bytes) do
    with :ok <- File.chmod(temp, 0o600),
         :ok <- :file.write(file, bytes),
         :ok <- :file.sync(file) do
      :file.close(file)
    else
      error ->
        :file.close(file)
        error
    end
  end

  defp publish(state) do
    Enum.each(Map.keys(state.monitors), &Process.demonitor(&1, [:flush]))
    by_fleet = Enum.group_by(Map.values(state.entries), & &1.fleet)

    for fleet <- Service.list_fleets(),
        not Map.has_key?(by_fleet, fleet),
        do: Service.retire(fleet)

    monitors =
      Map.new(by_fleet, fn {fleet, entries} ->
        pid = Service.ensure(fleet)
        resources = Enum.map(entries, &{&1.kind, {&1.name, &1.payload}})

        # A fleet that dies during the replace is republished on its DOWN.
        try do
          :ok = Service.replace(fleet, resources)
        catch
          :exit, _ -> :ok
        end

        {Process.monitor(pid), fleet}
      end)

    %{state | monitors: monitors}
  end

  defp manifests(entries),
    do: entries |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(fn {_id, e} -> e.manifest end)

  defp load(path) do
    case File.read(path) do
      {:ok, bytes} ->
        case Jason.decode(bytes) do
          {:ok, %{"version" => 1, "resources" => docs}} -> Manifest.decode(docs)
          _ -> {:error, "#{path} is not a version 1 snapshot"}
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, "#{path}: #{:file.format_error(reason)}"}
    end
  end
end
