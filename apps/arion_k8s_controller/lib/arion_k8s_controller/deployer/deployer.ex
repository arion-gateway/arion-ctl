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

defmodule Arion.K8sController.Deployer.Deployer do
  @moduledoc """
  Leader-only provisioning for Arion-managed Gateway data planes.

  Server-side apply, deterministic names, and Gateway ownerReferences keep
  provisioning convergent and garbage-collected. Each reconcile computes the
  desired objects and applies the ones that are new or changed, and the ones
  whose live object is missing or has drifted in a controller-owned field.
  Deployments and Services are watched, so they are checked against the
  snapshot on every reconcile; ConfigMaps and ServiceAccounts are read on a
  periodic verification tick instead, so reconciles never call the API.

  A failed apply is retried with bounded exponential backoff, one timer per
  object. Leadership changes are forwarded by the Engine: a follower keeps no
  provisioning state and dispatches nothing. The Kubernetes effects (`apply`
  and `get`) are injectable so tests are deterministic.
  """

  use GenServer
  require Logger

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Deployer.{Objects, Params}
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Store

  @initial_backoff_ms 1_000
  @max_backoff_ms 60_000

  # Identity fields the key already carries; list items from the API server omit them.
  @identity ["apiVersion", "kind"]

  defstruct [
    :config,
    :apply,
    :get,
    :initial_backoff_ms,
    leader?: false,
    # Bumped on every leadership change; retry timers from older ones are stale.
    generation: 0,
    desired: %{},
    # Objects whose last apply succeeded, by key.
    applied: %{},
    # Objects whose last apply failed: key => %{object, attempts, timer}.
    pending: %{}
  ]

  @doc """
  Options: `:config` (required), `:conn`, and the effect boundary `:apply`
  (`object -> :ok | {:error, reason}`) and `:get`
  (`object -> {:ok, live} | {:error, :not_found} | {:error, reason}`), which
  default to the cluster connection. `:initial_backoff_ms` shortens retries in
  tests; production uses #{@initial_backoff_ms}ms.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def reconcile(server \\ __MODULE__, %Ir.Graph{} = graph, snapshot),
    do: GenServer.cast(server, {:reconcile, graph, snapshot})

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

  @doc """
  Whether `live` holds every field of `desired` with the same value: maps need
  each desired key, lists the same length pairwise, scalars equality. Fields
  only the server sets (status, resource versions, defaults) are not compared.
  """
  def subset?(desired, live) when is_map(desired) and is_map(live),
    do: Enum.all?(desired, fn {k, v} -> Map.has_key?(live, k) and subset?(v, live[k]) end)

  def subset?(desired, live) when is_list(desired) and is_list(live),
    do: length(desired) == length(live) and Enum.all?(Enum.zip_with(desired, live, &subset?/2))

  def subset?(desired, live), do: desired == live

  @impl true
  def init(opts) do
    conn = Keyword.get(opts, :conn)
    config = Keyword.fetch!(opts, :config)
    Process.send_after(self(), :verify, config.resync_interval_ms)

    {:ok,
     %__MODULE__{
       config: config,
       apply: Keyword.get(opts, :apply, default_apply(conn)),
       get: Keyword.get(opts, :get, default_get(conn)),
       initial_backoff_ms: Keyword.get(opts, :initial_backoff_ms, @initial_backoff_ms)
     }}
  end

  @impl true
  def handle_cast({:reconcile, graph, snapshot}, %{leader?: true} = state) do
    objects = objects(graph, state.config)
    desired = Map.new(objects, &{key(&1), &1})

    # Retry work for objects no longer desired, or desired with new content, is stale.
    state =
      Enum.reduce(state.pending, state, fn {key, %{object: object}}, acc ->
        if desired[key] == object, do: acc, else: drop_pending(acc, key)
      end)

    state = %{state | desired: desired, applied: Map.take(state.applied, Map.keys(desired))}

    state =
      Enum.reduce(objects, state, fn object, acc ->
        key = key(object)

        cond do
          Map.has_key?(acc.pending, key) -> acc
          acc.applied[key] != object -> dispatch(acc, key)
          drifted?(object, snapshot) -> dispatch(acc, key)
          true -> acc
        end
      end)

    {:noreply, state}
  end

  def handle_cast({:reconcile, _graph, _snapshot}, state), do: {:noreply, state}

  def handle_cast({:leadership, :acquired}, state),
    do: {:noreply, %{state | leader?: true, generation: state.generation + 1}}

  # A follower holds nothing: reacquisition starts over from a fresh reconcile.
  def handle_cast({:leadership, :lost}, state) do
    Enum.each(state.pending, fn {_key, %{timer: timer}} -> Process.cancel_timer(timer) end)

    {:noreply,
     %{
       state
       | leader?: false,
         generation: state.generation + 1,
         desired: %{},
         applied: %{},
         pending: %{}
     }}
  end

  @impl true
  def handle_info({:retry, generation, key}, %{generation: generation} = state) do
    if Map.has_key?(state.pending, key),
      do: {:noreply, dispatch(state, key)},
      else: {:noreply, state}
  end

  def handle_info({:retry, _stale_generation, _key}, state), do: {:noreply, state}

  def handle_info(:verify, state) do
    Process.send_after(self(), :verify, state.config.resync_interval_ms)
    if state.leader?, do: {:noreply, verify(state)}, else: {:noreply, state}
  end

  @doc "The objects to apply for the graph's provisioned Gateways."
  def objects(%Ir.Graph{} = graph, config) do
    for gateway <- graph.gateways,
        is_nil(gateway.invalid_params),
        params = Params.plan(gateway, config),
        not params.self_managed?,
        object <- Objects.build(gateway, params, config),
        do: object
  end

  defp key(%{"kind" => kind, "metadata" => meta}), do: {kind, meta["namespace"], meta["name"]}

  defp dispatch(state, key) do
    object = Map.fetch!(state.desired, key)

    case state.apply.(object) do
      :ok ->
        %{
          state
          | applied: Map.put(state.applied, key, object),
            pending: Map.delete(state.pending, key)
        }

      {:error, reason} ->
        attempts = (get_in(state.pending, [key, :attempts]) || 0) + 1
        delay = backoff_ms(attempts, state.initial_backoff_ms)

        Logger.warning(
          "arion_k8s_controller: deployer apply failed for #{describe(object)} " <>
            "(attempt #{attempts}, retry in #{delay}ms): #{inspect(reason)}"
        )

        timer = Process.send_after(self(), {:retry, state.generation, key}, delay)
        put_in(state.pending[key], %{object: object, attempts: attempts, timer: timer})
    end
  end

  defp drop_pending(state, key) do
    {%{timer: timer}, pending} = Map.pop!(state.pending, key)
    Process.cancel_timer(timer)
    %{state | pending: pending}
  end

  # Watched kinds are compared with the snapshot; the others wait for `verify/1`.
  defp drifted?(object, snapshot) do
    case watched_gvk(object["kind"]) do
      nil -> false
      gvk -> not converged?(object, Store.get(snapshot, gvk, namespace(object), name(object)))
    end
  end

  defp converged?(_object, nil), do: false
  defp converged?(object, live), do: subset?(Map.drop(object, @identity), live)

  defp watched_gvk("Deployment"), do: Gvk.deployment()
  defp watched_gvk("Service"), do: Gvk.service()
  defp watched_gvk(_kind), do: nil

  defp verify(state) do
    Enum.reduce(state.desired, state, fn {key, object}, acc ->
      if watched_gvk(object["kind"]) || Map.has_key?(acc.pending, key),
        do: acc,
        else: verify(acc, key, object)
    end)
  end

  defp verify(state, key, object) do
    case state.get.(object) do
      {:ok, live} ->
        if converged?(object, live), do: state, else: dispatch(state, key)

      {:error, :not_found} ->
        dispatch(state, key)

      {:error, reason} ->
        Logger.warning(
          "arion_k8s_controller: deployer read failed for #{describe(object)}: #{inspect(reason)}"
        )

        state
    end
  end

  defp default_apply(nil) do
    fn object ->
      Logger.debug("arion_k8s_controller: deployer (no conn) #{describe(object)}")
      :ok
    end
  end

  defp default_apply(conn) do
    fn object ->
      op = K8s.Client.apply(object, field_manager: Objects.field_manager(), force: true)

      case K8s.Client.run(conn, op) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp default_get(nil), do: fn object -> {:ok, object} end

  defp default_get(conn) do
    fn object ->
      path = [namespace: namespace(object), name: name(object)]
      op = K8s.Client.get(object["apiVersion"], object["kind"], path)

      case K8s.Client.run(conn, op) do
        {:ok, live} -> {:ok, live}
        {:error, %K8s.Client.APIError{reason: "NotFound"}} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp namespace(object), do: object["metadata"]["namespace"]
  defp name(object), do: object["metadata"]["name"]
  defp describe(object), do: "#{object["kind"]}/#{name(object)}"
end
