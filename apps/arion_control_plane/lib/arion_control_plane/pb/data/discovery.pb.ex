defmodule Arion.ControlPlane.Pb.Data.DiscoveryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "data.DiscoveryRequest",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :version_info, 1, type: :string, json_name: "versionInfo"
  field :node, 2, type: Arion.ControlPlane.Pb.Data.Node
  field :resource_names, 3, repeated: true, type: :string, json_name: "resourceNames"
  field :type_url, 4, type: :string, json_name: "typeUrl"
  field :response_nonce, 5, type: :string, json_name: "responseNonce"
  field :error_detail, 6, type: Arion.ControlPlane.Pb.Data.Status, json_name: "errorDetail"
end

defmodule Arion.ControlPlane.Pb.Data.DiscoveryResponse do
  @moduledoc false

  use Protobuf,
    full_name: "data.DiscoveryResponse",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :version_info, 1, type: :string, json_name: "versionInfo"
  field :resources, 2, repeated: true, type: Google.Protobuf.Any
  field :type_url, 4, type: :string, json_name: "typeUrl"
  field :nonce, 5, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.DeltaDiscoveryRequest.InitialResourceVersionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.DeltaDiscoveryRequest.InitialResourceVersionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.DeltaDiscoveryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "data.DeltaDiscoveryRequest",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :node, 1, type: Arion.ControlPlane.Pb.Data.Node
  field :type_url, 2, type: :string, json_name: "typeUrl"

  field :resource_names_subscribe, 3,
    repeated: true,
    type: :string,
    json_name: "resourceNamesSubscribe"

  field :resource_names_unsubscribe, 4,
    repeated: true,
    type: :string,
    json_name: "resourceNamesUnsubscribe"

  field :initial_resource_versions, 5,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.DeltaDiscoveryRequest.InitialResourceVersionsEntry,
    json_name: "initialResourceVersions",
    map: true

  field :response_nonce, 6, type: :string, json_name: "responseNonce"
  field :error_detail, 7, type: Arion.ControlPlane.Pb.Data.Status, json_name: "errorDetail"
end

defmodule Arion.ControlPlane.Pb.Data.DeltaDiscoveryResponse do
  @moduledoc false

  use Protobuf,
    full_name: "data.DeltaDiscoveryResponse",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :system_version_info, 1, type: :string, json_name: "systemVersionInfo"
  field :resources, 2, repeated: true, type: Arion.ControlPlane.Pb.Data.Resource
  field :type_url, 4, type: :string, json_name: "typeUrl"
  field :nonce, 5, type: :string
  field :removed_resources, 6, repeated: true, type: :string, json_name: "removedResources"
end
