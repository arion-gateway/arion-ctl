# Repository guidance

`arion-ctl` contains three independent Mix projects:

- `apps/arion_control_plane`: embeddable xDS library, resource helpers, proto sources and generated modules.
- `apps/arion_ctl`: durable standalone state, strict YAML/protobuf codec and local release CLI.
- `apps/arion_k8s_controller`: Kubernetes watches, reconciliation, provisioning and HA.

Run Mix commands from the relevant app. Preserve namespace isolation through 
xDS `node.cluster` (default `arion`). Standalone CLI and IEx mutations must 
pass through `Arion.Ctl` and its Store.

Proto files are a supported subset of Envoy/Arion schemas with removed fields
reserved. Keep standard Envoy wire type URLs; custom types use Arion wire URLs.
Regenerate with `bin/generate-protos`; do not edit generated modules manually.
Supported message types (modules and wire URLs) live in one registry,
`Arion.ControlPlane.Xds.ResourceTypes`; the helpers and the standalone codec derive from it.

Run affected tests and format checks. Changes to publishing/persistence need
atomic-failure, removal and restart coverage. Use `scripts/smoke.py` for the real
proxy and `apps/arion_k8s_controller/conformance/run.sh` for kind integration.

Helm is the controller installation entry point. Keep public identities, CRD,
RBAC, chart defaults and release workflow versions consistent. Image references
must be versioned. 
