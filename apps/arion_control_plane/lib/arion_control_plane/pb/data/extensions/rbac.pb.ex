defmodule Arion.ControlPlane.Pb.Data.Extensions.RBAC.Action do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.RBAC.Action",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :ALLOW, 0
  field :DENY, 1
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RBACNetworkFilter do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RBACNetworkFilter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :rules, 1, type: Arion.ControlPlane.Pb.Data.Extensions.RBAC
  field :stat_prefix, 3, type: :string, json_name: "statPrefix"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RBACConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RBACConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :rules, 1, type: Arion.ControlPlane.Pb.Data.Extensions.RBAC
  field :rules_stat_prefix, 6, type: :string, json_name: "rulesStatPrefix"
  field :track_per_rule_stats, 7, type: :bool, json_name: "trackPerRuleStats"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RBACPerRoute do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RBACPerRoute",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :rbac, 2, type: Arion.ControlPlane.Pb.Data.Extensions.RBACConfig
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RBAC.PoliciesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RBAC.PoliciesEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Arion.ControlPlane.Pb.Data.Extensions.Policy
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RBAC do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RBAC",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :action, 1, type: Arion.ControlPlane.Pb.Data.Extensions.RBAC.Action, enum: true

  field :policies, 2,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.RBAC.PoliciesEntry,
    map: true
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Policy do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Policy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :permissions, 1, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.Permission
  field :principals, 2, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.Principal
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Permission.Set do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Permission.Set",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :rules, 1, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.Permission
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Permission do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Permission",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :rule, 0

  field :and_rules, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.Permission.Set,
    json_name: "andRules",
    oneof: 0

  field :or_rules, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.Permission.Set,
    json_name: "orRules",
    oneof: 0

  field :any, 3, type: :bool, oneof: 0
  field :header, 4, type: Arion.ControlPlane.Pb.Data.HeaderMatcher, oneof: 0

  field :url_path, 10,
    type: Arion.ControlPlane.Pb.Data.PathMatcher,
    json_name: "urlPath",
    oneof: 0

  field :destination_ip, 5,
    type: Arion.ControlPlane.Pb.Data.CidrRange,
    json_name: "destinationIp",
    oneof: 0

  field :destination_port, 6, type: :uint32, json_name: "destinationPort", oneof: 0

  field :destination_port_range, 11,
    type: Arion.ControlPlane.Pb.Data.Int32Range,
    json_name: "destinationPortRange",
    oneof: 0

  field :not_rule, 8,
    type: Arion.ControlPlane.Pb.Data.Extensions.Permission,
    json_name: "notRule",
    oneof: 0

  field :requested_server_name, 9,
    type: Arion.ControlPlane.Pb.Data.StringMatcher,
    json_name: "requestedServerName",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Principal.Set do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Principal.Set",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :ids, 1, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.Principal
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Principal.Authenticated do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Principal.Authenticated",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :principal_name, 2,
    type: Arion.ControlPlane.Pb.Data.StringMatcher,
    json_name: "principalName"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Principal do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Principal",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :identifier, 0

  field :and_ids, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.Principal.Set,
    json_name: "andIds",
    oneof: 0

  field :or_ids, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.Principal.Set,
    json_name: "orIds",
    oneof: 0

  field :any, 3, type: :bool, oneof: 0

  field :authenticated, 4,
    type: Arion.ControlPlane.Pb.Data.Extensions.Principal.Authenticated,
    oneof: 0

  field :direct_remote_ip, 10,
    type: Arion.ControlPlane.Pb.Data.CidrRange,
    json_name: "directRemoteIp",
    oneof: 0

  field :remote_ip, 11,
    type: Arion.ControlPlane.Pb.Data.CidrRange,
    json_name: "remoteIp",
    oneof: 0

  field :header, 6, type: Arion.ControlPlane.Pb.Data.HeaderMatcher, oneof: 0
  field :url_path, 9, type: Arion.ControlPlane.Pb.Data.PathMatcher, json_name: "urlPath", oneof: 0

  field :not_id, 8,
    type: Arion.ControlPlane.Pb.Data.Extensions.Principal,
    json_name: "notId",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Action do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Action",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :action, 2, type: Arion.ControlPlane.Pb.Data.Extensions.RBAC.Action, enum: true
end
