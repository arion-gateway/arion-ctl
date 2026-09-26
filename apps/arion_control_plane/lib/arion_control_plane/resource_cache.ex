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

defmodule Arion.ControlPlane.ResourceCache do
  @moduledoc """
  A fleet's resources by kind and name. Each is encoded once, into the wire
  `Resource` (name, content version, `Any` payload) every stream receives.
  """

  alias Arion.ControlPlane.Pb.Data.Resource
  alias Arion.ControlPlane.Xds.ResourceTypes

  defmodule Entry do
    @moduledoc "A cached resource as given and as sent."
    defstruct [:resource, :wire]
  end

  def new, do: Map.new(ResourceTypes.discovery_kinds(), &{&1, %{}})

  def add(cache, kind, resource) do
    entry = entry(kind, resource)
    put_in(cache[kind][entry.wire.name], entry)
  end

  @doc """
  Encodes a discovery resource, given as its protobuf value or as a
  `{name, value}` pair. Raises `ArgumentError` before any fleet is touched on a
  kind that is not served over ADS, a value of another module, or an empty name.
  """
  def entry(kind, resource) do
    ResourceTypes.discovery_kind!(kind)
    payload = payload_of(resource)
    ResourceTypes.check_module!(kind, payload)
    name = ResourceTypes.resource_name!(resource)
    encoded = Protobuf.encode(payload)

    wire = %Resource{
      name: name,
      version: version(encoded),
      resource: %Google.Protobuf.Any{type_url: ResourceTypes.type_url!(kind), value: encoded}
    }

    %Entry{resource: resource, wire: wire}
  end

  def get(cache, kind, name), do: cache |> Map.fetch!(kind) |> Map.get(name)

  def remove(cache, kind, name), do: Map.update!(cache, kind, &Map.delete(&1, name))

  def list(cache, kind), do: cache |> Map.fetch!(kind) |> Map.values()

  @doc "The resources as given, `%{kind => %{name => resource}}`."
  def resources(cache) do
    Map.new(cache, fn {kind, entries} ->
      {kind, Map.new(entries, fn {name, entry} -> {name, entry.resource} end)}
    end)
  end

  # Derived from the content, so replicas running the same build compute the same
  # version: a client reconnecting to another replica reports versions it can
  # compare, and a resource is resent only when its bytes changed.
  defp version(encoded), do: :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower)

  defp payload_of({name, payload}) when is_binary(name), do: payload
  defp payload_of(payload), do: payload
end
