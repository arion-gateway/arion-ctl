defmodule Arion.ControlPlane.Pb.Route.RetryPolicy.ResetHeaderFormat do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "route.RetryPolicy.ResetHeaderFormat",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :SECONDS, 0
  field :UNIX_TIMESTAMP, 1
end

defmodule Arion.ControlPlane.Pb.Route.RetryPolicy.RetryBackOff do
  @moduledoc false

  use Protobuf,
    full_name: "route.RetryPolicy.RetryBackOff",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :base_interval, 1, type: Google.Protobuf.Duration, json_name: "baseInterval"
  field :max_interval, 2, type: Google.Protobuf.Duration, json_name: "maxInterval"
end

defmodule Arion.ControlPlane.Pb.Route.RetryPolicy.ResetHeader do
  @moduledoc false

  use Protobuf,
    full_name: "route.RetryPolicy.ResetHeader",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :format, 2, type: Arion.ControlPlane.Pb.Route.RetryPolicy.ResetHeaderFormat, enum: true
end

defmodule Arion.ControlPlane.Pb.Route.RetryPolicy.RateLimitedRetryBackOff do
  @moduledoc false

  use Protobuf,
    full_name: "route.RetryPolicy.RateLimitedRetryBackOff",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :reset_headers, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Route.RetryPolicy.ResetHeader,
    json_name: "resetHeaders"

  field :max_interval, 2, type: Google.Protobuf.Duration, json_name: "maxInterval"
end

defmodule Arion.ControlPlane.Pb.Route.RetryPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "route.RetryPolicy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :retry_on, 1, type: :string, json_name: "retryOn"
  field :num_retries, 2, type: Google.Protobuf.UInt32Value, json_name: "numRetries"
  field :per_try_timeout, 3, type: Google.Protobuf.Duration, json_name: "perTryTimeout"

  field :retriable_status_codes, 7,
    repeated: true,
    type: :uint32,
    json_name: "retriableStatusCodes"

  field :retry_back_off, 8,
    type: Arion.ControlPlane.Pb.Route.RetryPolicy.RetryBackOff,
    json_name: "retryBackOff"

  field :retriable_headers, 9,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HeaderMatcher,
    json_name: "retriableHeaders"

  field :retriable_request_headers, 10,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HeaderMatcher,
    json_name: "retriableRequestHeaders"
end
