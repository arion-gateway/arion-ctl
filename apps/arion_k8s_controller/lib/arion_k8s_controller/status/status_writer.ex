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

defmodule Arion.K8sController.Status.StatusWriter do
  @moduledoc """
  Patches Gateway API `/status` with the entries the Engine computes.

  Every enqueue carries the full set of entries whose live status differs, so
  it replaces the pending set: an entry missing from it is satisfied, deleted
  or no longer owned and loses its retry work; one still present takes the
  newer content and keeps its attempt count, so a retry never writes an older
  payload. Fresh entries are coalesced by a short flush timer; a failed patch
  is retried with bounded exponential backoff, one timer per entry.

  Leadership changes are forwarded by the Engine: a follower drops its pending
  entries and ignores enqueues. The `patch` effect is injectable for tests.
  """

  use GenServer
  require Logger

  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Status.Conditions.StatusEntry

  @flush_interval_ms 100

  @initial_backoff_ms 1_000
  @max_backoff_ms 60_000

  defstruct [
    :patch,
    :flush_interval_ms,
    :initial_backoff_ms,
    leader?: false,
    # Bumped on every leadership change; retry timers from older ones are stale.
    generation: 0,
    # {gvk, namespace, name} => %{entry, attempts, retry}; `retry` is nil until a patch fails.
    pending: %{},
    flush_timer: nil
  ]

  @doc """
  Options: `:conn`, or the effect boundary `:patch`
  (`entry -> :ok | {:error, reason}`), which defaults to a `/status` merge
  patch over the connection. `:flush_interval_ms` and `:initial_backoff_ms`
  shorten timers in tests; production uses #{@flush_interval_ms}ms and
  #{@initial_backoff_ms}ms.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def enqueue(server \\ __MODULE__, entries) when is_list(entries),
    do: GenServer.cast(server, {:enqueue, entries})

  def leadership(server \\ __MODULE__, event) when event in [:acquired, :lost],
    do: GenServer.cast(server, {:leadership, event})

  @doc """
  The delay before retry number `attempt` (from 1): `initial_ms` doubling per
  attempt, capped at #{@max_backoff_ms}ms.
  """
  def backoff_ms(attempt, initial_ms \\ @initial_backoff_ms) do
    # The exponent is capped too, so a long outage never grows a bignum.
    min(initial_ms * Integer.pow(2, min(attempt - 1, 16)), @max_backoff_ms)
  end

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       patch: Keyword.get(opts, :patch, default_patch(Keyword.get(opts, :conn))),
       flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @flush_interval_ms),
       initial_backoff_ms: Keyword.get(opts, :initial_backoff_ms, @initial_backoff_ms)
     }}
  end

  @impl true
  def handle_cast({:enqueue, entries}, %{leader?: true} = state) do
    fresh = Map.new(entries, &{key(&1), &1})

    for {key, %{retry: timer}} <- state.pending, not Map.has_key?(fresh, key), do: cancel(timer)

    pending =
      Map.new(fresh, fn {key, entry} ->
        {key, Map.put(state.pending[key] || %{attempts: 0, retry: nil}, :entry, entry)}
      end)

    state = %{state | pending: pending}
    {:noreply, if(pending == %{}, do: state, else: ensure_flush_timer(state))}
  end

  def handle_cast({:enqueue, _entries}, state), do: {:noreply, state}

  def handle_cast({:leadership, :acquired}, state),
    do: {:noreply, %{state | leader?: true, generation: state.generation + 1}}

  def handle_cast({:leadership, :lost}, state) do
    Enum.each(state.pending, fn {_key, %{retry: timer}} -> cancel(timer) end)
    {:noreply, %{state | leader?: false, generation: state.generation + 1, pending: %{}}}
  end

  # Entries with a retry scheduled wait for it; the others are patched now.
  @impl true
  def handle_info(:flush, state) do
    state = %{state | flush_timer: nil}
    keys = for {key, %{retry: nil}} <- state.pending, do: key
    {:noreply, Enum.reduce(keys, state, &dispatch(&2, &1))}
  end

  def handle_info({:retry, generation, key}, %{generation: generation} = state) do
    if Map.has_key?(state.pending, key),
      do: {:noreply, dispatch(state, key)},
      else: {:noreply, state}
  end

  def handle_info({:retry, _stale_generation, _key}, state), do: {:noreply, state}

  defp ensure_flush_timer(%{flush_timer: nil} = state) do
    %{state | flush_timer: Process.send_after(self(), :flush, state.flush_interval_ms)}
  end

  defp ensure_flush_timer(state), do: state

  defp dispatch(state, key) do
    %{entry: entry, attempts: attempts} = Map.fetch!(state.pending, key)

    case state.patch.(entry) do
      :ok ->
        %{state | pending: Map.delete(state.pending, key)}

      {:error, reason} ->
        attempts = attempts + 1
        delay = backoff_ms(attempts, state.initial_backoff_ms)

        Logger.warning(
          "arion_k8s_controller: status write failed for #{describe(entry)} " <>
            "(attempt #{attempts}, retry in #{delay}ms): #{inspect(reason)}"
        )

        timer = Process.send_after(self(), {:retry, state.generation, key}, delay)
        put_in(state.pending[key], %{entry: entry, attempts: attempts, retry: timer})
    end
  end

  defp cancel(nil), do: :ok
  defp cancel(timer), do: Process.cancel_timer(timer)

  defp key(%StatusEntry{gvk: gvk, namespace: namespace, name: name}), do: {gvk, namespace, name}

  defp default_patch(nil) do
    fn entry ->
      Logger.debug("arion_k8s_controller: status (no conn) #{describe(entry)}")
      :ok
    end
  end

  defp default_patch(conn) do
    fn %StatusEntry{} = entry ->
      op =
        K8s.Client.patch(
          Gvk.api_version(entry.gvk),
          {Gvk.kind(entry.gvk), "status"},
          patch_path(entry),
          %{"status" => entry.status},
          :merge
        )

      case K8s.Client.run(conn, op) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp patch_path(%StatusEntry{namespace: nil, name: name}), do: [name: name]
  defp patch_path(%StatusEntry{namespace: ns, name: name}), do: [namespace: ns, name: name]

  defp describe(%StatusEntry{} = entry), do: "#{Gvk.kind(entry.gvk)}/#{entry.name}"
end
