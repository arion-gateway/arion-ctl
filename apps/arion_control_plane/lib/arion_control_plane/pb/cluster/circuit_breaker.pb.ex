defmodule Arion.ControlPlane.Pb.Cluster.CircuitBreakers.RoutingPriority do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "cluster.CircuitBreakers.RoutingPriority",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :DEFAULT, 0
  field :HIGH, 1
end

defmodule Arion.ControlPlane.Pb.Cluster.CircuitBreakers.Thresholds do
  @moduledoc false

  use Protobuf,
    full_name: "cluster.CircuitBreakers.Thresholds",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :priority, 1,
    type: Arion.ControlPlane.Pb.Cluster.CircuitBreakers.RoutingPriority,
    enum: true

  field :max_requests, 4, type: Google.Protobuf.UInt32Value, json_name: "maxRequests"
  field :max_retries, 5, type: Google.Protobuf.UInt32Value, json_name: "maxRetries"
  field :track_remaining, 6, type: :bool, json_name: "trackRemaining"
end

defmodule Arion.ControlPlane.Pb.Cluster.CircuitBreakers do
  @moduledoc false

  use Protobuf,
    full_name: "cluster.CircuitBreakers",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :thresholds, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Cluster.CircuitBreakers.Thresholds
end
