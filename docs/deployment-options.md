# Deployment options

[Documentation index](README.md) · [Architecture](architecture.md)

Choose where desired configuration should live and who should update it.
The same control-plane library serves xDS in every option.

| Option | Use when | Desired state / recovery | Availability responsibility |
| --- | --- | --- | --- |
| Embedded library | An Elixir application computes configuration | Your application republishes its own persisted/source state | Your application coordinates replicas and recovery |
| Standalone release | Operators configure Arion resources on a host/VM | One local snapshot restored on startup | One process per state directory; no built-in replicated store |
| Standalone container | You want the same service packaged as a container | Snapshot on a persistent mounted volume | Same standalone ownership rules |
| Kubernetes controller | Gateway API should drive configuration and proxy provisioning | Replicas reconstruct resources from the Kubernetes API | Clustered controllers; leader coordinates status and provisioning |

`arionctl shell` is an operator interface to the standalone service.
It shares the same store and lifetime; it is not a separate deployment.

## Embedded library

Your application supervises `Arion.ControlPlane` and publishes protobuf
resources using `Service`. It can use helper modules to construct those
resources. Proxies connect to that application's ADS port.

Start the cache first, restore your desired state, and then start serving xDS.
One control-plane tree can hold multiple fleets within a VM. Keeping multiple
VMs consistent requires your application's own design and state source.

See the [library README](../apps/arion_control_plane/README.md) for a runnable
example and the public resource API.

## Standalone host or VM

Run `arionctl serve` as a long-running process. Run the proxy separately with a
bootstrap that names a reachable ADS endpoint and the intended fleet.

Operator commands and `arionctl shell` use Erlang distribution and the release
cookie. Use the same release and node configuration; the walkthrough uses local
operator processes on the service host. It is not a REST management endpoint.

Use a persistent local state directory, keep it private, and allow only one
service to write it. Changes are explicitly applied or deleted; files are not
watched. Back up the state directory while the service is stopped, and restore
it with matching ownership before starting it again. An invalid snapshot causes
startup to fail rather than silently serving an empty view.

There is no built-in active/active standalone deployment. Copying a snapshot to
several independently writable services does not coordinate their updates.
Use the [standalone walkthrough](standalone-walkthrough.md) for a first run and
the [app README](../apps/arion_ctl/README.md#runtime-settings) for settings.

## Standalone container

This example puts **only the control plane** in a container. The backend and
Arion proxy remain on the host, as in the walkthrough. This keeps the example's
loopback backend/listener addresses correct for the host proxy.

Build locally from the repository root:

```sh
docker build -f apps/arion_ctl/Dockerfile -t arion-ctl:0.1.0-local .
docker run -d --name arion-ctl-docs \
  -p 127.0.0.1:15051:50051 \
  -v arion-docs-state:/var/lib/arion-ctl \
  arion-ctl:0.1.0-local
docker logs arion-ctl-docs
```

Use this in place of the walkthrough's host service, not alongside a service
already listening on port 15051. The host proxy's unchanged bootstrap connects
to host port 15051, which Docker forwards to container ADS port 50051.

Copy the resource configuration file into the container and invoke the release
there:

```sh
docker cp docs/examples/http.yaml arion-ctl-docs:/tmp/http.yaml
docker exec arion-ctl-docs /app/bin/arionctl validate -f /tmp/http.yaml
docker exec arion-ctl-docs /app/bin/arionctl apply -f /tmp/http.yaml
docker exec arion-ctl-docs /app/bin/arionctl status
docker exec -it arion-ctl-docs /app/bin/arionctl shell
```

Run the host backend and proxy from the walkthrough, then verify
`curl http://127.0.0.1:18080/`. In IEx, `Arion.Ctl.apply_file("/tmp/http.yaml")`
reads the container's copy. Detach with Ctrl+G, then `q` and Enter.

The image runs as UID 10001 and sets `ARION_CTL_STATE_DIR=/var/lib/arion-ctl`.
A bind-mounted host directory must be writable by that UID. The named volume
retains the snapshot when the container is replaced:

```sh
docker stop arion-ctl-docs
docker rm arion-ctl-docs
```

Recreate it with the same volume to restore configuration. Remove the volume
only when its saved configuration is no longer needed.

A versioned published image can replace the local image after you have confirmed
that the chosen release is available and compatible. The packaging target is
`ghcr.io/arion-gateway/arion-ctl:0.1.0`; its presence is not assumed here.

### If the proxy or backend also runs in a container

Addresses are interpreted by the process using them:

- The bootstrap ADS address must be reachable **from the proxy**.
- Cluster backend endpoints must be reachable **from the proxy**.
- Listener bind addresses belong to the proxy's network namespace.
- CLI file paths belong to the invoking container/process; IEx file paths belong
  to the service container.

`127.0.0.1` inside one container does not reach a different container or the
host. Use a shared container network and appropriate service DNS names, configure
DNS-capable clusters where needed, and bind proxy listeners to an interface
accessible through your chosen port mappings. Changing only Docker's published
ports is insufficient.

## Kubernetes controller

Install the [Helm chart](../charts/arion-ctl/README.md) after the required Gateway
API CRDs. The chart installs the controller and supporting RBAC/services. By
default, the controller provisions a separate data-plane Deployment, Service,
ServiceAccount, and bootstrap ConfigMap per Gateway.

Each Gateway gets a fleet. Each controller replica computes and serves the
desired resources locally, so proxies can reconnect through the ADS Service.
The chart defaults to two controller replicas with leader election enabled.
The leader alone writes Kubernetes status and provisions data-plane objects.

The controller initially waits for its watches to be listed and the translated
state published before binding ADS. Kubernetes readiness then admits it to the
service. The replicas need a shared Erlang cookie and private connectivity on
distribution ports as documented in the chart.

Use `ArionGatewayParameters` to configure images, replica counts, service types,
resource requests, and self-managed proxies. See
[controller provisioning](../apps/arion_k8s_controller/README.md#provisioning-and-ariongatewayparameters)
for parameter precedence and responsibilities.

Kubernetes is the configuration owner. Use Gateway API resources for routes and
Arion-specific parameters for provisioning; direct cache changes are not a
durable configuration source for this controller.

## Connectivity and operational checks

Keep configuration/distribution endpoints reachable by their intended trusted
processes. Application traffic, ADS configuration traffic, and operator
distribution traffic have different destinations.

After startup or a configuration change:

1. Confirm the desired resources exist in their source of truth.
2. Confirm the proxy connects to the intended ADS endpoint and fleet.
3. Inspect ACK/NACK information or controller/proxy logs.
4. Send a real request through the proxy to the backend.

A reachable ADS port or an ACK alone does not prove that application routing is
healthy. The [architecture guide](architecture.md#what-does-success-mean)
explains the separate stages.
