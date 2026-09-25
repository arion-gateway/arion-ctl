defmodule Arion.ControlPlane.Pb.Data.Extensions.TlsInspector do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.TlsInspector",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :enable_ja3_fingerprinting, 1,
    type: Google.Protobuf.BoolValue,
    json_name: "enableJa3Fingerprinting"

  field :initial_read_buffer_size, 2,
    type: Google.Protobuf.UInt32Value,
    json_name: "initialReadBufferSize"
end
