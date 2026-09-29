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

defmodule Arion.K8sController.Kube.Watcher do
  @moduledoc """
  Watches a single Kubernetes GVK and feeds events into the `Store`.

  Each cycle is one coherent list/watch: one list returns the items and the
  exact `metadata.resourceVersion` they were taken at; the Store's view of the
  kind is replaced by that snapshot, deletions included, and acknowledged
  before the stream starts; the watch then opens from exactly that version, so
  nothing that changed in between is skipped. An expired version (`410 Gone`),
  a stream end or a stream error stops that stream and repeats the cycle after
  a short pause (which also bounds a server that keeps expiring fresh
  versions); the periodic `relist/1` repeats it at once. A replaced stream is
  killed before the next list and only the current stream's completion is
  handled, so stale events and completions never reach the Store. Every
  replica watches into its own local Store.

  A kind the API server does not serve (its CRD is not installed, or not at
  this version) counts as listed and empty, and is rechecked periodically.
  Other list errors, including a list without an `items` list or a
  `metadata.resourceVersion`, are retried and keep the Store unsynced.

  The k8s library's watch (`K8s.Client.stream/2`) lists on its own for a
  version, discards those items, and silently lists again after a 410, so the
  watch is built here from its lower-level pieces: the raw HTTP stream of the
  list operation with `watch=1&resourceVersion=<version>`, decoded line by
  line. The `:list` and `:watch` options replace both calls in tests.
  """

  use GenServer
  require Logger

  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Store

  @backoff_ms 1_000
  @unserved_recheck_ms 30_000

  defstruct [:gvk, :store, :list, :watch, :backoff, :task]

  @doc """
  Options: `:gvk`, `:conn`, `:store` (default `Store`), `:backoff_ms` (the
  pause before a failed list is retried or an ended stream is replaced,
  default 1 s) and the list/watch boundary, built from `:conn` unless given:

    * `list: (gvk -> {:ok, items, resource_version} | {:error, reason})`
    * `watch: (gvk, resource_version -> {:ok, events} | {:error, reason})`,
      where `events` enumerates watch events as the API server sends them
      (an `"ERROR"` with code 410 included) or `{:error, reason}` for a
      transport error.
  """
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Lists again and watches from there, dropping the current stream."
  def relist(watcher), do: GenServer.cast(watcher, :relist)

  @impl true
  def init(opts) do
    conn = Keyword.get(opts, :conn)

    state = %__MODULE__{
      gvk: Keyword.fetch!(opts, :gvk),
      store: Keyword.get(opts, :store, Store),
      list: Keyword.get(opts, :list, &list(conn, &1)),
      watch: Keyword.get(opts, :watch, &watch(conn, &1, &2)),
      backoff: Keyword.get(opts, :backoff_ms, @backoff_ms)
    }

    {:ok, state, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, state), do: {:noreply, start_watch(state)}

  @impl true
  def handle_cast(:relist, state), do: {:noreply, state |> stop_stream() |> start_watch()}

  # A retry while a stream is already running is stale.
  @impl true
  def handle_info(:start, %{task: nil} = state), do: {:noreply, start_watch(state)}
  def handle_info(:start, state), do: {:noreply, state}

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    log_stream_end(state.gvk, result)
    Process.send_after(self(), :start, state.backoff)
    {:noreply, %{state | task: nil}}
  end

  def handle_info(_stale, state), do: {:noreply, state}

  defp log_stream_end(_gvk, :ended), do: :ok

  defp log_stream_end(gvk, :gone),
    do: Logger.info("arion_k8s_controller: #{Gvk.kind(gvk)} watch expired; listing again")

  defp log_stream_end(gvk, {:error, reason}),
    do: Logger.warning("arion_k8s_controller: watch #{Gvk.kind(gvk)} failed: #{inspect(reason)}")

  # The snapshot is acknowledged before the stream starts, so no early event is overwritten.
  defp start_watch(%{gvk: gvk} = state) do
    case state.list.(gvk) do
      {:ok, items, version} ->
        :ok = Store.replace_kind(state.store, gvk, Enum.map(items, &prune(gvk, &1)))
        %{state | task: spawn_stream(state, version)}

      {:error, reason} ->
        retry(state, reason)
    end
  end

  defp retry(%{gvk: gvk} = state, reason) do
    if not_served?(gvk, reason) do
      Logger.info("arion_k8s_controller: #{Gvk.kind(gvk)} is not served; treating it as empty")
      :ok = Store.replace_kind(state.store, gvk, [])
      Process.send_after(self(), :start, @unserved_recheck_ms)
    else
      Logger.warning(
        "arion_k8s_controller: list #{Gvk.kind(gvk)} failed: #{inspect(reason)}; retrying"
      )

      Process.send_after(self(), :start, state.backoff)
    end

    state
  end

  defp stop_stream(%{task: nil} = state), do: state

  defp stop_stream(%{task: task} = state) do
    Task.shutdown(task, :brutal_kill)
    %{state | task: nil}
  end

  # Built-in APIs are always served, so their errors keep the store unsynced.
  # The k8s 2.8 error shapes are pinned by the watcher test.
  defp not_served?({group, _version, _kind}, _reason)
       when group in ["", "apps", "discovery.k8s.io"],
       do: false

  defp not_served?(_gvk, %K8s.Discovery.Error{}), do: true
  defp not_served?(_gvk, %K8s.Client.HTTPError{message: "HTTP Error 404"}), do: true
  defp not_served?(_gvk, %K8s.Client.APIError{reason: "NotFound"}), do: true
  defp not_served?(_gvk, _reason), do: false

  # The task applies events straight to the Store and returns why the stream stopped.
  defp spawn_stream(%{gvk: gvk, store: store, watch: watch}, version) do
    Task.async(fn ->
      case watch.(gvk, version) do
        {:ok, events} ->
          Enum.reduce_while(events, :ended, fn event, _ -> handle_event(store, gvk, event) end)

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp handle_event(store, gvk, %{"type" => type, "object" => object})
       when type in ["ADDED", "MODIFIED"] do
    Store.upsert(store, gvk, prune(gvk, object))
    {:cont, :ended}
  end

  defp handle_event(store, gvk, %{"type" => "DELETED", "object" => %{"metadata" => meta}}) do
    Store.delete(store, gvk, Map.get(meta, "namespace"), Map.get(meta, "name"))
    {:cont, :ended}
  end

  defp handle_event(_store, _gvk, %{"type" => "ERROR", "object" => %{"code" => 410}}),
    do: {:halt, :gone}

  defp handle_event(_store, _gvk, %{"type" => "ERROR", "object" => status}),
    do: {:halt, {:error, status}}

  defp handle_event(_store, _gvk, {:error, reason}), do: {:halt, {:error, reason}}
  defp handle_event(_store, _gvk, _bookmark_or_unknown), do: {:cont, :ended}

  # Every Pod in the cluster is cached, so only what InferencePool endpoints use is kept;
  # updates to anything else then store an identical object.
  @doc false
  def prune(gvk, object) do
    if gvk == Gvk.pod(), do: prune_pod(object), else: object
  end

  defp prune_pod(pod) do
    status = pod["status"] || %{}

    ready =
      for %{"type" => "Ready"} = c <- status["conditions"] || [],
          do: Map.take(c, ["type", "status"])

    %{
      "metadata" =>
        Map.take(pod["metadata"], ["name", "namespace", "labels", "deletionTimestamp"]),
      "status" => status |> Map.take(["podIP", "podIPs"]) |> Map.put("conditions", ready)
    }
  end

  defp list(conn, gvk) do
    case K8s.Client.run(conn, op(gvk)) do
      {:ok, %{"items" => items, "metadata" => %{"resourceVersion" => version}}}
      when is_list(items) and is_binary(version) ->
        {:ok, items, version}

      {:ok, _incomplete} ->
        {:error, :incomplete_list}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A non-200 reply carries a Status, surfaced as an ERROR event so that a 410
  # ends the stream as `:gone` either way.
  defp watch(conn, gvk, version) do
    params = [watch: 1, resourceVersion: version]

    with {:ok, chunks} <- K8s.Client.Runner.Base.stream(conn, op(gvk), params: params) do
      events =
        chunks
        |> K8s.Client.HTTPStream.decode_json_objects()
        |> Stream.flat_map(fn
          {:object, %{"type" => _} = event} -> [event]
          {:object, %{"kind" => "Status"} = status} -> [%{"type" => "ERROR", "object" => status}]
          {:error, reason} -> [{:error, reason}]
          _status_headers_or_done -> []
        end)

      {:ok, events}
    end
  end

  defp op(gvk) do
    opts = if Gvk.namespaced?(gvk), do: [namespace: :all], else: []
    K8s.Client.list(Gvk.api_version(gvk), Gvk.kind(gvk), opts)
  end
end
