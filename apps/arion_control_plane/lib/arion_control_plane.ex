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

defmodule Arion.ControlPlane do
  @moduledoc """
  Embeddable xDS server. Add `{Arion.ControlPlane, port: 50051}` to your supervisor.

  Resources are grouped into fleets, selected by a proxy's `node.cluster`; one
  control plane serves many fleets in a BEAM node. Loading this dependency does
  not bind a port. Start with `serve?: false`, publish the desired state through
  `Arion.ControlPlane.Service`, then call `serve/1`, so reconnecting proxies are
  never served an empty fleet.
  """

  use Supervisor

  def start_link(opts \\ []),
    do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__.Supervisor)

  @impl true
  def init(opts) do
    children = [
      {Registry, keys: :unique, name: Arion.ControlPlane.Registry},
      {DynamicSupervisor, name: Arion.ControlPlane.FleetSupervisor, strategy: :one_for_one}
    ]

    children =
      if Keyword.get(opts, :serve?, true), do: children ++ [server_child(opts)], else: children

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Starts the xDS server under a control plane started with `serve?: false`, once
  the desired state is published. Idempotent; a control plane restart drops the server.
  """
  def serve(opts \\ []) do
    case Supervisor.start_child(__MODULE__.Supervisor, server_child(opts)) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The server's child spec, for callers managing that lifecycle themselves."
  def server_child(opts \\ []) do
    {GRPC.Server.Supervisor,
     endpoint: Arion.ControlPlane.Endpoint,
     port: Keyword.get(opts, :port, 50051),
     start_server: true}
  end
end
