defmodule Arion.ControlPlane.Pb.Data.HealthStatus do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.HealthStatus",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :UNKNOWN, 0
  field :HEALTHY, 1
  field :UNHEALTHY, 2
  field :DRAINING, 3
  field :TIMEOUT, 4
  field :DEGRADED, 5
end

defmodule Arion.ControlPlane.Pb.Data.HealthCheck.CodecClientType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.HealthCheck.CodecClientType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :HTTP1, 0
  field :HTTP2, 1
end

defmodule Arion.ControlPlane.Pb.Data.HealthStatusSet do
  @moduledoc false

  use Protobuf,
    full_name: "data.HealthStatusSet",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :statuses, 1, repeated: true, type: Arion.ControlPlane.Pb.Data.HealthStatus, enum: true
end

defmodule Arion.ControlPlane.Pb.Data.HealthCheck.Payload do
  @moduledoc false

  use Protobuf,
    full_name: "data.HealthCheck.Payload",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :payload, 0

  field :text, 1, type: :string, oneof: 0
  field :binary, 2, type: :bytes, oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.HealthCheck.HttpHealthCheck do
  @moduledoc false

  use Protobuf,
    full_name: "data.HealthCheck.HttpHealthCheck",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :host, 1, type: :string
  field :path, 2, type: :string

  field :expected_statuses, 9,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Int64Range,
    json_name: "expectedStatuses"

  field :retriable_statuses, 12,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Int64Range,
    json_name: "retriableStatuses"

  field :codec_client_type, 10,
    type: Arion.ControlPlane.Pb.Data.HealthCheck.CodecClientType,
    json_name: "codecClientType",
    enum: true

  field :method, 13, type: Arion.ControlPlane.Pb.Data.RequestMethod, enum: true
end

defmodule Arion.ControlPlane.Pb.Data.HealthCheck.TcpHealthCheck do
  @moduledoc false

  use Protobuf,
    full_name: "data.HealthCheck.TcpHealthCheck",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :send, 1, type: Arion.ControlPlane.Pb.Data.HealthCheck.Payload
  field :receive, 2, repeated: true, type: Arion.ControlPlane.Pb.Data.HealthCheck.Payload
end

defmodule Arion.ControlPlane.Pb.Data.HealthCheck.GrpcHealthCheck do
  @moduledoc false

  use Protobuf,
    full_name: "data.HealthCheck.GrpcHealthCheck",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :service_name, 1, type: :string, json_name: "serviceName"
end

defmodule Arion.ControlPlane.Pb.Data.HealthCheck do
  @moduledoc false

  use Protobuf,
    full_name: "data.HealthCheck",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :health_checker, 0

  field :timeout, 1, type: Google.Protobuf.Duration
  field :interval, 2, type: Google.Protobuf.Duration
  field :initial_jitter, 20, type: Google.Protobuf.Duration, json_name: "initialJitter"
  field :interval_jitter, 3, type: Google.Protobuf.Duration, json_name: "intervalJitter"
  field :interval_jitter_percent, 18, type: :uint32, json_name: "intervalJitterPercent"
  field :unhealthy_interval, 14, type: Google.Protobuf.Duration, json_name: "unhealthyInterval"

  field :unhealthy_edge_interval, 15,
    type: Google.Protobuf.Duration,
    json_name: "unhealthyEdgeInterval"

  field :healthy_edge_interval, 16,
    type: Google.Protobuf.Duration,
    json_name: "healthyEdgeInterval"

  field :unhealthy_threshold, 4,
    type: Google.Protobuf.UInt32Value,
    json_name: "unhealthyThreshold"

  field :healthy_threshold, 5, type: Google.Protobuf.UInt32Value, json_name: "healthyThreshold"

  field :http_health_check, 8,
    type: Arion.ControlPlane.Pb.Data.HealthCheck.HttpHealthCheck,
    json_name: "httpHealthCheck",
    oneof: 0

  field :tcp_health_check, 9,
    type: Arion.ControlPlane.Pb.Data.HealthCheck.TcpHealthCheck,
    json_name: "tcpHealthCheck",
    oneof: 0

  field :grpc_health_check, 11,
    type: Arion.ControlPlane.Pb.Data.HealthCheck.GrpcHealthCheck,
    json_name: "grpcHealthCheck",
    oneof: 0
end
