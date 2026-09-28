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

defmodule Arion.Ctl.Codec do
  @moduledoc """
  Strict protobuf JSON decoding, and the encoding that inverts it: every object
  is checked field by field, and nested `Any` payloads are resolved through the
  type registry in both directions.
  """

  alias Arion.ControlPlane.Xds.ResourceTypes

  @free_form [Google.Protobuf.Struct, Google.Protobuf.Value, Google.Protobuf.ListValue]

  def decode!(kind, data), do: message(ResourceTypes.module!(kind), data, "spec")

  @doc """
  The JSON spec of a `kind` payload, as the snapshot stores it: camelCase field
  names, protobuf JSON scalars, and every nested `Any` expanded under its
  registered `@type`. Raises `ArgumentError` on a payload of another module or
  an `Any` the registry cannot decode.
  """
  def encode!(kind, payload) do
    ResourceTypes.check_module!(kind, payload)
    payload |> to_json("spec") |> Jason.encode!() |> Jason.decode!()
  end

  defp message(Google.Protobuf.Any, %{"@type" => url} = data, path) do
    case ResourceTypes.kind_for_type_url(url) do
      {:ok, kind} ->
        payload = message(ResourceTypes.module!(kind), Map.delete(data, "@type"), path)
        %Google.Protobuf.Any{type_url: url, value: Protobuf.encode(payload)}

      :error ->
        raise ArgumentError, "#{path}: unsupported Any type #{inspect(url)}"
    end
  end

  defp message(Google.Protobuf.Any, _data, path),
    do: raise(ArgumentError, "#{path}: Any needs @type")

  defp message(mod, data, path) when is_map(data) and mod not in @free_form do
    props = mod.__message_props__()

    fields =
      Enum.map(data, fn {key, value} ->
        field = Enum.find(Map.values(props.field_props), &(&1.name == key or &1.json_name == key))
        unless field, do: raise(ArgumentError, "#{path}: unknown field #{inspect(key)}")
        {field, value}
      end)

    unique!(Enum.map(fields, fn {f, _} -> f.name end), "#{path}: duplicate field spelling")
    oneofs = for {f, v} <- fields, v != nil, f.oneof != nil, not f.proto3_optional?, do: f.oneof
    unique!(oneofs, "#{path}: multiple values for oneof")

    {embedded, scalar} = Enum.split_with(fields, fn {f, _} -> f.embedded? end)
    base = json_decode!(Map.new(scalar, fn {f, v} -> {f.name, v} end), mod, path)

    Enum.reduce(embedded, base, fn
      {_field, nil}, acc ->
        acc

      {field, value}, acc ->
        decoded = field_value(field, value, "#{path}.#{field.name}")

        case oneof_name(field, props) do
          nil -> Map.put(acc, field.name_atom, decoded)
          oneof -> Map.put(acc, oneof, {field.name_atom, decoded})
        end
    end)
  end

  # Scalars, wrappers, "1.5s" durations and free-form values, as the library reads them.
  defp message(mod, data, path), do: json_decode!(data, mod, path)

  defp field_value(%{map?: true, type: mod}, values, path) when is_map(values) do
    key_type = mod.__message_props__().field_props[1].type

    Map.new(values, fn {key, value} ->
      entry = message(mod, %{"key" => map_key(key_type, key, path), "value" => value}, path)
      {entry.key, entry.value}
    end)
  end

  defp field_value(%{map?: true}, _values, path),
    do: raise(ArgumentError, "#{path}: expected a map")

  defp field_value(%{repeated?: true, type: mod}, values, path) when is_list(values) do
    for {value, index} <- Enum.with_index(values), do: message(mod, value, "#{path}[#{index}]")
  end

  defp field_value(%{repeated?: true}, _values, path),
    do: raise(ArgumentError, "#{path}: expected a list")

  defp field_value(%{type: mod}, value, path), do: message(mod, value, path)

  defp map_key(:string, key, _path), do: key
  defp map_key(:bool, "true", _path), do: true
  defp map_key(:bool, "false", _path), do: false

  defp map_key(_integer, key, path) do
    case Integer.parse(key) do
      {int, ""} -> int
      _ -> raise ArgumentError, "#{path}: invalid map key #{inspect(key)}"
    end
  end

  defp to_json(%Google.Protobuf.Any{type_url: url, value: bytes}, path) do
    case ResourceTypes.kind_for_type_url(url) do
      {:ok, kind} ->
        bytes
        |> decode_any!(ResourceTypes.module!(kind), path)
        |> to_json(path)
        |> Map.put("@type", url)

      :error ->
        raise ArgumentError, "#{path}: unsupported Any type #{inspect(url)}"
    end
  end

  defp to_json(%mod{} = message, _path) when mod in @free_form, do: encodable!(message)

  # Scalars and well-known types go through the library's JSON encoder; fields
  # holding messages are expanded here, so every Any meets the registry.
  defp to_json(%mod{} = message, path) do
    props = mod.__message_props__()

    fields =
      for {_, %{embedded?: true} = field} <- props.field_props, message_field?(field), do: field

    base = fields |> Enum.reduce(message, &put_field(&2, &1, props, empty(&1))) |> encodable!()

    Enum.reduce(fields, base, fn field, json ->
      case get_field(message, field, props) do
        empty when empty in [nil, [], %{}] ->
          json

        value ->
          Map.put(json, field.json_name, values_json(field, value, "#{path}.#{field.name}"))
      end
    end)
  end

  defp values_json(%{map?: true}, values, path),
    do: Map.new(values, fn {key, value} -> {to_string(key), to_json(value, path)} end)

  defp values_json(%{repeated?: true}, values, path),
    do: for({value, index} <- Enum.with_index(values), do: to_json(value, "#{path}[#{index}]"))

  defp values_json(_field, value, path), do: to_json(value, path)

  # A map field holds messages when its entry's value does.
  defp message_field?(%{map?: true, type: entry}),
    do: entry.__message_props__().field_props[2].embedded?

  defp message_field?(_field), do: true

  defp empty(%{map?: true}), do: %{}
  defp empty(%{repeated?: true}), do: []
  defp empty(_field), do: nil

  defp get_field(message, %{name_atom: name} = field, props) do
    case {oneof_name(field, props), message} do
      {nil, _} -> Map.get(message, name)
      {oneof, _} -> with({^name, value} <- Map.get(message, oneof), do: value, else: (_ -> nil))
    end
  end

  defp put_field(message, field, props, value) do
    case {oneof_name(field, props), get_field(message, field, props)} do
      {nil, _current} -> Map.put(message, field.name_atom, value)
      {_oneof, nil} -> message
      {oneof, _current} -> Map.put(message, oneof, value)
    end
  end

  defp oneof_name(%{oneof: nil}, _props), do: nil
  defp oneof_name(%{proto3_optional?: true}, _props), do: nil

  defp oneof_name(field, props) do
    {name, _index} = Enum.find(props.oneof, fn {_, index} -> index == field.oneof end)
    name
  end

  defp decode_any!(bytes, mod, path) do
    Protobuf.decode(bytes, mod)
  rescue
    Protobuf.DecodeError ->
      reraise ArgumentError, "#{path}: undecodable Any payload", __STACKTRACE__
  end

  defp encodable!(message) do
    case Protobuf.JSON.to_encodable(message) do
      {:ok, json} -> json
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  defp json_decode!(data, mod, path) do
    case Protobuf.JSON.from_decoded(data, mod) do
      {:ok, message} -> message
      {:error, error} -> raise ArgumentError, "#{path}: #{Exception.message(error)}"
    end
  end

  defp unique!(values, error) do
    if values != Enum.uniq(values), do: raise(ArgumentError, error)
  end
end
