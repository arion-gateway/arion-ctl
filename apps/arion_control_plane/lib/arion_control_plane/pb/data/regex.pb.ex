defmodule Arion.ControlPlane.Pb.Data.RegexMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "data.RegexMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :regex, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.RegexMatchAndSubstitute do
  @moduledoc false

  use Protobuf,
    full_name: "data.RegexMatchAndSubstitute",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :pattern, 1, type: Arion.ControlPlane.Pb.Data.RegexMatcher
  field :substitution, 2, type: :string
end
