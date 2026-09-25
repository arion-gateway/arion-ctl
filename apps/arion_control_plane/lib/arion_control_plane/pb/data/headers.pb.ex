defmodule Arion.ControlPlane.Pb.Data.HeaderValueOption.HeaderAppendAction do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.HeaderValueOption.HeaderAppendAction",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :APPEND_IF_EXISTS_OR_ADD, 0
  field :ADD_IF_ABSENT, 1
  field :OVERWRITE_IF_EXISTS_OR_ADD, 2
  field :OVERWRITE_IF_EXISTS, 3
end

defmodule Arion.ControlPlane.Pb.Data.HeaderMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "data.HeaderMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :header_match_specifier, 0

  field :name, 1, type: :string
  field :exact_match, 4, type: :string, json_name: "exactMatch", oneof: 0

  field :safe_regex_match, 11,
    type: Arion.ControlPlane.Pb.Data.RegexMatcher,
    json_name: "safeRegexMatch",
    oneof: 0

  field :range_match, 6,
    type: Arion.ControlPlane.Pb.Data.Int64Range,
    json_name: "rangeMatch",
    oneof: 0

  field :present_match, 7, type: :bool, json_name: "presentMatch", oneof: 0

  field :string_match, 13,
    type: Arion.ControlPlane.Pb.Data.StringMatcher,
    json_name: "stringMatch",
    oneof: 0

  field :invert_match, 8, type: :bool, json_name: "invertMatch"
end

defmodule Arion.ControlPlane.Pb.Data.HeaderValue do
  @moduledoc false

  use Protobuf,
    full_name: "data.HeaderValue",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.HeaderValueOption do
  @moduledoc false

  use Protobuf,
    full_name: "data.HeaderValueOption",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :header, 1, type: Arion.ControlPlane.Pb.Data.HeaderValue

  field :append_action, 3,
    type: Arion.ControlPlane.Pb.Data.HeaderValueOption.HeaderAppendAction,
    json_name: "appendAction",
    enum: true
end
