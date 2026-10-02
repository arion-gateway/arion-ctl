# Standalone control plane and arionctl

[Project overview](../../README.md) · [Complete walkthrough](../../docs/standalone-walkthrough.md)

This app packages the xDS library as a long-running service with a durable
configuration store. Use `arionctl` to validate, apply, inspect, and delete Arion
resources: listeners, routes, clusters, endpoints, and secrets. The service
saves their configuration and delivers updates to proxies over xDS. Use
`arionctl shell` to open IEx, Elixir's interactive shell, inside the same running
service.

The package/app name is `arion_ctl`, the operator executable is `arionctl`, and
the durable Elixir API is `Arion.Ctl`.

## Build and start

Use Elixir 1.20 and Erlang/OTP 29. From the repository root:

```sh
cd apps/arion_ctl
mix deps.get
MIX_ENV=prod mix release
cd ../..
export PATH="$PWD/apps/arion_ctl/_build/prod/rel/arion_ctl/bin:$PATH"
export RELEASE_NODE=arionctl_docs
export ARION_CTL_PORT=15051
export ARION_CTL_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arionctl-docs.XXXXXX")"
export ARION_DOCS_ROOT="$PWD"
arionctl serve
```

This starts the service in the foreground. The
[walkthrough](../../docs/standalone-walkthrough.md) starts the backend and proxy
in separate terminals, explains their bootstrap, and demonstrates a real request.

From another terminal at the repository root, using the same release/node/cookie:

```sh
export PATH="$PWD/apps/arion_ctl/_build/prod/rel/arion_ctl/bin:$PATH"
export RELEASE_NODE=arionctl_docs
arionctl validate -f docs/examples/http.yaml
arionctl apply -f docs/examples/http.yaml
arionctl get --fleet arion
arionctl status
arionctl shell
```

The sample contains a Cluster pointing to backend port 18081 and a Listener on
18080. Applying it stores two resources and publishes them to fleet `arion`.
The proxy still needs to connect to ADS, and the backend must be running, before
HTTP requests can succeed.

## Commands

| Command | Behavior |
| --- | --- |
| `arionctl serve` | Start the foreground service; configure it through environment variables. |
| `arionctl shell` | Attach a remote IEx shell to the running service. |
| `arionctl validate -f FILE` | Validate a YAML document stream or JSON array locally; no running service required. |
| `arionctl apply -f FILE` | Validate a YAML document stream or JSON array, then merge resources into the running service's desired state. |
| `arionctl delete -f FILE` | Validate documents and delete their fleet/kind/name identities. |
| `arionctl delete KIND NAME [--fleet FLEET]` | Delete one identity; fleet defaults to `arion`. Kind is case-sensitive, such as `Listener`. |
| `arionctl get [--fleet FLEET]` | Print saved Arion resource definitions as a JSON array; omission of the filter returns all fleets. |
| `arionctl status` | Print resource counts and connected-stream ACK/NACK state by fleet. |
| `arionctl --help` | Show the accepted command forms. |

`get` shows the desired resource configuration saved in the control plane. Its
JSON output can be passed directly to `validate -f` or `apply -f`. Use `status`
to inspect proxy ACKs and NACKs for published updates.

Commands accept the argument order shown. Failures return a nonzero exit status.
File-based commands read files in the invoking CLI process. Remote IEx file
operations read paths in the service's filesystem.

There is no `arionctl stop` verb. Use the underlying release command, with the
same node/cookie environment, from the repository root:

```sh
apps/arion_ctl/_build/prod/rel/arion_ctl/bin/arion_ctl stop
```

## Runtime settings

| Variable | Default | Meaning |
| --- | --- | --- |
| `ARION_CTL_PORT` | `50051` | ADS listen port |
| `ARION_CTL_STATE_DIR` | `$HOME/.local/state/arionctl` | Directory containing `state.json` |
| `RELEASE_NODE` | `arionctl` | Erlang short node name; match it in operator terminals |
| `RELEASE_COOKIE` | Generated release cookie | Erlang distribution credential; keep it consistent between service and operators |

The examples select port 15051 and node `arionctl_docs` to distinguish the
exercise. The release uses short-name distribution. Operator commands use
Erlang distribution to the service, not an HTTP management API. The cookie
authenticates that connection; a remote shell has the service process's privileges.

Keep ADS and distribution on trusted networks. A snapshot can contain TLS private
keys. The Store creates its directory with mode 0700 and the snapshot with mode
0600. Container UID and network details are in [deployment options](../../docs/deployment-options.md).

## Apply, persistence, and failure behavior

A resource identity is `{fleet, kind, name}`. Apply validates the complete input
before committing it. It replaces supplied resource specifications in full and
preserves identities that were not supplied. It writes and syncs a temporary
snapshot, renames it over `state.json`, then publishes the new view to fleet caches.

An invalid document prevents the entire input from being committed. A snapshot
write failure leaves the previous desired state active. Successful application
does not wait for proxy ACKs and cannot guarantee that all proxies have switched
configuration together.

Delete removes identities explicitly. File deletion validates the supplied
documents, so using `delete KIND NAME` is useful when the original file is no
longer available. The service does not watch configuration files.

On startup, the Store restores the snapshot before ADS is started. An invalid or
unsupported snapshot causes startup to fail. Give each running instance its own
local state directory; there is no shared-directory locking or distributed
standalone store. The Store also republishes desired state after a fleet process
restarts.

For a backup, stop the service and copy its state directory to protected storage.
Restore it while the service is stopped, preserving ownership. See the
[configuration reference](../../docs/configuration-reference.md#exporting-configuration)
for exporting saved resource configuration through the API.

## Shell API

The [shell walkthrough](../../docs/shell-walkthrough.md) shows complete examples.

| Function | Result / purpose |
| --- | --- |
| `Arion.Ctl.validate(documents)` | Validate YAML, JSON array text, or a list of Elixir maps; return `{:ok, entries}` or `{:error, reason}` without committing |
| `Arion.Ctl.apply(documents)` | Apply Arion resource definitions from YAML, JSON array text, or a list of Elixir maps |
| `Arion.Ctl.apply_resources(pairs, fleet: "arion")` | Apply protobuf values built with the library helpers, as `{kind, payload}` or `{kind, {name, payload}}` pairs; they are saved as resource definitions |
| `Arion.Ctl.apply_file(path)` | Read and apply a file on the service host |
| `Arion.Ctl.delete_file(path)` | Read and delete identities from a file |
| `Arion.Ctl.delete_documents(yaml_or_maps)` | Delete identities from documents |
| `Arion.Ctl.delete(kind, name, fleet \\ "arion")` | Delete one identity |
| `Arion.Ctl.get(fleet \\ nil)` | Return saved Arion resource definitions as Elixir maps, optionally filtered by fleet |
| `Arion.Ctl.status()` | Return per-fleet counts and stream status |

Mutation functions return `{:ok, %{resources: total}}` or `{:error, reason}`.
The count is the total number of stored resources, not the number changed.

Use this API for shell changes. The underlying `Arion.ControlPlane.Service`
mutates in-memory caches directly and bypasses the standalone snapshot.
`apply_resources` is the durable way to publish helper-built values: it turns
them into the same documents `get` exports, validates the whole batch, and
only then saves and publishes it. Nested extension messages are expanded under
their `@type`, so the saved definition is readable and reapplies unchanged.

## Development

Run `mix format --check-formatted` and `mix test` from this app directory.
See [development and integration verification](../../docs/development.md) for
release, proxy, and external-consumer checks.
