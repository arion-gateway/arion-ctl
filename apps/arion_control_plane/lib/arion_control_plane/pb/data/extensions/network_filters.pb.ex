defmodule Arion.ControlPlane.Pb.Data.Extensions.ConnectionLimit do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ConnectionLimit",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :stat_prefix, 1, type: :string, json_name: "statPrefix"
  field :max_connections, 2, type: Google.Protobuf.UInt64Value, json_name: "maxConnections"
  field :delay, 3, type: Google.Protobuf.Duration
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RateLimitDescriptor.Entry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RateLimitDescriptor.Entry",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RateLimitDescriptor do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RateLimitDescriptor",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :entries, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.RateLimitDescriptor.Entry
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RateLimitServiceConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RateLimitServiceConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :grpc_service, 2, type: Arion.ControlPlane.Pb.Data.GrpcService, json_name: "grpcService"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.NetworkRateLimit do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.NetworkRateLimit",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :stat_prefix, 1, type: :string, json_name: "statPrefix"
  field :domain, 2, type: :string

  field :descriptors, 3,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.RateLimitDescriptor

  field :failure_mode_deny, 5, type: :bool, json_name: "failureModeDeny"

  field :rate_limit_service, 6,
    type: Arion.ControlPlane.Pb.Data.Extensions.RateLimitServiceConfig,
    json_name: "rateLimitService"
end
