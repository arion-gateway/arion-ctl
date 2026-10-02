# Run and configure a standalone proxy

[Documentation index](README.md) · [Command reference](../apps/arion_ctl/README.md) ·
[Next: the shell](shell-walkthrough.md)

This walkthrough starts three processes: an HTTP backend, the standalone control
plane, and Arion Proxy. A fourth terminal runs operator commands. By the end,
you will route real requests, update the configuration, and restore it after a
restart.

| Process | Local port | Purpose |
| --- | --- | --- |
| Control plane | 15051 | Supplies configuration over xDS/ADS |
| Arion Proxy | 18080 | Receives your HTTP requests |
| Python backend | 18081 | Returns `hello from backend-a` |

These ports must be free. To use different ports, copy and edit the example
files consistently: bootstrap ADS address, listener address, and backend endpoint.
The service's normal ADS default is 50051; this exercise explicitly selects 15051.

## 1. Build and prepare

You need a Unix shell, Elixir 1.20, Erlang/OTP 29, Python 3, curl, and an Arion
binary. Elixir's `mix` command installs dependencies and creates the release:

```sh
# Start in the arion-ctl repository root.
cd apps/arion_ctl
mix deps.get
MIX_ENV=prod mix release
cd ../..
```

The release lives at `apps/arion_ctl/_build/prod/rel/arion_ctl`. Its `bin/arionctl`
wrapper is the operator command; `bin/arion_ctl` is the underlying Elixir release
management command. You will use the latter to stop the service.

