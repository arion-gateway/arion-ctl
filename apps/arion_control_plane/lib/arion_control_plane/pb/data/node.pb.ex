defmodule Arion.ControlPlane.Pb.Data.Locality do
  @moduledoc false

  use Protobuf, full_name: "data.Locality", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :region, 1, type: :string
  field :zone, 2, type: :string
  field :sub_zone, 3, type: :string, json_name: "subZone"
end

defmodule Arion.ControlPlane.Pb.Data.Node do
  @moduledoc false

  use Protobuf, full_name: "data.Node", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :id, 1, type: :string
  field :cluster, 2, type: :string
  field :locality, 4, type: Arion.ControlPlane.Pb.Data.Locality
  field :user_agent_name, 6, type: :string, json_name: "userAgentName"
end
