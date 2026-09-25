defmodule Arion.ControlPlane.Pb.Data.StringMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "data.StringMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :match_pattern, 0

  field :exact, 1, type: :string, oneof: 0
  field :prefix, 2, type: :string, oneof: 0
  field :suffix, 3, type: :string, oneof: 0

  field :safe_regex, 5,
    type: Arion.ControlPlane.Pb.Data.RegexMatcher,
    json_name: "safeRegex",
    oneof: 0

  field :contains, 7, type: :string, oneof: 0
  field :ignore_case, 6, type: :bool, json_name: "ignoreCase"
end
