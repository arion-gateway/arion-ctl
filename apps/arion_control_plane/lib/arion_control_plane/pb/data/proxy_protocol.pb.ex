defmodule Arion.ControlPlane.Pb.Data.ProxyProtocolPassThroughTLVs.PassTLVsMatchType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.ProxyProtocolPassThroughTLVs.PassTLVsMatchType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :INCLUDE_ALL, 0
  field :INCLUDE, 1
end

defmodule Arion.ControlPlane.Pb.Data.ProxyProtocolConfig.Version do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.ProxyProtocolConfig.Version",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :V1, 0
  field :V2, 1
end

defmodule Arion.ControlPlane.Pb.Data.ProxyProtocolPassThroughTLVs do
  @moduledoc false

  use Protobuf,
    full_name: "data.ProxyProtocolPassThroughTLVs",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :match_type, 1,
    type: Arion.ControlPlane.Pb.Data.ProxyProtocolPassThroughTLVs.PassTLVsMatchType,
    json_name: "matchType",
    enum: true

  field :tlv_type, 2, repeated: true, type: :uint32, json_name: "tlvType"
end

defmodule Arion.ControlPlane.Pb.Data.TlvEntry do
  @moduledoc false

  use Protobuf, full_name: "data.TlvEntry", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :type, 1, type: :uint32
  field :value, 2, type: :bytes
end

defmodule Arion.ControlPlane.Pb.Data.ProxyProtocolConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.ProxyProtocolConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :version, 1, type: Arion.ControlPlane.Pb.Data.ProxyProtocolConfig.Version, enum: true

  field :pass_through_tlvs, 2,
    type: Arion.ControlPlane.Pb.Data.ProxyProtocolPassThroughTLVs,
    json_name: "passThroughTlvs"

  field :added_tlvs, 3,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.TlvEntry,
    json_name: "addedTlvs"
end

defmodule Arion.ControlPlane.Pb.Data.PerHostConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.PerHostConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :added_tlvs, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.TlvEntry,
    json_name: "addedTlvs"
end
