defmodule Arion.ControlPlane.Pb.Data.Extensions.ProxyProtocolUpstreamTransport do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ProxyProtocolUpstreamTransport",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :config, 1, type: Arion.ControlPlane.Pb.Data.ProxyProtocolConfig

  field :transport_socket, 2,
    type: Arion.ControlPlane.Pb.Data.TransportSocket,
    json_name: "transportSocket"
end
