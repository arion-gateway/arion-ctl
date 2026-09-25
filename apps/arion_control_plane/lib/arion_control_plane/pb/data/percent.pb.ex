defmodule Arion.ControlPlane.Pb.Data.FractionalPercent.DenominatorType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.FractionalPercent.DenominatorType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :HUNDRED, 0
  field :TEN_THOUSAND, 1
  field :MILLION, 2
end

defmodule Arion.ControlPlane.Pb.Data.Percent do
  @moduledoc false

  use Protobuf, full_name: "data.Percent", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :value, 1, type: :double
end

defmodule Arion.ControlPlane.Pb.Data.FractionalPercent do
  @moduledoc false

  use Protobuf,
    full_name: "data.FractionalPercent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :numerator, 1, type: :uint32

  field :denominator, 2,
    type: Arion.ControlPlane.Pb.Data.FractionalPercent.DenominatorType,
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.RuntimeFractionalPercent do
  @moduledoc false

  use Protobuf,
    full_name: "data.RuntimeFractionalPercent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :default_value, 1,
    type: Arion.ControlPlane.Pb.Data.FractionalPercent,
    json_name: "defaultValue"

  field :runtime_key, 2, type: :string, json_name: "runtimeKey"
end
