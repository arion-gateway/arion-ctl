# Copyright 2026 The arion-gateway Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Arion.K8sController.Reconcile.Resolver do
  @moduledoc """
  Resolves a raw `Store` snapshot into an `Ir.Graph`: pure, deterministic data
  for translation, status and provisioning.

  The snapshot is indexed once into a context the policy modules under
  `Reconcile.Resolve` share, and the stages run in order:

    1. `Gateway` claims this controller's classes and Gateways, validating their
       parameters; `Listener` parses each Gateway's listeners, TLS and port conflicts
    2. `Route` parses every route and its filters; `Backend` and `Inference`
       resolve their backendRefs, `Reference` checking ReferenceGrants
    3. `Attachment` attaches the routes to the listeners and records parent status
    4. `Inference` derives the InferencePools' parent status from the routes

  `Hostname` is the hostname policy those stages and translation share.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Resolve.{Attachment, Gateway, Inference, Reference, Route}
  alias Arion.K8sController.Store

  def resolve(snapshot, controller_name) when is_map(snapshot) do
    ctx = context(snapshot, controller_name)
    classes = Gateway.classes(Store.list(snapshot, Gvk.gateway_class()), ctx)
    ctx = Map.put(ctx, :classes, Map.new(classes, &{&1.name, &1}))
    gateways = Gateway.gateways(Store.list(snapshot, Gvk.gateway()), ctx)
    routes = for {kind, obj} <- ctx.routes, do: Route.parse(kind, obj, ctx)
    {gateways, routes} = Attachment.attach(gateways, routes, ctx)

    %Ir.Graph{
      classes: classes,
      gateways: gateways,
      routes: routes,
      inference_pools: Inference.pools(routes, ctx)
    }
  end

  # `classes` joins once claimed.
  defp context(snapshot, controller_name) do
    %{
      controller_name: controller_name,
      params: by_namespace_name(Store.list(snapshot, Gvk.params())),
      pools: by_namespace_name(Store.list(snapshot, Gvk.inference_pool())),
      services: by_namespace_name(Store.list(snapshot, Gvk.service())),
      secrets: by_namespace_name(Store.list(snapshot, Gvk.secret())),
      deployments: by_namespace_name(Store.list(snapshot, Gvk.deployment())),
      namespaces: Map.new(Store.list(snapshot, Gvk.namespace()), &{&1["metadata"]["name"], &1}),
      pods:
        Enum.group_by(Store.list(snapshot, Gvk.pod()), &get_in(&1, ["metadata", "namespace"])),
      slices: Enum.group_by(Store.list(snapshot, Gvk.endpoint_slice()), &slice_service/1),
      grants: Enum.map(Store.list(snapshot, Gvk.reference_grant()), &Reference.parse_grant/1),
      routes:
        for({kind, gvk} <- Gvk.route_kinds(), obj <- Store.list(snapshot, gvk), do: {kind, obj})
    }
  end

  defp by_namespace_name(objects),
    do: Map.new(objects, &{{&1["metadata"]["namespace"], &1["metadata"]["name"]}, &1})

  defp slice_service(slice) do
    meta = slice["metadata"]
    {meta["namespace"], get_in(meta, ["labels", "kubernetes.io/service-name"])}
  end
end
