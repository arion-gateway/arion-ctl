defmodule Arion.ControlPlane.Pb.Data.SocketOption.SocketState do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.SocketOption.SocketState",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :STATE_PREBIND, 0
  field :STATE_BOUND, 1
  field :STATE_LISTENING, 2
end

defmodule Arion.ControlPlane.Pb.Data.SocketOption do
  @moduledoc false

  use Protobuf,
    full_name: "data.SocketOption",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :value, 0

  field :description, 1, type: :string
  field :level, 2, type: :int64
  field :name, 3, type: :int64
  field :int_value, 4, type: :int64, json_name: "intValue", oneof: 0
  field :buf_value, 5, type: :bytes, json_name: "bufValue", oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.SocketOptionsOverride do
  @moduledoc false

  use Protobuf,
    full_name: "data.SocketOptionsOverride",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :socket_options, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.SocketOption,
    json_name: "socketOptions"
end
