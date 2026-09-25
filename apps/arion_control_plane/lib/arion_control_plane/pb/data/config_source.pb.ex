defmodule Arion.ControlPlane.Pb.Data.ApiVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.ApiVersion",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :AUTO, 0
  field :V3, 2
end

defmodule Arion.ControlPlane.Pb.Data.ApiConfigSource.ApiType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.ApiConfigSource.ApiType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :DEPRECATED_AND_UNAVAILABLE_DO_NOT_USE, 0
  field :GPRC, 2
  field :DELTA_GRPC, 3
  field :AGGREGATED_DELTA_GRPC, 6
end

defmodule Arion.ControlPlane.Pb.Data.ApiConfigSource do
  @moduledoc false

  use Protobuf,
    full_name: "data.ApiConfigSource",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :api_type, 1,
    type: Arion.ControlPlane.Pb.Data.ApiConfigSource.ApiType,
    json_name: "apiType",
    enum: true

  field :grpc_services, 4,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.GrpcService,
    json_name: "grpcServices"

  field :request_timeout, 5, type: Google.Protobuf.Duration, json_name: "requestTimeout"

  field :transport_api_version, 8,
    type: Arion.ControlPlane.Pb.Data.ApiVersion,
    json_name: "transportApiVersion",
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.AggregatedConfigSource do
  @moduledoc false

  use Protobuf,
    full_name: "data.AggregatedConfigSource",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.ConfigSource do
  @moduledoc false

  use Protobuf,
    full_name: "data.ConfigSource",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :config_source_specifier, 0

  field :api_config_source, 2,
    type: Arion.ControlPlane.Pb.Data.ApiConfigSource,
    json_name: "apiConfigSource",
    oneof: 0

  field :ads, 3, type: Arion.ControlPlane.Pb.Data.AggregatedConfigSource, oneof: 0

  field :resource_api_version, 6,
    type: Arion.ControlPlane.Pb.Data.ApiVersion,
    json_name: "resourceApiVersion",
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.GrpcService.EnvoyGrpc do
  @moduledoc false

  use Protobuf,
    full_name: "data.GrpcService.EnvoyGrpc",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :cluster_name, 1, type: :string, json_name: "clusterName"

  field :max_receive_message_length, 4,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxReceiveMessageLength"
end

defmodule Arion.ControlPlane.Pb.Data.GrpcService.GoogleGrpc do
  @moduledoc false

  use Protobuf,
    full_name: "data.GrpcService.GoogleGrpc",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :target_uri, 1, type: :string, json_name: "targetUri"
end

defmodule Arion.ControlPlane.Pb.Data.GrpcService do
  @moduledoc false

  use Protobuf,
    full_name: "data.GrpcService",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :target_specifier, 0

  field :envoy_grpc, 1,
    type: Arion.ControlPlane.Pb.Data.GrpcService.EnvoyGrpc,
    json_name: "envoyGrpc",
    oneof: 0

  field :google_grpc, 2,
    type: Arion.ControlPlane.Pb.Data.GrpcService.GoogleGrpc,
    json_name: "googleGrpc",
    oneof: 0

  field :timeout, 3, type: Google.Protobuf.Duration
end
