defmodule Arion.ControlPlane.Pb.Data.DataSource do
  @moduledoc false

  use Protobuf, full_name: "data.DataSource", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :specifier, 0

  field :filename, 1, type: :string, oneof: 0
  field :inline_bytes, 2, type: :bytes, json_name: "inlineBytes", oneof: 0
  field :inline_string, 3, type: :string, json_name: "inlineString", oneof: 0
  field :environment_variable, 4, type: :string, json_name: "environmentVariable", oneof: 0
end
