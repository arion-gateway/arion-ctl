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

defmodule Arion.ControlPlaneTest do
  use ExUnit.Case

  alias Arion.ControlPlane.Helpers.AccessLog
  alias Arion.ControlPlane.Helpers.Cluster
  alias Arion.ControlPlane.Helpers.Cors
  alias Arion.ControlPlane.Helpers.ExtProc
  alias Arion.ControlPlane.Helpers.FilterChain
  alias Arion.ControlPlane.Helpers.Hcm
  alias Arion.ControlPlane.Helpers.Jwt
  alias Arion.ControlPlane.Helpers.Listener
  alias Arion.ControlPlane.Helpers.McpGateway
  alias Arion.ControlPlane.Helpers.ProxyProtocol
  alias Arion.ControlPlane.Helpers.RateLimit
  alias Arion.ControlPlane.Helpers.Rbac
  alias Arion.ControlPlane.Helpers.Route
  alias Arion.ControlPlane.Helpers.RouteConfig
  alias Arion.ControlPlane.Helpers.Secret
  alias Arion.ControlPlane.Helpers.TcpProxy
  alias Arion.ControlPlane.Helpers.Tls
  alias Arion.ControlPlane.Helpers.VirtualHost
  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Cluster.Cluster, as: PbCluster
  alias Arion.ControlPlane.Pb.Data.Extensions.CertificateValidationContext
  alias Arion.ControlPlane.Pb.Data.Extensions.UpstreamTlsContext
  alias Arion.ControlPlane.Pb.Endpoint.ClusterLoadAssignment
  alias Arion.ControlPlane.Pb.Listener.Listener, as: PbListener
  alias Arion.ControlPlane.ResourceCache
  alias Arion.ControlPlane.Xds.ResourceTypes

  @tag :capture_log
  test "serve starts the xDS server once, and a control plane restart drops it" do
    start_supervised!({Arion.ControlPlane, serve?: false})
    refute serving?()

    assert :ok = Arion.ControlPlane.serve(port: 0)
    assert is_integer(:ranch.get_port("Arion.ControlPlane.Endpoint"))
    assert :ok = Arion.ControlPlane.serve(port: 0)

    stop_supervised!(Arion.ControlPlane)
    start_supervised!({Arion.ControlPlane, serve?: false})
    refute serving?()
  end

  defp serving? do
    Arion.ControlPlane.Supervisor
    |> Supervisor.which_children()
    |> Enum.any?(&match?({GRPC.Server.Supervisor, _, _, _}, &1))
  end

  test "xDS helpers centralize type URLs and Any encoding" do
    assert Xds.type_url(:cluster) == "type.googleapis.com/envoy.config.cluster.v3.Cluster"
    assert Xds.type_url(:mcp_tool) == ResourceTypes.type_url!(:mcp_tool)

    any = Xds.any(:local_rate_limit, RateLimit.local(1, 1, 1))

    assert any.type_url == Xds.type_url(:local_rate_limit)
    assert is_binary(any.value)
    assert byte_size(any.value) > 0

    stats_sink =
      Xds.any(
        :opentelemetry_stats_sink,
        %Arion.ControlPlane.Pb.Data.Extensions.OpenTelemetrySinkConfig{
          protocol_specifier: {:grpc_service, Xds.grpc_service(:envoy, "otel-stats")},
          prefix: "demo"
        }
      )

    assert stats_sink.type_url == Xds.type_url(:opentelemetry_stats_sink)
  end

  test "the type registry maps every kind to a module and a wire URL, and back" do
    assert ResourceTypes.module!(:cluster) == PbCluster
    assert ResourceTypes.kind_for_type_url(Xds.type_url(:route)) == {:ok, :route}
    assert ResourceTypes.kind_for_type_url(Xds.type_url(:tcp_proxy)) == {:ok, :tcp_proxy}
    assert ResourceTypes.kind_for_type_url("type.googleapis.com/unknown.Type") == :error
    assert ResourceTypes.discovery_kind?(:mcp_tool)
    refute ResourceTypes.discovery_kind?(:tcp_proxy)
    assert ResourceTypes.api_kind!(:load_assignment) == "ClusterLoadAssignment"
    assert ResourceTypes.kind_for_api_kind("McpToolkit") == {:ok, :mcp_toolkit}

    for kind <- ResourceTypes.discovery_kinds() do
      assert {:ok, ^kind} = ResourceTypes.kind_for_type_url(ResourceTypes.type_url!(kind))
      assert {:ok, ^kind} = ResourceTypes.kind_for_api_kind(ResourceTypes.api_kind!(kind))
      assert %{field_props: _} = ResourceTypes.module!(kind).__message_props__()
    end
  end

  test "resource cache stores resources by xDS name and encodes each once" do
    tool =
      McpGateway.tool(
        "docs",
        "search",
        "Search",
        McpGateway.rest_backend("api", "POST", "/search")
      )

    tool_resource = McpGateway.tool_resource("demo-gateway", "gateway", tool)
    load_assignment = %ClusterLoadAssignment{cluster_name: "service-a"}

    cache =
      ResourceCache.new()
      |> ResourceCache.add(:cluster, %PbCluster{name: "cluster-a"})
      |> ResourceCache.add(:load_assignment, load_assignment)
      |> ResourceCache.add(:mcp_tool, tool_resource)

    assert %ResourceCache.Entry{resource: ^load_assignment, wire: wire} =
             ResourceCache.get(cache, :load_assignment, "service-a")

    assert wire.name == "service-a"
    assert wire.version != ""
    assert wire.resource.type_url == ResourceTypes.type_url!(:load_assignment)
    assert ClusterLoadAssignment.decode(wire.resource.value) == load_assignment

    tool_entry = ResourceCache.get(cache, :mcp_tool, "demo-gateway/gateway/docs.search")
    assert tool_entry.resource == tool_resource
    assert tool_entry.wire.name == "demo-gateway/gateway/docs.search"
    assert tool_entry.wire.resource.type_url == ResourceTypes.type_url!(:mcp_tool)

    assert ResourceCache.resources(cache) == %{
             cluster: %{"cluster-a" => %PbCluster{name: "cluster-a"}},
             listener: %{},
             load_assignment: %{"service-a" => load_assignment},
             route: %{},
             secret: %{},
             mcp_tool: %{"demo-gateway/gateway/docs.search" => tool_resource},
             mcp_dynamic_server: %{},
             mcp_toolkit: %{},
             mcp_openapi_source: %{}
           }

    cache = ResourceCache.remove(cache, :mcp_tool, "demo-gateway/gateway/docs.search")
    assert ResourceCache.get(cache, :mcp_tool, "demo-gateway/gateway/docs.search") == nil

    same = ResourceCache.entry(:cluster, {"other-name", %PbCluster{name: "cluster-a"}})
    entry = ResourceCache.get(cache, :cluster, "cluster-a")
    assert same.wire.name == "other-name"
    assert same.wire.version == entry.wire.version

    assert entry.wire.version ==
             :crypto.hash(:sha256, entry.wire.resource.value) |> Base.encode16(case: :lower)

    changed =
      ResourceCache.entry(:cluster, %PbCluster{
        name: "cluster-a",
        connect_timeout: Xds.duration(1)
      })

    assert changed.wire.version != entry.wire.version
  end

  test "resource cache rejects what cannot be served before encoding it" do
    assert_raise ArgumentError, ~r/not a discovery resource kind/, fn ->
      ResourceCache.entry(:tcp_proxy, %Arion.ControlPlane.Pb.Filter.TcpProxy{})
    end

    assert_raise ArgumentError, ~r/cluster expects .*Cluster, got .*Listener/, fn ->
      ResourceCache.entry(:cluster, %PbListener{name: "x"})
    end

    assert_raise ArgumentError, ~r/expects a .*Cluster struct/, fn ->
      ResourceCache.entry(:cluster, %{})
    end

    assert_raise ArgumentError, ~r/no discovery name/, fn ->
      ResourceCache.entry(:cluster, %PbCluster{name: ""})
    end

    assert_raise ArgumentError, ~r/no discovery name/, fn ->
      ResourceCache.entry(:cluster, {"", %PbCluster{name: "named"}})
    end

    assert_raise ArgumentError, ~r/cors expects .*Cors, got .*CorsPolicy/, fn ->
      Xds.any(:cors, %Arion.ControlPlane.Pb.Data.Extensions.CorsPolicy{})
    end

    assert_raise ArgumentError, ~r/unknown resource kind :nope/, fn -> Xds.any(:nope, %{}) end
  end

  test "client states track pushed resources per kind" do
    states =
      Arion.ControlPlane.ClientStates.new()
      |> Arion.ControlPlane.ClientStates.pushed(
        :load_assignment,
        "nonce-1",
        [{"service-a", "7"}],
        false
      )
      |> Arion.ControlPlane.ClientStates.ack("nonce-1")

    assert states.load_assignment["service-a"] == {:ack, "7"}
    assert Map.has_key?(states, :mcp_tool)
    assert Map.has_key?(states, :mcp_dynamic_server)
  end

  test "client states forget a removal the client NACKs" do
    states =
      Arion.ControlPlane.ClientStates.new()
      |> Arion.ControlPlane.ClientStates.pushed(:load_assignment, "1", [{"svc", "7"}], false)
      |> Arion.ControlPlane.ClientStates.ack("1")
      |> Arion.ControlPlane.ClientStates.pushed(:load_assignment, "2", [{"svc", nil}], true)
      |> Arion.ControlPlane.ClientStates.nack("2", "svc No cluster found")

    assert states.load_assignment == %{}
    assert states.pending == %{}
  end

  test "cluster helpers support current discovery and load balancing surfaces" do
    assert Cluster.gen_ports(18_000, 1..3) == [18_001, 18_002, 18_003]

    cluster =
      "service-a"
      |> Cluster.static("127.0.0.1", [8080])
      |> Cluster.lb({:typed, :least_request})
      |> Cluster.put_http_protocol_options(Cluster.http2_options())
      |> Cluster.circuit_breakers([Cluster.threshold(priority: :HIGH, max_requests: 25)])

    assert cluster.cluster_discovery_type == {:type, :STATIC}
    assert cluster.lb_policy == :ROUND_ROBIN
    assert cluster.load_assignment.cluster_name == "service-a"
    assert [threshold] = cluster.circuit_breakers.thresholds
    assert threshold.priority == :HIGH
    assert threshold.max_requests.value == 25

    assert [policy] = cluster.load_balancing_policy.policies
    assert policy.typed_extension_config.typed_config.type_url == Xds.type_url(:lb_least_request)

    override =
      Cluster.new("override")
      |> Cluster.lb({:override_host_header, "x-host", :round_robin})

    assert [policy] = override.load_balancing_policy.policies
    assert policy.typed_extension_config.typed_config.type_url == Xds.type_url(:lb_override_host)

    assert {:typed_config, raw_buffer_any} = Cluster.raw_buffer_socket().config_type
    assert raw_buffer_any.type_url == Xds.type_url(:raw_buffer)

    original_dst = Cluster.original_dst("original")

    assert original_dst.cluster_discovery_type == {:type, :ORIGINAL_DST}
    assert original_dst.lb_policy == :CLUSTER_PROVIDED
    assert {:original_dst_lb_config, _config} = original_dst.lb_config
  end

  test "bind device socket options encode the raw device name" do
    cluster = "bound" |> Cluster.new() |> Cluster.put_bind_device("eth0")
    decoded = cluster |> Protobuf.encode() |> PbCluster.decode()

    assert [%{level: 1, name: 25, value: {:buf_value, "eth0"}}] =
             decoded.upstream_bind_config.socket_options

    listener =
      "bound"
      |> Listener.new(Listener.local_address(8080))
      |> Listener.add_socket_option(Xds.bind_to_device("eth0"))

    decoded = listener |> Protobuf.encode() |> PbListener.decode()
    assert [%{level: 1, name: 25, value: {:buf_value, "eth0"}}] = decoded.socket_options
  end

  test "route, virtual host, and route config helpers compose directly" do
    route =
      "header-route"
      |> Route.new()
      |> Route.match_prefix("/api")
      |> Route.to_cluster_header("x-cluster")
      |> Route.priority(:HIGH)
      |> Route.hash_header("x-user", terminal: true)

    assert route.match.path_specifier == {:prefix, "/api"}
    assert {:route, action} = route.action
    assert action.cluster_specifier == {:cluster_header, "x-cluster"}
    assert action.priority == :HIGH
    assert [%Arion.ControlPlane.Pb.Route.HashPolicy{terminal: true}] = action.hash_policy

    retry_policy = Route.retry_policy("5xx", num_retries: 2)

    route_config =
      "local"
      |> RouteConfig.new()
      |> RouteConfig.most_specific_header_mutations_wins()
      |> RouteConfig.add_virtual_host(
        "app"
        |> VirtualHost.new(["example.com"])
        |> VirtualHost.retry(retry_policy)
        |> VirtualHost.add_route(route)
      )

    assert route_config.most_specific_header_mutations_wins == true
    assert [virtual_host] = route_config.virtual_hosts
    assert virtual_host.retry_policy.retry_on == "5xx"
    assert [^route] = virtual_host.routes

    redirect =
      Route.redirect_action(host: "www.google.com", path_redirect: "/search", port: 443)

    assert redirect.scheme_rewrite_specifier == {:https_redirect, true}
    assert redirect.path_rewrite_specifier == {:path_redirect, "/search"}

    # Refining a route action before choosing a destination is a mistake, not a
    # route to cluster "".
    assert_raise ArgumentError, ~r/no action/, fn -> Route.timeout(Route.new("x"), 1) end

    assert_raise ArgumentError, ~r/redirect action/, fn ->
      "r" |> Route.new() |> Route.redirect() |> Route.prefix_rewrite("/")
    end
  end

  test "retargeting a route or changing its path keeps the settings it does not name" do
    route =
      "r"
      |> Route.new()
      |> Route.match_prefix("/api")
      |> Route.to_cluster("a")
      |> Route.timeout(30)
      |> Route.priority(:HIGH)
      |> Route.hash_header("x-user")

    match = Route.add_header(route.match, Route.header_match(:exists, "x-a"))
    route = route |> Route.put_match(match) |> Route.match_path("/exact")
    retargeted = Route.to_weighted_clusters(route, [{"b", 1}])

    assert {:route, action} = retargeted.action
    assert {:weighted_clusters, %{clusters: [%{name: "b"}]}} = action.cluster_specifier
    assert action.timeout == Xds.duration(30)
    assert action.priority == :HIGH
    assert [_hash] = action.hash_policy
    assert retargeted.match.path_specifier == {:path, "/exact"}
    assert [%{name: "x-a"}] = retargeted.match.headers
    assert retargeted.match.case_sensitive == Xds.bool(true)

    # Explicit replacement and a non-forwarding action start from the defaults.
    replaced = Route.put_action(retargeted, Route.route_action({:cluster, "c"}))

    assert {:route, %{priority: :DEFAULT, hash_policy: [], timeout: %{seconds: 15}}} =
             replaced.action

    redirected = "x" |> Route.new() |> Route.redirect() |> Route.to_cluster("a")

    assert {:route, %{cluster_specifier: {:cluster, "a"}, timeout: %{seconds: 15}}} =
             redirected.action
  end

  test "an HCM's filters end with exactly one router" do
    hcm =
      Hcm.new()
      |> Hcm.put_filters([Cors.filter(), Hcm.router_filter()])
      |> Hcm.add_filter(Cors.filter("second"))

    assert Enum.map(hcm.http_filters, & &1.name) == [
             "envoy.filters.http.cors",
             "second",
             "envoy.filters.http.router"
           ]

    assert_raise ArgumentError, ~r/exactly one router, got 0/, fn ->
      Hcm.put_filters(hcm, [Cors.filter()])
    end

    assert_raise ArgumentError, ~r/exactly one router, got 2/, fn ->
      Hcm.put_filters(hcm, [Hcm.router_filter(), Hcm.router_filter()])
    end

    assert_raise ArgumentError, ~r/router must be the last/, fn ->
      Hcm.put_filters(hcm, [Hcm.router_filter(), Cors.filter()])
    end

    assert_raise ArgumentError, ~r/exactly one router, got 2/, fn ->
      Hcm.add_filter(hcm, Hcm.router_filter())
    end
  end

  test "original destination clusters take the common cluster options" do
    cluster =
      Cluster.original_dst("original",
        connect_timeout: 1,
        use_http_header: true,
        http_header_name: "x-dst"
      )

    assert cluster.connect_timeout == Xds.duration(1)
    assert cluster.cluster_discovery_type == {:type, :ORIGINAL_DST}
    assert cluster.lb_policy == :CLUSTER_PROVIDED

    assert {:original_dst_lb_config, %{use_http_header: true, http_header_name: "x-dst"}} =
             cluster.lb_config
  end

  test "HCM, listener, access log, proxy protocol, and TCP proxy helpers wrap typed configs" do
    route_config = RouteConfig.new("local")
    access_log = AccessLog.stdout(AccessLog.text_format("%REQ(:METHOD)% %RESPONSE_CODE%"))

    hcm =
      Hcm.new(stat_prefix: "ingress")
      |> Hcm.route_config(route_config)
      |> Hcm.add_access_log(access_log)
      |> Hcm.add_filter(Cors.filter())
      |> Hcm.tracing(Hcm.opentelemetry_tracing(Xds.grpc_service(:envoy, "otel"), "demo"))

    assert [cors_filter, router_filter] = hcm.http_filters
    assert {:typed_config, cors_any} = cors_filter.config_type
    assert cors_any.type_url == Xds.type_url(:cors)
    assert {:typed_config, router_any} = router_filter.config_type
    assert router_any.type_url == Xds.type_url(:router)
    assert [%Arion.ControlPlane.Pb.Data.Extensions.AccessLog{}] = hcm.access_log

    chain = FilterChain.new("gateway") |> FilterChain.add_hcm(hcm)

    listener =
      "listener"
      |> Listener.new(Listener.local_address(8080))
      |> Listener.add_filter_chain(chain)
      |> Listener.add_listener_filter(Listener.tls_inspector())
      |> Listener.add_listener_filter(RateLimit.listener_filter("listener-rl", 10, 1, 1))
      |> Listener.add_listener_filter(ProxyProtocol.listener_filter(allow_without_pp: true))

    assert [^chain] = listener.filter_chains

    assert Enum.map(listener.listener_filters, & &1.name) == [
             "envoy.filters.listener.tls_inspector",
             "envoy.filters.listener.local_ratelimit",
             "envoy.filters.listener.proxy_protocol"
           ]

    tcp_proxy = TcpProxy.filter("service-a")
    assert {:typed_config, tcp_any} = tcp_proxy.config_type
    assert tcp_any.type_url == Xds.type_url(:tcp_proxy)
  end

  test "rate limit, RBAC, ext_proc, JWT, and CORS helpers build HTTP and network configs" do
    local_rate_limit = RateLimit.local(5, 1, 1)

    route =
      RateLimit.per_route(
        Route.new("limited"),
        "envoy.filters.http.local_ratelimit",
        local_rate_limit
      )

    assert route.typed_per_filter_config["envoy.filters.http.local_ratelimit"].type_url ==
             Xds.type_url(:local_rate_limit)

    connection_limit = RateLimit.connection_limit_filter("conn-limit", "conn", 10)
    assert {:typed_config, conn_any} = connection_limit.config_type
    assert conn_any.type_url == Xds.type_url(:network_connection_limit)

    network_rate_limit =
      RateLimit.network_rate_limit_filter(
        "net-rl",
        "net",
        Xds.grpc_service(:envoy, "rate-limit"),
        [RateLimit.descriptor([{"path", "/api"}])],
        domain: "demo"
      )

    assert {:typed_config, net_rl_any} = network_rate_limit.config_type
    assert net_rl_any.type_url == Xds.type_url(:network_rate_limit)

    user_rate_limiter =
      RateLimit.user_limiter("x-user", [
        RateLimit.user_limit("alice", {:simple, 10, 1}),
        RateLimit.user_limit("bob", RateLimit.local(2, 1, 1))
      ])

    assert {:typed_config, user_rl_any} =
             RateLimit.user_filter("user-rate-limit", user_rate_limiter).config_type

    assert user_rl_any.type_url == Xds.type_url(:user_rate_limiter)

    rbac =
      :ALLOW
      |> Rbac.rules(%{
        "allow-all" => Rbac.policy([Rbac.any_permission()], [Rbac.any_principal()])
      })

    assert {:typed_config, rbac_any} = Rbac.http_filter("rbac", rbac).config_type
    assert rbac_any.type_url == Xds.type_url(:rbac_http_filter)

    processor =
      Xds.grpc_service(:envoy, "ext-proc")
      |> ExtProc.processor(processing_mode: ExtProc.processing_mode(request_body_mode: :BUFFERED))

    assert {:typed_config, ext_proc_any} = ExtProc.filter("ext-proc", processor).config_type
    assert ext_proc_any.type_url == Xds.type_url(:ext_proc)

    ext_proc_route =
      Route.put_per_filter_config(
        Route.new("ext-proc-route"),
        "envoy.filters.http.ext_proc",
        :ext_proc_per_route,
        ExtProc.per_route_disabled()
      )

    assert ext_proc_route.typed_per_filter_config["envoy.filters.http.ext_proc"].type_url ==
             Xds.type_url(:ext_proc_per_route)

    rbac_route =
      Route.put_per_filter_config(
        Route.new("rbac-route"),
        "envoy.filters.http.rbac",
        :rbac_per_route,
        Rbac.per_route(%Arion.ControlPlane.Pb.Data.Extensions.RBACConfig{})
      )

    assert rbac_route.typed_per_filter_config["envoy.filters.http.rbac"].type_url ==
             Xds.type_url(:rbac_per_route)

    provider =
      Jwt.provider(
        "https://issuer.example",
        Jwt.local_jwks(:inline_string, "{}"),
        from_headers: [Jwt.from_header("authorization", "Bearer ")]
      )

    authn =
      Jwt.authentication(
        %{
          "main" => provider
        },
        [
          Jwt.rule(Route.match_prefix("/"), Jwt.requires_provider("main"))
        ]
      )

    assert {:typed_config, jwt_any} = Jwt.filter("jwt", authn).config_type
    assert jwt_any.type_url == Xds.type_url(:jwt_authn)

    cors_route = Cors.per_route(Route.new("cors"), "envoy.filters.http.cors", Cors.policy())

    assert cors_route.typed_per_filter_config["envoy.filters.http.cors"].type_url ==
             Xds.type_url(:cors_policy)
  end

  test "MCP gateway helpers cover inline resources, TDS resources, RBAC, and search" do
    rbac = McpGateway.rbac(:ALLOW, [McpGateway.jwt_claim("sub", "demo")])

    tool =
      McpGateway.tool(
        "docs",
        "search",
        "Search documents",
        McpGateway.rest_backend("search-api", "POST", "/search",
          query_params: [{"q", "input.query"}],
          body_template: ~s({"query":"{{input.query}}"}),
          upstream_policy: McpGateway.upstream_policy(authority: "search.internal", timeout: 5)
        ),
        rbac: rbac,
        embedding: [0.1, 0.2],
        disclosure: :eager
      )

    mcp_server_tool =
      McpGateway.tool(
        "docs",
        "remote",
        "Remote documentation server",
        McpGateway.mcp_server_backend("https://docs.example/mcp")
      )

    dynamic_server =
      McpGateway.dynamic_server("ops", "Operations MCP", "https://ops.example/mcp",
        cache_duration: 30,
        rbac: McpGateway.rbac(:DENY, [McpGateway.jwt_header("role", "guest")]),
        tool_disclosure: :eager
      )

    open_api_source =
      McpGateway.open_api_source("billing", "billing-api", ~s({"openapi":"3.0.0"}),
        path_prefix: "/v1",
        skip_unsupported_operations: true,
        include_operations: ["listInvoices"]
      )

    gateway =
      McpGateway.gateway("demo-gateway",
        version: "1.2.3",
        tools: [tool, mcp_server_tool],
        dynamic_servers: [dynamic_server],
        open_api_sources: [open_api_source],
        tds: McpGateway.tds("gateway"),
        upstream_timeout: 15,
        max_upstream_response_bytes: 1_048_576,
        search:
          McpGateway.tool_search(
            max_allowable_results: 3,
            embeddings: McpGateway.remote_embeddings("embeddings", "bge-small", 384)
          )
      )

    assert {:typed_config, any} = McpGateway.filter("mcp", gateway).config_type
    assert any.type_url == Xds.type_url(:mcp_gateway)
    assert gateway.server_info.version == "1.2.3"
    assert gateway.search.max_allowable_results == 3
    assert gateway.search.embeddings.dimensions == 384
    assert gateway.tds.config_name == "gateway"
    assert gateway.mode == McpGateway.tools_mode()
    assert tool.disclosure_mode == :EAGER
    assert mcp_server_tool.disclosure_mode == :PROGRESSIVE
    assert McpGateway.qualified_name(tool) == "docs.search"

    assert {:rest_backend, rest} = tool.upstream_backend
    assert {:body_template, _} = rest.body
    assert rest.upstream_policy.authority == "search.internal"

    assert McpGateway.resource_id("demo-gateway", "gateway", "docs.search") ==
             "demo-gateway/gateway/docs.search"

    assert {"demo-gateway/gateway/docs.search", ^tool} =
             McpGateway.tool_resource("demo-gateway", "gateway", tool)

    assert {"demo-gateway/gateway/ops", ^dynamic_server} =
             McpGateway.dynamic_server_resource("demo-gateway", "gateway", dynamic_server)

    assert {"demo-gateway/gateway/billing", ^open_api_source} =
             McpGateway.open_api_source_resource("demo-gateway", "gateway", open_api_source)
  end

  test "MCP code mode helpers build toolkits and a code mode gateway" do
    toolkit =
      McpGateway.toolkit(
        "billing-dispute",
        "Resolve a duplicate charge for a customer.",
        "Look up the customer first, then scan transactions before issuing a refund.",
        [{"crm", "lookup_customer"}, {"payments", "issue_refund"}]
      )

    gateway =
      McpGateway.gateway("code-gateway",
        mode:
          McpGateway.code_mode(toolkits: [toolkit], execution_timeout: 20, max_host_calls: 50),
        search: McpGateway.tool_search(max_allowable_results: 8)
      )

    assert gateway.search.max_allowable_results == 8
    assert {:code_mode, code_mode} = gateway.mode
    assert code_mode.execution_timeout.seconds == 20
    assert code_mode.max_host_calls == 50
    assert [%{name: "billing-dispute", tools: refs}] = code_mode.toolkits
    assert Enum.map(refs, & &1.namespace) == ["crm", "payments"]

    assert {"code-gateway/gateway/billing-dispute", ^toolkit} =
             McpGateway.toolkit_resource("code-gateway", "gateway", toolkit)
  end

  test "TLS and secret helpers build transport sockets and SDS secrets" do
    chain = Secret.data_source(:inline_string, "CERT")
    key = Secret.data_source(:inline_string, "KEY")
    certificate = Tls.certificate(chain, key)
    secret = Secret.tls_certificate("server-cert", certificate)

    assert secret.type == {:tls_certificate, certificate}

    upstream_socket = Tls.upstream_sds_validation("validation", sni: "example.com")
    downstream_socket = Tls.downstream_sds_certificate("server-cert", alpn_protocols: ["h2"])

    assert {:typed_config, upstream_any} = upstream_socket.config_type
    assert upstream_any.type_url == Xds.type_url(:upstream_tls_context)
    assert {:typed_config, downstream_any} = downstream_socket.config_type
    assert downstream_any.type_url == Xds.type_url(:downstream_tls_context)
  end

  test "accept-untrusted upstream TLS carries one parseable CA on Envoy's field numbers" do
    socket = Tls.upstream_accept_untrusted("epp.ns.svc.cluster.local")
    assert {:typed_config, any} = socket.config_type
    context = UpstreamTlsContext.decode(any.value)
    assert context.sni == "epp.ns.svc.cluster.local"
    assert {:validation_context, validation} = context.common_tls_context.validation_context_type
    assert validation.trust_chain_verification == :ACCEPT_UNTRUSTED
    assert {:inline_string, pem} = validation.trusted_ca.specifier
    assert [{:Certificate, der, :not_encrypted}] = :public_key.pem_decode(pem)
    assert {:OTPCertificate, _, _, _} = :public_key.pkix_decode_cert(der, :otp)

    assert Protobuf.encode(%CertificateValidationContext{
             trust_chain_verification: :ACCEPT_UNTRUSTED
           }) == <<0x50, 0x01>>
  end

  test "ext_proc metadata forwarding namespaces encode on Envoy's field numbers" do
    options = ExtProc.metadata_options(forwarding_untyped: ["envoy.lb"])

    assert Protobuf.encode(ExtProc.processor(nil, metadata_options: options)) ==
             <<0x82, 0x01, 0x0C, 0x0A, 0x0A, 0x0A, 0x08, "envoy.lb">>
  end
