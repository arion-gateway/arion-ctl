defmodule Arion.ControlPlane.Pb.Data.Extensions.DisclosureMode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.DisclosureMode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :PROGRESSIVE, 0
  field :EAGER, 1
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.McpServerBackend.TransportUpstream do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.McpServerBackend.TransportUpstream",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :Sse, 0
  field :StreamableHttp, 1
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ToolRbac.Action do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.ToolRbac.Action",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :ALLOW, 0
  field :DENY, 1
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.McpGateway do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.McpGateway",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :mode, 0

  field :server_info, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.ServerInfo,
    json_name: "serverInfo"

  field :tools, 2, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.Tool
  field :search, 3, type: Arion.ControlPlane.Pb.Data.Extensions.ToolSearch
  field :tds, 4, type: Arion.ControlPlane.Pb.Data.Extensions.TdsSpecifier

  field :dynamic_mcp_servers, 5,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.DynamicMcpServer,
    json_name: "dynamicMcpServers"

  field :upstream_timeout, 6, type: Google.Protobuf.Duration, json_name: "upstreamTimeout"

  field :max_upstream_response_bytes, 7,
    proto3_optional: true,
    type: :uint64,
    json_name: "maxUpstreamResponseBytes"

  field :tools_mode, 8,
    type: Arion.ControlPlane.Pb.Data.Extensions.ToolsMode,
    json_name: "toolsMode",
    oneof: 0

  field :code_mode, 9,
    type: Arion.ControlPlane.Pb.Data.Extensions.CodeMode,
    json_name: "codeMode",
    oneof: 0

  field :open_api_tool_sources, 10,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.OpenApiToolSource,
    json_name: "openApiToolSources"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ServerInfo do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ServerInfo",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :version, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ToolsMode do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ToolsMode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.CodeMode do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.CodeMode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :execution_timeout, 1, type: Google.Protobuf.Duration, json_name: "executionTimeout"
  field :max_host_calls, 2, type: :uint32, json_name: "maxHostCalls"
  field :max_concurrent_executions, 3, type: :uint32, json_name: "maxConcurrentExecutions"
  field :max_concurrent_tool_calls, 8, type: :uint32, json_name: "maxConcurrentToolCalls"
  field :max_output_bytes, 4, type: :uint64, json_name: "maxOutputBytes"
  field :memory_limit_bytes, 5, type: :uint64, json_name: "memoryLimitBytes"

  field :engine_artifact_path, 6,
    proto3_optional: true,
    type: :string,
    json_name: "engineArtifactPath"

  field :toolkits, 7, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.Toolkit
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Tool do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Tool",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :upstream_backend, 0

  field :namespace, 1, type: :string
  field :name, 2, type: :string
  field :description, 3, type: :string
  field :input_schema, 4, type: Arion.ControlPlane.Pb.Data.DataSource, json_name: "inputSchema"
  field :output_schema, 5, type: Arion.ControlPlane.Pb.Data.DataSource, json_name: "outputSchema"

  field :rest_backend, 6,
    type: Arion.ControlPlane.Pb.Data.Extensions.RestBackend,
    json_name: "restBackend",
    oneof: 0

  field :function_graph_backend, 7,
    type: Arion.ControlPlane.Pb.Data.Extensions.FunctionGraphBackend,
    json_name: "functionGraphBackend",
    oneof: 0

  field :mcp_server_backend, 8,
    type: Arion.ControlPlane.Pb.Data.Extensions.McpServerBackend,
    json_name: "mcpServerBackend",
    oneof: 0

  field :rbac, 9, proto3_optional: true, type: Arion.ControlPlane.Pb.Data.Extensions.ToolRbac
  field :embedding, 10, repeated: true, type: :float, packed: true, deprecated: false

  field :disclosure_mode, 11,
    type: Arion.ControlPlane.Pb.Data.Extensions.DisclosureMode,
    json_name: "disclosureMode",
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RestBackend do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RestBackend",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :body, 0

  field :method, 1, type: :string
  field :path, 2, type: :string

  field :query_params, 3,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.QueryParam,
    json_name: "queryParams"

  field :cluster, 4, type: :string

  field :body_template, 5,
    type: Arion.ControlPlane.Pb.Data.DataSource,
    json_name: "bodyTemplate",
    oneof: 0

  field :body_json, 7, type: :string, json_name: "bodyJson", oneof: 0

  field :upstream_policy, 6,
    type: Arion.ControlPlane.Pb.Data.Extensions.HttpUpstreamPolicy,
    json_name: "upstreamPolicy"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.HttpUpstreamPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.HttpUpstreamPolicy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :authority, 1, proto3_optional: true, type: :string
  field :timeout, 2, type: Google.Protobuf.Duration
  field :retry_policy, 3, type: Arion.ControlPlane.Pb.Route.RetryPolicy, json_name: "retryPolicy"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.QueryParam do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.QueryParam",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :source, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.FunctionGraphBackend do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.FunctionGraphBackend",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.McpServerBackend do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.McpServerBackend",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :transport, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.McpServerBackend.TransportUpstream,
    enum: true

  field :url, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.DynamicMcpServer do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.DynamicMcpServer",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :namespace, 1, type: :string
  field :description, 2, type: :string

  field :transport, 3,
    type: Arion.ControlPlane.Pb.Data.Extensions.McpServerBackend.TransportUpstream,
    enum: true

  field :url, 4, type: :string
  field :cache_duration, 5, type: Google.Protobuf.Duration, json_name: "cacheDuration"
  field :rbac, 6, proto3_optional: true, type: Arion.ControlPlane.Pb.Data.Extensions.ToolRbac

  field :tool_disclosure_mode, 7,
    type: Arion.ControlPlane.Pb.Data.Extensions.DisclosureMode,
    json_name: "toolDisclosureMode",
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.OpenApiToolSource do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.OpenApiToolSource",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :spec, 1, type: Arion.ControlPlane.Pb.Data.DataSource
  field :namespace, 2, type: :string
  field :cluster, 3, type: :string

  field :upstream_policy, 4,
    type: Arion.ControlPlane.Pb.Data.Extensions.HttpUpstreamPolicy,
    json_name: "upstreamPolicy"

  field :rbac, 5, proto3_optional: true, type: Arion.ControlPlane.Pb.Data.Extensions.ToolRbac

  field :tool_disclosure_mode, 6,
    type: Arion.ControlPlane.Pb.Data.Extensions.DisclosureMode,
    json_name: "toolDisclosureMode",
    enum: true

  field :path_prefix, 7, proto3_optional: true, type: :string, json_name: "pathPrefix"
  field :skip_unsupported_operations, 8, type: :bool, json_name: "skipUnsupportedOperations"
  field :include_operations, 9, repeated: true, type: :string, json_name: "includeOperations"
  field :exclude_operations, 10, repeated: true, type: :string, json_name: "excludeOperations"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.TdsSpecifier do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.TdsSpecifier",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :config_name, 1, type: :string, json_name: "configName"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ToolRbac do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ToolRbac",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :action, 1, type: Arion.ControlPlane.Pb.Data.Extensions.ToolRbac.Action, enum: true
  field :permissions, 2, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.McpPermission
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.McpPermission do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.McpPermission",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :permission_type, 0

  field :jwt_header, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.JwtHeaderMatcher,
    json_name: "jwtHeader",
    oneof: 0

  field :jwt_claim, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.JwtClaimMatcher,
    json_name: "jwtClaim",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.JwtHeaderMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.JwtHeaderMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :field, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.JwtClaimMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.JwtClaimMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :field, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ToolSearch do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ToolSearch",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :max_allowable_results, 1,
    proto3_optional: true,
    type: :uint32,
    json_name: "maxAllowableResults"

  field :embeddings, 2, type: Arion.ControlPlane.Pb.Data.Extensions.RemoteEmbeddings
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.RemoteEmbeddings do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.RemoteEmbeddings",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :cluster, 1, type: :string
  field :model_id, 2, type: :string, json_name: "modelId"
  field :path, 3, type: :string
  field :timeout, 4, type: Google.Protobuf.Duration
  field :dimensions, 5, type: :uint32
  field :max_batch_size, 6, proto3_optional: true, type: :uint32, json_name: "maxBatchSize"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Toolkit do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Toolkit",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :description, 2, type: :string
  field :instructions, 3, type: :string
  field :tools, 4, repeated: true, type: Arion.ControlPlane.Pb.Data.Extensions.ToolkitToolRef
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.ToolkitToolRef do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.ToolkitToolRef",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :namespace, 1, type: :string
  field :name, 2, type: :string
end
