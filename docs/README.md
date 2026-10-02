# arion-ctl documentation

Start with [what the project does](../README.md), then choose a path below.
The guides assume basic HTTP and command-line knowledge. Elixir, xDS, and
Arion-specific terms are introduced where needed.

| Goal | Reading path |
| --- | --- |
| Understand the system | [Architecture](architecture.md) → [Deployment options](deployment-options.md) |
| Run and configure my first proxy | [Standalone walkthrough](standalone-walkthrough.md) → [Shell walkthrough](shell-walkthrough.md) → [Recipes](recipes.md) |
| Embed a control plane in Elixir | [Library README](../apps/arion_control_plane/README.md) → [Configuration reference](configuration-reference.md) |
| Install on Kubernetes | [Controller README](../apps/arion_k8s_controller/README.md) → [Helm installation](../charts/arion-ctl/README.md) |
| Look up commands or resource shapes | [Standalone command reference](../apps/arion_ctl/README.md#commands) → [Configuration reference](configuration-reference.md) |
| Contribute or prepare a release | [Development](development.md) |

The [example directory](examples/README.md) contains the complete configurations
used by these guides. All local walkthrough ports are deliberately distinct:
ADS on 15051, proxy HTTP on 18080, and backend HTTP on 18081. ADS means
Aggregated Discovery Service, the xDS endpoint proxies connect to.


