defmodule Arion.ControlPlane.Pb.Cluster.OutlierDetection do
  @moduledoc false

  use Protobuf,
    full_name: "cluster.OutlierDetection",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :consecutive_5xx, 1, type: Google.Protobuf.UInt32Value, json_name: "consecutive5xx"
  field :interval, 2, type: Google.Protobuf.Duration
  field :base_ejection_time, 3, type: Google.Protobuf.Duration, json_name: "baseEjectionTime"

  field :max_ejection_percent, 4,
    type: Google.Protobuf.UInt32Value,
    json_name: "maxEjectionPercent"
end
