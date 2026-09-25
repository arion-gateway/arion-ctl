defmodule Arion.ControlPlane.Pb.Route.RouteConfiguration do
  @moduledoc false

  use Protobuf,
    full_name: "route.RouteConfiguration",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string

  field :virtual_hosts, 2,
    repeated: true,
    type: Arion.ControlPlane.Pb.Route.VirtualHost,
    json_name: "virtualHosts"

  field :response_headers_to_add, 4,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HeaderValueOption,
    json_name: "responseHeadersToAdd"

  field :response_headers_to_remove, 5,
    repeated: true,
    type: :string,
    json_name: "responseHeadersToRemove"

  field :request_headers_to_add, 6,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HeaderValueOption,
    json_name: "requestHeadersToAdd"

  field :request_headers_to_remove, 8,
    repeated: true,
    type: :string,
    json_name: "requestHeadersToRemove"

  field :most_specific_header_mutations_wins, 10,
    type: :bool,
    json_name: "mostSpecificHeaderMutationsWins"
end
