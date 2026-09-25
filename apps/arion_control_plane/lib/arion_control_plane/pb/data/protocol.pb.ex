defmodule Arion.ControlPlane.Pb.Data.RoutingPriority do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.RoutingPriority",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :DEFAULT, 0
  field :HIGH, 1
end

defmodule Arion.ControlPlane.Pb.Data.HttpProtocolOptions do
  @moduledoc false

  use Protobuf,
    full_name: "data.HttpProtocolOptions",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :idle_timeout, 1, type: Google.Protobuf.Duration, json_name: "idleTimeout"

  field :max_connection_duration, 3,
    type: Google.Protobuf.Duration,
    json_name: "maxConnectionDuration"

  field :max_headers_count, 2, type: Google.Protobuf.UInt32Value, json_name: "maxHeadersCount"
  field :max_stream_duration, 4, type: Google.Protobuf.Duration, json_name: "maxStreamDuration"

  field :max_requests_per_connection, 6,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxRequestsPerConnection"
end

defmodule Arion.ControlPlane.Pb.Data.Http1ProtocolOptions do
  @moduledoc false

  use Protobuf,
    full_name: "data.Http1ProtocolOptions",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :allow_absolute_url, 1, type: Google.Protobuf.BoolValue, json_name: "allowAbsoluteUrl"
  field :enable_trailers, 5, type: :bool, json_name: "enableTrailers"
end

defmodule Arion.ControlPlane.Pb.Data.KeepaliveSettings do
  @moduledoc false

  use Protobuf,
    full_name: "data.KeepaliveSettings",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :interval, 1, type: Google.Protobuf.Duration
  field :timeout, 2, type: Google.Protobuf.Duration
  field :interval_jitter, 3, type: Arion.ControlPlane.Pb.Data.Percent, json_name: "intervalJitter"

  field :connection_idle_interval, 4,
    type: Google.Protobuf.Duration,
    json_name: "connectionIdleInterval"
end

defmodule Arion.ControlPlane.Pb.Data.Http2ProtocolOptions.SettingsParameter do
  @moduledoc false

  use Protobuf,
    full_name: "data.Http2ProtocolOptions.SettingsParameter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :identifier, 1, type: Google.Protobuf.UInt32Value
  field :value, 2, type: Google.Protobuf.UInt32Value
end

defmodule Arion.ControlPlane.Pb.Data.Http2ProtocolOptions do
  @moduledoc false

  use Protobuf,
    full_name: "data.Http2ProtocolOptions",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :hpack_table_size, 1, type: Google.Protobuf.UInt32Value, json_name: "hpackTableSize"

  field :max_concurrent_streams, 2,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxConcurrentStreams"

  field :initial_stream_window_size, 3,
    type: Google.Protobuf.UInt32Value,
    json_name: "initialStreamWindowSize"

  field :initial_connection_window_size, 4,
    type: Google.Protobuf.UInt32Value,
    json_name: "initialConnectionWindowSize"

  field :allow_connect, 5, type: :bool, json_name: "allowConnect"
  field :max_outbound_frames, 7, type: Google.Protobuf.UInt32Value, json_name: "maxOutboundFrames"

  field :max_outbound_control_frames, 8,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxOutboundControlFrames"

  field :max_consecutive_inbound_frames_with_empty_payload, 9,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxConsecutiveInboundFramesWithEmptyPayload"

  field :max_inbound_priority_frames_per_stream, 10,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxInboundPriorityFramesPerStream"

  field :max_inbound_window_update_frames_per_data_frame_sent, 11,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxInboundWindowUpdateFramesPerDataFrameSent"

  field :connection_keepalive, 15,
    type: Arion.ControlPlane.Pb.Data.KeepaliveSettings,
    json_name: "connectionKeepalive"
end

defmodule Arion.ControlPlane.Pb.Data.UpstreamHttpProtocolOptions do
  @moduledoc false

  use Protobuf,
    full_name: "data.UpstreamHttpProtocolOptions",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :auto_sni, 1, type: :bool, json_name: "autoSni"
  field :auto_san_validation, 2, type: :bool, json_name: "autoSanValidation"
  field :override_auto_sni_header, 3, type: :string, json_name: "overrideAutoSniHeader"
end
