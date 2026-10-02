# Arion.ControlPlane

[Project overview](../../README.md) · [Architecture](../../docs/architecture.md) ·
[Configuration reference](../../docs/configuration-reference.md)

This library serves configuration to Arion proxies over delta xDS/ADS. Embed it
when your Elixir application should decide what configuration exists. It supplies
fleet caches, discovery streams, protobuf modules, and resource-building helpers.

Loading the dependency does not start a server or bind a port. Your application
starts the supervision tree and owns the source of desired state.

## Install and supervise

For a local checkout, add a dependency to your application's `mix.exs`:

```elixir
{:arion_control_plane,
 path: "/absolute/path/to/arion-ctl/apps/arion_control_plane"}
```

After a corresponding Git tag is actually published, a consumer can instead use:

```elixir
{:arion_control_plane,
 git: "https://github.com/arion-gateway/arion-ctl.git",
 tag: "v0.1.0", subdir: "apps/arion_control_plane"}
```

The library declares Elixir `~> 1.17`; the documentation examples were checked
with Elixir 1.20 / Erlang/OTP 29, also used by the standalone/controller apps.

Add the control plane to your application's children:

```elixir
children = [
  {Arion.ControlPlane, port: 50051}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

There is one control-plane tree per Erlang VM, containing many fleets. A fleet is
the resource set a proxy selects with its `node.cluster`.

When restoring saved configuration, start with `serve?: false`, publish the
restored resources, then call `Arion.ControlPlane.serve(port: 50051)`.
This keeps reconnecting proxies from receiving an empty view during restoration.
Arrange the same restoration sequence after a control-plane restart.
`server_child/1` exposes the server child specification for callers managing
that lifecycle themselves.

## Complete HTTP example

Use the backend and proxy setup from the
[standalone walkthrough](../../docs/standalone-walkthrough.md), but run this
embedded application in place of its standalone service. The backend remains on
18081, ADS on 15051, and proxy HTTP on 18080.

From the repository root, start the backend in one terminal:

```sh
python3 docs/examples/backend.py --port 18081 --name backend-a
```

In another terminal, run the complete example in this app:

```sh
cd apps/arion_control_plane
mix deps.get
iex -S mix
```

At the IEx prompt, load the script into the live session:

```elixir
Code.require_file("../../docs/examples/embedded.exs")
```

The [script](../../docs/examples/embedded.exs) contains:

```elixir
alias Arion.ControlPlane.Service

alias Arion.ControlPlane.Helpers.{
  Cluster,
  FilterChain,
  Hcm,
  Listener,
  Route,
  RouteConfig,
  VirtualHost
}

# These variables configure this example only.
ads_port = String.to_integer(System.get_env("ARION_DOCS_ADS_PORT", "15051"))
http_port = String.to_integer(System.get_env("ARION_DOCS_HTTP_PORT", "18080"))
backend_port = String.to_integer(System.get_env("ARION_DOCS_BACKEND_PORT", "18081"))

{:ok, _pid} = Arion.ControlPlane.start_link(serve?: false)

cluster = Cluster.static("backend", "127.0.0.1", [backend_port])
route = Route.new("all") |> Route.match_prefix("/") |> Route.to_cluster("backend")
host = VirtualHost.new("all", ["*"]) |> VirtualHost.add_route(route)
routes = RouteConfig.new("http-routes") |> RouteConfig.add_virtual_host(host)
hcm = Hcm.new(codec_type: :HTTP1) |> Hcm.route_config(routes)
chain = FilterChain.new("http") |> FilterChain.add_hcm(hcm)

listener =
  Listener.new("http", Listener.local_address(http_port, "127.0.0.1"))
  |> Listener.add_filter_chain(chain)

