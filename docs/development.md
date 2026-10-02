# Development and verification

[Documentation index](README.md) · [Project overview](../README.md)

The repository contains three independent Mix projects. Run Mix commands from
the app being checked:

| App | Responsibility |
| --- | --- |
| `apps/arion_control_plane` | xDS server, fleet caches, resource helpers, protobuf schemas |
| `apps/arion_ctl` | Arion resource configuration, durable store, CLI, standalone release |
| `apps/arion_k8s_controller` | Kubernetes watches, resolution/translation, status, provisioning |

Use Elixir 1.20 / Erlang/OTP 29 for the complete project. Check the app's
`mix.exs` and the CI workflow when updating supported versions.

## App checks

In each affected app:

```sh
mix deps.get --check-locked
mix format --check-formatted
mix test
```

Standalone tests exercise decoding, whole-input validation, snapshot errors,
removals, recovery, fleet isolation, and CLI/API consistency. Controller tests
cover resource resolution, translation, status, provisioning, and startup
ordering. Passing unit tests does not establish proxy or Kubernetes conformance.

When working alongside another task, use a separate checkout/copy and separate
build artifacts, state directories, node names, and ports. Check the latest
source again before finalizing documentation about interfaces being changed.

## Protobuf regeneration

Definitions under `apps/arion_control_plane/proto/` are the supported
Envoy/Arion subset. Removed fields retain reserved numbers/names. Generated
modules live under `apps/arion_control_plane/lib/arion_control_plane/pb/`;
do not edit them by hand.

Install `protoc`, Python 3, and the generator matching the locked `protobuf`
dependency (currently 0.17.0):

```sh
mix escript.install hex protobuf 0.17.0
export PATH="$HOME/.mix/escripts:$PATH"
# From the arion-ctl repository root:
bin/generate-protos
```

The generator uses the gRPC plugin and
`package_prefix=Arion.ControlPlane.Pb`, generates in a temporary directory,
and maps paths back to the local source layout. Review generated changes and
run checks in the library and both consuming apps.

Keep standard Envoy wire URLs and Arion extension URLs distinct from local
module/package names. A new message type becomes usable by the helpers and the
standalone codec once it is added to the type registry,
`Arion.ControlPlane.Xds.ResourceTypes`. Changing a proto field number is a
wire-compatibility change even when names and type URLs match.

## Builds and integration checks

From the repository root, build the standalone release:

```sh
(cd apps/arion_ctl && MIX_ENV=prod mix release)
```

Verify an external library consumer:

```sh
ARION_CTL_PATH="$PWD" bin/verify-consumer
# Requires an actually published, compatible tag:
ARION_CTL_TAG=v0.1.0 bin/verify-consumer
```

Exercise the packaged CLI against a separate Arion build:

```sh
python3 scripts/smoke.py \
  --release apps/arion_ctl/_build/prod/rel/arion_ctl \
  --proxy /absolute/path/to/arion/target/debug/arion
```

The smoke script creates temporary state and local processes. Check the script's
current scope when reporting results; it covers more than the introductory
HTTP example.

Build images from the repository root:

```sh
docker build -f apps/arion_ctl/Dockerfile -t arion-ctl:0.1.0-local .
docker build -f apps/arion_k8s_controller/Dockerfile -t arion-ctl-controller:0.1.0-local .
```

Build the proxy from its separate repository using its `docker/Dockerfile`.
Controller/proxy image compatibility must be checked together.

Check the chart without deploying it:

```sh
helm lint charts/arion-ctl
helm template arion-ctl charts/arion-ctl \
  --namespace arion-system --include-crds \
  --set cookie.existingSecret=arion-cookie
```

The external cookie setting makes the offline render stable; create that Secret
in the target cluster before using such a render for installation.

## Kubernetes conformance

The runner requires Docker, kind, kubectl, and Helm. It creates/selects a kind
context, installs CRDs and the chart, builds/loads images, checks a route, and
runs the Gateway HTTP and Inference Extension suites; `all` runs both suites
even when the first fails and prints a summary of their reports. The
[runner guide](../apps/arion_k8s_controller/conformance/README.md) lists the
prerequisites and the expected results.

Run it against a disposable cluster with an isolated kubeconfig:

```sh
export KUBECONFIG="$(mktemp "${TMPDIR:-/tmp}/arion-kubeconfig.XXXXXX")"
CLUSTER=arion-docs-check \
RUN_NAMESPACE=arion-docs-check \
ARION_PROXY_REPO=/absolute/path/to/arion \
  apps/arion_k8s_controller/conformance/run.sh all
```

Reports default to `apps/arion_k8s_controller/conformance/reports`; override
`REPORT_DIR` to keep them elsewhere. The current defaults are Gateway API
`v1.6.0`, Inference Extension `v1.5.0`, and `GO_IMAGE=golang:1.26`.
If overriding the API versions, choose a Go image new enough for both suites.

Other useful overrides are `CONTROLLER_IMAGE`, `ARION_IMAGE`,
`GATEWAY_CLASS`, and `BUILD_IMAGES=false` for existing/published images.
Keep published image references versioned. The runner's `clean` action cleans
the chosen cluster; retain the same environment when using it.

Report the exact tested images, API versions, and suite/profile. Do not describe
translation test coverage or successful Helm rendering as conformance.

## Releases

Version 0.1.0 is the initial packaging target in the current release configuration.
Confirm remote artifacts exist before directing consumers to them. Building locally
does not publish repositories, tags, images, or charts.

Before release, align Mix versions, chart version/appVersion, the default proxy
image, and documentation/examples. Publish the compatible Arion proxy first,
then the matching arion-ctl tag.

The [release workflow](../.github/workflows/release.yml), triggered by a `v*`
tag, currently:

1. Runs app checks, builds the standalone release, verifies a tagged external
   consumer, and tests CLI/proxy integration.
2. Publishes versioned standalone and controller images to GHCR.
3. Runs kind integration/conformance against those published images.
4. Publishes the OCI chart at
   `oci://ghcr.io/arion-gateway/charts/arion-ctl` after integration succeeds.

Controller image tags default to chart appVersion. Configure package visibility
for the intended installation audience. Review unresolved compatibility findings
before declaring a version ready.
