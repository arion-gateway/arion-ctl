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

defmodule Arion.K8sController.Kube.WatcherTest do
  @moduledoc """
  Pins the k8s 2.8 error shapes that decide whether a kind counts as served,
  that watchers register locally so every HA replica can watch, and the
  coherent list/watch cycle through an injected list/watch boundary.
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Kube.{Gvk, Watcher}
  alias Arion.K8sController.Store
  alias K8s.Client.{APIError, HTTPError}

  defmodule StubProvider do
    @moduledoc false

    # The gateway group's discovery omits TCPRoute; every other group version is absent.
    def request(:get, %URI{path: path}, _body, _headers, _opts) do
      case path do
        "/apis/gateway.networking.k8s.io/v1" ->
          {:ok,
           %{
             "resources" => [
               %{"name" => "tlsroutes", "kind" => "TLSRoute", "namespaced" => true},
               %{"name" => "referencegrants", "kind" => "ReferenceGrant", "namespaced" => true},
               %{"name" => "httproutes", "kind" => "HTTPRoute", "namespaced" => true},
               %{"name" => "grpcroutes", "kind" => "GRPCRoute", "namespaced" => true}
             ]
           }}

        "/apis/gateway.networking.k8s.io/v1/tlsroutes" ->
          {:error, %APIError{reason: "NotFound", message: "the server could not find it"}}

        "/apis/gateway.networking.k8s.io/v1/referencegrants" ->
          {:error, %APIError{reason: "Forbidden", message: "forbidden"}}

        "/apis/gateway.networking.k8s.io/v1/httproutes" ->
          {:ok, %{"items" => []}}

        "/apis/gateway.networking.k8s.io/v1/grpcroutes" ->
          {:ok, %{"metadata" => %{"resourceVersion" => "1"}}}

        _group_version_or_core ->
          {:error, HTTPError.new(message: "HTTP Error 404")}
      end
    end
  end

  @conn %K8s.Conn{url: "https://kube.test", http_provider: StubProvider}
  @service Gvk.service()

  for {name, gvk} <- [
        discovery_error: Gvk.tcp_route(),
        http_404: Gvk.inference_pool(),
        api_not_found: Gvk.tls_route()
      ] do
    test "a kind that is not served counts as listed and empty (#{name})" do
      assert synced_after_list?(unquote(Macro.escape(gvk)))
    end
  end

  test "a forbidden kind keeps the store unsynced" do
    refute synced_after_list?(Gvk.reference_grant())
  end

  for {name, gvk} <- [core: Gvk.service(), discovery: Gvk.endpoint_slice()] do
    test "a built-in kind that is not found keeps the store unsynced (#{name})" do
      refute synced_after_list?(unquote(Macro.escape(gvk)))
    end
  end

  for {name, gvk} <- [no_resource_version: Gvk.http_route(), no_items: Gvk.grpc_route()] do
    test "an incomplete list is an error and keeps the store unsynced (#{name})" do
      refute synced_after_list?(unquote(Macro.escape(gvk)))
    end
  end

  test "watchers of one kind in different stores start independently" do
    stores = for id <- [:a, :b], do: start_store(Gvk.tcp_route(), id)
    watchers = for store <- stores, do: start_watcher(Gvk.tcp_route(), store)

    for watcher <- watchers, do: :sys.get_state(watcher)
    assert Enum.all?(stores, &Store.synced?/1)
  end

  test "the watch starts from the listed version and its events reach the store" do
    store = start_store(@service, :store)
    start_watcher(store, lists([{:ok, [object("a"), object("b")], "7"}]))

    assert_receive {:watch, "7", stream}
    assert names(store) == ["a", "b"]

    send(stream, {:event, event("MODIFIED", object("a", "8"))})
    send(stream, {:event, event("DELETED", object("b"))})
    eventually(fn -> Store.list(Store.snapshot(store), @service) == [object("a", "8")] end)
  end

  test "a 410 lists again and replaces the kind, deletions included" do
    store = start_store(@service, :store)

    start_watcher(
      store,
      lists([{:ok, [object("a"), object("b")], "7"}, {:ok, [object("a")], "9"}])
    )

    assert_receive {:watch, "7", stream}
    send(stream, {:event, event("ADDED", object("c"))})
    eventually(fn -> names(store) == ["a", "b", "c"] end)

    send(stream, {:event, event("ERROR", %{"kind" => "Status", "code" => 410})})
    assert_receive {:watch, "9", _stream}
    assert names(store) == ["a"]
  end

  test "a replaced stream is stopped, so its events cannot overwrite the replacement" do
    store = start_store(@service, :store)
    watcher = start_watcher(store, lists([{:ok, [object("a")], "7"}, {:ok, [object("b")], "9"}]))
    assert_receive {:watch, "7", stale}

    Watcher.relist(watcher)
    assert_receive {:watch, "9", _stream}
    refute Process.alive?(stale)

    send(stale, {:event, event("ADDED", object("a"))})
    assert names(store) == ["b"]
  end

  test "a failed initial list keeps the store unsynced and opens no watch" do
    store = start_store(@service, :store)
    watcher = start_watcher(store, fn _gvk -> {:error, :timeout} end)

    assert %{task: nil} = :sys.get_state(watcher)
    refute Store.synced?(store)
  end

  test "only Pods are pruned, to labels, deletionTimestamp, pod IPs and the Ready condition" do
    pod = %{
      "apiVersion" => "v1",
      "kind" => "Pod",
      "metadata" => %{
        "name" => "a",
        "namespace" => "default",
        "labels" => %{"app" => "llm"},
        "deletionTimestamp" => "2026-01-01T00:00:00Z",
        "resourceVersion" => "42",
        "managedFields" => [%{}]
      },
      "spec" => %{"containers" => [%{"name" => "llm"}]},
      "status" => %{
        "phase" => "Running",
        "podIP" => "10.1.0.1",
        "podIPs" => [%{"ip" => "10.1.0.1"}],
        "conditions" => [
          %{"type" => "Initialized", "status" => "True"},
          %{"type" => "Ready", "status" => "True", "lastTransitionTime" => "2026-01-01T00:00:00Z"}
        ]
      }
    }

    pruned = %{
      "metadata" => %{
        "name" => "a",
        "namespace" => "default",
        "labels" => %{"app" => "llm"},
        "deletionTimestamp" => "2026-01-01T00:00:00Z"
      },
      "status" => %{
        "podIP" => "10.1.0.1",
        "podIPs" => [%{"ip" => "10.1.0.1"}],
        "conditions" => [%{"type" => "Ready", "status" => "True"}]
      }
    }

    assert Watcher.prune(Gvk.pod(), pod) == pruned
    # List items of built-in kinds carry no apiVersion or kind; watch events do.
    assert Watcher.prune(Gvk.pod(), Map.drop(pod, ["apiVersion", "kind"])) == pruned

    service = put_in(Fixtures.service(), ["metadata", "resourceVersion"], "42")
    assert Watcher.prune(Gvk.service(), service) == service
  end

  defp synced_after_list?(gvk) do
    store = start_store(gvk, :store)
    # The first list runs in handle_continue, before :sys.get_state is served.
    :sys.get_state(start_watcher(gvk, store))
    Store.synced?(store)
  end

  defp start_store(gvk, id),
    do: start_supervised!({Store, name: nil, engine: nil, kinds: [gvk]}, id: {Store, id})

  defp start_watcher(gvk, store) when is_tuple(gvk),
    do: start_supervised!({Watcher, gvk: gvk, conn: @conn, store: store}, id: {Watcher, store})

  # Each watch reports its start version and streams the events the test sends it.
  defp start_watcher(store, list) when is_function(list, 1) do
    test = self()

    watch = fn _gvk, version ->
      send(test, {:watch, version, self()})
      {:ok, Stream.repeatedly(fn -> receive(do: ({:event, event} -> event)) end)}
    end

    start_supervised!(
      {Watcher, gvk: @service, store: store, list: list, watch: watch, backoff_ms: 0},
      id: {Watcher, store}
    )
  end

  defp lists(answers) do
    {:ok, agent} = Agent.start_link(fn -> answers end)

    fn _gvk ->
      Agent.get_and_update(agent, fn
        [last] -> {last, [last]}
        [answer | rest] -> {answer, rest}
      end)
    end
  end

  defp object(name, resource_version \\ "1") do
    %{
      "metadata" => %{
        "namespace" => "default",
        "name" => name,
        "resourceVersion" => resource_version
      }
    }
  end

  defp event(type, object), do: %{"type" => type, "object" => object}

  defp names(store) do
    store
    |> Store.snapshot()
    |> Store.list(@service)
    |> Enum.map(& &1["metadata"]["name"])
    |> Enum.sort()
  end

  # Stream events are cast to the store by the watcher's stream task.
  defp eventually(check, tries \\ 100) do
    cond do
      check.() ->
        :ok

      tries == 0 ->
        flunk("condition not met")

      true ->
        Process.sleep(10)
        eventually(check, tries - 1)
    end
  end
end
