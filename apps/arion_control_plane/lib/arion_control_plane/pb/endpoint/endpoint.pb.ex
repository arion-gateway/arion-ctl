defmodule Arion.ControlPlane.Pb.Endpoint.ClusterLoadAssignment do
  @moduledoc false

  use Protobuf,
    full_name: "endpoint.ClusterLoadAssignment",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :cluster_name, 1, type: :string, json_name: "clusterName"
  field :endpoints, 2, repeated: true, type: Arion.ControlPlane.Pb.Endpoint.LocalityLbEndpoints
end
