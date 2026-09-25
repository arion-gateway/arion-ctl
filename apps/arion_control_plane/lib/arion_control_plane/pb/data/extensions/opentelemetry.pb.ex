defmodule Arion.ControlPlane.Pb.Data.Extensions.OpenTelemetryConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.OpenTelemetryConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :grpc_service, 1, type: Arion.ControlPlane.Pb.Data.GrpcService, json_name: "grpcService"
  field :service_name, 2, type: :string, json_name: "serviceName"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.OpenTelemetrySinkConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.OpenTelemetrySinkConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :protocol_specifier, 0

  field :grpc_service, 1,
    type: Arion.ControlPlane.Pb.Data.GrpcService,
    json_name: "grpcService",
    oneof: 0

  field :report_counters_as_deltas, 2, type: :bool, json_name: "reportCountersAsDeltas"
  field :report_histograms_as_deltas, 3, type: :bool, json_name: "reportHistogramsAsDeltas"
  field :prefix, 6, type: :string
end
