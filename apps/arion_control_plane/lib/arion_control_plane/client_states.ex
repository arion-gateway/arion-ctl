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

defmodule Arion.ControlPlane.ClientStates do
  @moduledoc """
  What one stream has been sent and what it answered: per kind and name,
  `{:ack, version}` or `{:nack, version, error}`, plus the responses still
  pending under their nonce.
  """

  alias Arion.ControlPlane.Xds.ResourceTypes

  def new do
    ResourceTypes.discovery_kinds()
    |> Map.new(&{&1, %{}})
    |> Map.put(:pending, %{})
  end

  @doc "Records a response of `[{name, version}]` pending under `nonce`."
  def pushed(states, kind, nonce, name_versions, removed?) do
    put_in(states[:pending][nonce], {kind, name_versions, removed?})
  end

  @doc "Marks a resource accepted without a round trip: the client already holds this version."
  def seed_ack(states, kind, name, version), do: put_in(states[kind][name], {:ack, version})

  def ack(states, nonce) do
    case pop_in(states[:pending][nonce]) do
      {{kind, name_versions, false}, states} ->
        Enum.reduce(name_versions, states, fn {name, version}, states ->
          put_in(states[kind][name], {:ack, version})
        end)

      # An acknowledged removal: the stream no longer holds the resource.
      {{kind, name_versions, true}, states} ->
        Enum.reduce(name_versions, states, fn {name, _}, states ->
          elem(pop_in(states[kind][name]), 1)
        end)

      {nil, states} ->
        states
    end
  end

  def nack(states, nonce, error) do
    case pop_in(states[:pending][nonce]) do
      {{kind, name_versions, false}, states} ->
        Enum.reduce(name_versions, states, fn {name, version}, states ->
          put_in(states[kind][name], {:nack, version, error})
        end)

      # Arion rejects removing an assignment whose cluster a replay already removed;
      # the resource is gone either way.
      {{_kind, _name_versions, true}, _states} ->
        ack(states, nonce)

      {nil, states} ->
        states
    end
  end
end
