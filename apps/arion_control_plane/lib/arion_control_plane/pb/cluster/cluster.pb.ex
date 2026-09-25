defmodule Arion.ControlPlane.Pb.Cluster.Cluster.DiscoveryType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "cluster.Cluster.DiscoveryType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :STATIC, 0
  field :STRICT_DNS, 1
  field :EDS, 3
  field :ORIGINAL_DST, 4
end

defmodule Arion.ControlPlane.Pb.Cluster.Cluster.LbPolicy do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "cluster.Cluster.LbPolicy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :ROUND_ROBIN, 0
  field :LEAST_REQUEST, 1
  field :RING_HASH, 2
  field :RANDOM, 3
  field :MAGLEV, 5
  field :CLUSTER_PROVIDED, 6
end

defmodule Arion.ControlPlane.Pb.Cluster.Cluster.OriginalDstLbConfig do
  @moduledoc false

  use Protobuf,
    full_name: "cluster.Cluster.OriginalDstLbConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :use_http_header, 1, type: :bool, json_name: "useHttpHeader"
  field :http_header_name, 2, type: :string, json_name: "httpHeaderName"

  field :upstream_port_override, 3,
    type: Google.Protobuf.UInt32Value,
    json_name: "upstreamPortOverride"

  field :metadata_key, 4, type: Arion.ControlPlane.Pb.Data.MetadataKey, json_name: "metadataKey"
end

defmodule Arion.ControlPlane.Pb.Cluster.Cluster.EdsClusterConfig do
  @moduledoc false

  use Protobuf,
    full_name: "cluster.Cluster.EdsClusterConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :eds_config, 1, type: Arion.ControlPlane.Pb.Data.ConfigSource, json_name: "edsConfig"
end

defmodule Arion.ControlPlane.Pb.Cluster.Cluster.TypedExtensionProtocolOptionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cluster.Cluster.TypedExtensionProtocolOptionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Google.Protobuf.Any
end

defmodule Arion.ControlPlane.Pb.Cluster.Cluster do
  @moduledoc false

  use Protobuf, full_name: "cluster.Cluster", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :cluster_discovery_type, 0

  oneof :lb_config, 1

  field :name, 1, type: :string
  field :type, 2, type: Arion.ControlPlane.Pb.Cluster.Cluster.DiscoveryType, enum: true, oneof: 0

  field :eds_cluster_config, 3,
    type: Arion.ControlPlane.Pb.Cluster.Cluster.EdsClusterConfig,
    json_name: "edsClusterConfig"

  field :connect_timeout, 4, type: Google.Protobuf.Duration, json_name: "connectTimeout"

  field :lb_policy, 6,
    type: Arion.ControlPlane.Pb.Cluster.Cluster.LbPolicy,
    json_name: "lbPolicy",
    enum: true

  field :load_assignment, 33,
    type: Arion.ControlPlane.Pb.Endpoint.ClusterLoadAssignment,
    json_name: "loadAssignment"

  field :health_checks, 8,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HealthCheck,
    json_name: "healthChecks"

  field :circuit_breakers, 10,
    type: Arion.ControlPlane.Pb.Cluster.CircuitBreakers,
    json_name: "circuitBreakers"

  field :typed_extension_protocol_options, 36,
    repeated: true,
    type: Arion.ControlPlane.Pb.Cluster.Cluster.TypedExtensionProtocolOptionsEntry,
    json_name: "typedExtensionProtocolOptions",
    map: true

  field :outlier_detection, 19,
    type: Arion.ControlPlane.Pb.Cluster.OutlierDetection,
    json_name: "outlierDetection"

  field :upstream_bind_config, 21,
    type: Arion.ControlPlane.Pb.Data.BindConfig,
    json_name: "upstreamBindConfig"

  field :transport_socket, 24,
    type: Arion.ControlPlane.Pb.Data.TransportSocket,
    json_name: "transportSocket"

  field :cleanup_interval, 20, type: Google.Protobuf.Duration, json_name: "cleanupInterval"

  field :original_dst_lb_config, 34,
    type: Arion.ControlPlane.Pb.Cluster.Cluster.OriginalDstLbConfig,
    json_name: "originalDstLbConfig",
    oneof: 1

  field :load_balancing_policy, 41,
    type: Arion.ControlPlane.Pb.Data.Extensions.LoadBalancingPolicy,
    json_name: "loadBalancingPolicy"
end
