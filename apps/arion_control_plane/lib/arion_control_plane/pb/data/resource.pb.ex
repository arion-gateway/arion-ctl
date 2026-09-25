defmodule Arion.ControlPlane.Pb.Data.Resource do
  @moduledoc false

  use Protobuf, full_name: "data.Resource", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :name, 3, type: :string
  field :version, 1, type: :string
  field :resource, 2, type: Google.Protobuf.Any
  field :ttl, 6, type: Google.Protobuf.Duration
end
