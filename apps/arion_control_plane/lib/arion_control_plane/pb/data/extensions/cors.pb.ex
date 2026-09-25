defmodule Arion.ControlPlane.Pb.Data.Extensions.Cors do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Cors",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.CorsPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.CorsPolicy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :allow_origin_string_match, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.StringMatcher,
    json_name: "allowOriginStringMatch"

  field :allow_methods, 2, type: :string, json_name: "allowMethods"
  field :allow_headers, 3, type: :string, json_name: "allowHeaders"
  field :expose_headers, 4, type: :string, json_name: "exposeHeaders"
  field :max_age, 5, type: :string, json_name: "maxAge"
  field :allow_credentials, 6, type: Google.Protobuf.BoolValue, json_name: "allowCredentials"

  field :forward_not_matching_preflights, 10,
    type: Google.Protobuf.BoolValue,
    json_name: "forwardNotMatchingPreflights"
end
