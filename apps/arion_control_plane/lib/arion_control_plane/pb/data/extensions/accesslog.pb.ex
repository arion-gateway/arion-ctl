defmodule Arion.ControlPlane.Pb.Data.Extensions.AccessLogType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.AccessLogType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :NotSet, 0
  field :TcpUpstreamConnected, 1
  field :TcpPeriodic, 2
  field :TcpConnectionEnd, 3
  field :DownstreamStart, 4
  field :DownstreamPeriodic, 5
  field :DownstreamEnd, 6
  field :UpstreamPoolReady, 7
  field :UpstreamPeriodic, 8
  field :UpstreamEnd, 9
  field :DownstreamTunnelSuccessfullyEstablished, 10
  field :UdpTunnelUpstreamConnected, 11
  field :UdpPeriodic, 12
  field :UdpSessionEnd, 13
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ComparisonFilter.Op do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.ComparisonFilter.Op",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :EQ, 0
  field :GE, 1
  field :LE, 2
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.GrpcStatusFilter.Status do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.GrpcStatusFilter.Status",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :OK, 0
  field :CANCELED, 1
  field :UNKNOWN, 2
  field :INVALID_ARGUMENT, 3
  field :DEADLINE_EXCEEDED, 4
  field :NOT_FOUND, 5
  field :ALREADY_EXISTS, 6
  field :PERMISSION_DENIED, 7
  field :RESOURCE_EXHAUSTED, 8
  field :FAILED_PRECONDITION, 9
  field :ABORTED, 10
  field :OUT_OF_RANGE, 11
  field :UNIMPLEMENTED, 12
  field :INTERNAL, 13
  field :UNAVAILABLE, 14
  field :DATA_LOSS, 15
  field :UNAUTHENTICATED, 16
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HTTPAccessLogEntry.HTTPVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.HTTPAccessLogEntry.HTTPVersion",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :PROTOCOL_UNSPECIFIED, 0
  field :HTTP10, 1
  field :HTTP11, 2
  field :HTTP2, 3
  field :HTTP3, 4
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ResponseFlags.Unauthorized.Reason do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.ResponseFlags.Unauthorized.Reason",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :REASON_UNSPECIFIED, 0
  field :EXTERNAL_SERVICE, 1
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.TLSProperties.TLSVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.TLSProperties.TLSVersion",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :VERSION_UNSPECIFIED, 0
  field :TLSv1, 1
  field :TLSv1_1, 2
  field :TLSv1_2, 3
  field :TLSv1_3, 4
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.AccessLog do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.AccessLog",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :config_type, 0

  field :name, 1, type: :string
  field :filter, 2, type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogFilter
  field :typed_config, 4, type: Google.Protobuf.Any, json_name: "typedConfig", oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.AccessLogFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.AccessLogFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :filter_specifier, 0

  field :status_code_filter, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.StatusCodeFilter,
    json_name: "statusCodeFilter",
    oneof: 0

  field :duration_filter, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.DurationFilter,
    json_name: "durationFilter",
    oneof: 0

  field :runtime_filter, 5,
    type: Arion.ControlPlane.Pb.Data.Extensions.RuntimeFilter,
    json_name: "runtimeFilter",
    oneof: 0

  field :and_filter, 6,
    type: Arion.ControlPlane.Pb.Data.Extensions.AndFilter,
    json_name: "andFilter",
    oneof: 0

  field :or_filter, 7,
    type: Arion.ControlPlane.Pb.Data.Extensions.OrFilter,
    json_name: "orFilter",
    oneof: 0

  field :header_filter, 8,
    type: Arion.ControlPlane.Pb.Data.Extensions.HeaderFilter,
    json_name: "headerFilter",
    oneof: 0

  field :response_flag_filter, 9,
    type: Arion.ControlPlane.Pb.Data.Extensions.ResponseFlagFilter,
    json_name: "responseFlagFilter",
    oneof: 0

  field :grpc_status_filter, 10,
    type: Arion.ControlPlane.Pb.Data.Extensions.GrpcStatusFilter,
    json_name: "grpcStatusFilter",
    oneof: 0

  field :log_type_filter, 13,
    type: Arion.ControlPlane.Pb.Data.Extensions.LogTypeFilter,
    json_name: "logTypeFilter",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ComparisonFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ComparisonFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :op, 1, type: Arion.ControlPlane.Pb.Data.Extensions.ComparisonFilter.Op, enum: true
  field :value, 2, type: Arion.ControlPlane.Pb.Data.Extensions.RuntimeUInt32
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RuntimeUInt32 do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RuntimeUInt32",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :default_value, 2, type: :uint32, json_name: "defaultValue"
  field :runtime_key, 3, type: :string, json_name: "runtimeKey"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.StatusCodeFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.StatusCodeFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :comparison, 1, type: Arion.ControlPlane.Pb.Data.Extensions.ComparisonFilter
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.DurationFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.DurationFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :comparison, 1, type: Arion.ControlPlane.Pb.Data.Extensions.ComparisonFilter
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RuntimeFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RuntimeFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :runtime_key, 1, type: :string, json_name: "runtimeKey"

  field :percent_sampled, 2,
    type: Arion.ControlPlane.Pb.Data.FractionalPercent,
    json_name: "percentSampled"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.AndFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.AndFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :filters, 1, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogFilter
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.OrFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.OrFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :filters, 2, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogFilter
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HeaderFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HeaderFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :header, 1, type: Arion.ControlPlane.Pb.Data.HeaderMatcher
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ResponseFlagFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ResponseFlagFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :flags, 1, repeated: true, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.LogTypeFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.LogTypeFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :types, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogType,
    enum: true

  field :exclude, 2, type: :bool
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.GrpcStatusFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.GrpcStatusFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :statuses, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.GrpcStatusFilter.Status,
    enum: true

  field :exclude, 2, type: :bool
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.TCPAccessLogEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.TCPAccessLogEntry",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :common_properties, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogCommon,
    json_name: "commonProperties"

  field :connection_properties, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.ConnectionProperties,
    json_name: "connectionProperties"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HTTPAccessLogEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HTTPAccessLogEntry",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :common_properties, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogCommon,
    json_name: "commonProperties"

  field :protocol_version, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.HTTPAccessLogEntry.HTTPVersion,
    json_name: "protocolVersion",
    enum: true

  field :request, 3, type: Arion.ControlPlane.Pb.Data.Extensions.HTTPRequestProperties
  field :response, 4, type: Arion.ControlPlane.Pb.Data.Extensions.HTTPResponseProperties
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ConnectionProperties do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ConnectionProperties",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :received_bytes, 1, type: :uint64, json_name: "receivedBytes"
  field :sent_bytes, 2, type: :uint64, json_name: "sentBytes"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.AccessLogCommon.FilterStateObjectsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.AccessLogCommon.FilterStateObjectsEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Google.Protobuf.Any
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.AccessLogCommon.CustomTagsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.AccessLogCommon.CustomTagsEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.AccessLogCommon do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.AccessLogCommon",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :downstream_remote_address, 2,
    type: Arion.ControlPlane.Pb.Data.Address,
    json_name: "downstreamRemoteAddress"

  field :downstream_local_address, 3,
    type: Arion.ControlPlane.Pb.Data.Address,
    json_name: "downstreamLocalAddress"

  field :tls_properties, 4,
    type: Arion.ControlPlane.Pb.Data.Extensions.TLSProperties,
    json_name: "tlsProperties"

  field :start_time, 5, type: Google.Protobuf.Timestamp, json_name: "startTime"
  field :time_to_last_rx_byte, 6, type: Google.Protobuf.Duration, json_name: "timeToLastRxByte"

  field :time_to_first_upstream_tx_byte, 7,
    type: Google.Protobuf.Duration,
    json_name: "timeToFirstUpstreamTxByte"

  field :time_to_last_upstream_tx_byte, 8,
    type: Google.Protobuf.Duration,
    json_name: "timeToLastUpstreamTxByte"

  field :time_to_first_upstream_rx_byte, 9,
    type: Google.Protobuf.Duration,
    json_name: "timeToFirstUpstreamRxByte"

  field :time_to_last_upstream_rx_byte, 10,
    type: Google.Protobuf.Duration,
    json_name: "timeToLastUpstreamRxByte"

  field :time_to_first_downstream_tx_byte, 11,
    type: Google.Protobuf.Duration,
    json_name: "timeToFirstDownstreamTxByte"

  field :time_to_last_downstream_tx_byte, 12,
    type: Google.Protobuf.Duration,
    json_name: "timeToLastDownstreamTxByte"

  field :upstream_remote_address, 13,
    type: Arion.ControlPlane.Pb.Data.Address,
    json_name: "upstreamRemoteAddress"

  field :upstream_local_address, 14,
    type: Arion.ControlPlane.Pb.Data.Address,
    json_name: "upstreamLocalAddress"

  field :upstream_cluster, 15, type: :string, json_name: "upstreamCluster"

  field :response_flags, 16,
    type: Arion.ControlPlane.Pb.Data.Extensions.ResponseFlags,
    json_name: "responseFlags"

  field :metadata, 17, type: Arion.ControlPlane.Pb.Data.Metadata

  field :upstream_transport_failure_reason, 18,
    type: :string,
    json_name: "upstreamTransportFailureReason"

  field :route_name, 19, type: :string, json_name: "routeName"

  field :downstream_direct_remote_address, 20,
    type: Arion.ControlPlane.Pb.Data.Address,
    json_name: "downstreamDirectRemoteAddress"

  field :filter_state_objects, 21,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogCommon.FilterStateObjectsEntry,
    json_name: "filterStateObjects",
    map: true

  field :custom_tags, 22,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogCommon.CustomTagsEntry,
    json_name: "customTags",
    map: true

  field :duration, 23, type: Google.Protobuf.Duration

  field :upstream_request_attempt_count, 24,
    type: :uint32,
    json_name: "upstreamRequestAttemptCount"

  field :connection_termination_details, 25,
    type: :string,
    json_name: "connectionTerminationDetails"

  field :stream_id, 26, type: :string, json_name: "streamId"

  field :downstream_transport_failure_reason, 28,
    type: :string,
    json_name: "downstreamTransportFailureReason"

  field :downstream_wire_bytes_sent, 29, type: :uint64, json_name: "downstreamWireBytesSent"

  field :downstream_wire_bytes_received, 30,
    type: :uint64,
    json_name: "downstreamWireBytesReceived"

  field :upstream_wire_bytes_sent, 31, type: :uint64, json_name: "upstreamWireBytesSent"
  field :upstream_wire_bytes_received, 32, type: :uint64, json_name: "upstreamWireBytesReceived"

  field :access_log_type, 33,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLogType,
    json_name: "accessLogType",
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ResponseFlags.Unauthorized do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ResponseFlags.Unauthorized",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :reason, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.ResponseFlags.Unauthorized.Reason,
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ResponseFlags do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ResponseFlags",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :failed_local_healthcheck, 1, type: :bool, json_name: "failedLocalHealthcheck"
  field :no_healthy_upstream, 2, type: :bool, json_name: "noHealthyUpstream"
  field :upstream_request_timeout, 3, type: :bool, json_name: "upstreamRequestTimeout"
  field :local_reset, 4, type: :bool, json_name: "localReset"
  field :upstream_remote_reset, 5, type: :bool, json_name: "upstreamRemoteReset"
  field :upstream_connection_failure, 6, type: :bool, json_name: "upstreamConnectionFailure"

  field :upstream_connection_termination, 7,
    type: :bool,
    json_name: "upstreamConnectionTermination"

  field :upstream_overflow, 8, type: :bool, json_name: "upstreamOverflow"
  field :no_route_found, 9, type: :bool, json_name: "noRouteFound"
  field :delay_injected, 10, type: :bool, json_name: "delayInjected"
  field :fault_injected, 11, type: :bool, json_name: "faultInjected"
  field :rate_limited, 12, type: :bool, json_name: "rateLimited"

  field :unauthorized_details, 13,
    type: Arion.ControlPlane.Pb.Data.Extensions.ResponseFlags.Unauthorized,
    json_name: "unauthorizedDetails"

  field :rate_limit_service_error, 14, type: :bool, json_name: "rateLimitServiceError"

  field :downstream_connection_termination, 15,
    type: :bool,
    json_name: "downstreamConnectionTermination"

  field :upstream_retry_limit_exceeded, 16, type: :bool, json_name: "upstreamRetryLimitExceeded"
  field :stream_idle_timeout, 17, type: :bool, json_name: "streamIdleTimeout"
  field :invalid_envoy_request_headers, 18, type: :bool, json_name: "invalidEnvoyRequestHeaders"
  field :downstream_protocol_error, 19, type: :bool, json_name: "downstreamProtocolError"

  field :upstream_max_stream_duration_reached, 20,
    type: :bool,
    json_name: "upstreamMaxStreamDurationReached"

  field :response_from_cache_filter, 21, type: :bool, json_name: "responseFromCacheFilter"
  field :no_filter_config_found, 22, type: :bool, json_name: "noFilterConfigFound"
  field :duration_timeout, 23, type: :bool, json_name: "durationTimeout"
  field :upstream_protocol_error, 24, type: :bool, json_name: "upstreamProtocolError"
  field :no_cluster_found, 25, type: :bool, json_name: "noClusterFound"
  field :overload_manager, 26, type: :bool, json_name: "overloadManager"
  field :dns_resolution_failure, 27, type: :bool, json_name: "dnsResolutionFailure"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.TLSProperties.CertificateProperties.SubjectAltName do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.TLSProperties.CertificateProperties.SubjectAltName",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :san, 0

  field :uri, 1, type: :string, oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.TLSProperties.CertificateProperties do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.TLSProperties.CertificateProperties",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :subject_alt_name, 1,
    repeated: true,
    type:
      Arion.ControlPlane.Pb.Data.Extensions.TLSProperties.CertificateProperties.SubjectAltName,
    json_name: "subjectAltName"

  field :subject, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.TLSProperties do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.TLSProperties",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :tls_version, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.TLSProperties.TLSVersion,
    json_name: "tlsVersion",
    enum: true

  field :tls_cipher_suite, 2, type: Google.Protobuf.UInt32Value, json_name: "tlsCipherSuite"
  field :tls_sni_hostname, 3, type: :string, json_name: "tlsSniHostname"

  field :local_certificate_properties, 4,
    type: Arion.ControlPlane.Pb.Data.Extensions.TLSProperties.CertificateProperties,
    json_name: "localCertificateProperties"

  field :peer_certificate_properties, 5,
    type: Arion.ControlPlane.Pb.Data.Extensions.TLSProperties.CertificateProperties,
    json_name: "peerCertificateProperties"

  field :tls_session_id, 6, type: :string, json_name: "tlsSessionId"
  field :ja3_fingerprint, 7, type: :string, json_name: "ja3Fingerprint"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HTTPRequestProperties.RequestHeadersEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HTTPRequestProperties.RequestHeadersEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HTTPRequestProperties do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HTTPRequestProperties",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :request_method, 1,
    type: Arion.ControlPlane.Pb.Data.RequestMethod,
    json_name: "requestMethod",
    enum: true

  field :scheme, 2, type: :string
  field :authority, 3, type: :string
  field :port, 4, type: Google.Protobuf.UInt32Value
  field :path, 5, type: :string
  field :user_agent, 6, type: :string, json_name: "userAgent"
  field :referer, 7, type: :string
  field :forwarded_for, 8, type: :string, json_name: "forwardedFor"
  field :request_id, 9, type: :string, json_name: "requestId"
  field :original_path, 10, type: :string, json_name: "originalPath"
  field :request_headers_bytes, 11, type: :uint64, json_name: "requestHeadersBytes"
  field :request_body_bytes, 12, type: :uint64, json_name: "requestBodyBytes"

  field :request_headers, 13,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.HTTPRequestProperties.RequestHeadersEntry,
    json_name: "requestHeaders",
    map: true

  field :upstream_header_bytes_sent, 14, type: :uint64, json_name: "upstreamHeaderBytesSent"

  field :downstream_header_bytes_received, 15,
    type: :uint64,
    json_name: "downstreamHeaderBytesReceived"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HTTPResponseProperties.ResponseHeadersEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HTTPResponseProperties.ResponseHeadersEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HTTPResponseProperties.ResponseTrailersEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HTTPResponseProperties.ResponseTrailersEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HTTPResponseProperties do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HTTPResponseProperties",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :response_code, 1, type: Google.Protobuf.UInt32Value, json_name: "responseCode"
  field :response_headers_bytes, 2, type: :uint64, json_name: "responseHeadersBytes"
  field :response_body_bytes, 3, type: :uint64, json_name: "responseBodyBytes"

  field :response_headers, 4,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.HTTPResponseProperties.ResponseHeadersEntry,
    json_name: "responseHeaders",
    map: true

  field :response_trailers, 5,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.HTTPResponseProperties.ResponseTrailersEntry,
    json_name: "responseTrailers",
    map: true

  field :response_code_details, 6, type: :string, json_name: "responseCodeDetails"

  field :upstream_header_bytes_received, 7,
    type: :uint64,
    json_name: "upstreamHeaderBytesReceived"

  field :downstream_header_bytes_sent, 8, type: :uint64, json_name: "downstreamHeaderBytesSent"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.FileAccessLog do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.FileAccessLog",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :access_log_format, 0

  field :path, 1, type: :string

  field :log_format, 5,
    type: Arion.ControlPlane.Pb.Data.Extensions.SubstitutionFormatString,
    json_name: "logFormat",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.StdoutAccessLog do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.StdoutAccessLog",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :access_log_format, 0

  field :log_format, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.SubstitutionFormatString,
    json_name: "logFormat",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.StderrAccessLog do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.StderrAccessLog",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :access_log_format, 0

  field :log_format, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.SubstitutionFormatString,
    json_name: "logFormat",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.SubstitutionFormatString do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.SubstitutionFormatString",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :format, 0

  field :text_format, 1, type: :string, json_name: "textFormat", oneof: 0

  field :text_format_source, 5,
    type: Arion.ControlPlane.Pb.Data.DataSource,
    json_name: "textFormatSource",
    oneof: 0

  field :omit_empty_values, 3, type: :bool, json_name: "omitEmptyValues"
end
