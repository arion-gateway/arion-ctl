defmodule Arion.ControlPlane.Pb.Data.Extensions.ProxyProtocolListenerFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ProxyProtocolListenerFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :allow_requests_without_proxy_protocol, 2,
    type: :bool,
    json_name: "allowRequestsWithoutProxyProtocol"

  field :pass_through_tlvs, 3,
    type: Arion.ControlPlane.Pb.Data.ProxyProtocolPassThroughTLVs,
    json_name: "passThroughTlvs"

  field :disallowed_versions, 4,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.ProxyProtocolConfig.Version,
    json_name: "disallowedVersions",
    enum: true

  field :stat_prefix, 5, type: :string, json_name: "statPrefix"
end
