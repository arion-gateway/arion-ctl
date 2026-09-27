# Copyright 2026 The arion-gateway Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Arion.ControlPlane.Helpers.McpGateway do
  @moduledoc """
  The Arion MCP gateway HTTP filter: its inline tools, dynamic servers and
  OpenAPI sources, the same as TDS resources, and code mode toolkits. `add_*`
  appends one item in call order; `gateway/2` takes whole lists. Durations
  are seconds; an omitted option leaves its field unset.
  """

  import Arion.ControlPlane.Helpers.Xds, only: [duration: 1]

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Pb

  # Arion reads zero on these as "use the built-in default", so they are only
  # set when supplied.
  @code_mode_limits [
    :max_host_calls,
    :max_concurrent_executions,
    :max_concurrent_tool_calls,
    :max_output_bytes,
    :memory_limit_bytes
  ]

  def gateway(server_name, opts \\ []) do
    %Pb.McpGateway{
      server_info: server_info(server_name, Keyword.get(opts, :version, "1.0.0")),
      tools: Keyword.get(opts, :tools, []),
      search: Keyword.get(opts, :search),
      tds: Keyword.get(opts, :tds),
      dynamic_mcp_servers: Keyword.get(opts, :dynamic_servers, []),
      open_api_tool_sources: Keyword.get(opts, :open_api_sources, []),
      upstream_timeout: duration(Keyword.get(opts, :upstream_timeout)),
      max_upstream_response_bytes: Keyword.get(opts, :max_upstream_response_bytes),
      mode: Keyword.get(opts, :mode, tools_mode())
    }
  end

  def filter(name, gateway), do: Xds.http_filter(name, :mcp_gateway, gateway)

  def server_info(name, version), do: %Pb.ServerInfo{name: name, version: version}

  def tds(config_name), do: %Pb.TdsSpecifier{config_name: config_name}

  @spec add_tool(Pb.McpGateway.t(), Pb.Tool.t()) :: Pb.McpGateway.t()
  def add_tool(%Pb.McpGateway{} = gateway, %Pb.Tool{} = tool),
    do: %{gateway | tools: gateway.tools ++ [tool]}

  @spec add_dynamic_server(Pb.McpGateway.t(), Pb.DynamicMcpServer.t()) :: Pb.McpGateway.t()
  def add_dynamic_server(%Pb.McpGateway{} = gateway, %Pb.DynamicMcpServer{} = server),
    do: %{gateway | dynamic_mcp_servers: gateway.dynamic_mcp_servers ++ [server]}

  @spec add_open_api_source(Pb.McpGateway.t(), Pb.OpenApiToolSource.t()) :: Pb.McpGateway.t()
  def add_open_api_source(%Pb.McpGateway{} = gateway, %Pb.OpenApiToolSource{} = source),
    do: %{gateway | open_api_tool_sources: gateway.open_api_tool_sources ++ [source]}

  @doc "Adds a toolkit to a `code_mode/1` mode value."
  @spec add_toolkit({:code_mode, Pb.CodeMode.t()}, Pb.Toolkit.t()) ::
          {:code_mode, Pb.CodeMode.t()}
  def add_toolkit({:code_mode, code_mode}, %Pb.Toolkit{} = toolkit),
    do: {:code_mode, %{code_mode | toolkits: code_mode.toolkits ++ [toolkit]}}

  @doc "Conventional MCP tool discovery and invocation."
  def tools_mode, do: {:tools_mode, %Pb.ToolsMode{}}

  @doc "Sandboxed TypeScript execution exposed as the exclusive `execute` tool."
  def code_mode(opts \\ []) do
    code_mode = %Pb.CodeMode{
      execution_timeout: duration(Keyword.get(opts, :execution_timeout)),
      engine_artifact_path: Keyword.get(opts, :engine_artifact_path),
      toolkits: Keyword.get(opts, :toolkits, [])
    }

    {:code_mode, struct(code_mode, Keyword.take(opts, @code_mode_limits))}
  end

  def tool(namespace, name, description, backend, opts \\ []) do
    %Pb.Tool{
      namespace: namespace,
      name: name,
      description: description,
      upstream_backend: backend,
      input_schema: data_source(Keyword.get(opts, :input_schema)),
      output_schema: data_source(Keyword.get(opts, :output_schema)),
      rbac: Keyword.get(opts, :rbac),
      embedding: Keyword.get(opts, :embedding, []),
      disclosure_mode: disclosure(Keyword.get(opts, :disclosure))
    }
  end

  @doc "Public MCP name of a tool: `namespace.name`."
  def qualified_name(%Pb.Tool{namespace: namespace, name: name}), do: "#{namespace}.#{name}"

  def rest_backend(cluster, method, path, opts \\ []) do
    {:rest_backend,
     %Pb.RestBackend{
       cluster: cluster,
       method: method,
       path: path,
       query_params: Enum.map(Keyword.get(opts, :query_params, []), &query_param/1),
       body: rest_body(opts),
       upstream_policy: Keyword.get(opts, :upstream_policy)
     }}
  end

  def query_param(%Pb.QueryParam{} = param), do: param
  def query_param({name, source}), do: query_param(name, source)
  def query_param(name, source), do: %Pb.QueryParam{name: name, source: source}

  def mcp_server_backend(url, transport \\ :StreamableHttp) do
    {:mcp_server_backend, %Pb.McpServerBackend{transport: transport, url: url}}
  end

  def upstream_policy(opts \\ []) do
    %Pb.HttpUpstreamPolicy{
      authority: Keyword.get(opts, :authority),
      timeout: duration(Keyword.get(opts, :timeout)),
      retry_policy: Keyword.get(opts, :retry_policy)
    }
  end

  def dynamic_server(namespace, description, url, opts \\ []) do
    %Pb.DynamicMcpServer{
      namespace: namespace,
      description: description,
      url: url,
      transport: Keyword.get(opts, :transport, :StreamableHttp),
      cache_duration: duration(Keyword.get(opts, :cache_duration)),
      rbac: Keyword.get(opts, :rbac),
      tool_disclosure_mode: disclosure(Keyword.get(opts, :tool_disclosure))
    }
  end

  @doc "An OpenAPI 3.x document expanded into one REST-backed tool per operation."
  def open_api_source(namespace, cluster, spec, opts \\ []) do
    %Pb.OpenApiToolSource{
      namespace: namespace,
      cluster: cluster,
      spec: data_source(spec),
      upstream_policy: Keyword.get(opts, :upstream_policy),
      rbac: Keyword.get(opts, :rbac),
      tool_disclosure_mode: disclosure(Keyword.get(opts, :tool_disclosure)),
      path_prefix: Keyword.get(opts, :path_prefix),
      skip_unsupported_operations: Keyword.get(opts, :skip_unsupported_operations, false),
      include_operations: Keyword.get(opts, :include_operations, []),
      exclude_operations: Keyword.get(opts, :exclude_operations, [])
    }
  end

  @doc """
  Search and ranking configuration. Arion uses BM25 unless embeddings are set.

  `max_allowable_results` caps what a caller may request, it is not the number
  of results returned.
  """
  def tool_search(opts \\ []) do
    %Pb.ToolSearch{
      max_allowable_results: Keyword.get(opts, :max_allowable_results),
      embeddings: Keyword.get(opts, :embeddings)
    }
  end

  def remote_embeddings(cluster, model_id, dimensions, opts \\ []) do
    %Pb.RemoteEmbeddings{
      cluster: cluster,
      model_id: model_id,
      dimensions: dimensions,
      path: Keyword.get(opts, :path, ""),
      timeout: duration(Keyword.get(opts, :timeout)),
      max_batch_size: Keyword.get(opts, :max_batch_size)
    }
  end

  @doc "A curated, Code Mode-only tool list. Requires at least two tool references."
  def toolkit(name, description, instructions, tools) do
    %Pb.Toolkit{
      name: name,
      description: description,
      instructions: instructions,
      tools: Enum.map(tools, &toolkit_tool_ref/1)
    }
  end

  def toolkit_tool_ref(%Pb.ToolkitToolRef{} = ref), do: ref

  def toolkit_tool_ref(%Pb.Tool{namespace: namespace, name: name}),
    do: toolkit_tool_ref(namespace, name)

  def toolkit_tool_ref({namespace, name}), do: toolkit_tool_ref(namespace, name)

  def toolkit_tool_ref(namespace, name),
    do: %Pb.ToolkitToolRef{namespace: namespace, name: name}

  def rbac(action, permissions) do
    %Pb.ToolRbac{action: action, permissions: permissions}
  end

  def jwt_claim(field, value) do
    %Pb.McpPermission{
      permission_type: {:jwt_claim, %Pb.JwtClaimMatcher{field: field, value: value}}
    }
  end

  def jwt_header(field, value) do
    %Pb.McpPermission{
      permission_type: {:jwt_header, %Pb.JwtHeaderMatcher{field: field, value: value}}
    }
  end

  def inline_json_schema(json), do: Xds.data_source(:inline_string, json)

  @doc "TDS resource IDs are `{server_name}/{config_name}/{resource_name}`."
  def resource_id(server_name, config_name, resource_name),
    do: "#{server_name}/#{config_name}/#{resource_name}"

  def tool_resource(server_name, config_name, %Pb.Tool{} = tool),
    do: {resource_id(server_name, config_name, qualified_name(tool)), tool}

  def dynamic_server_resource(server_name, config_name, %Pb.DynamicMcpServer{} = server),
    do: {resource_id(server_name, config_name, server.namespace), server}

  def toolkit_resource(server_name, config_name, %Pb.Toolkit{} = toolkit),
    do: {resource_id(server_name, config_name, toolkit.name), toolkit}

  def open_api_source_resource(server_name, config_name, %Pb.OpenApiToolSource{} = source),
    do: {resource_id(server_name, config_name, source.namespace), source}

  defp rest_body(opts) do
    case {Keyword.get(opts, :body_template), Keyword.get(opts, :body_json)} do
      {nil, nil} -> nil
      {template, nil} -> {:body_template, data_source(template)}
      {nil, source} -> {:body_json, source}
      _ -> raise ArgumentError, "rest_backend accepts :body_template or :body_json, not both"
    end
  end

  defp data_source(%Arion.ControlPlane.Pb.Data.DataSource{} = source), do: source
  defp data_source(inline) when is_binary(inline), do: Xds.data_source(:inline_string, inline)
  defp data_source(nil), do: nil

  defp disclosure(nil), do: :PROGRESSIVE
  defp disclosure(:progressive), do: :PROGRESSIVE
  defp disclosure(:eager), do: :EAGER
  defp disclosure(mode) when mode in [:EAGER, :PROGRESSIVE], do: mode
end
