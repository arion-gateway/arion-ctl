# Configuration recipes

[Documentation index](README.md) · [Configuration reference](configuration-reference.md)

These recipes extend the [standalone walkthrough](standalone-walkthrough.md).
Keep its control plane (15051), first proxy (18080), backend A (18081), and
operator terminal running. Use the same release, node, and state directory.

Start backend B in an extra terminal, from the repository root:

```sh
python3 docs/examples/backend.py --port 18082 --name backend-b
```

All resource files below are complete and live in [examples](examples/README.md).
Run recipes sequentially and perform each cleanup before proceeding. The
configurations use the subset exercised with the local Arion build; relevant
[compatibility limits](configuration-reference.md#validation-and-compatibility)
explain why some optional Envoy fields are omitted.

## 1. Update routes and endpoints independently

The basic walkthrough puts routes inside its Listener and endpoints inside its
Cluster. This recipe separates both into named resources:

```text
Listener http → RouteConfiguration http-routes → Cluster backend
                                                   ↓
                                   ClusterLoadAssignment backend
```

The Cluster uses `type: EDS`. The Listener uses RDS with
`routeConfigName: http-routes` and `configSource: {ads: {}}`.
The endpoint assignment's identity is `backend`, matching the Cluster.
The complete configuration is [discovery.yaml](examples/discovery.yaml).

In the operator terminal, remove the earlier configuration before starting this
exercise; this briefly stops the HTTP listener:

```sh
arionctl delete -f docs/examples/http.yaml
arionctl validate -f docs/examples/discovery.yaml
arionctl apply -f docs/examples/discovery.yaml
curl --fail http://127.0.0.1:18080/
```

Expect `hello from backend-a`. Four resources now exist in fleet `arion`.

Change only the ClusterLoadAssignment:

```sh
arionctl apply -f docs/examples/endpoints-b.yaml
curl --fail http://127.0.0.1:18080/
```

Expect `hello from backend-b`. The Listener, route configuration, and Cluster
were not included in this apply.

Change only the RouteConfiguration:

```sh
arionctl apply -f docs/examples/routes-updated.yaml
arionctl status
curl --fail http://127.0.0.1:18080/hello
curl -i http://127.0.0.1:18080/
```

Expect backend B for `/hello` and HTTP 404/`No route` for `/`.
Check resource ACKs as well as the HTTP response; publication happens across
resource types asynchronously.

Restore the original two-resource configuration:

```sh
arionctl delete -f docs/examples/discovery.yaml
arionctl apply -f docs/examples/http.yaml
curl --fail http://127.0.0.1:18080/
```

Expect backend A again.

## 2. Isolate two fleets

Two fleets may contain resources with the same names. The first proxy uses
`node.cluster: arion`; the second will use `node.cluster: fleet-b`.
The resource names remain `http` and `backend`, but the second fleet binds
port 18090 and forwards to backend B on 18082.

In the operator terminal:

```sh
arionctl validate -f docs/examples/fleet-b.yaml
arionctl apply -f docs/examples/fleet-b.yaml
arionctl get --fleet arion
arionctl get --fleet fleet-b
```

In another terminal, start a second proxy:

```sh
cd /path/to/arion-ctl
export ARION_PROXY_BIN=/absolute/path/to/arion/target/debug/arion
"$ARION_PROXY_BIN" --with-envoy-bootstrap docs/examples/bootstrap-fleet-b.yaml -C 1 -R 1
```

Verify the two independent views:

```sh
curl --fail http://127.0.0.1:18080/
curl --fail http://127.0.0.1:18090/
arionctl status
```

The responses are backend A and backend B respectively. Status shows connected
clients under their respective fleet names.

Delete just the second fleet's Listener:

```sh
arionctl delete Listener http --fleet fleet-b
curl --connect-timeout 2 http://127.0.0.1:18090/
curl --fail http://127.0.0.1:18080/
arionctl delete Cluster backend --fleet fleet-b
```

Port 18090 stops accepting connections; port 18080 still serves backend A.
Stop the second proxy with Ctrl+C. An empty namespace can remain visible in
status while its process exists; resource count zero is expected.

Fleets separate configuration but are not an access-control mechanism. Use
trusted connectivity for ADS.

## 3. Terminate TLS with a Secret

This recipe adds an HTTPS Listener on 18443 to the existing backend-A
configuration. It references an xDS Secret named `docs-cert`. Generate a local,
one-day self-signed certificate with OpenSSL; the client will explicitly trust it.

In the operator terminal, from the repository root:

```sh
export ARION_DOCS_TLS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arionctl-tls.XXXXXX")"
(
  umask 077
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$ARION_DOCS_TLS_DIR/key.pem" \
    -out "$ARION_DOCS_TLS_DIR/cert.pem" \
    -days 1 -subj '/CN=localhost' \
    -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
  python3 docs/examples/make-tls-secret.py \
    "$ARION_DOCS_TLS_DIR/cert.pem" "$ARION_DOCS_TLS_DIR/key.pem" \
    > "$ARION_DOCS_TLS_DIR/tls-secret.json"
)
arionctl validate -f "$ARION_DOCS_TLS_DIR/tls-secret.json"
printf 'Secret file for IEx: %s\n' "$ARION_DOCS_TLS_DIR/tls-secret.json"
arionctl shell
```

The generator produces a single JSON object, which is also a valid YAML document.
It embeds the certificate and private key, so the service snapshot will contain
them too.

For this recipe, use the durable shell API to apply the Secret. The current CLI
can truncate sufficiently large payloads when constructing its RPC expression,
causing a CompileError; file-based shell application avoids that path.

At the **IEx prompt**, substitute the exact file path printed above:

```elixir
{:ok, _} = Arion.Ctl.apply_file("/tmp/arionctl-tls.REPLACE_ME/tls-secret.json")
```

The file must exist on the service host. Detach with Ctrl+G, then `q` and Enter.
Back in the ordinary operator terminal:

```sh
arionctl validate -f docs/examples/tls-listener.yaml
arionctl apply -f docs/examples/tls-listener.yaml
arionctl status
curl --fail --cacert "$ARION_DOCS_TLS_DIR/cert.pem" https://127.0.0.1:18443/
```

Expect `hello from backend-a`. Curl verifies both trust and the certificate's
IP subject alternative name. The TLS transport references the Secret by name;
the HTTP route still selects Cluster `backend`.


Remove the TLS resources and local key material:

```sh
arionctl delete Listener https
arionctl delete Secret docs-cert
rm -r -- "$ARION_DOCS_TLS_DIR"
```

The original HTTP listener remains on port 18080. Stop backend B when finished,
then follow the [standalone cleanup](standalone-walkthrough.md#8-continue-or-clean-up)
to remove the remaining resources and stop the service/backend/proxy.
