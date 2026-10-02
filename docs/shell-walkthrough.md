# Configure the service through arionctl shell

[Documentation index](README.md) · [Standalone walkthrough](standalone-walkthrough.md) ·
[API reference](../apps/arion_ctl/README.md#shell-api)

The shell is an interactive session in the running standalone service. It
operates on the same durable resources as CLI commands. It does not start a
second control plane.

Complete steps 1–7 of the [standalone walkthrough](standalone-walkthrough.md)
and leave the backend, service, and proxy running. Keep terminal D's release
`PATH` and `RELEASE_NODE=arionctl_docs`.

## 1. Attach and inspect

In terminal D:

```sh
arionctl shell
```

You should see an `iex(arionctl_docs@...)>` prompt. The commands below are
**Elixir**, entered at that prompt; omit the prompt itself when copying.

```elixir
Arion.Ctl.get("arion")
Arion.Ctl.status()
```

`get` returns the Arion resource definitions saved in the control plane as a
list of Elixir maps. These define the desired configuration delivered to proxies
over xDS. `status` includes resource counts and per-client resource versions.
Elixir represents an accepted version as
`{:ack, version}` and a rejection as `{:nack, version, error}`. Check the error
and proxy logs if an update is rejected.

A few conventions used below:

- `%{"name" => "backend"}` is a map with string keys, like a JSON object.
- `[first, second]` is a list.
- `{:ok, result}` is a tuple describing success; `{:error, reason}` describes failure.
- `{:ok, _} = ...` asserts success. A match error means the operation did not
  return success; inspect its error before continuing.
- Variables bind values. Editing a map creates a new value; call `apply` to save it.

## 2. Apply a file on the service host

The service in the walkthrough was started with `ARION_DOCS_ROOT` pointing to
the checkout. Read that environment variable **inside IEx**:

```elixir
root = System.fetch_env!("ARION_DOCS_ROOT")
path = Path.join(root, "docs/examples/http.yaml")
{:ok, _} = Arion.Ctl.apply_file(path)
Arion.Ctl.get("arion")
```

This restores the initial route accepting every path. In a separate ordinary
terminal:

```sh
curl --fail http://127.0.0.1:18080/
```

Expect `hello from backend-a`. If you started the service differently, set
`root = "/absolute/path/to/arion-ctl"` in IEx instead.

Paths in this session are resolved by the service process. A file on your laptop
is not automatically present in a container or remote host. For a container,
copy the file into it and use the container path.

## 3. Construct and apply an Arion resource in Elixir

Start a second backend in **terminal E**, from the repository root:

```sh
python3 docs/examples/backend.py --port 18082 --name backend-b
```

Back in **IEx**, create a replacement for the existing Cluster:

```elixir
cluster = %{
  "apiVersion" => "ctl.arion.io/v1alpha1",
  "kind" => "Cluster",
  "metadata" => %{"name" => "backend", "fleet" => "arion"},
  "spec" => %{
    "type" => "STATIC",
    "connectTimeout" => "1s",
    "loadAssignment" => %{
      "clusterName" => "backend",
      "endpoints" => [
        %{"lbEndpoints" => [
          %{"endpoint" => %{
            "address" => %{
              "socketAddress" => %{"address" => "127.0.0.1", "portValue" => 18082}
            }
          }}
        ]}
      ]
    }
  }
}
{:ok, _} = Arion.Ctl.validate([cluster])
{:ok, _} = Arion.Ctl.apply([cluster])
Arion.Ctl.status()
```

The API accepts a list of maps, so the brackets around `cluster` matter.
This updates the existing Cluster identity while preserving the Listener.

In an ordinary terminal, curl the same proxy address again:

```sh
curl --fail http://127.0.0.1:18080/
```

It should now print `hello from backend-b`. Neither the proxy nor the control
plane needed a restart.

The same change can be built with the library's resource helpers and applied
through `Arion.Ctl.apply_resources/2`, which saves it like a document:

```elixir
alias Arion.ControlPlane.Helpers.Cluster
cluster_b = Cluster.static("backend", "127.0.0.1", [18082], connect_timeout: 1)
{:ok, _} = Arion.Ctl.apply_resources([cluster: cluster_b])
Arion.Ctl.get("arion")
```

`get` shows the helper-built Cluster as a resource definition. Publishing the
value with `Arion.ControlPlane.Service` instead would skip the snapshot.

## 4. Modify, inspect, and delete

Use `put_in` to change a nested map field, then persist the replacement:

```elixir
cluster = put_in(cluster, ["spec", "connectTimeout"], "2s")
{:ok, _} = Arion.Ctl.apply([cluster])
Arion.Ctl.get("arion")
```

As a deletion exercise, create an unused Cluster with a distinct name:

```elixir
extra =
  cluster
  |> put_in(["metadata", "name"], "unused")
  |> put_in(["spec", "loadAssignment", "clusterName"], "unused")

{:ok, _} = Arion.Ctl.apply([extra])
{:ok, _} = Arion.Ctl.delete("Cluster", "unused")
```

The `|>` operator passes the value on its left as the first argument to the next
function. Both the resource identity and endpoint assignment name must agree.
The live `backend` Cluster remains present.

Apply validates the whole input before persisting it. For example:

```elixir
bad = put_in(cluster, ["spec", "unknownField"], true)
{:error, reason} = Arion.Ctl.apply([bad])
IO.puts(reason)
```

The invalid update leaves the saved configuration unchanged. Use
`Arion.Ctl.apply` and `delete` for mutations in this service. Calling the
lower-level library `Service.push` or `replace` would bypass persistence.

## 5. Detach without stopping the service

Press **Ctrl+G** to enter the Erlang user switch command menu, then type
`q` and Enter. This quits the attached shell process. Do not call
`System.halt` or `System.stop` from remote IEx: those stop the service VM.

Back at the ordinary terminal prompt:

```sh
arionctl get --fleet arion
curl --fail http://127.0.0.1:18080/
```

The service continues running and the request still reaches backend B.

Use the [restart procedure](standalone-walkthrough.md#7-restart-and-verify-persistence),
preserving terminal B's state directory. After both the service and proxy restart,
the request should still reach backend B. Shell changes use the same snapshot
as CLI changes.

## 6. Restore the original configuration or clean up

From an ordinary operator terminal:

```sh
arionctl apply -f docs/examples/http.yaml
curl --fail http://127.0.0.1:18080/
```

Expect backend A again. Stop backend B with Ctrl+C in terminal E.
Continue to the [recipes](recipes.md), or follow the standalone
[cleanup steps](standalone-walkthrough.md#8-continue-or-clean-up).

For attachment failures, check the release location, running node, and cookie
as described in [troubleshooting](standalone-walkthrough.md#troubleshooting).
