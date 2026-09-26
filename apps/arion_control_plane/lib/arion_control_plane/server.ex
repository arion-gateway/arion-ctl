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

defmodule Arion.ControlPlane.AdsServer do
  @moduledoc """
  Delta ADS over one gRPC stream per proxy.

  Every subscription is a wildcard for its type within the proxy's fleet
  (`node.cluster`): the resource names a request subscribes to or unsubscribes
  from are ignored, and every request after the first is treated as an ACK or
  NACK of the response it names. The first request binds the stream to its
  fleet; a later request naming another fleet ends the stream.
  """

  use GRPC.Server,
    service: Arion.ControlPlane.Pb.Envoy.Service.Discovery.V3.AggregatedDiscoveryService.Service

  require Logger

  alias Arion.ControlPlane.AdsServer.StreamHandler

  # Requests are read in a linked process so this one stays free to end the stream:
  # raising a GRPC.RPCError here is the only exit the grpc adapter turns into a status.
  def delta_aggregated_resources(request_stream, reply_stream) do
    Logger.debug("received streaming rpc request for delta aggregated resources")
    rpc = self()
    {:ok, handler} = StreamHandler.start_link(reply_stream, rpc)

    spawn_link(fn ->
      Enum.each(request_stream, &StreamHandler.process_request(handler, &1))
      send(rpc, :requests_done)
    end)

    try do
      receive do
        :requests_done -> :ok
        {:terminate_stream, %GRPC.RPCError{} = error} -> raise error
      end
    after
      stop_handler(handler)
    end
  end

  # An exit here would replace the status being raised.
  defp stop_handler(handler) do
    GenServer.stop(handler)
  catch
    :exit, _ -> :ok
  end
end

