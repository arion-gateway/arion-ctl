defmodule Arion.ControlPlane.Pb.Data.Extensions.SimpleRateLimit do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.SimpleRateLimit",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :max_tokens, 1, type: :uint32, json_name: "maxTokens"
  field :rate, 2, type: :uint32
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.UserRateLimit do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.UserRateLimit",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :limit, 0

  field :user_id, 1, proto3_optional: true, type: :string, json_name: "userId"

  field :local_rate_limit, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.LocalRateLimit,
    json_name: "localRateLimit",
    oneof: 0

  field :simple_rate_limit, 3,
    type: Arion.ControlPlane.Pb.Data.Extensions.SimpleRateLimit,
    json_name: "simpleRateLimit",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.UserRateLimiter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.UserRateLimiter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :user_id_header_name, 1, type: :string, json_name: "userIdHeaderName"
  field :stat_prefix, 2, type: :string, json_name: "statPrefix"
  field :status, 3, type: Arion.ControlPlane.Pb.Data.HttpStatus

  field :user_rate_limits, 4,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.UserRateLimit,
    json_name: "userRateLimits"
end
