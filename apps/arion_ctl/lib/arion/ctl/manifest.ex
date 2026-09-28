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

defmodule Arion.Ctl.Manifest do
  @moduledoc """
  Versioned resource documents: `apiVersion`, `kind`, `metadata` (`name`, and
  `fleet` for the proxies' `node.cluster`) and the resource `spec`.
  """

  alias Arion.ControlPlane.Service
  alias Arion.ControlPlane.Xds.ResourceTypes
  alias Arion.Ctl.Codec

  @version "ctl.arion.io/v1alpha1"

  # Core resource names are part of the protobuf and must match metadata.name;
  # MCP delta names identify a gateway/listener independently of the payload.
  @name_field %{
    cluster: {"name", "name"},
    listener: {"name", "name"},
    route: {"name", "name"},
    secret: {"name", "name"},
    load_assignment: {"cluster_name", "clusterName"}
  }

  @doc """
  Decodes a YAML document stream, a JSON array, or a list of maps into entries:
  `%{id: {fleet, kind, name}, fleet, kind, name, payload, manifest}`. Nothing is
  returned unless every document decodes and encodes.
  """
  def decode(input) when is_binary(input) or is_list(input) do
    entries = input |> documents!() |> Enum.map(&entry!/1)
    ids = Enum.map(entries, & &1.id)
    if ids != Enum.uniq(ids), do: raise(ArgumentError, "duplicate resource identity in input")
    {:ok, entries}
  rescue
    error -> {:error, Exception.message(error)}
  end

  def decode(_input),
    do: {:error, "expected YAML or JSON resource documents, or a list of resource maps"}

  @doc """
  The documents of helper-built resources, given as `{kind, payload}` or
  `{kind, {name, payload}}` pairs like `Arion.ControlPlane.Service.replace/2`
  takes them: `{:ok, documents}` or `{:error, message}`. The documents still
  go through `decode/1`, which checks that a payload's own name agrees.
  """
  def from_resources(fleet, resources) when is_list(resources) do
    {:ok, Enum.map(resources, &document!(fleet, &1))}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp document!(fleet, {kind, resource}) do
    ResourceTypes.discovery_kind!(kind)
    name = ResourceTypes.resource_name!(resource)
    payload = with {_name, payload} <- resource, do: payload

    %{
      "apiVersion" => @version,
      "kind" => ResourceTypes.api_kind!(kind),
      "metadata" => %{"name" => name, "fleet" => fleet},
      "spec" => Codec.encode!(kind, payload)
    }
  end

  defp document!(_fleet, _other), do: raise(ArgumentError, "expected {kind, resource} pairs")

  defp documents!(yaml) when is_binary(yaml) do
    case YamlElixir.read_all_from_string!(yaml) do
      [resources] when is_list(resources) -> resources
      documents -> documents
    end
  end

  defp documents!(documents), do: documents

  defp entry!(doc) do
    object!(doc, "document", ~w(apiVersion kind metadata spec))
    doc["apiVersion"] == @version || raise(ArgumentError, "apiVersion must be #{@version}")
    kind = kind!(doc["kind"])
    meta = object!(doc["metadata"], "metadata", ~w(name), ~w(fleet))
    name = nonempty!(meta["name"], "metadata.name")
    fleet = nonempty!(Map.get(meta, "fleet", Service.default_fleet()), "metadata.fleet")
    payload = Codec.decode!(kind, named_spec!(kind, doc["spec"], name))
    # Encoded now, so a payload the wire rejects never becomes a partial commit.
    Protobuf.encode(payload)

    %{
      id: {fleet, kind, name},
      fleet: fleet,
      kind: kind,
      name: name,
      payload: payload,
      manifest: Map.put(doc, "metadata", %{"name" => name, "fleet" => fleet})
    }
  end

  defp kind!(api_kind) do
    case ResourceTypes.kind_for_api_kind(api_kind) do
      {:ok, kind} -> kind
      :error -> raise ArgumentError, "unsupported kind #{inspect(api_kind)}"
    end
  end

  defp named_spec!(kind, spec, name) do
    spec = object!(spec, "spec", [], :any)

    case @name_field[kind] do
      nil ->
        spec

      {field, json_field} ->
        if field != json_field and Map.has_key?(spec, field) and Map.has_key?(spec, json_field),
          do: raise(ArgumentError, "spec: #{field} and #{json_field} are the same field")

        given = Map.get(spec, field, Map.get(spec, json_field))

        if given not in [nil, name],
          do: raise(ArgumentError, "metadata.name and spec #{json_field} disagree")

        spec |> Map.delete(json_field) |> Map.put(field, name)
    end
  end

  defp object!(map, label, required, optional \\ [])

  defp object!(map, label, required, optional) when is_map(map) do
    for key <- required,
        not Map.has_key?(map, key),
        do: raise(ArgumentError, "#{label}: missing #{key}")

    if optional != :any do
      for key <- Map.keys(map),
          key not in (required ++ optional),
          do: raise(ArgumentError, "#{label}: unknown field #{inspect(key)}")
    end

    map
  end

  defp object!(_map, label, _required, _optional),
    do: raise(ArgumentError, "#{label} must be an object")

  defp nonempty!(value, _field) when is_binary(value) and byte_size(value) > 0, do: value
  defp nonempty!(_value, field), do: raise(ArgumentError, "#{field} must be a nonempty string")
end