defmodule Arion.ControlPlane.AdsServer.StreamHandler do
  @moduledoc false

  use GenServer

  require Logger

  alias Arion.ControlPlane.ClientStates
  alias Arion.ControlPlane.Pb.Data.{DeltaDiscoveryRequest, DeltaDiscoveryResponse, Node}
  alias Arion.ControlPlane.Service
  alias Arion.ControlPlane.Xds.ResourceTypes

  defstruct [:reply_stream, :rpc, :fleet, :client_states, nonce: 0, monitored: MapSet.new()]

  def start_link(reply_stream, rpc), do: GenServer.start_link(__MODULE__, {reply_stream, rpc})

  def process_request(pid, request), do: GenServer.cast(pid, {:request, request})

  @doc "Sends the wire resources of `kind`."
  def publish(pid, kind, wires), do: GenServer.cast(pid, {:publish, kind, wires})

  @doc "Sends the removal of the named resources of `kind`."
  def unpublish(pid, kind, names), do: GenServer.cast(pid, {:unpublish, kind, names})

  @doc "Marks resources ACK'd without sending them: the client already holds these versions."
  def seed_acks(pid, kind, name_versions),
    do: GenServer.cast(pid, {:seed_acks, kind, name_versions})

  @doc "Ends the stream with UNAVAILABLE, so the proxy reconnects and subscribes again."
  def unavailable(pid, message), do: GenServer.cast(pid, {:unavailable, message})

  def acks(pid) do
    GenServer.call(pid, :acks, 1_000)
  catch
    :exit, _ -> %{}
  end

  @impl true
  def init({reply_stream, rpc}) do
    {:ok, %__MODULE__{reply_stream: reply_stream, rpc: rpc, client_states: ClientStates.new()}}
  end

  @impl true
  def handle_call(:acks, _from, state), do: {:reply, state.client_states, state}

  @impl true
  def handle_cast({:request, %DeltaDiscoveryRequest{} = request}, state) do
    case bind(state, request) do
      {:ok, state} -> {:noreply, state |> acknowledge(request) |> subscribe(request)}
      {:error, message} -> close(state, :invalid_argument, message)
    end
  end

  def handle_cast({:publish, kind, wires}, state) do
    response = %DeltaDiscoveryResponse{type_url: ResourceTypes.type_url!(kind), resources: wires}
    name_versions = Enum.map(wires, &{&1.name, &1.version})
    {:noreply, send_response(state, kind, response, name_versions, false)}
  end

  def handle_cast({:unpublish, kind, names}, state) do
    Logger.debug("notifying #{kind} resources removed: #{Enum.join(names, ", ")}")

    response = %DeltaDiscoveryResponse{
      type_url: ResourceTypes.type_url!(kind),
      removed_resources: names
    }

    {:noreply, send_response(state, kind, response, Enum.map(names, &{&1, nil}), true)}
  end

  def handle_cast({:seed_acks, kind, name_versions}, state) do
    client_states =
      Enum.reduce(name_versions, state.client_states, fn {name, version}, acc ->
        ClientStates.seed_ack(acc, kind, name, version)
      end)

    {:noreply, %{state | client_states: client_states}}
  end

  def handle_cast({:unavailable, message}, state), do: close(state, :unavailable, message)

  # A restarted fleet has no subscribers; ending the stream makes the proxy
  # reconnect and subscribe again.
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state),
    do: close(state, :unavailable, "fleet went down")

  # Stops, so nothing queued behind the rejection is sent; the fleet's monitor
  # drops the subscription.
  defp close(state, status, message) do
    send(
      state.rpc,
      {:terminate_stream, GRPC.RPCError.exception(status: status, message: message)}
    )

    {:stop, :normal, state}
  end

  # The node is sent on the first request of a stream and may be omitted later.
  defp bind(%{fleet: nil} = state, request),
    do: {:ok, %{state | fleet: fleet_from(request) || Service.default_fleet()}}

  defp bind(state, request) do
    case fleet_from(request) do
      nil -> {:ok, state}
      fleet when fleet == state.fleet -> {:ok, state}
      other -> {:error, "stream is bound to fleet #{state.fleet}, not #{other}"}
    end
  end

  defp fleet_from(%DeltaDiscoveryRequest{node: %Node{cluster: cluster}})
       when is_binary(cluster) and cluster != "",
       do: cluster

  defp fleet_from(_request), do: nil

  defp acknowledge(state, %{response_nonce: ""}), do: state

  defp acknowledge(state, %{response_nonce: nonce, error_detail: %{code: code} = error} = request)
       when code > 0 do
    error_msg = "error is #{code}, #{error.message}"

    Logger.warning(
      "received negative acknowledgement for resource #{request.type_url}, nonce=#{nonce}, #{error_msg}"
    )

    %{state | client_states: ClientStates.nack(state.client_states, nonce, error_msg)}
  end

  defp acknowledge(state, %{response_nonce: nonce} = request) do
    Logger.debug("received ack for resource #{request.type_url}, nonce=#{nonce}")
    %{state | client_states: ClientStates.ack(state.client_states, nonce)}
  end

  # A plain ACK subscribes to nothing new; the fleet ignores a repeated subscription.
  defp subscribe(state, %{response_nonce: nonce, resource_names_subscribe: []}) when nonce != "",
    do: state

  defp subscribe(state, request) do
    Logger.debug("received subscription for #{request.type_url} in fleet #{state.fleet}")

    pid =
      Service.subscribe(self(), state.fleet, request.type_url, request.initial_resource_versions)

    if MapSet.member?(state.monitored, pid) do
      state
    else
      Process.monitor(pid)
      %{state | monitored: MapSet.put(state.monitored, pid)}
    end
  end

  defp send_response(state, kind, response, name_versions, removed?) do
    nonce = to_string(state.nonce + 1)

    GRPC.Server.send_reply(state.reply_stream, %{
      response
      | nonce: nonce,
        system_version_info: nonce
    })

    client_states = ClientStates.pushed(state.client_states, kind, nonce, name_versions, removed?)
    %{state | nonce: state.nonce + 1, client_states: client_states}
  end
end
