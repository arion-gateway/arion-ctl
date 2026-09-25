defmodule Arion.ControlPlane.Pb.Filter.TcpProxy.WeightedCluster.ClusterWeight do
  @moduledoc false

  use Protobuf,
    full_name: "filter.TcpProxy.WeightedCluster.ClusterWeight",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :weight, 2, type: :uint32
end

defmodule Arion.ControlPlane.Pb.Filter.TcpProxy.WeightedCluster do
  @moduledoc false

  use Protobuf,
    full_name: "filter.TcpProxy.WeightedCluster",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :clusters, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Filter.TcpProxy.WeightedCluster.ClusterWeight
end

defmodule Arion.ControlPlane.Pb.Filter.TcpProxy.TcpAccessLogOptions do
  @moduledoc false

  use Protobuf,
    full_name: "filter.TcpProxy.TcpAccessLogOptions",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :access_log_flush_interval, 1,
    type: Google.Protobuf.Duration,
    json_name: "accessLogFlushInterval"

  field :flush_access_log_on_connected, 2, type: :bool, json_name: "flushAccessLogOnConnected"
end

defmodule Arion.ControlPlane.Pb.Filter.TcpProxy do
  @moduledoc false

  use Protobuf, full_name: "filter.TcpProxy", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :cluster_specifier, 0

  field :stat_prefix, 1, type: :string, json_name: "statPrefix"
  field :cluster, 2, type: :string, oneof: 0

  field :weighted_clusters, 10,
    type: Arion.ControlPlane.Pb.Filter.TcpProxy.WeightedCluster,
    json_name: "weightedClusters",
    oneof: 0

  field :idle_timeout, 8, type: Google.Protobuf.Duration, json_name: "idleTimeout"

  field :access_log, 5,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.AccessLog,
    json_name: "accessLog"

  field :max_connect_attempts, 7,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxConnectAttempts"

  field :max_downstream_connection_duration, 13,
    type: Google.Protobuf.Duration,
    json_name: "maxDownstreamConnectionDuration"

  field :access_log_options, 17,
    type: Arion.ControlPlane.Pb.Filter.TcpProxy.TcpAccessLogOptions,
    json_name: "accessLogOptions"
end
