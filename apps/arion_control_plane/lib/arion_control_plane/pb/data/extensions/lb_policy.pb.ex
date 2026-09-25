defmodule Arion.ControlPlane.Pb.Data.Extensions.RoundRobin do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RoundRobin",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Random do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Random",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.LeastRequest do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.LeastRequest",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RingHash do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RingHash",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Maglev do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Maglev",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.OverrideHost.OverrideHostSource do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.OverrideHost.OverrideHostSource",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :header, 1, type: :string
  field :metadata, 2, type: Arion.ControlPlane.Pb.Data.MetadataKey
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.OverrideHost do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.OverrideHost",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :override_host_sources, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.OverrideHost.OverrideHostSource,
    json_name: "overrideHostSources"

  field :fallback_policy, 3,
    type: Arion.ControlPlane.Pb.Data.Extensions.LoadBalancingPolicy,
    json_name: "fallbackPolicy"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.LoadBalancingPolicy.Policy do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.LoadBalancingPolicy.Policy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :typed_extension_config, 4,
    type: Arion.ControlPlane.Pb.Data.TypedExtensionConfig,
    json_name: "typedExtensionConfig"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.LoadBalancingPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.LoadBalancingPolicy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :policies, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.LoadBalancingPolicy.Policy
end
