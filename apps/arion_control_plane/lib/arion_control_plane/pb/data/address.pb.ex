defmodule Arion.ControlPlane.Pb.Data.SocketAddress.Protocol do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.SocketAddress.Protocol",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :TCP, 0
  field :UDP, 1
end

defmodule Arion.ControlPlane.Pb.Data.Address do
  @moduledoc false

  use Protobuf, full_name: "data.Address", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :address, 0

  field :socket_address, 1,
    type: Arion.ControlPlane.Pb.Data.SocketAddress,
    json_name: "socketAddress",
    oneof: 0

  field :pipe, 2, type: Arion.ControlPlane.Pb.Data.Pipe, oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Pipe do
  @moduledoc false

  use Protobuf, full_name: "data.Pipe", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :path, 1, type: :string
  field :mode, 2, type: :uint32
end

defmodule Arion.ControlPlane.Pb.Data.SocketAddress do
  @moduledoc false

  use Protobuf,
    full_name: "data.SocketAddress",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :port_specifier, 0

  field :protocol, 1, type: Arion.ControlPlane.Pb.Data.SocketAddress.Protocol, enum: true
  field :address, 2, type: :string
  field :port_value, 3, type: :uint32, json_name: "portValue", oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.TcpKeepalive do
  @moduledoc false

  use Protobuf,
    full_name: "data.TcpKeepalive",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :keepalive_probes, 1, type: Google.Protobuf.UInt32Value, json_name: "keepaliveProbes"
  field :keepalive_time, 2, type: Google.Protobuf.UInt32Value, json_name: "keepaliveTime"
  field :keepalive_interval, 3, type: Google.Protobuf.UInt32Value, json_name: "keepaliveInterval"
end

defmodule Arion.ControlPlane.Pb.Data.BindConfig do
  @moduledoc false

  use Protobuf, full_name: "data.BindConfig", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :source_address, 1,
    type: Arion.ControlPlane.Pb.Data.SocketAddress,
    json_name: "sourceAddress"

  field :freebind, 2, type: Google.Protobuf.BoolValue

  field :socket_options, 3,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.SocketOption,
    json_name: "socketOptions"
end

defmodule Arion.ControlPlane.Pb.Data.CidrRange do
  @moduledoc false

  use Protobuf, full_name: "data.CidrRange", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :address_prefix, 1, type: :string, json_name: "addressPrefix"
  field :prefix_len, 2, type: Google.Protobuf.UInt32Value, json_name: "prefixLen"
end
