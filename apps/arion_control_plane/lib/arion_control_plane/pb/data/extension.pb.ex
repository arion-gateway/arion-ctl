defmodule Arion.ControlPlane.Pb.Data.TypedExtensionConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.TypedExtensionConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :typed_config, 2, type: Google.Protobuf.Any, json_name: "typedConfig"
end
