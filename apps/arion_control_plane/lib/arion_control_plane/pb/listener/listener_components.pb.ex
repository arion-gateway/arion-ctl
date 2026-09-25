defmodule Arion.ControlPlane.Pb.Listener.FilterChainMatch.ConnectionSourceType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "listener.FilterChainMatch.ConnectionSourceType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :ANY, 0
  field :SAME_IP_OR_LOOPBACK, 1
  field :EXTERNAL, 2
end

defmodule Arion.ControlPlane.Pb.Listener.Filter do
  @moduledoc false

  use Protobuf, full_name: "listener.Filter", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :config_type, 0

  field :name, 1, type: :string
  field :typed_config, 4, type: Google.Protobuf.Any, json_name: "typedConfig", oneof: 0
end

defmodule Arion.ControlPlane.Pb.Listener.FilterChainMatch do
  @moduledoc false

  use Protobuf,
    full_name: "listener.FilterChainMatch",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :destination_port, 8, type: Google.Protobuf.UInt32Value, json_name: "destinationPort"

  field :prefix_ranges, 3,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.CidrRange,
    json_name: "prefixRanges"

  field :source_type, 12,
    type: Arion.ControlPlane.Pb.Listener.FilterChainMatch.ConnectionSourceType,
    json_name: "sourceType",
    enum: true

  field :source_ports, 7, repeated: true, type: :uint32, json_name: "sourcePorts"
  field :server_names, 11, repeated: true, type: :string, json_name: "serverNames"
  field :transport_protocol, 9, type: :string, json_name: "transportProtocol"

  field :application_protocols, 10,
    repeated: true,
    type: :string,
    json_name: "applicationProtocols"
end

defmodule Arion.ControlPlane.Pb.Listener.FilterChain do
  @moduledoc false

  use Protobuf,
    full_name: "listener.FilterChain",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :filter_chain_match, 1,
    type: Arion.ControlPlane.Pb.Listener.FilterChainMatch,
    json_name: "filterChainMatch"

  field :filters, 3, repeated: true, type: Arion.ControlPlane.Pb.Listener.Filter

  field :transport_socket, 6,
    type: Arion.ControlPlane.Pb.Data.TransportSocket,
    json_name: "transportSocket"

  field :transport_socket_connect_timeout, 9,
    type: Google.Protobuf.Duration,
    json_name: "transportSocketConnectTimeout"

  field :name, 7, type: :string
end

defmodule Arion.ControlPlane.Pb.Listener.ListenerFilter do
  @moduledoc false

  use Protobuf,
    full_name: "listener.ListenerFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :config_type, 0

  field :name, 1, type: :string
  field :typed_config, 3, type: Google.Protobuf.Any, json_name: "typedConfig", oneof: 0
end
