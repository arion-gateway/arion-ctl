# Runnable documentation examples

Return to the [documentation index](../README.md). Start with the
[standalone walkthrough](../standalone-walkthrough.md) for terminal setup,
commands, expected responses, and cleanup.

| Files | Purpose |
| --- | --- |
| [backend.py](backend.py) | Local HTTP server using only Python's standard library; defaults to 127.0.0.1:18081 |
| [bootstrap.yaml](bootstrap.yaml) | Proxy connection to ADS on 127.0.0.1:15051; fleet `arion` |
| [http.yaml](http.yaml) | Backend Cluster plus HTTP Listener on 18080 |
| [http-updated.yaml](http-updated.yaml) | Replace the Listener so only `/hello` and its prefix matches reach the backend |
| [embedded.exs](embedded.exs) | Publish equivalent HTTP configuration through Elixir helpers |
| [discovery.yaml](discovery.yaml) | Separate Listener, RouteConfiguration, Cluster, and ClusterLoadAssignment |
| [endpoints-b.yaml](endpoints-b.yaml), [routes-updated.yaml](routes-updated.yaml) | Independent endpoint and route changes |
| [bootstrap-fleet-b.yaml](bootstrap-fleet-b.yaml), [fleet-b.yaml](fleet-b.yaml) | Second proxy on 18090 in fleet `fleet-b`, forwarding to backend port 18082 |
| [tls-listener.yaml](tls-listener.yaml), [make-tls-secret.py](make-tls-secret.py) | HTTPS on 18443 and generation of a Secret resource definition from your local certificate/key |
| [kubernetes/parameters.yaml](kubernetes/parameters.yaml) | ArionGatewayParameters and a Gateway; apply with kubectl after installing the chart |

The [recipes](../recipes.md) explain the additional assets. All addresses are
loopback addresses for a single-host exercise. Container deployments require the
[network adjustments](../deployment-options.md#standalone-container).

The Elixir example accepts `ARION_DOCS_ADS_PORT`, `ARION_DOCS_HTTP_PORT`, and
`ARION_DOCS_BACKEND_PORT` to override 15051, 18080, and 18081. These settings belong
to the example script, not the library API. Change the bootstrap consistently if
you change its ADS port.

The TLS generator writes a Secret resource definition containing the private key
to stdout. Redirect it to a private temporary file as shown in the recipe.
No certificate or key is checked into this directory.
