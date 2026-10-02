# Configuration reference

[Documentation index](README.md) · [Architecture](architecture.md) ·
[Standalone commands](../apps/arion_ctl/README.md#commands)

This reference describes Arion resources delivered over xDS, their configuration
format in the standalone service, and the resource model exposed by the Elixir
library. Kubernetes users configure the
[controller](../apps/arion_k8s_controller/README.md) through Gateway API and
Arion-specific parameters instead.

## Native resource documents

A configuration file can contain YAML resource definitions separated by `---`,
or a JSON array of resource definitions. Each definition has this envelope:

```yaml
apiVersion: ctl.arion.io/v1alpha1
kind: Cluster
metadata:
  name: backend
  fleet: arion
spec:
  type: STATIC
  connectTimeout: 1s
  loadAssignment:
    clusterName: backend
    endpoints:
      - lbEndpoints:
          - endpoint:
              address:
                socketAddress: {address: 127.0.0.1, portValue: 18081}
```

This creates an upstream Cluster; combine it with a Listener as in
[the complete HTTP example](examples/http.yaml) to receive traffic.
The outer fields identify the resource's kind, name, and fleet. The `spec`
contains its protobuf configuration, which the control plane encodes and sends
to Arion over xDS.

| Field | Rule |
| --- | --- |
| `apiVersion` | Exactly `ctl.arion.io/v1alpha1` |
| `kind` | One of the case-sensitive names below |
| `metadata.name` | Nonempty resource identity |
| `metadata.fleet` | Nonempty fleet name; defaults to `arion` |
| `spec` | Object using the supported protobuf JSON shape for that kind |

Unknown envelope/metadata fields are rejected. Labels, annotations, and arbitrary
application metadata are not accepted in this native format. The complete input
must contain unique `{fleet, kind, name}` identities.

For core resources, the decoder sets the resource's own name (`name`, or
`clusterName` for a `ClusterLoadAssignment`) from `metadata.name`; an explicit
one must agree. MCP resource identities have separate meaning from a tool name
or namespace within the payload.

## Resource kinds and relationships

| Resource kind | Library kind | Relationship |
| --- | --- | --- |
| `Listener` | `:listener` | Binds an address; contains network filters and optional TLS transport |
| `RouteConfiguration` | `:route` | Named routes referenced by a listener's RDS settings |
| `Cluster` | `:cluster` | Upstream service named by route actions |
| `ClusterLoadAssignment` | `:load_assignment` | Endpoints for the Cluster with the matching assignment name |
| `Secret` | `:secret` | Certificate/key or validation context referenced by TLS settings |
| `McpTool` | `:mcp_tool` | Arion MCP tool resource |
| `McpDynamicServer` | `:mcp_dynamic_server` | Arion MCP upstream discovery resource |
| `McpToolkit` | `:mcp_toolkit` | Arion MCP toolkit resource |
| `McpOpenApiSource` | `:mcp_openapi_source` | Arion MCP OpenAPI tool source |

