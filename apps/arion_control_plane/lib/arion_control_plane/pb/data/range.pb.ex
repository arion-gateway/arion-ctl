defmodule Arion.ControlPlane.Pb.Data.Int64Range do
  @moduledoc false

  use Protobuf, full_name: "data.Int64Range", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :start, 1, type: :int64
  field :end, 2, type: :int64
end

defmodule Arion.ControlPlane.Pb.Data.Int32Range do
  @moduledoc false

  use Protobuf, full_name: "data.Int32Range", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :start, 1, type: :int32
  field :end, 2, type: :int32
end

defmodule Arion.ControlPlane.Pb.Data.DoubleRange do
  @moduledoc false

  use Protobuf,
    full_name: "data.DoubleRange",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :start, 1, type: :double
  field :end, 2, type: :double
end
