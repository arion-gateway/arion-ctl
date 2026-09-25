defmodule Arion.ControlPlane.Pb.Endpoint.Endpoint.HealthCheckConfig do
  @moduledoc false

  use Protobuf,
    full_name: "endpoint.Endpoint.HealthCheckConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :port_value, 1, type: :uint32, json_name: "portValue"
  field :hostname, 2, type: :string
  field :address, 3, type: Arion.ControlPlane.Pb.Data.Address
  field :disable_active_health_check, 4, type: :bool, json_name: "disableActiveHealthCheck"
end

defmodule Arion.ControlPlane.Pb.Endpoint.Endpoint.AdditionalAddress do
  @moduledoc false

  use Protobuf,
    full_name: "endpoint.Endpoint.AdditionalAddress",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :address, 1, type: Arion.ControlPlane.Pb.Data.Address
end

defmodule Arion.ControlPlane.Pb.Endpoint.Endpoint do
  @moduledoc false

  use Protobuf,
    full_name: "endpoint.Endpoint",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :address, 1, type: Arion.ControlPlane.Pb.Data.Address

  field :health_check_config, 2,
    type: Arion.ControlPlane.Pb.Endpoint.Endpoint.HealthCheckConfig,
    json_name: "healthCheckConfig"

  field :hostname, 3, type: :string

  field :additional_addresses, 4,
    repeated: true,
    type: Arion.ControlPlane.Pb.Endpoint.Endpoint.AdditionalAddress,
    json_name: "additionalAddresses"
end

defmodule Arion.ControlPlane.Pb.Endpoint.LbEndpoint do
  @moduledoc false

  use Protobuf,
    full_name: "endpoint.LbEndpoint",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :host_identifier, 0

  field :endpoint, 1, type: Arion.ControlPlane.Pb.Endpoint.Endpoint, oneof: 0

  field :health_status, 2,
    type: Arion.ControlPlane.Pb.Data.HealthStatus,
    json_name: "healthStatus",
    enum: true

  field :load_balancing_weight, 4,
    type: Google.Protobuf.UInt32Value,
    json_name: "loadBalancingWeight"
end

defmodule Arion.ControlPlane.Pb.Endpoint.Locality do
  @moduledoc false

  use Protobuf,
    full_name: "endpoint.Locality",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :region, 1, type: :string
  field :zone, 2, type: :string
  field :sub_zone, 3, type: :string, json_name: "subZone"
end

defmodule Arion.ControlPlane.Pb.Endpoint.LocalityLbEndpoints do
  @moduledoc false

  use Protobuf,
    full_name: "endpoint.LocalityLbEndpoints",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :locality, 1, type: Arion.ControlPlane.Pb.Endpoint.Locality

  field :lb_endpoints, 2,
    repeated: true,
    type: Arion.ControlPlane.Pb.Endpoint.LbEndpoint,
    json_name: "lbEndpoints"

  field :priority, 5, type: :uint32
end
