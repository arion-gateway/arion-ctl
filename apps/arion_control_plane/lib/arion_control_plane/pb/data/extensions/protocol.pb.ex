defmodule Arion.ControlPlane.Pb.Data.Extensions.HttpProtocolOptions.ExplicitHttpConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HttpProtocolOptions.ExplicitHttpConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :protocol_config, 0

  field :http_protocol_options, 1,
    type: Arion.ControlPlane.Pb.Data.Http1ProtocolOptions,
    json_name: "httpProtocolOptions",
    oneof: 0

  field :http2_protocol_options, 2,
    type: Arion.ControlPlane.Pb.Data.Http2ProtocolOptions,
    json_name: "http2ProtocolOptions",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HttpProtocolOptions.UseDownstreamHttpConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HttpProtocolOptions.UseDownstreamHttpConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :http_protocol_options, 1,
    type: Arion.ControlPlane.Pb.Data.Http1ProtocolOptions,
    json_name: "httpProtocolOptions"

  field :http2_protocol_options, 2,
    type: Arion.ControlPlane.Pb.Data.Http2ProtocolOptions,
    json_name: "http2ProtocolOptions"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HttpProtocolOptions.AutoHttpConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HttpProtocolOptions.AutoHttpConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :http_protocol_options, 1,
    type: Arion.ControlPlane.Pb.Data.Http1ProtocolOptions,
    json_name: "httpProtocolOptions"

  field :http2_protocol_options, 2,
    type: Arion.ControlPlane.Pb.Data.Http2ProtocolOptions,
    json_name: "http2ProtocolOptions"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HttpProtocolOptions do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HttpProtocolOptions",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :upstream_protocol_options, 0

  field :common_http_protocol_options, 1,
    type: Arion.ControlPlane.Pb.Data.HttpProtocolOptions,
    json_name: "commonHttpProtocolOptions"

  field :upstream_http_protocol_options, 2,
    type: Arion.ControlPlane.Pb.Data.UpstreamHttpProtocolOptions,
    json_name: "upstreamHttpProtocolOptions"

  field :explicit_http_config, 3,
    type: Arion.ControlPlane.Pb.Data.Extensions.HttpProtocolOptions.ExplicitHttpConfig,
    json_name: "explicitHttpConfig",
    oneof: 0

  field :use_downstream_protocol_config, 4,
    type: Arion.ControlPlane.Pb.Data.Extensions.HttpProtocolOptions.UseDownstreamHttpConfig,
    json_name: "useDownstreamProtocolConfig",
    oneof: 0

  field :auto_config, 5,
    type: Arion.ControlPlane.Pb.Data.Extensions.HttpProtocolOptions.AutoHttpConfig,
    json_name: "autoConfig",
    oneof: 0
end
