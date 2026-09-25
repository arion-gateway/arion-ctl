defmodule Arion.ControlPlane.Pb.Data.Extensions.LocalRateLimit do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.LocalRateLimit",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :stat_prefix, 1, type: :string, json_name: "statPrefix"
  field :status, 2, type: Arion.ControlPlane.Pb.Data.HttpStatus
  field :token_bucket, 3, type: Arion.ControlPlane.Pb.Data.TokenBucket, json_name: "tokenBucket"

  field :local_rate_limit_per_downstream_connection, 11,
    type: :bool,
    json_name: "localRateLimitPerDownstreamConnection"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ListenerLocalRateLimit do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ListenerLocalRateLimit",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :stat_prefix, 1, type: :string, json_name: "statPrefix"
  field :token_bucket, 2, type: Arion.ControlPlane.Pb.Data.TokenBucket, json_name: "tokenBucket"
end