The final four kinds are recognized by the decoder; see the current
[compatibility limits](#validation-and-compatibility) before using them with a proxy.

An inline `routeConfig` belongs to its Listener and is replaced with that
Listener. A separate RouteConfiguration is referenced by
`rds.routeConfigName`. Similarly, a STATIC Cluster includes a `loadAssignment`;
an EDS Cluster uses separate ClusterLoadAssignment updates.
The [independent discovery recipe](recipes.md#1-update-routes-and-endpoints-independently)
demonstrates the supported combination.

## Protobuf field conventions

Within `spec`, snake_case and protobuf JSON camelCase field names are accepted,
such as `connect_timeout` and `connectTimeout`. Supplying both spellings of the
same field is rejected. Examples use camelCase consistently.

Enums use their protobuf names, such as `STATIC`, `EDS`, and `HTTP1`.
Durations use protobuf JSON strings such as `1s` or `0.250s`.
Repeated fields are lists, protobuf maps are objects, and protobuf `bytes`
values use base64. An `inlineString` data source contains literal text;
`inlineBytes` contains base64-encoded bytes.

Alternative fields in a protobuf `oneof` are mutually exclusive. For example,
a route chooses a forwarding action or a direct response, and a TLS Secret
chooses a certificate or validation context.

Only fields represented in the checked-in
[proto definitions](../apps/arion_control_plane/proto) are accepted. Referencing
the full Envoy API does not add missing fields to this decoder.

## Nested extension messages: Any and type URLs

Filters and transport sockets contain protobuf `Any` messages. The decoder needs
an explicit `@type` URL to know how to decode their fields:

```yaml
httpFilters:
  - name: envoy.filters.http.router
    typedConfig:
      '@type': type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

Use the full wire type URL, including the `type.googleapis.com/` prefix. The
Elixir module name and the simplified local proto package are not wire type URLs.

The [type registry](../apps/arion_control_plane/lib/arion_control_plane/xds/resource_types.ex) lists accepted nested
message kinds; [Xds](../apps/arion_control_plane/lib/arion_control_plane/helpers/xds.ex)
maps them to wire URLs. Unknown URLs and missing `@type` fields are rejected.
A resource definition cannot load arbitrary extensions just by naming a URL.

## Elixir resource helpers

The library accepts protobuf values. `Arion.Ctl` accepts resource definitions
expressed as YAML or Elixir maps, and helper-built protobuf values through
`Arion.Ctl.apply_resources/2`, which saves them as resource definitions.
The helpers create protobuf values and compose nested messages for embedded use.
Start with the [complete embedded example](../apps/arion_control_plane/README.md#complete-http-example).

| Helpers | Configuration represented |
| --- | --- |
| `Cluster`, `Endpoint` | Static/DNS/EDS/original-destination clusters, endpoints, load balancing, connection and upstream settings |
| `Listener`, `FilterChain`, `Hcm` | Incoming sockets, filter chains, HTTP connection management, inline routes/RDS, filter order |
| `RouteConfig`, `VirtualHost`, `Route` | Host/path/header/query matching, forwarding, weighted backends, redirects, rewrites, timeouts, retries |
| `Tls`, `Secret` | Downstream/upstream TLS, certificates, validation contexts, Secret references |
| `TcpProxy`, `ProxyProtocol` | Stream forwarding and PROXY protocol settings |
| `Jwt`, `Rbac`, `Cors` | Authentication, authorization, and cross-origin policy messages |
| `RateLimit` | HTTP/listener/network rate-limit and connection-limit messages |
| `ExtProc` | External processing filter and per-route configuration |
| `AccessLog`, `Hcm` | Logging and tracing messages |
| `McpGateway` | Arion MCP gateway, tool, and related extension messages |
| `Xds` | Type URLs and wrapping messages into `Any` / typed configuration |

The [helper sources](../apps/arion_control_plane/lib/arion_control_plane/helpers)
are the function-level reference: each module documents its inputs, duration
units, nil handling and ordering. This is a catalog of available builders forming
a DSL to make it nicer to work programatically with configurations.

### Helper vocabulary

Helpers are plain functions over immutable protobuf values. Their names say
what happens to the value:

| Name | Meaning |
| --- | --- |
| `new/…`, `match_prefix/1`, `route_action/1` | Constructors with documented defaults |
| `add_*` | Appends one item to an ordered collection, in call order |
| `put_*` | Replaces a whole field: a list (`put_filters`, `put_routes`), a match, an action, or one key of a keyed map (`put_per_filter_config`) |
| `to_cluster`, `timeout`, `retry`, `lb`, … | Refines one setting of the value, leaving the rest as it is |

Destination helpers (`Route.to_cluster/2`, `to_cluster_header/2`,
`to_weighted_clusters/2`) change only the destination of an existing forwarding
action; a route with no action, a redirect or a direct response gets a new
forwarding action with the `Route.route_action/1` defaults. Route-level path
setters (`Route.match_path/2` and friends) change only the path of the existing
match. `Hcm.put_filters/2` requires a list ending with exactly one router;
`Hcm.add_filter/2` inserts before it.

Retargeting a route keeps its policy, and a filter sequence composes without
breaking the router invariant:

```elixir
alias Arion.ControlPlane.Helpers.{Cors, Hcm, Jwt, Route}

api =
  Route.new("api")
  |> Route.match_path_separated_prefix("/api")
  |> Route.to_cluster("v1")
  |> Route.timeout(30)
  |> Route.retry(Route.retry_policy("5xx", num_retries: 2))

# Same timeout and retries, new destination and path.
canary = api |> Route.to_weighted_clusters([{"v1", 90}, {"v2", 10}]) |> Route.match_prefix("/")

hcm =
  Hcm.new()
  |> Hcm.add_filter(Jwt.filter("jwt", authn))
  |> Hcm.add_filter(Cors.filter())
  # => [jwt, cors, router]; the router stays last.
```

Names before the vocabulary was standardized map as follows; the old names
are gone, and the new ones keep their behavior unless noted.

| Old | New |
| --- | --- |
| `Route.header/2`, `Route.query/2` (on a match) | `Route.add_header/2`, `Route.add_query/2` |
| `Route.request_header/2`, `Route.response_header/2` (also on `VirtualHost`, `RouteConfig`) | `add_request_header/2`, `add_response_header/2` |
| `Route.per_filter_config/4` | `Route.put_per_filter_config/4` |
| `Route.to_cluster/2` and other destinations | Same name; now keep the existing action's other settings |
| `Route.match_prefix/2` and other path setters | Same name; now keep the existing match's headers and queries |
| `VirtualHost.route/2`, `VirtualHost.routes/2` | `VirtualHost.add_route/2`, `VirtualHost.put_routes/2` |
| `RouteConfig.virtual_host/2`, `RouteConfig.virtual_hosts/2` | `RouteConfig.add_virtual_host/2`, `RouteConfig.put_virtual_hosts/2` |
| `Hcm.filter/2`, `Hcm.access_log/2`, `Hcm.upgrade/3` | `Hcm.add_filter/2`, `Hcm.add_access_log/2`, `Hcm.add_upgrade/3` |
| `Hcm.put_filters/2` | Same name; now rejects a list without exactly one terminal router |
| `Hcm.http_filter/3` | `Xds.http_filter/3` |
| `FilterChain.filter/2`, `FilterChain.hcm/3` | `FilterChain.add_filter/2`, `FilterChain.add_hcm/3` |
| `FilterChain.match/2`, `FilterChain.transport_socket/2` | `FilterChain.put_match/2`, `FilterChain.put_transport_socket/2` |
| `Listener.filter_chain/2`, `Listener.listener_filter/2`, `Listener.socket_option/2` | `Listener.add_filter_chain/2`, `Listener.add_listener_filter/2`, `Listener.add_socket_option/2` |
| `Cluster.endpoint/2,3` | `Cluster.add_endpoint/2,3` |
| `Cluster.health_check/2` | `Cluster.add_health_check/2`; appends instead of replacing the list |
| `Cluster.original_dst/2` | Same name; now honors the common options such as `:connect_timeout` |
| `McpGateway.put_tool/2`, `put_dynamic_server/2`, `put_open_api_source/2`, `put_toolkit/2` | `add_tool/2`, `add_dynamic_server/2`, `add_open_api_source/2`, `add_toolkit/2`; one item each, lists go to `gateway/2` or `code_mode/1` | 

## Validation and compatibility

Validation decodes all input documents and forces protobuf encoding before
committing them. It catches unknown fields/types, duplicate identities, duplicate
field spellings, conflicting oneof values, and resource-name disagreements.

It does not resolve every resource reference, verify a backend is reachable,
validate all proxy semantics, or guarantee compatibility with the proxy binary.
A saved resource can still be NACKed. Configuration persists even when a proxy
rejects it; correct and reapply the resource.

## Exporting configuration

`arionctl get` prints saved Arion resource definitions as a JSON array.
`validate -f` and `apply -f` accept that array directly. YAML document streams
remain supported.

From an operator terminal with the release environment set as in the
[standalone README](../apps/arion_ctl/README.md#build-and-start):

```sh
export ARION_DOCS_EXPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arionctl-export.XXXXXX")"
(
  umask 077
  arionctl get --fleet arion > "$ARION_DOCS_EXPORT_DIR/resources.json"
)
arionctl validate -f "$ARION_DOCS_EXPORT_DIR/resources.json"
arionctl apply -f "$ARION_DOCS_EXPORT_DIR/resources.json"
```

The private temporary directory keeps exports containing TLS material separate
from other files. An empty fleet produces `[]` and needs no apply operation.
Remove the export directory when it is no longer needed.

Inside IEx, an already decoded list can be passed directly to `Arion.Ctl.apply/1`.
Apply merges; importing an export will not delete other existing identities.
For an exact standalone recovery, restore the protected snapshot while the
service is stopped, as described in the [app README](../apps/arion_ctl/README.md#apply-persistence-and-failure-behavior).
