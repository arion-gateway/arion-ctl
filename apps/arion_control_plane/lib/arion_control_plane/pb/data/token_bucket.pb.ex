defmodule Arion.ControlPlane.Pb.Data.TokenBucket do
  @moduledoc false

  use Protobuf,
    full_name: "data.TokenBucket",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :max_tokens, 1, type: :uint32, json_name: "maxTokens"
  field :tokens_per_fill, 2, type: Google.Protobuf.UInt32Value, json_name: "tokensPerFill"
  field :fill_interval, 3, type: Google.Protobuf.Duration, json_name: "fillInterval"
end
