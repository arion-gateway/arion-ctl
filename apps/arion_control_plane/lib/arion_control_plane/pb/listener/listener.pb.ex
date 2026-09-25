defmodule Arion.ControlPlane.Pb.Listener.Listener do
  @moduledoc false

  use Protobuf,
    full_name: "listener.Listener",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :address, 2, type: Arion.ControlPlane.Pb.Data.Address
  field :stat_prefix, 28, type: :string, json_name: "statPrefix"

  field :filter_chains, 3,
    repeated: true,
    type: Arion.ControlPlane.Pb.Listener.FilterChain,
    json_name: "filterChains"

  field :listener_filters, 9,
    repeated: true,
    type: Arion.ControlPlane.Pb.Listener.ListenerFilter,
    json_name: "listenerFilters"

  field :socket_options, 13,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.SocketOption,
    json_name: "socketOptions"

  field :enable_reuse_port, 29, type: Google.Protobuf.BoolValue, json_name: "enableReusePort"

  field :access_log, 22,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLog,
    json_name: "accessLog"
end
