# arion-ctl

Configure [Arion Proxy](https://github.com/arion-gateway/arion) from an Elixir
application, a standalone service, or Kubernetes.

Arion is the **data plane**: it accepts connections and forwards requests to your
backends. This project is the **control plane**: it describes which ports Arion
should listen on, which requests go to which backends, and how those connections
are secured. The control plane sends configuration to connected proxies through
**xDS**, a family of discovery APIs. Application traffic flows through the proxy.

## Choose how to use it

| I want to… | Use | Configuration lives in |
| --- | --- | --- |
| Build a control plane into my Elixir application | [`Arion.ControlPlane`](apps/arion_control_plane/README.md) | Your application; the library serves an in-memory view |
| Configure proxies using files and commands | [Standalone `arionctl`](apps/arion_ctl/README.md) | A durable snapshot managed by the standalone service |
| Inspect and change a running standalone service interactively | [`arionctl shell`](docs/shell-walkthrough.md) | The same standalone snapshot, through `Arion.Ctl` |
| Configure and provision proxies through Kubernetes | [Kubernetes controller](apps/arion_k8s_controller/README.md) and [Helm chart](charts/arion-ctl/README.md) | Kubernetes resources |

The shell attaches to a running standalone service. The three apps under
`apps/` are independent Mix projects, Elixir's build units. Both the standalone
app and the Kubernetes controller use the control-plane library.

See [deployment options](docs/deployment-options.md) for process placement,
containers, state ownership, and availability.

## Your first working proxy

Start with the [standalone walkthrough](docs/standalone-walkthrough.md). It
builds the service from source, starts a local HTTP backend and Arion, applies a
configuration, changes routing, and verifies recovery after a restart. It
explains each terminal and includes expected responses.

The control-plane release builds with Elixir 1.20 and Erlang/OTP 29:

```sh
# From the arion-ctl repository root:
cd apps/arion_ctl
mix deps.get
MIX_ENV=prod mix release
```

This produces `apps/arion_ctl/_build/prod/rel/arion_ctl/bin/arionctl`, relative
to the repository root. The walkthrough also explains how to obtain the separate
Arion proxy binary. Source builds are the documented starting point; version
numbers in packaging files do not establish that downloadable releases exist.

## What can I configure?

The control plane serves listeners (incoming ports), routes (request matching),
clusters and endpoints (upstream backends), and secrets (TLS material). It
supports live resource changes and separate **fleets**: configuration namespaces
selected by a proxy's bootstrap `node.cluster`.

Use the [architecture guide](docs/architecture.md) to understand these concepts
and the [configuration reference](docs/configuration-reference.md) for resource
configuration, resource helpers, extensions, and compatibility limits. This project
contains a supported subset of Envoy/Arion schemas; schema availability alone
does not establish proxy support.

On Kubernetes, the controller translates Gateway API resources into xDS and can
provision a proxy Deployment, Service, and bootstrap ConfigMap for each Gateway.
See its [support table](apps/arion_k8s_controller/README.md#supported-resources-and-features)
before choosing features.

## Keep learning

- [Documentation index](docs/README.md): suggested reading paths.
- [Shell walkthrough](docs/shell-walkthrough.md): configure the service from IEx.
- [Configuration recipes](docs/recipes.md): separate route/endpoint updates,
  fleet isolation, and TLS Secrets.
- [Development](docs/development.md): app checks, protobuf generation, releases,
  and integration verification.
