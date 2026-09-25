defmodule Arion.ControlPlane.Pb.Data.Metadata.FilterMetadataEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.Metadata.FilterMetadataEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Google.Protobuf.Struct
end

defmodule Arion.ControlPlane.Pb.Data.Metadata.TypedFilterMetadataEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.Metadata.TypedFilterMetadataEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Google.Protobuf.Any
end

defmodule Arion.ControlPlane.Pb.Data.Metadata do
  @moduledoc false

  use Protobuf, full_name: "data.Metadata", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :filter_metadata, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Metadata.FilterMetadataEntry,
    json_name: "filterMetadata",
    map: true

  field :typed_filter_metadata, 2,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Metadata.TypedFilterMetadataEntry,
    json_name: "typedFilterMetadata",
    map: true
end

defmodule Arion.ControlPlane.Pb.Data.MetadataKey.PathSegment do
  @moduledoc false

  use Protobuf,
    full_name: "data.MetadataKey.PathSegment",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :segment, 0

  field :key, 1, type: :string, oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.MetadataKey do
  @moduledoc false

  use Protobuf,
    full_name: "data.MetadataKey",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :path, 2, repeated: true, type: Arion.ControlPlane.Pb.Data.MetadataKey.PathSegment
end
