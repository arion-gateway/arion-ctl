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

defmodule Arion.K8sController.Reconcile.EngineTest do
  @moduledoc """
  Covers the HA split (every replica publishes xDS, only the leader writes
  status) and publishing through `Arion.ControlPlane.Service.replace/2`.
  """
  use ExUnit.Case, async: false

  alias Arion.ControlPlane.Service
  alias Arion.ControlPlane.Xds.ResourceTypes
  alias Arion.K8sController.{Config, Fixtures, Ir}
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Engine
  alias Arion.K8sController.Store

  @fleet "gateway/default/demo"

  setup do
    start_supervised!({Arion.ControlPlane, serve?: false})

    config = %Config{
      controller_name: Fixtures.controller_name(),
      debounce_ms: 5,
      debounce_max_ms: 20
    }

    store = start_supervised!({Store, engine: :test_engine})
    Store.upsert(store, Gvk.gateway_class(), Fixtures.gateway_class())

    engine =
      start_supervised!(
        {Engine,
         name: :test_engine, config: config, store: store, status_writer: self(), deployer: self()}
      )

    %{engine: engine, store: store}
  end

  test "a follower applies xDS but does not write status", %{engine: engine} do
    send(engine, :dirty)
    refute_receive {:"$gen_cast", {:enqueue, _}}, 100
  end

  test "the leader writes status on acquiring leadership", %{engine: engine} do
    send(engine, {:leadership, :acquired})
    assert_receive {:"$gen_cast", {:enqueue, entries}}, 200
    assert Enum.any?(entries, &(&1.name == "arion"))
  end

  test "leadership changes reach the status writer and the deployer", %{engine: engine} do
    send(engine, {:leadership, :acquired})
    assert_receive {:"$gen_cast", {:leadership, :acquired}}, 200
    assert_receive {:"$gen_cast", {:leadership, :acquired}}, 200
    assert_receive {:"$gen_cast", {:reconcile, %Ir.Graph{}, _snapshot}}, 200

    send(engine, {:leadership, :lost})
    assert_receive {:"$gen_cast", {:leadership, :lost}}, 200
    assert_receive {:"$gen_cast", {:leadership, :lost}}, 200
    send(engine, :dirty)
    refute_receive {:"$gen_cast", {:reconcile, _, _}}, 100
  end

  test "losing leadership stops status writes", %{engine: engine} do
    send(engine, {:leadership, :acquired})
    assert_receive {:"$gen_cast", {:enqueue, _}}, 200

    send(engine, {:leadership, :lost})
    send(engine, :dirty)
    refute_receive {:"$gen_cast", {:enqueue, _}}, 100
  end

  test "reconcile_now keeps a follower from writing status", %{engine: engine} do
    Engine.reconcile_now(engine)
    send(engine, :dirty)
    refute_receive {:"$gen_cast", {:enqueue, _}}, 100
  end

  test "an unchanged recompute publishes nothing", ctx do
    publish_gateway(ctx)
    Enum.each(ResourceTypes.discovery_kinds(), &subscribe/1)
    assert_receive {:"$gen_cast", {:publish, :listener, [_]}}
    assert_receive {:"$gen_cast", {:publish, :cluster, [_]}}

    Engine.reconcile_now(ctx.engine)
    refute_receive {:"$gen_cast", {:publish, _, _}}, 100
  end

  test "an edited route republishes its listener", ctx do
    publish_gateway(ctx)
    subscribe(:listener)
    assert_receive {:"$gen_cast", {:publish, :listener, [original]}}

    route =
      Fixtures.http_route(
        rules: [
          %{
            "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/v2"}}],
            "backendRefs" => [%{"name" => "app-svc", "port" => 8080}]
          }
        ]
      )

    Store.upsert(ctx.store, Fixtures.gvk(route), route)
    Store.snapshot(ctx.store)
    Engine.reconcile_now(ctx.engine)

    assert_receive {:"$gen_cast", {:publish, :listener, [edited]}}
    assert edited.name == original.name
    assert edited != original
  end

  test "a removed Gateway's fleet is emptied", ctx do
    publish_gateway(ctx)
    subscribe(:listener)
    assert_receive {:"$gen_cast", {:publish, :listener, [_]}}

    Store.delete(ctx.store, Gvk.gateway(), "default", "demo")
    Store.snapshot(ctx.store)
    Engine.reconcile_now(ctx.engine)

    assert_receive {:"$gen_cast", {:unpublish, :listener, ["default-demo-80"]}}
    assert Enum.all?(Map.values(Service.resources(@fleet)), &(&1 == %{}))
  end

  test "a removed Gateway's idle fleet is stopped, not republished", ctx do
    publish_gateway(ctx)
    pid = Service.ensure(@fleet)
    ref = Process.monitor(pid)

    Store.delete(ctx.store, Gvk.gateway(), "default", "demo")
    Store.snapshot(ctx.store)
    Engine.reconcile_now(ctx.engine)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Service.list_fleets() == []

    # Past the debounce, so a republish triggered by that exit has run.
    Process.sleep(50)
    Engine.reconcile_now(ctx.engine)
    assert Service.list_fleets() == []
  end

  test "fleets that are not Gateway fleets are left alone", ctx do
    :ok = Service.replace("arion", [])
    publish_gateway(ctx)
    assert Enum.sort(Service.list_fleets()) == ["arion", @fleet]
  end

  test "a removed Gateway's fleet kept by a proxy stops on a later reconcile", ctx do
    publish_gateway(ctx)
    test = self()

    proxy =
      spawn(fn ->
        Service.subscribe(self(), @fleet, ResourceTypes.type_url!(:listener), %{})
        send(test, :subscribed)
        Process.sleep(:infinity)
      end)

    assert_receive :subscribed
    Store.delete(ctx.store, Gvk.gateway(), "default", "demo")
    Store.snapshot(ctx.store)
    Engine.reconcile_now(ctx.engine)
    assert Service.list_fleets() == [@fleet]
    assert listeners() == %{}

    Process.exit(proxy, :kill)
    assert eventually(fn -> Service.list_fleets() == [] end)
  end

  test "a restarted fleet is repopulated without a store change", ctx do
    publish_gateway(ctx)
    old = Service.ensure(@fleet)
    Process.exit(old, :kill)

    assert eventually(fn ->
             Service.ensure(@fleet) != old and Map.has_key?(listeners(), "default-demo-80")
           end)
  end

  test "status written back through the Store is not written again", ctx do
    for object <- [Fixtures.gateway(), Fixtures.service(), Fixtures.http_route()] do
      Store.upsert(ctx.store, Fixtures.gvk(object), object)
    end

    Store.snapshot(ctx.store)
    send(ctx.engine, {:leadership, :acquired})
    assert status_writes(ctx.store, 5) == 1
  end

  # Stands in for the API server: a status patch that changes the object comes
  # back as a watch event. Counts the non-empty enqueues, up to `max`.
  defp status_writes(store, max, writes \\ 0) do
    receive do
      {:"$gen_cast", {:enqueue, []}} ->
        status_writes(store, max, writes)

      {:"$gen_cast", {:enqueue, entries}} when writes < max ->
        snapshot = Store.snapshot(store)

        for entry <- entries do
          object = Store.get(snapshot, entry.gvk, entry.namespace, entry.name)
          patched = Map.update(object, "status", entry.status, &Map.merge(&1, entry.status))
          if patched != object, do: Store.upsert(store, entry.gvk, patched)
        end

        status_writes(store, max, writes + 1)
    after
      300 -> writes
    end
  end

  defp publish_gateway(%{store: store, engine: engine}) do
    for object <- [Fixtures.gateway(), Fixtures.service(), Fixtures.http_route()] do
      Store.upsert(store, Fixtures.gvk(object), object)
    end

    Store.snapshot(store)
    Engine.reconcile_now(engine)
    assert Map.has_key?(listeners(), "default-demo-80")
  end

  defp subscribe(kind) do
    Service.subscribe(self(), @fleet, ResourceTypes.type_url!(kind), %{})
    Service.resources(@fleet)
  end

  defp listeners, do: Service.resources(@fleet).listener

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end
end