Arion Proxy is built separately. Follow its
[build instructions](https://github.com/arion-gateway/arion#quick-start)
for Rust and system prerequisites. In an Arion source checkout:

```sh
# In the separate arion repository:
cargo build --locked -p arion-proxy --bin arion
```

The resulting binary is `target/debug/arion` in that checkout. Use a proxy build
compatible with the control-plane schemas; see
[compatibility](configuration-reference.md#validation-and-compatibility).
These instructions do not require a published image or Git tag.

In the commands below, replace `/path/to/arion-ctl` and the proxy binary path
with your actual locations. Each terminal starts at the arion-ctl repository root.

## 2. Start the backend — terminal A

```sh
cd /path/to/arion-ctl
python3 docs/examples/backend.py --port 18081 --name backend-a
```

Leave it running. This small server uses Python's standard library and listens
only on loopback. From another terminal, `curl http://127.0.0.1:18081/` should
print `hello from backend-a`.

## 3. Start the control plane — terminal B

```sh
cd /path/to/arion-ctl
export PATH="$PWD/apps/arion_ctl/_build/prod/rel/arion_ctl/bin:$PATH"
export RELEASE_NODE=arionctl_docs
export ARION_CTL_PORT=15051
export ARION_CTL_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arionctl-docs.XXXXXX")"
export ARION_DOCS_ROOT="$PWD"
printf 'State directory: %s\n' "$ARION_CTL_STATE_DIR"
arionctl serve
```

Keep this terminal and its environment for the restart step. The temporary
directory isolates the exercise from any existing standalone state.
`ARION_DOCS_ROOT` is a convenience for the later shell walkthrough, not a
service configuration setting.

The service restores any snapshot in its state directory, then listens for
proxies. It does not launch the proxy or backend.

## 4. Start Arion — terminal C

```sh
cd /path/to/arion-ctl
export ARION_PROXY_BIN=/absolute/path/to/arion/target/debug/arion
"$ARION_PROXY_BIN" --with-envoy-bootstrap docs/examples/bootstrap.yaml -C 1 -R 1
```

The final options keep the local exercise to one proxy CPU/runtime.
The [bootstrap](examples/bootstrap.yaml) tells the proxy to connect to
`127.0.0.1:15051` using the static HTTP/2 cluster `xds`.
Its `node.cluster: arion` selects the fleet containing our resources.

The proxy has no application listener yet. A request to port 18080 will fail
until the next step supplies one.

## 5. Apply the HTTP configuration — terminal D

```sh
cd /path/to/arion-ctl
export PATH="$PWD/apps/arion_ctl/_build/prod/rel/arion_ctl/bin:$PATH"
export RELEASE_NODE=arionctl_docs

arionctl validate -f docs/examples/http.yaml
arionctl apply -f docs/examples/http.yaml
arionctl get --fleet arion
arionctl status
curl --fail http://127.0.0.1:18080/
```

Use the same release directory and `RELEASE_NODE` as terminal B. The release
supplies its cookie automatically; if you explicitly set `RELEASE_COOKIE`, use
the same value in both terminals. `validate` is offline; `apply`, `get`, and
`status` communicate with the running Erlang VM.

Validation reports `"valid": true` and two resources. Apply reports two resources
in the store. Allow a moment for the proxy to accept the update, then curl should
print:

```text
hello from backend-a
```

Read [http.yaml](examples/http.yaml) alongside this explanation:

- The `Cluster` named `backend` contains the upstream endpoint 127.0.0.1:18081.
- The `Listener` named `http` binds 127.0.0.1:18080.
- Its HTTP connection manager contains a virtual host matching any hostname.
- The route matching prefix `/` forwards to cluster `backend`.
- The router filter performs that forwarding.

Each resource's `metadata.fleet: arion` must match the bootstrap's `node.cluster`.
`arionctl` saves these resource definitions and publishes them to Arion over xDS.

## 6. Change routing without restarting

In terminal D:

```sh
arionctl apply -f docs/examples/http-updated.yaml
arionctl status
curl --fail http://127.0.0.1:18080/hello
curl -i http://127.0.0.1:18080/
```

The first request still returns `hello from backend-a`. The second now returns
HTTP 404 with body `No route`. The updated listener routes the `/hello` prefix to
the backend and rewrites that prefix to `/`; its fallback route returns 404.

The update contains only the Listener. Apply replaces that resource's full
specification and preserves the Cluster. Omission is not deletion. Editing the
YAML alone does not change anything; the service does not watch files.

In `status`, look under fleet `arion` and its `clients`. Accepted resources have
entries such as `["ack", "<version>"]`; rejected updates have
`["nack", "<version>", "<error>"]`. Stream IDs and versions vary.
A successful apply reports persistence and publication, while ACK/NACK arrives
asynchronously. Check both status and an actual request.

## 7. Restart and verify persistence

In terminal D, stop the service gracefully:

```sh
apps/arion_ctl/_build/prod/rel/arion_ctl/bin/arion_ctl stop
```

Terminal B returns to its shell. In **that same terminal**, restart using its
existing environment and state directory:

```sh
arionctl serve
```

Do not repeat the `mktemp` assignment: that would create an empty state directory.
Once the proxy reconnects, terminal D should show the restored resources:

```sh
arionctl get --fleet arion
arionctl status
curl --fail http://127.0.0.1:18080/hello
```

You can also stop the proxy with Ctrl+C in terminal C and rerun its original
command. It should receive the restored configuration and serve the same request.

The state directory contains `state.json`. Keep it on persistent local storage
for a lasting installation. The [deployment guide](deployment-options.md) covers
storage ownership and container mounts.

## 8. Continue or clean up

To try interactive configuration now, leave the three processes running and
continue to the [shell walkthrough](shell-walkthrough.md). The
[recipes](recipes.md) reuse this setup too.

Otherwise, in terminal D:

```sh
arionctl delete -f docs/examples/http.yaml
arionctl get
curl --connect-timeout 2 http://127.0.0.1:18080/
apps/arion_ctl/_build/prod/rel/arion_ctl/bin/arion_ctl stop
```

Delete uses the identities in the file, so it removes the current Listener even
though its contents were updated later. With only this walkthrough's resources,
`get` prints `[]` and the HTTP connection fails after removal is delivered.

Stop the backend and proxy with Ctrl+C in their terminals. Back in terminal B,
after the service has stopped, remove only this exercise's temporary state:

```sh
rm -r -- "$ARION_CTL_STATE_DIR"
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `arionctl` is not found | Export the release's absolute `bin` path in that terminal. |
| Cannot contact the release / invalid cookie | Start terminal B; use its release, node name, and cookie. This release uses short node names. |
| Port already in use | Stop your previous exercise process, or change all corresponding example ports together. |
| No clients in `status` | Check the proxy process/logs and bootstrap ADS address. Ensure HTTP/2 is configured for its xDS cluster. |
| Resources exist but the proxy has no listener | Compare `metadata.fleet` with `node.cluster`; inspect NACKs and proxy logs. |
| Validation fails | Use the supported field names and type URLs in the [reference](configuration-reference.md); ordinary Envoy examples may contain unsupported fields. |
| NACK after a successful apply | The desired state was saved, but the proxy rejected it. Read the error, correct the file, and apply it again. |
| HTTP 404 | Check the request's host/path and the route configuration. After step 6 use `/hello`. |
| Backend connection fails | Test port 18081 directly; the Cluster must point to the backend, not port 18080. |
| Cannot write state, or startup reports restore failure | Check directory ownership and the saved snapshot. Preserve a failing snapshot for diagnosis instead of deleting production state. |
