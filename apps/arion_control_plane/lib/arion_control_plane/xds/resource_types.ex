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

defmodule Arion.ControlPlane.Xds.ResourceTypes do
  @moduledoc """
  The one table of xDS message types this control plane speaks: each kind's
  Elixir module and wire type URL.

  Discovery kinds are served over ADS and cached per fleet; they also carry the
  `Kind` their standalone manifests use. Typed configs are the `Any` payloads
  found inside those resources. Adding a type here is all the helpers and the
  standalone codec need.
  """

  alias Arion.ControlPlane.Pb
  alias Pb.Data.Extensions, as: Ext

  @discovery [
    cluster:
      {Pb.Cluster.Cluster, "type.googleapis.com/envoy.config.cluster.v3.Cluster", "Cluster"},
    listener:
      {Pb.Listener.Listener, "type.googleapis.com/envoy.config.listener.v3.Listener", "Listener"},
    load_assignment:
      {Pb.Endpoint.ClusterLoadAssignment,
       "type.googleapis.com/envoy.config.endpoint.v3.ClusterLoadAssignment",
       "ClusterLoadAssignment"},
    route:
      {Pb.Route.RouteConfiguration,
       "type.googleapis.com/envoy.config.route.v3.RouteConfiguration", "RouteConfiguration"},
    secret:
      {Ext.Secret, "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret",
       "Secret"},
    mcp_tool:
      {Ext.Tool, "type.googleapis.com/arion.extensions.filters.http.mcp.mcp_gateway.v3.Tool",
       "McpTool"},
    mcp_dynamic_server:
      {Ext.DynamicMcpServer,
       "type.googleapis.com/arion.extensions.filters.http.mcp.mcp_gateway.v3.DynamicMcpServer",
       "McpDynamicServer"},
    mcp_toolkit:
      {Ext.Toolkit,
       "type.googleapis.com/arion.extensions.filters.http.mcp.mcp_gateway.v3.Toolkit",
       "McpToolkit"},
    mcp_openapi_source:
      {Ext.OpenApiToolSource,
       "type.googleapis.com/arion.extensions.filters.http.mcp.mcp_gateway.v3.OpenApiToolSource",
       "McpOpenApiSource"}
  ]

  @typed_configs [
    http_connection_manager:
      {Pb.Filter.HttpConnectionManager,
       "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager"},
    router:
      {Google.Protobuf.Empty,
       "type.googleapis.com/envoy.extensions.filters.http.router.v3.Router"},
    tcp_proxy:
      {Pb.Filter.TcpProxy,
       "type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy"},
    upstream_tls_context:
      {Ext.UpstreamTlsContext,
       "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext"},
    downstream_tls_context:
      {Ext.DownstreamTlsContext,
       "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.DownstreamTlsContext"},
    raw_buffer:
      {Ext.RawBuffer,
       "type.googleapis.com/envoy.extensions.transport_sockets.raw_buffer.v3.RawBuffer"},
    proxy_protocol_transport:
      {Ext.ProxyProtocolUpstreamTransport,
       "type.googleapis.com/envoy.extensions.transport_sockets.proxy_protocol.v3.ProxyProtocolUpstreamTransport"},
    http_protocol_options:
      {Ext.HttpProtocolOptions,
       "type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions"},
    tls_inspector:
      {Ext.TlsInspector,
       "type.googleapis.com/envoy.extensions.filters.listener.tls_inspector.v3.TlsInspector"},
    proxy_protocol_listener_filter:
      {Ext.ProxyProtocolListenerFilter,
       "type.googleapis.com/envoy.extensions.filters.listener.proxy_protocol.v3.ProxyProtocol"},
    listener_local_rate_limit:
      {Ext.ListenerLocalRateLimit,
       "type.googleapis.com/envoy.extensions.filters.listener.local_ratelimit.v3.LocalRateLimit"},
    local_rate_limit:
      {Ext.LocalRateLimit,
       "type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit"},
    network_connection_limit:
      {Ext.ConnectionLimit,
       "type.googleapis.com/envoy.extensions.filters.network.connection_limit.v3.ConnectionLimit"},
    network_rate_limit:
      {Ext.NetworkRateLimit,
       "type.googleapis.com/envoy.extensions.filters.network.ratelimit.v3.RateLimit"},
    user_rate_limiter:
      {Ext.UserRateLimiter,
       "type.googleapis.com/arion.extensions.filters.http.user_rate_limit.v3.UserRateLimiter"},
    rbac_network_filter:
      {Ext.RBACNetworkFilter, "type.googleapis.com/envoy.extensions.filters.network.rbac.v3.RBAC"},
    rbac_http_filter:
      {Ext.RBACConfig, "type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBAC"},
    rbac_per_route:
      {Ext.RBACPerRoute, "type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBACPerRoute"},
    ext_proc:
      {Ext.ExternalProcessor,
       "type.googleapis.com/envoy.extensions.filters.http.ext_proc.v3.ExternalProcessor"},
    ext_proc_per_route:
      {Ext.ExtProcPerRoute,
       "type.googleapis.com/envoy.extensions.filters.http.ext_proc.v3.ExtProcPerRoute"},
    jwt_authn:
      {Ext.JwtAuthentication,
       "type.googleapis.com/envoy.extensions.filters.http.jwt_authn.v3.JwtAuthentication"},
    cors: {Ext.Cors, "type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors"},
    cors_policy:
      {Ext.CorsPolicy, "type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy"},
    mcp_gateway:
      {Ext.McpGateway,
       "type.googleapis.com/arion.extensions.filters.http.mcp.mcp_gateway.v3.McpGateway"},
    file_access_log:
      {Ext.FileAccessLog,
       "type.googleapis.com/envoy.extensions.access_loggers.file.v3.FileAccessLog"},
    stdout_access_log:
      {Ext.StdoutAccessLog,
       "type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog"},
    stderr_access_log:
      {Ext.StderrAccessLog,
       "type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StderrAccessLog"},
    lb_round_robin:
      {Ext.RoundRobin,
       "type.googleapis.com/envoy.extensions.load_balancing_policies.round_robin.v3.RoundRobin"},
    lb_random:
      {Ext.Random,
       "type.googleapis.com/envoy.extensions.load_balancing_policies.random.v3.Random"},
    lb_least_request:
      {Ext.LeastRequest,
       "type.googleapis.com/envoy.extensions.load_balancing_policies.least_request.v3.LeastRequest"},
    lb_ring_hash:
      {Ext.RingHash,
       "type.googleapis.com/envoy.extensions.load_balancing_policies.ring_hash.v3.RingHash"},
    lb_maglev:
      {Ext.Maglev,
       "type.googleapis.com/envoy.extensions.load_balancing_policies.maglev.v3.Maglev"},
    lb_override_host:
      {Ext.OverrideHost,
       "type.googleapis.com/envoy.extensions.load_balancing_policies.override_host.v3.OverrideHost"},
    opentelemetry_tracing:
      {Ext.OpenTelemetryConfig, "type.googleapis.com/envoy.config.trace.v3.OpenTelemetryConfig"},
    opentelemetry_stats_sink:
      {Ext.OpenTelemetrySinkConfig,
       "type.googleapis.com/envoy.extensions.stat_sinks.open_telemetry.v3.SinkConfig"}
  ]

  @types Map.new(
           Enum.map(@discovery, fn {kind, {module, url, _api}} -> {kind, {module, url}} end) ++
             @typed_configs
         )
  @by_type_url Map.new(@types, fn {kind, {_module, url}} -> {url, kind} end)
  @discovery_kinds Keyword.keys(@discovery)
  @by_api_kind Map.new(@discovery, fn {kind, {_module, _url, api}} -> {api, kind} end)

  @doc "The kinds served over ADS, in no particular order."
  def discovery_kinds, do: @discovery_kinds

  def discovery_kind?(kind), do: kind in @discovery_kinds

  @doc "Raises unless `kind` is served over ADS."
  def discovery_kind!(kind) do
    if discovery_kind?(kind),
      do: kind,
      else: raise(ArgumentError, "#{inspect(kind)} is not a discovery resource kind")
  end

  def module!(kind), do: kind |> fetch!() |> elem(0)

  def type_url!(kind), do: kind |> fetch!() |> elem(1)

  @doc "Raises unless `message` is a struct of the module registered for `kind`."
  def check_module!(kind, message) do
    expected = module!(kind)

    case message do
      %^expected{} ->
        :ok

      %actual{} ->
        raise ArgumentError, "#{kind} expects #{inspect(expected)}, got #{inspect(actual)}"

      _ ->
        raise ArgumentError, "#{kind} expects a #{inspect(expected)} struct"
    end
  end

  @doc "The kind of a wire type URL, discovery or typed config."
  def kind_for_type_url(type_url), do: Map.fetch(@by_type_url, type_url)

  @doc "The standalone manifest `Kind` of a discovery kind, and back."
  def api_kind!(kind), do: @discovery |> Keyword.fetch!(kind) |> elem(2)

  def kind_for_api_kind(api_kind), do: Map.fetch(@by_api_kind, api_kind)

  @doc """
  The name a resource is cached and discovered under: its protobuf name, a
  load assignment's cluster name, or the name of a `{name, resource}` pair for
  payloads whose own name is not unique. Raises on an empty or missing name.
  """
  def resource_name!(resource) do
    case name_of(resource) do
      name when is_binary(name) and name != "" -> name
      _ -> raise ArgumentError, "resource has no discovery name"
    end
  end

  defp name_of({name, _resource}), do: name
  defp name_of(%Pb.Endpoint.ClusterLoadAssignment{cluster_name: name}), do: name
  defp name_of(%{name: name}), do: name
  defp name_of(%{namespace: name}), do: name
  defp name_of(_resource), do: nil

  defp fetch!(kind) do
    case Map.fetch(@types, kind) do
      {:ok, entry} -> entry
      :error -> raise ArgumentError, "unknown resource kind #{inspect(kind)}"
    end
  end
end
