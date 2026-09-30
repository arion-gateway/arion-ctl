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

defmodule Arion.K8sController.Status.StatusWriterTest do
  @moduledoc """
  Covers retrying failed status patches, the replacement of pending entries by
  each enqueue, and the leadership gate. Condition content (transition times,
  other controllers' parents) is covered by the Conditions tests.
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Status.Conditions.StatusEntry
  alias Arion.K8sController.Status.StatusWriter

  @key {Gvk.gateway(), "default", "demo"}

  test "a failed patch is retried until it succeeds without a new enqueue" do
    writer = start_writer(%{"demo" => [{:error, :down}, {:error, :down}]})
    StatusWriter.enqueue(writer, [entry("demo")])

    assert patched(1) == ["demo"]
    assert patched(1) == ["demo"]
    assert patched(1) == ["demo"]
    refute_receive {:patched, _}, 50
    assert :sys.get_state(writer).pending == %{}
  end

  test "only the failed entries of a flush are retried" do
    writer = start_writer(%{"a" => [{:error, :down}]})
    StatusWriter.enqueue(writer, [entry("a"), entry("b")])

    assert Enum.sort(patched(2)) == ["a", "b"]
    assert patched(1) == ["a"]
    refute_receive {:patched, _}, 50
  end

  test "a newer status replaces the pending content and keeps the attempt count" do
    writer = start_writer(%{"demo" => [{:error, :down}]}, backoff_ms: 50)
    StatusWriter.enqueue(writer, [entry("demo", %{"addresses" => []})])
    assert_receive {:patched, %StatusEntry{status: %{"addresses" => []}}}, 500

    newer = %{"addresses" => [%{"type" => "IPAddress", "value" => "203.0.113.5"}]}
    StatusWriter.enqueue(writer, [entry("demo", newer)])
    assert %{attempts: 1, entry: %{status: ^newer}} = :sys.get_state(writer).pending[@key]

    assert_receive {:patched, %StatusEntry{status: ^newer}}, 500
    refute_receive {:patched, _}, 50
  end

  test "entries missing from the next enqueue lose their retry" do
    writer = start_writer(%{"demo" => [{:error, :down}]})
    StatusWriter.enqueue(writer, [entry("demo")])
    assert patched(1) == ["demo"]

    StatusWriter.enqueue(writer, [])
    assert :sys.get_state(writer).pending == %{}
    refute_receive {:patched, _}, 50
  end

  test "losing leadership between enqueue and flush drops the entries" do
    writer = start_writer(%{}, flush_ms: 50)
    StatusWriter.enqueue(writer, [entry("demo")])
    StatusWriter.leadership(writer, :lost)

    refute_receive {:patched, _}, 100
    assert :sys.get_state(writer).pending == %{}
  end

  test "retry timers from before a leadership change are ignored" do
    writer = start_writer(%{"demo" => [{:error, :down}, {:error, :down}]}, backoff_ms: 200)
    StatusWriter.enqueue(writer, [entry("demo")])
    assert patched(1) == ["demo"]

    StatusWriter.leadership(writer, :lost)
    StatusWriter.leadership(writer, :acquired)
    StatusWriter.enqueue(writer, [entry("demo")])
    assert patched(1) == ["demo"]

    send(writer, {:retry, 1, @key})
    refute_receive {:patched, _}, 50

    send(writer, {:retry, :sys.get_state(writer).generation, @key})
    assert patched(1) == ["demo"]
  end

  test "a follower ignores enqueues" do
    writer = start_writer(%{}, follower?: true)
    StatusWriter.enqueue(writer, [entry("demo")])
    refute_receive {:patched, _}, 50
  end

  test "backoff doubles from the initial delay and is capped at a minute" do
    assert Enum.map(1..7, &StatusWriter.backoff_ms/1) ==
             [1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 60_000]

    assert StatusWriter.backoff_ms(100) == 60_000
    assert StatusWriter.backoff_ms(3, 10) == 40
  end

  defp entry(name, status \\ %{"conditions" => []}),
    do: %StatusEntry{gvk: Gvk.gateway(), namespace: "default", name: name, status: status}

  # Patches send `{:patched, entry}` and return the name's next scripted result, else :ok.
  defp start_writer(results, opts \\ []) do
    test = self()
    agent = start_supervised!({Agent, fn -> results end})

    writer =
      start_supervised!(
        {StatusWriter,
         flush_interval_ms: Keyword.get(opts, :flush_ms, 5),
         initial_backoff_ms: Keyword.get(opts, :backoff_ms, 10),
         patch: fn entry ->
           send(test, {:patched, entry})

           Agent.get_and_update(agent, fn results ->
             case results[entry.name] do
               [result | rest] -> {result, Map.put(results, entry.name, rest)}
               _ -> {:ok, results}
             end
           end)
         end}
      )

    unless opts[:follower?], do: StatusWriter.leadership(writer, :acquired)
    writer
  end

  defp patched(count) do
    for _ <- 1..count do
      assert_receive {:patched, entry}, 500
      entry.name
    end
  end
end
