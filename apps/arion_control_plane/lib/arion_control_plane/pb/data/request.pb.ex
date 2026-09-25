defmodule Arion.ControlPlane.Pb.Data.RequestMethod do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.RequestMethod",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :METHOD_UNSPECIFIED, 0
  field :GET, 1
  field :HEAD, 2
  field :POST, 3
  field :PUT, 4
  field :DELETE, 5
  field :CONNECT, 6
  field :OPTIONS, 7
  field :TRACE, 8
  field :PATCH, 9
end

defmodule Arion.ControlPlane.Pb.Data.PathMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "data.PathMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :rule, 0

  field :path, 1, type: Arion.ControlPlane.Pb.Data.StringMatcher, oneof: 0
end
