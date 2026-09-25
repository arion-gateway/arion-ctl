defmodule Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode.HeaderSendMode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.ProcessingMode.HeaderSendMode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :DEFAULT, 0
  field :SEND, 1
  field :SKIP, 2
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode.BodySendMode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.ProcessingMode.BodySendMode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :NONE, 0
  field :STREAMED, 1
  field :BUFFERED, 2
  field :BUFFERED_PARTIAL, 3
  field :FULL_DUPLEX_STREAMED, 4
  field :GRPC, 5
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ExternalProcessor.RouteCacheAction do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.ExternalProcessor.RouteCacheAction",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :DEFAULT, 0
  field :CLEAR, 1
  field :RETAIN, 2
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ProcessingMode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :request_header_mode, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode.HeaderSendMode,
    json_name: "requestHeaderMode",
    enum: true

  field :response_header_mode, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode.HeaderSendMode,
    json_name: "responseHeaderMode",
    enum: true

  field :request_body_mode, 3,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode.BodySendMode,
    json_name: "requestBodyMode",
    enum: true

  field :response_body_mode, 4,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode.BodySendMode,
    json_name: "responseBodyMode",
    enum: true

  field :request_trailer_mode, 5,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode.HeaderSendMode,
    json_name: "requestTrailerMode",
    enum: true

  field :response_trailer_mode, 6,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode.HeaderSendMode,
    json_name: "responseTrailerMode",
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HeaderMutationRules do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HeaderMutationRules",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :allow_all_routing, 1, type: Google.Protobuf.BoolValue, json_name: "allowAllRouting"
  field :allow_envoy, 2, type: Google.Protobuf.BoolValue, json_name: "allowEnvoy"
  field :disallow_system, 3, type: Google.Protobuf.BoolValue, json_name: "disallowSystem"
  field :disallow_all, 4, type: Google.Protobuf.BoolValue, json_name: "disallowAll"

  field :allow_expression, 5,
    type: Arion.ControlPlane.Pb.Data.RegexMatcher,
    json_name: "allowExpression"

  field :disallow_expression, 6,
    type: Arion.ControlPlane.Pb.Data.RegexMatcher,
    json_name: "disallowExpression"

  field :disallow_is_error, 7, type: Google.Protobuf.BoolValue, json_name: "disallowIsError"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ListStringMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ListStringMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :patterns, 1, repeated: true, type: Arion.ControlPlane.Pb.Data.StringMatcher
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HeaderForwardingRules do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HeaderForwardingRules",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :allowed_headers, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.ListStringMatcher,
    json_name: "allowedHeaders"

  field :disallowed_headers, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.ListStringMatcher,
    json_name: "disallowedHeaders"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.MetadataOptions.MetadataNamespaces do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.MetadataOptions.MetadataNamespaces",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :untyped, 1, repeated: true, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.MetadataOptions do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.MetadataOptions",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :forwarding_namespaces, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.MetadataOptions.MetadataNamespaces,
    json_name: "forwardingNamespaces"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ExternalProcessor do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ExternalProcessor",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :grpc_service, 1, type: Arion.ControlPlane.Pb.Data.GrpcService, json_name: "grpcService"
  field :failure_mode_allow, 2, type: :bool, json_name: "failureModeAllow"

  field :processing_mode, 3,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode,
    json_name: "processingMode"

  field :message_timeout, 7, type: Google.Protobuf.Duration, json_name: "messageTimeout"

  field :mutation_rules, 9,
    type: Arion.ControlPlane.Pb.Data.Extensions.HeaderMutationRules,
    json_name: "mutationRules"

  field :max_message_timeout, 10, type: Google.Protobuf.Duration, json_name: "maxMessageTimeout"

  field :forward_rules, 12,
    type: Arion.ControlPlane.Pb.Data.Extensions.HeaderForwardingRules,
    json_name: "forwardRules"

  field :allow_mode_override, 14, type: :bool, json_name: "allowModeOverride"
  field :disable_immediate_response, 15, type: :bool, json_name: "disableImmediateResponse"

  field :metadata_options, 16,
    type: Arion.ControlPlane.Pb.Data.Extensions.MetadataOptions,
    json_name: "metadataOptions"

  field :observability_mode, 17, type: :bool, json_name: "observabilityMode"

  field :route_cache_action, 18,
    type: Arion.ControlPlane.Pb.Data.Extensions.ExternalProcessor.RouteCacheAction,
    json_name: "routeCacheAction",
    enum: true

  field :deferred_close_timeout, 19,
    type: Google.Protobuf.Duration,
    json_name: "deferredCloseTimeout"

  field :send_body_without_waiting_for_header_response, 21,
    type: :bool,
    json_name: "sendBodyWithoutWaitingForHeaderResponse"

  field :allowed_override_modes, 22,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode,
    json_name: "allowedOverrideModes"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ExtProcPerRoute do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ExtProcPerRoute",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :override, 0

  field :disabled, 1, type: :bool, oneof: 0
  field :overrides, 2, type: Arion.ControlPlane.Pb.Data.Extensions.ExtProcOverrides, oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ExtProcOverrides do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ExtProcOverrides",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :processing_mode, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.ProcessingMode,
    json_name: "processingMode"

  field :grpc_service, 5, type: Arion.ControlPlane.Pb.Data.GrpcService, json_name: "grpcService"
  field :failure_mode_allow, 8, type: Google.Protobuf.BoolValue, json_name: "failureModeAllow"
end