:ok = Service.replace("arion", [{:cluster, cluster}, {:listener, listener}])
:ok = Arion.ControlPlane.serve(port: ads_port)
IO.puts("Fleet arion is ready on ADS port #{ads_port}; start the backend and proxy.")
```

`|>` passes each resource to the next builder. The Cluster supplies the backend,
the route refers to that Cluster by name, the virtual host contains the route,
and the Listener contains the HTTP connection manager/filter chain.

From the repository root in a third terminal, start the separate proxy:

```sh
export ARION_PROXY_BIN=/absolute/path/to/arion/target/debug/arion
"$ARION_PROXY_BIN" --with-envoy-bootstrap docs/examples/bootstrap.yaml -C 1 -R 1
```

From a fourth terminal:

```sh
curl --fail http://127.0.0.1:18080/
```

Expect `hello from backend-a`. The proxy bootstrap selects fleet `arion`;
the script published that fleet before accepting xDS connections.

## Inspect, update, and remove

At the running IEx prompt:

```elixir
alias Arion.ControlPlane.Service
Service.list_fleets()
Service.resources("arion")
Service.acks("arion")
```

`resources/1` returns the fleet's resources as `%{kind => %{name => resource}}`;
`acks/1` returns, per connected stream, what it was sent and whether it
accepted it. ACK/NACK status is asynchronous and per stream.

To change the backend, first start a second server on port 18082 using
`backend.py --port 18082 --name backend-b`, then enter:

```elixir
cluster = Arion.ControlPlane.Helpers.Cluster.static("backend", "127.0.0.1", [18082])
Service.push("arion", :cluster, cluster)
```

Once delivered, the same proxy URL returns `hello from backend-b`.

| Operation | Semantics |
| --- | --- |
| `Service.push(fleet, kind, resource)` | Asynchronously add or replace one resource |
| `Service.drop(fleet, kind, name)` | Asynchronously remove one resource |
| `Service.replace(fleet, resources)` | Synchronously replace the fleet's complete set of `{kind, resource}` pairs |
| `Service.resources(fleet)` | Read the fleet's resources by kind and name |
| `Service.acks(fleet)` | Read per-stream acceptance/rejection state |
| `Service.list_fleets()` | List the running fleets |
| `Service.retire(fleet)` | Empty a fleet and stop it once no proxy is subscribed |

The leading fleet argument defaults to `"arion"`. Resources are named and
encoded when they are published, so a malformed resource raises in the caller.
The resource kinds are listed in the
[reference](../../docs/configuration-reference.md#resource-kinds-and-relationships).
`ensure` is a lower-level interface used by fleet management; ordinary
configuration code can use the operations above.

`replace` builds a new cache, swaps one fleet's state in a single process
operation, and queues changes/removals before returning. It does not wait for
proxies to ACK, and the proxy does not receive all resource types as one atomic
transaction. Supplying only a Cluster to `replace` removes the fleet's Listener.
A resource a proxy rejected (NACK) is sent again only when its content changes.

A fleet process that crashes restarts empty and refuses subscriptions until it
is published to again, so a reconnecting proxy keeps the configuration it holds.

To remove this example's configuration:

```elixir
:ok = Service.replace("arion", [])
```

The proxy eventually stops accepting connections on 18080. Stop the local IEx,
proxy, and backend processes when finished.

## State ownership and helpers

All library state is in memory. Your application must retain enough desired
state to republish after restart; it also decides how multiple application
replicas obtain consistent configuration. The library alone supplies neither
durable snapshots nor leader election.

For a packaged durable service, use [`arion_ctl`](../arion_ctl/README.md). Its
shell operations must go through `Arion.Ctl` to keep the snapshot consistent.
For Kubernetes, the [controller](../arion_k8s_controller/README.md) derives its
view from Kubernetes objects.

The [helper catalog](../../docs/configuration-reference.md#elixir-resource-helpers)
covers routing, TLS, traffic policies, external processing, and Arion extensions.
Builders represent the checked-in schema; check the linked compatibility notes
before using an option with a particular proxy build.

## Development

Run `mix format --check-formatted` and `mix test` from this app.
Definitions under `proto/` generate modules under `lib/arion_control_plane/pb/`.
See [protobuf regeneration](../../docs/development.md#protobuf-regeneration)
for the generator and source of truth; do not edit generated modules manually.
