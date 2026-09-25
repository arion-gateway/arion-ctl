defmodule Arion.ControlPlane.Pb.Filter.HttpConnectionManager.CodecType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "filter.HttpConnectionManager.CodecType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :AUTO, 0
  field :HTTP1, 1
  field :HTTP2, 2
  field :HTTP3, 3
end

defmodule Arion.ControlPlane.Pb.Filter.HttpConnectionManager.Tracing.Provider do
  @moduledoc false

  use Protobuf,
    full_name: "filter.HttpConnectionManager.Tracing.Provider",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :config_type, 0

  field :name, 1, type: :string
  field :typed_config, 3, type: Google.Protobuf.Any, json_name: "typedConfig", oneof: 0
end

defmodule Arion.ControlPlane.Pb.Filter.HttpConnectionManager.Tracing do
  @moduledoc false

  use Protobuf,
    full_name: "filter.HttpConnectionManager.Tracing",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :client_sampling, 3, type: Arion.ControlPlane.Pb.Data.Percent, json_name: "clientSampling"
  field :random_sampling, 4, type: Arion.ControlPlane.Pb.Data.Percent, json_name: "randomSampling"

  field :overall_sampling, 5,
    type: Arion.ControlPlane.Pb.Data.Percent,
    json_name: "overallSampling"

  field :verbose, 6, type: :bool
  field :max_path_tag_length, 7, type: Google.Protobuf.UInt32Value, json_name: "maxPathTagLength"
  field :provider, 9, type: Arion.ControlPlane.Pb.Filter.HttpConnectionManager.Tracing.Provider
  field :spawn_upstream_span, 10, type: Google.Protobuf.BoolValue, json_name: "spawnUpstreamSpan"
end

defmodule Arion.ControlPlane.Pb.Filter.HttpConnectionManager.UpgradeConfig do
  @moduledoc false

  use Protobuf,
    full_name: "filter.HttpConnectionManager.UpgradeConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :upgrade_type, 1, type: :string, json_name: "upgradeType"
  field :enabled, 3, type: Google.Protobuf.BoolValue
end

defmodule Arion.ControlPlane.Pb.Filter.HttpConnectionManager do
  @moduledoc false

  use Protobuf,
    full_name: "filter.HttpConnectionManager",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :route_specifier, 0

  field :codec_type, 1,
    type: Arion.ControlPlane.Pb.Filter.HttpConnectionManager.CodecType,
    json_name: "codecType",
    enum: true

  field :stat_prefix, 2, type: :string, json_name: "statPrefix"
  field :rds, 3, type: Arion.ControlPlane.Pb.Filter.Rds, oneof: 0

  field :route_config, 4,
    type: Arion.ControlPlane.Pb.Route.RouteConfiguration,
    json_name: "routeConfig",
    oneof: 0

  field :http_filters, 5,
    repeated: true,
    type: Arion.ControlPlane.Pb.Filter.HttpFilter,
    json_name: "httpFilters"

  field :tracing, 7, type: Arion.ControlPlane.Pb.Filter.HttpConnectionManager.Tracing

  field :http_protocol_options, 8,
    type: Arion.ControlPlane.Pb.Data.Http1ProtocolOptions,
    json_name: "httpProtocolOptions"

  field :http2_protocol_options, 9,
    type: Arion.ControlPlane.Pb.Data.Http2ProtocolOptions,
    json_name: "http2ProtocolOptions"

  field :access_log, 13,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLog,
    json_name: "accessLog"

  field :use_remote_address, 14, type: Google.Protobuf.BoolValue, json_name: "useRemoteAddress"
  field :generate_request_id, 15, type: Google.Protobuf.BoolValue, json_name: "generateRequestId"
  field :xff_num_trusted_hops, 19, type: :uint32, json_name: "xffNumTrustedHops"
  field :skip_xff_append, 21, type: :bool, json_name: "skipXffAppend"

  field :upgrade_configs, 23,
    repeated: true,
    type: Arion.ControlPlane.Pb.Filter.HttpConnectionManager.UpgradeConfig,
    json_name: "upgradeConfigs"

  field :request_timeout, 28, type: Google.Protobuf.Duration, json_name: "requestTimeout"
  field :preserve_external_request_id, 32, type: :bool, json_name: "preserveExternalRequestId"

  field :always_set_request_id_in_response, 37,
    type: :bool,
    json_name: "alwaysSetRequestIdInResponse"
end

defmodule Arion.ControlPlane.Pb.Filter.Rds do
  @moduledoc false

  use Protobuf, full_name: "filter.Rds", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :config_source, 1,
    type: Arion.ControlPlane.Pb.Data.ConfigSource,
    json_name: "configSource"

  field :route_config_name, 2, type: :string, json_name: "routeConfigName"
end

defmodule Arion.ControlPlane.Pb.Filter.HttpFilter do
  @moduledoc false

  use Protobuf,
    full_name: "filter.HttpFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :config_type, 0

  field :name, 1, type: :string
  field :typed_config, 4, type: Google.Protobuf.Any, json_name: "typedConfig", oneof: 0
end
