defmodule Arion.ControlPlane.Pb.Data.TransportSocket do
  @moduledoc false

  use Protobuf,
    full_name: "data.TransportSocket",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :config_type, 0

  field :name, 1, type: :string
  field :typed_config, 3, type: Google.Protobuf.Any, json_name: "typedConfig", oneof: 0
end
