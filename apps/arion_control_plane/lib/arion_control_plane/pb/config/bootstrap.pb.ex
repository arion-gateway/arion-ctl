defmodule Arion.ControlPlane.Pb.Config.Bootstrap.StaticResources do
  @moduledoc false

  use Protobuf,
    full_name: "config.Bootstrap.StaticResources",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :listeners, 1, repeated: true, type: Arion.ControlPlane.Pb.Listener.Listener
  field :clusters, 2, repeated: true, type: Arion.ControlPlane.Pb.Cluster.Cluster
  field :secrets, 3, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.Secret
end

defmodule Arion.ControlPlane.Pb.Config.Bootstrap.DynamicResources do
  @moduledoc false

  use Protobuf,
    full_name: "config.Bootstrap.DynamicResources",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :lds_config, 1, type: Arion.ControlPlane.Pb.Data.ConfigSource, json_name: "ldsConfig"
  field :cds_config, 2, type: Arion.ControlPlane.Pb.Data.ConfigSource, json_name: "cdsConfig"
  field :ads_config, 3, type: Arion.ControlPlane.Pb.Data.ApiConfigSource, json_name: "adsConfig"
end

defmodule Arion.ControlPlane.Pb.Config.Bootstrap do
  @moduledoc false

  use Protobuf,
    full_name: "config.Bootstrap",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :node, 1, type: Arion.ControlPlane.Pb.Data.Node

  field :static_resources, 2,
    type: Arion.ControlPlane.Pb.Config.Bootstrap.StaticResources,
    json_name: "staticResources"

  field :dynamic_resources, 3,
    type: Arion.ControlPlane.Pb.Config.Bootstrap.DynamicResources,
    json_name: "dynamicResources"

  field :admin, 12, type: Arion.ControlPlane.Pb.Config.Admin
end

defmodule Arion.ControlPlane.Pb.Config.Admin do
  @moduledoc false

  use Protobuf, full_name: "config.Admin", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :address, 3, type: Arion.ControlPlane.Pb.Data.Address

  field :socket_options, 4,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.SocketOption,
    json_name: "socketOptions"
end