end

defmodule Arion.ControlPlane.FleetTest do
  use ExUnit.Case

  @moduletag :capture_log

  alias Arion.ControlPlane.Helpers.{Cluster, Endpoint}
  alias Arion.ControlPlane.Pb.Data.Extensions.Secret
  alias Arion.ControlPlane.Pb.Endpoint.ClusterLoadAssignment
  alias Arion.ControlPlane.Pb.Listener.Listener
  alias Arion.ControlPlane.Pb.Route.RouteConfiguration
  alias Arion.ControlPlane.ResourceCache
  alias Arion.ControlPlane.Service
  alias Arion.ControlPlane.Xds.ResourceTypes

  setup do
    start_supervised!({Arion.ControlPlane, serve?: false})
    :ok
  end

  defp cluster(name), do: Cluster.static(name, "127.0.0.1", [1234])

  defp wire(kind, resource), do: ResourceCache.entry(kind, resource).wire

  defp version(kind, resource), do: wire(kind, resource).version

  # self() stands in for the subscribing StreamHandler.
  defp subscribe(fleet, kind, initial_versions \\ %{}),
    do: Service.subscribe(self(), fleet, ResourceTypes.type_url!(kind), initial_versions)

  test "resources pushed to one fleet are isolated from another" do
    a = cluster("cluster-a")
    b = cluster("cluster-b")

    Service.push("fleet-a", :cluster, a)
    Service.push("fleet-b", :cluster, b)

    assert %{cluster: %{"cluster-a" => ^a}} = Service.resources("fleet-a")
    assert %{cluster: %{"cluster-b" => ^b}} = Service.resources("fleet-b")
  end

  test "push without a fleet targets the default \"arion\" fleet" do
    assert "arion" == Service.default_fleet()

    c = cluster("cluster-default")
    Service.push(:cluster, c)

    assert %{cluster: %{"cluster-default" => ^c}} = Service.resources()
  end

  test "a malformed push, replace or drop raises in the caller and leaves the fleet as it was" do
    ok = cluster("ok")
    Service.push("fleet-a", :cluster, ok)
    pid = Service.ensure("fleet-a")
    before = Service.resources("fleet-a")

    assert_raise ArgumentError, fn -> Service.push("fleet-a", :cluster, %{}) end
    assert_raise ArgumentError, fn -> Service.push("fleet-a", :tcp_proxy, ok) end
    assert_raise ArgumentError, fn -> Service.push("fleet-a", :listener, ok) end
    assert_raise ArgumentError, fn -> Service.push("fleet-a", :cluster, cluster("")) end

    assert_raise ArgumentError, fn ->
      Service.replace("fleet-a", cluster: cluster("b"), listener: ok)
    end

    assert_raise ArgumentError, fn -> Service.drop("fleet-a", :tcp_proxy, "ok") end
    assert_raise FunctionClauseError, fn -> Service.drop("fleet-a", :cluster, "") end

    assert Service.ensure("fleet-a") == pid
    assert Service.resources("fleet-a") == before

    # Rejected input does not start a fleet either.
    assert_raise ArgumentError, fn -> Service.push("fleet-b", :cluster, %{}) end
    assert_raise ArgumentError, fn -> Service.drop("fleet-b", :tcp_proxy, "x") end
    assert Service.list_fleets() == ["fleet-a"]
  end

  test "a subscriber only receives resources from its own fleet" do
    a = cluster("cluster-a")
    b = cluster("cluster-b")

    Service.push("fleet-a", :cluster, a)
    subscribe("fleet-a", :cluster)
    assert_receive {:"$gen_cast", {:publish, :cluster, [_]}}

    Service.push("fleet-a", :cluster, cluster("cluster-c"))
    assert_receive {:"$gen_cast", {:publish, :cluster, [_]}}

    Service.push("fleet-b", :cluster, b)
    refute_receive {:"$gen_cast", {:publish, :cluster, _}}
  end

  test "subscribing replays resources already cached for that fleet, as wire resources" do
    a = cluster("cluster-a")
    wire = wire(:cluster, a)

    Service.push("fleet-a", :cluster, a)
    subscribe("fleet-a", :cluster)

    assert_receive {:"$gen_cast", {:publish, :cluster, [^wire]}}
  end

  test "a fleet that has nothing published yet refuses subscriptions" do
    subscribe("fleet-a", :cluster)
    assert_receive {:"$gen_cast", {:unavailable, _message}}
    refute_receive {:"$gen_cast", {:unpublish, _, _}}

    :ok = Service.replace("fleet-a", [])
    subscribe("fleet-a", :cluster, %{"stale" => "1"})
    assert_receive {:"$gen_cast", {:unpublish, :cluster, ["stale"]}}
  end

  test "a repeated subscription on one stream sends nothing" do
    Service.push("fleet-a", :cluster, cluster("cluster-a"))
    subscribe("fleet-a", :cluster)
    assert_receive {:"$gen_cast", {:publish, :cluster, [_]}}

    subscribe("fleet-a", :cluster)
    refute_receive {:"$gen_cast", _}
  end

  test "a subscription to an unsupported type is ignored" do
    Service.push("fleet-a", :cluster, cluster("cluster-a"))
    Service.subscribe(self(), "fleet-a", ResourceTypes.type_url!(:tcp_proxy), %{})
    Service.subscribe(self(), "fleet-a", "type.googleapis.com/unknown.Type", %{})
    refute_receive {:"$gen_cast", _}
  end

  test "reconnect with initial_resource_versions sends only deltas" do
    current = %RouteConfiguration{name: "current"}
    changed = %RouteConfiguration{name: "changed"}
    :ok = Service.replace("fleet-a", route: current, route: changed)

    initial = %{"current" => version(:route, current), "changed" => "stale", "gone" => "whatever"}
    subscribe("fleet-a", :route, initial)

    changed_wire = wire(:route, changed)
    current_version = version(:route, current)
    assert_receive {:"$gen_cast", {:publish, :route, [^changed_wire]}}
    assert_receive {:"$gen_cast", {:seed_acks, :route, [{"current", ^current_version}]}}
    assert_receive {:"$gen_cast", {:unpublish, :route, ["gone"]}}
    refute_receive {:"$gen_cast", _}
  end

  test "list_fleets reflects the running fleets" do
    Service.push("fleet-a", :cluster, cluster("cluster-a"))
    Service.push("fleet-b", :cluster, cluster("cluster-b"))

    assert Enum.sort(Service.list_fleets()) == ["fleet-a", "fleet-b"]
  end

  test "resources and acks of a fleet that is not running are empty, and start nothing" do
    assert Service.resources("absent") == ResourceCache.resources(ResourceCache.new())
    assert Service.acks("absent") == %{}
    assert Service.list_fleets() == []
  end

  test "retire stops an idle fleet, which is not restarted" do
    Service.push("fleet-a", :cluster, cluster("cluster-a"))
    pid = Service.ensure("fleet-a")
    ref = Process.monitor(pid)

    assert Service.retire("fleet-a") == :stopped
    assert Service.list_fleets() == []
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    assert eventually(fn ->
             DynamicSupervisor.which_children(Arion.ControlPlane.FleetSupervisor) == []
           end)
  end

  test "retire never starts a fleet" do
    assert Service.retire("absent") == :stopped
    assert Service.list_fleets() == []
  end

  test "retire empties a subscribed fleet, which stops once its last subscriber leaves" do
    test = self()

    subscriber =
      spawn(fn ->
        Service.subscribe(self(), "fleet-a", ResourceTypes.type_url!(:cluster), %{})
        send(test, :subscribed)

        receive do: ({:"$gen_cast", {:unpublish, :cluster, names}} ->
                       send(test, {:removed, names}))

        Process.sleep(:infinity)
      end)

    :ok = Service.replace("fleet-a", cluster: cluster("cluster-a"))
    assert_receive :subscribed

    assert Service.retire("fleet-a") == :kept
    assert_receive {:removed, ["cluster-a"]}
    assert Service.list_fleets() == ["fleet-a"]

    Process.exit(subscriber, :kill)
    assert eventually(fn -> Service.list_fleets() == [] end)
  end

  test "a subscribe racing retire either keeps the fleet or sees it go down" do
    :ok = Service.replace("fleet-a", [])
    subscribe = {:subscribe, self(), ResourceTypes.type_url!(:cluster), %{}}

    # Queued behind retire, the subscribe is dropped and its monitoring handler sees DOWN.
    pid = Service.ensure("fleet-a")
    ref = Process.monitor(pid)
    :sys.suspend(pid)
    retire = Task.async(fn -> Service.retire("fleet-a") end)
    assert eventually(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 1} end)
    GenServer.cast(pid, subscribe)
    :sys.resume(pid)
    assert Task.await(retire) == :stopped
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Service.ensure("fleet-a") != pid

    # Queued ahead of retire, the subscribe keeps the fleet.
    :ok = Service.replace("fleet-a", [])
    pid = Service.ensure("fleet-a")
    :sys.suspend(pid)
    GenServer.cast(pid, subscribe)
    retire = Task.async(fn -> Service.retire("fleet-a") end)
    assert eventually(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 2} end)
    :sys.resume(pid)
    assert Task.await(retire) == :kept
  end

  test "a crashed fleet is restarted empty and unpublished" do
    Service.push("fleet-a", :cluster, cluster("cluster-a"))
    pid = Service.ensure("fleet-a")
    Process.exit(pid, :kill)

    assert eventually(fn -> Service.ensure("fleet-a") != pid end)
    assert Service.resources("fleet-a").cluster == %{}

    subscribe("fleet-a", :cluster, %{"cluster-a" => "whatever"})
    assert_receive {:"$gen_cast", {:unavailable, _}}
    refute_receive {:"$gen_cast", {:unpublish, _, _}}
  end

  test "replace publishes in dependency order, then removes in reverse order" do
    order = [:secret, :cluster, :load_assignment, :listener, :route]
    :ok = Service.replace("fleet-a", [])
    Enum.each(order, &subscribe("fleet-a", &1))

    old = resources("old")
    :ok = Service.replace("fleet-a", old)
    assert casts() == Enum.map(order, &{:publish, &1, [wire(&1, old[&1])]})

    new = resources("new")
    :ok = Service.replace("fleet-a", new)

    assert casts() ==
             Enum.map(order, &{:publish, &1, [wire(&1, new[&1])]}) ++
               Enum.map(Enum.reverse(order), &{:unpublish, &1, ["old"]})
  end

  test "replace batches the removals of a kind into one response" do
    :ok = Service.replace("fleet-a", cluster: cluster("a"), cluster: cluster("b"))
    subscribe("fleet-a", :cluster)
    assert_receive {:"$gen_cast", {:publish, :cluster, [_, _]}}

    :ok = Service.replace("fleet-a", [])
    assert [{:unpublish, :cluster, names}] = casts()
    assert Enum.sort(names) == ["a", "b"]
  end

  test "replace republishes changed content under the same name and skips unchanged content" do
    v1 = Cluster.static("same", "127.0.0.1", [1])
    v2 = Cluster.static("same", "127.0.0.1", [2])
    :ok = Service.replace("fleet-a", cluster: v1)
    subscribe("fleet-a", :cluster)
    assert_receive {:"$gen_cast", {:publish, :cluster, [_]}}

    :ok = Service.replace("fleet-a", cluster: v2)
    :ok = Service.replace("fleet-a", cluster: v2)

    assert casts() == [{:publish, :cluster, [wire(:cluster, v2)]}]
  end

  test "a republished cluster is followed by its load assignment" do
    eds = Cluster.new("svc", discovery: :eds)
    h2 = Cluster.put_http_protocol_options(eds, Cluster.http2_options())
    a1 = Endpoint.assignment("svc", "10.0.0.1", [8080])
    a2 = Endpoint.assignment("svc", "10.0.0.2", [8080])

    :ok = Service.replace("fleet-a", cluster: eds, load_assignment: a1)
    for kind <- [:cluster, :load_assignment], do: subscribe("fleet-a", kind)

    assert casts() == [
             {:publish, :cluster, [wire(:cluster, eds)]},
             {:publish, :load_assignment, [wire(:load_assignment, a1)]}
           ]

    :ok = Service.replace("fleet-a", cluster: h2, load_assignment: a1)

    assert casts() == [
             {:publish, :cluster, [wire(:cluster, h2)]},
             {:publish, :load_assignment, [wire(:load_assignment, a1)]}
           ]

    :ok = Service.replace("fleet-a", cluster: eds, load_assignment: a2)

    assert casts() == [
             {:publish, :cluster, [wire(:cluster, eds)]},
             {:publish, :load_assignment, [wire(:load_assignment, a2)]}
           ]

    :ok = Service.replace("fleet-a", cluster: eds, load_assignment: a2)
    assert casts() == []

    Service.push("fleet-a", :cluster, h2)
    h2_wire = wire(:cluster, h2)
    a2_wire = wire(:load_assignment, a2)
    assert_receive {:"$gen_cast", {:publish, :cluster, [^h2_wire]}}
    assert_receive {:"$gen_cast", {:publish, :load_assignment, [^a2_wire]}}

    :ok = Service.replace("fleet-a", cluster: eds)

    assert casts() == [
             {:publish, :cluster, [wire(:cluster, eds)]},
             {:unpublish, :load_assignment, ["svc"]}
           ]
  end

  test "a republished named cluster is followed by its named load assignment" do
    cluster = Cluster.new("svc", discovery: :eds)
    eds = {"svc", cluster}
    h2 = {"svc", Cluster.put_http_protocol_options(cluster, Cluster.http2_options())}
    assignment = {"svc", Endpoint.assignment("svc", "10.0.0.1", [8080])}

    :ok = Service.replace("fleet-a", cluster: eds, load_assignment: assignment)
    for kind <- [:cluster, :load_assignment], do: subscribe("fleet-a", kind)

    assert casts() == [
             {:publish, :cluster, [wire(:cluster, eds)]},
             {:publish, :load_assignment, [wire(:load_assignment, assignment)]}
           ]

    :ok = Service.replace("fleet-a", cluster: h2, load_assignment: assignment)

    assert casts() == [
             {:publish, :cluster, [wire(:cluster, h2)]},
             {:publish, :load_assignment, [wire(:load_assignment, assignment)]}
           ]
  end

  test "a reconnect replays load assignments after the clusters, even when current" do
    cluster = Cluster.new("svc", discovery: :eds)
    assignment = Endpoint.assignment("svc", "10.0.0.1", [8080])
    :ok = Service.replace("fleet-a", cluster: cluster, load_assignment: assignment)

    subscribe("fleet-a", :cluster, %{"svc" => "stale"})
    subscribe("fleet-a", :load_assignment, %{"svc" => version(:load_assignment, assignment)})

    assert casts() == [
             {:publish, :cluster, [wire(:cluster, cluster)]},
             {:publish, :load_assignment, [wire(:load_assignment, assignment)]}
           ]
  end

  # Listed in reverse dependency order so that replace has to sort them.
  defp resources(name) do
    [
      route: %RouteConfiguration{name: name},
      listener: %Listener{name: name},
      load_assignment: %ClusterLoadAssignment{cluster_name: name},
      cluster: cluster(name),
      secret: %Secret{name: name}
    ]
  end

  defp casts do
    receive do
      {:"$gen_cast", message} -> [message | casts()]
    after
      50 -> []
    end
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(check, attempts - 1)
    end
  end
end
