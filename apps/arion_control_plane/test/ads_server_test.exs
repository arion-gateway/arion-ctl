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

defmodule Arion.ControlPlane.AdsServerTest do
  use ExUnit.Case

  @moduletag :capture_log

  alias Arion.ControlPlane.AdsServer.StreamHandler
  alias Arion.ControlPlane.Helpers.Cluster
  alias Arion.ControlPlane.Pb.Data.DeltaDiscoveryRequest
  alias Arion.ControlPlane.Pb.Data.Node
  alias Arion.ControlPlane.Pb.Data.Status
  alias Arion.ControlPlane.Pb.Envoy.Service.Discovery.V3.AggregatedDiscoveryService.Stub
  alias Arion.ControlPlane.Service
  alias Arion.ControlPlane.Xds.ResourceTypes

  @fleet "e2e"

  setup do
    # The gRPC client used as the proxy needs its own supervisor since grpc 0.11.
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: GRPC.Client.Supervisor})
    start_supervised!({Arion.ControlPlane, port: 0})
    :ok = Service.replace(@fleet, [{:cluster, Cluster.static("backend", "127.0.0.1", [80])}])

    {:ok, channel} =
      GRPC.Stub.connect("127.0.0.1:#{:ranch.get_port("Arion.ControlPlane.Endpoint")}")

    %{channel: channel}
  end

  test "a subscription receives cached resources and records ACKs and NACKs",
       %{channel: channel} do
    {stream, replies} = subscribe(channel)

    assert [{:ok, %{nonce: "1", resources: [%{name: "backend", version: v1}]}}] =
             Enum.take(replies, 1)

    respond(stream, "1", nil)
    handler = handler()
    assert eventually(fn -> match?(%{"backend" => {:ack, ^v1}}, clusters(handler)) end)

    Service.push(@fleet, :cluster, Cluster.static("backend", "127.0.0.1", [81]))
    assert [{:ok, %{nonce: "2", resources: [%{version: v2}]}}] = Enum.take(replies, 1)

    respond(stream, "2", %Status{code: 3, message: "rejected"})
    assert eventually(fn -> match?(%{"backend" => {:nack, ^v2, _}}, clusters(handler)) end)

    # An open stream holds up the server's shutdown for cowboy's GOAWAY timeouts.
    GRPC.Stub.cancel(stream)
  end

  test "a request subscribing to more names on an open stream resends nothing",
       %{channel: channel} do
    {stream, replies} = subscribe(channel)
    assert [{:ok, %{nonce: "1"}}] = Enum.take(replies, 1)

    GRPC.Stub.send_request(stream, %DeltaDiscoveryRequest{
      type_url: ResourceTypes.type_url!(:cluster),
      response_nonce: "1",
      resource_names_subscribe: ["another"]
    })

    Service.push(@fleet, :cluster, Cluster.static("backend", "127.0.0.1", [81]))
    assert [{:ok, %{nonce: "2", resources: [%{name: "backend"}]}}] = Enum.take(replies, 1)
    GRPC.Stub.cancel(stream)
  end

  test "a stream is bound to the fleet of its first request", %{channel: channel} do
    # Without a node the default fleet is selected, which has nothing published.
    stream =
      channel
      |> Stub.delta_aggregated_resources()
      |> GRPC.Stub.send_request(%DeltaDiscoveryRequest{
        type_url: ResourceTypes.type_url!(:cluster)
      })

    unavailable = GRPC.Status.unavailable()
    assert {:error, %GRPC.RPCError{status: ^unavailable}} = GRPC.Stub.recv(stream, timeout: 2_000)

    {stream, replies} = subscribe(channel)
    assert [{:ok, %{nonce: "1"}}] = Enum.take(replies, 1)

    # Repeating the fleet keeps the stream open.
    GRPC.Stub.send_request(stream, %DeltaDiscoveryRequest{
      node: %Node{id: "proxy", cluster: @fleet},
      type_url: ResourceTypes.type_url!(:cluster),
      response_nonce: "1"
    })

    Service.push(@fleet, :cluster, Cluster.static("backend", "127.0.0.1", [81]))
    assert [{:ok, %{nonce: "2"}}] = Enum.take(replies, 1)

    # Naming another fleet ends the stream without subscribing to that fleet.
    ref = Process.monitor(handler())

    GRPC.Stub.send_request(stream, %DeltaDiscoveryRequest{
      node: %Node{id: "proxy", cluster: "other"},
      type_url: ResourceTypes.type_url!(:cluster),
      response_nonce: "2"
    })

    invalid_argument = GRPC.Status.invalid_argument()
    assert [{:error, %GRPC.RPCError{status: ^invalid_argument}}] = Enum.take(replies, 1)
    assert_receive {:DOWN, ^ref, :process, _, _}
    refute "other" in Service.list_fleets()
    assert eventually(fn -> Service.acks(@fleet) == %{} end)
  end

  test "a reconnect lists held versions and receives only the delta", %{channel: channel} do
    [%{version: current}] = Service.resources(@fleet).cluster |> Map.keys() |> wires()

    stream =
      channel
      |> Stub.delta_aggregated_resources()
      |> GRPC.Stub.send_request(%DeltaDiscoveryRequest{
        node: %Node{id: "proxy", cluster: @fleet},
        type_url: ResourceTypes.type_url!(:cluster),
        initial_resource_versions: %{"backend" => current, "gone" => "1"}
      })

    {:ok, replies} = GRPC.Stub.recv(stream, timeout: 2_000)

    assert [{:ok, %{nonce: "1", resources: [], removed_resources: ["gone"]}}] =
             Enum.take(replies, 1)

    assert eventually(fn -> match?(%{"backend" => {:ack, ^current}}, clusters(handler())) end)
    GRPC.Stub.cancel(stream)
  end

  test "a fleet crash ends the stream with UNAVAILABLE, as does reconnecting before a republish",
       %{channel: channel} do
    {_stream, replies} = subscribe(channel)
    assert [{:ok, _}] = Enum.take(replies, 1)
    handler = handler()
    ref = Process.monitor(handler)

    Process.exit(Service.ensure(@fleet), :kill)

    unavailable = GRPC.Status.unavailable()
    assert [{:error, %GRPC.RPCError{status: ^unavailable}}] = Enum.take(replies, 1)
    assert_receive {:DOWN, ^ref, :process, ^handler, :normal}

    # The restarted fleet has nothing published: the proxy keeps what it holds and retries.
    assert eventually(fn -> Service.list_fleets() == [@fleet] end)
    stream = send_subscription(channel)
    assert {:error, %GRPC.RPCError{status: ^unavailable}} = GRPC.Stub.recv(stream, timeout: 2_000)

    :ok = Service.replace(@fleet, [{:cluster, Cluster.static("backend", "127.0.0.1", [80])}])
    {stream, replies} = subscribe(channel)
    assert [{:ok, %{resources: [%{name: "backend"}]}}] = Enum.take(replies, 1)
    GRPC.Stub.cancel(stream)
  end

  test "a connected proxy keeps a retired fleet, which stops once it leaves",
       %{channel: channel} do
    {stream, replies} = subscribe(channel)
    assert [{:ok, _}] = Enum.take(replies, 1)

    assert Service.retire(@fleet) == :kept
    assert [{:ok, %{removed_resources: ["backend"]}}] = Enum.take(replies, 1)

    assert_cleaned_up(fn -> GRPC.Stub.cancel(stream) end)
    assert eventually(fn -> Service.list_fleets() == [] end)
  end

  test "a subscription queued behind a retire ends the stream with UNAVAILABLE",
       %{channel: channel} do
    pid = Service.ensure(@fleet)
    :sys.suspend(pid)
    retire = Task.async(fn -> Service.retire(@fleet) end)
    assert eventually(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 1} end)

    stream = send_subscription(channel)
    assert eventually(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 2} end)
    :sys.resume(pid)
    assert Task.await(retire) == :stopped

    unavailable = GRPC.Status.unavailable()
    assert {:error, %GRPC.RPCError{status: ^unavailable}} = GRPC.Stub.recv(stream, timeout: 2_000)
  end

  test "cancelling a stream stops its handler and unsubscribes it", %{channel: channel} do
    {stream, replies} = subscribe(channel)
    assert [{:ok, _}] = Enum.take(replies, 1)
    assert_cleaned_up(fn -> GRPC.Stub.cancel(stream) end)
  end

  test "closing the connection stops its handler and unsubscribes it", %{channel: channel} do
    {_stream, replies} = subscribe(channel)
    assert [{:ok, _}] = Enum.take(replies, 1)
    # GRPC.Stub.disconnect/1 closes gracefully, waiting for open streams to end.
    assert_cleaned_up(fn -> :gun.close(channel.adapter_payload.conn_pid) end)
  end

  test "ending the request stream ends the reply stream with OK", %{channel: channel} do
    {stream, replies} = subscribe(channel)
    assert [{:ok, _}] = Enum.take(replies, 1)

    assert_cleaned_up(fn ->
      GRPC.Stub.end_stream(stream)
      assert Enum.to_list(replies) == []
    end)
  end

  defp assert_cleaned_up(close) do
    ref = Process.monitor(handler())
    close.()
    assert_receive {:DOWN, ^ref, :process, _, _}
    assert eventually(fn -> Service.acks(@fleet) == %{} end)
  end

  defp subscribe(channel) do
    stream = send_subscription(channel)
    {:ok, replies} = GRPC.Stub.recv(stream, timeout: 2_000)
    {stream, replies}
  end

  defp send_subscription(channel) do
    channel
    |> Stub.delta_aggregated_resources()
    |> GRPC.Stub.send_request(%DeltaDiscoveryRequest{
      node: %Node{id: "proxy", cluster: @fleet},
      type_url: ResourceTypes.type_url!(:cluster)
    })
  end

  defp respond(stream, nonce, error) do
    GRPC.Stub.send_request(stream, %DeltaDiscoveryRequest{
      type_url: ResourceTypes.type_url!(:cluster),
      response_nonce: nonce,
      error_detail: error
    })
  end

  defp wires(names) do
    resources = Service.resources(@fleet).cluster
    for name <- names, do: Arion.ControlPlane.ResourceCache.entry(:cluster, resources[name]).wire
  end

  defp clusters(handler), do: StreamHandler.acks(handler).cluster

  defp handler do
    [handler] = Map.keys(Service.acks(@fleet))
    handler
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(check, attempts - 1)
    end
  end
end
