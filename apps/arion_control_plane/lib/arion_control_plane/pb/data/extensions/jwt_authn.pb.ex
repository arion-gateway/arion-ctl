defmodule Arion.ControlPlane.Pb.Data.Extensions.HttpUri do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HttpUri",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :http_upstream_type, 0

  field :uri, 1, type: :string
  field :cluster, 2, type: :string, oneof: 0
  field :timeout, 3, type: Google.Protobuf.Duration
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.BackoffStrategy do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.BackoffStrategy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :base_interval, 1, type: Google.Protobuf.Duration, json_name: "baseInterval"
  field :max_interval, 2, type: Google.Protobuf.Duration, json_name: "maxInterval"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.CoreRetryPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.CoreRetryPolicy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :retry_back_off, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.BackoffStrategy,
    json_name: "retryBackOff"

  field :num_retries, 2, type: Google.Protobuf.UInt32Value, json_name: "numRetries"
  field :retry_on, 3, type: :string, json_name: "retryOn"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RemoteJwks do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RemoteJwks",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :http_uri, 1, type: Arion.ControlPlane.Pb.Data.Extensions.HttpUri, json_name: "httpUri"
  field :cache_duration, 2, type: Google.Protobuf.Duration, json_name: "cacheDuration"

  field :retry_policy, 4,
    type: Arion.ControlPlane.Pb.Data.Extensions.CoreRetryPolicy,
    json_name: "retryPolicy"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.JwtHeader do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.JwtHeader",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :value_prefix, 2, type: :string, json_name: "valuePrefix"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.JwtClaimToHeader do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.JwtClaimToHeader",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :header_name, 1, type: :string, json_name: "headerName"
  field :claim_name, 2, type: :string, json_name: "claimName"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.JwtProvider do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.JwtProvider",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :jwks_source_specifier, 0

  field :issuer, 1, type: :string
  field :audiences, 2, repeated: true, type: :string
  field :subjects, 19, type: Arion.ControlPlane.Pb.Data.StringMatcher

  field :remote_jwks, 3,
    type: Arion.ControlPlane.Pb.Data.Extensions.RemoteJwks,
    json_name: "remoteJwks",
    oneof: 0

  field :local_jwks, 4,
    type: Arion.ControlPlane.Pb.Data.DataSource,
    json_name: "localJwks",
    oneof: 0

  field :forward, 5, type: :bool

  field :from_headers, 6,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.JwtHeader,
    json_name: "fromHeaders"

  field :from_params, 7, repeated: true, type: :string, json_name: "fromParams"
  field :from_cookies, 13, repeated: true, type: :string, json_name: "fromCookies"
  field :forward_payload_header, 8, type: :string, json_name: "forwardPayloadHeader"
  field :pad_forward_payload_header, 11, type: :bool, json_name: "padForwardPayloadHeader"
  field :payload_in_metadata, 9, type: :string, json_name: "payloadInMetadata"
  field :header_in_metadata, 14, type: :string, json_name: "headerInMetadata"
  field :failed_status_in_metadata, 16, type: :string, json_name: "failedStatusInMetadata"
  field :clock_skew_seconds, 10, type: :uint32, json_name: "clockSkewSeconds"
  field :clear_route_cache, 17, type: :bool, json_name: "clearRouteCache"

  field :claim_to_headers, 15,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.JwtClaimToHeader,
    json_name: "claimToHeaders"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.JwtRequirement do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.JwtRequirement",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :requires_type, 0

  field :provider_name, 1, type: :string, json_name: "providerName", oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RequirementRule do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RequirementRule",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :requirement_type, 0

  field :match, 1, type: Arion.ControlPlane.Pb.Route.RouteMatch
  field :requires, 2, type: Arion.ControlPlane.Pb.Data.Extensions.JwtRequirement, oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.JwtAuthentication.ProvidersEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.JwtAuthentication.ProvidersEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Arion.ControlPlane.Pb.Data.Extensions.JwtProvider
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.JwtAuthentication do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.JwtAuthentication",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :providers, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.JwtAuthentication.ProvidersEntry,
    map: true

  field :rules, 2, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.RequirementRule
end
