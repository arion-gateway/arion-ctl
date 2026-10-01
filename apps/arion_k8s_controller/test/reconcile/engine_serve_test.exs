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

defmodule Arion.K8sController.Reconcile.EngineServeTest do
  @moduledoc """
  Covers the sync gate: nothing is published, reported or served until every
  watched kind is listed, and the xDS server starts and the replica joins the
  leader election after the first publish.
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Arion.ControlPlane.Service
  alias Arion.K8sController.{Config, Fixtures, Runtime}
  alias Arion.K8sController.Election.Leader
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Engine
  alias Arion.K8sController.Store

  @fleet "gateway/default/demo"

  setup do
    start_supervised!({Arion.ControlPlane, serve?: false})
    store = start_supervised!({Store, engine: nil, kinds: [Gvk.gateway_class(), Gvk.gateway()]})

    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(),
      Fixtures.service(),
      Fixtures.http_route()
    ]

    for object <- objects, do: Store.upsert(store, Fixtures.gvk(object), object)

    results = start_supervised!({Agent, fn -> [] end})
    %{store: store, results: results, engine: start_engine(store, results)}
  end

  # The engine's serve MFA: reports what is published when it is called.
  def serve(test, results) do
    result =
      Agent.get_and_update(results, fn
        [] -> {:ok, []}
        [r | rest] -> {r, rest}
      end)

    send(test, {:serve, result, listeners()})
    result
  end

  def lead(test) do
    send(test, :lead)
    :ok
  end

  test "an unsynced store publishes, reports, serves and leads nothing", %{engine: engine} do
    send(engine, {:leadership, :acquired})
    send(engine, :dirty)
    Engine.reconcile_now(engine)

    refute_receive {:"$gen_cast", {:enqueue, _}}, 100
    refute_received {:serve, _, _}
    refute_received :lead
    assert Service.list_fleets() == []
  end

  test "the first synced run publishes, then serves and leads once", %{engine: engine} = ctx do
    send(engine, {:leadership, :acquired})
    sync(ctx.store)
    Engine.reconcile_now(engine)

    assert_received {:serve, :ok, listeners}
    assert Map.has_key?(listeners, "default-demo-80")
    assert_received :lead
    assert_receive {:"$gen_cast", {:enqueue, _}}

    Engine.reconcile_now(engine)
    refute_received {:serve, _, _}
    refute_received :lead
  end

  test "an HA replica joins the leader election only once synced", ctx do
    stop_supervised!(Engine)

    config = %Config{
      controller_name: Fixtures.controller_name(),
      leader_election?: true,
      kubeconfig: "/nonexistent"
    }

    children = Runtime.children(config)
    refute List.keymember?(children, Highlander, 0)
    {Engine, opts} = List.keyfind(children, Engine, 0)

    engine =
      start_supervised!(
        {Engine, Keyword.merge(opts, store: ctx.store, status_writer: self(), serve: nil)}
      )

    Engine.reconcile_now(engine)
    assert :global.whereis_name({Highlander, Leader}) == :undefined

    sync(ctx.store)
    Engine.reconcile_now(engine)
    candidate = :global.whereis_name({Highlander, Leader})
    assert is_pid(candidate)
    assert_receive {:"$gen_cast", {:enqueue, _}}, 1_000

    # A restarted Engine waits for its first publish again.
    ref = Process.monitor(candidate)
    stop_supervised!(Engine)
    assert_receive {:DOWN, ^ref, :process, _, _}
  end

  test "the runtime's sync gate waits for EndpointSlices" do
    config = %Config{controller_name: Fixtures.controller_name(), kubeconfig: "/nonexistent"}
    {Store, opts} = List.keyfind(Runtime.children(config), Store, 0)
    assert Gvk.endpoint_slice() in opts[:kinds]
  end

  test "a restarted engine serves on its first run", ctx do
    sync(ctx.store)
    Engine.reconcile_now(ctx.engine)
    assert_received {:serve, :ok, _}

    stop_supervised!(Engine)
    engine = start_engine(ctx.store, ctx.results)
    Engine.reconcile_now(engine)
    assert_received {:serve, :ok, _}
  end

  test "a failed serve still publishes and is retried on the next run", ctx do
    Agent.update(ctx.results, fn _ -> [{:error, :eaddrinuse}] end)
    sync(ctx.store)

    Engine.reconcile_now(ctx.engine)
    assert_received {:serve, {:error, :eaddrinuse}, _}
    assert Map.has_key?(listeners(), "default-demo-80")

    Engine.reconcile_now(ctx.engine)
    assert_received {:serve, :ok, _}
  end

  defp start_engine(store, results) do
    config = %Config{
      controller_name: Fixtures.controller_name(),
      debounce_ms: 5,
      debounce_max_ms: 20
    }

    start_supervised!(
      {Engine,
       config: config,
       store: store,
       status_writer: self(),
       serve: {__MODULE__, :serve, [self(), results]},
       lead: {__MODULE__, :lead, [self()]}}
    )
  end

  defp sync(store) do
    Store.replace_kind(store, Gvk.gateway_class(), [Fixtures.gateway_class()])
    Store.replace_kind(store, Gvk.gateway(), [Fixtures.gateway()])
    assert Store.synced?(store)
  end

  defp listeners, do: Service.resources(@fleet).listener
end
