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

defmodule Arion.K8sController.Reconcile.Resolve.Attachment do
  @moduledoc """
  Attaches routes to the listeners of this controller's Gateways.

  A route attaches to a Gateway when a listener its parentRef selects allows
  its kind and namespace and shares a hostname: the listener gains an
  `Ir.Attachment` and the route an accepted `Ir.Parent`, whose ResolvedRefs
  reports the first unresolved backend. Otherwise the parent records why, in
  Gateway API terms, and a route the data plane cannot serve is rejected whole
  with UnsupportedValue rather than forwarded with a filter skipped.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Resolve.{Backend, Hostname}

  @doc "The Gateways with their attachments and the routes with their parents."
  def attach(gateways, routes, ctx) do
    index = Map.new(gateways, &{{&1.namespace, &1.name}, &1})

    {index, routes} =
      Enum.reduce(routes, {index, []}, fn route, {index, acc} ->
        {index, route} = attach_route(route, index, ctx)
        {index, [route | acc]}
      end)

    {Map.values(index), Enum.reverse(routes)}
  end

  # Only Arion's own Gateways are parents it attaches to and reports status for.
  defp attach_route(route, index, ctx) do
    Enum.reduce(route.parent_refs, {index, %{route | parents: []}}, fn ref, {index, acc} ->
      key = {ref["namespace"] || route.namespace, ref["name"]}

      with true <- gateway_ref?(ref), {:ok, gateway} <- Map.fetch(index, key) do
        attach_to_gateway(route, ref, gateway, index, key, ctx, acc)
      else
        _ -> {index, acc}
      end
    end)
  end

  defp gateway_ref?(ref) do
    (ref["group"] || Gvk.gateway_group()) == Gvk.gateway_group() and
      (ref["kind"] || "Gateway") == "Gateway"
  end

  defp attach_to_gateway(route, ref, gateway, index, key, ctx, acc) do
    outcomes =
      Enum.map(gateway.listeners, &listener_outcome(&1, route, ref, gateway.namespace, ctx))

    case attachment_reason(outcomes, route) do
      "Accepted" ->
        listeners = Enum.zip_with(gateway.listeners, outcomes, &attach_listener/2)
        acc = add_parent(acc, ref, ctx, true, "Accepted", first_unresolved(route))
        {Map.put(index, key, %{gateway | listeners: listeners}), acc}

      reason ->
        {index, add_parent(acc, ref, ctx, false, reason, nil)}
    end
  end

  defp listener_outcome(listener, route, ref, gateway_ns, ctx) do
    cond do
      not listener_ref_matches?(listener, ref) ->
        :no_matching_ref

      not listener_allows?(listener, route, gateway_ns, ctx) ->
        :not_allowed

      true ->
        case Hostname.intersect(listener.hostname, route.hostnames) do
          :none ->
            :hostname_mismatch

          domains ->
            {:attached,
             %Ir.Attachment{
               namespace: route.namespace,
               name: route.name,
               creation_ts: route.creation_ts,
               domains: domains,
               rules: route.rules
             }}
        end
    end
  end

  defp attachment_reason(outcomes, route) do
    cond do
      Enum.any?(outcomes, &match?({:attached, _}, &1)) ->
        if route.unsupported, do: "UnsupportedValue", else: "Accepted"

      Enum.all?(outcomes, &(&1 == :no_matching_ref)) ->
        "NoMatchingParent"

      :hostname_mismatch in outcomes ->
        "NoMatchingListenerHostname"

      true ->
        "NotAllowedByListeners"
    end
  end

  defp attach_listener(listener, {:attached, attachment}),
    do: %{listener | attached_routes: listener.attached_routes ++ [attachment]}

  defp attach_listener(listener, _outcome), do: listener

  defp listener_ref_matches?(listener, ref) do
    (is_nil(ref["sectionName"]) or ref["sectionName"] == listener.name) and
      (is_nil(ref["port"]) or ref["port"] == listener.port)
  end

  defp listener_allows?(listener, route, gateway_ns, ctx) do
    Gvk.route_kind_name(route.kind) in listener.allowed_routes.kinds and
      namespace_allowed?(listener.allowed_routes.namespaces, route.namespace, gateway_ns, ctx)
  end

  defp namespace_allowed?(:all, _route_ns, _gateway_ns, _ctx), do: true
  defp namespace_allowed?(:same, route_ns, gateway_ns, _ctx), do: route_ns == gateway_ns

  defp namespace_allowed?({:selector, selector}, route_ns, _gateway_ns, ctx),
    do: namespace_matches?(ctx.namespaces[route_ns], selector || %{})

  defp namespace_matches?(nil, _selector), do: false

  defp namespace_matches?(namespace, selector) do
    labels = get_in(namespace, ["metadata", "labels"]) || %{}
    match_labels = selector["matchLabels"] || %{}
    match_expressions = selector["matchExpressions"] || []

    Enum.all?(match_labels, fn {key, value} -> labels[key] == value end) and
      Enum.all?(match_expressions, &match_expression?(labels, &1))
  end

  defp match_expression?(labels, %{"key" => key, "operator" => "In", "values" => values}),
    do: labels[key] in (values || [])

  defp match_expression?(labels, %{"key" => key, "operator" => "NotIn", "values" => values}),
    do: labels[key] not in (values || [])

  defp match_expression?(labels, %{"key" => key, "operator" => "Exists"}),
    do: Map.has_key?(labels, key)

  defp match_expression?(labels, %{"key" => key, "operator" => "DoesNotExist"}),
    do: not Map.has_key?(labels, key)

  defp match_expression?(_labels, _expr), do: false

  defp first_unresolved(route), do: Enum.find(Ir.Route.backends(route), &(not &1.resolved?))

  defp add_parent(route, ref, ctx, accepted?, reason, unresolved) do
    parent = %Ir.Parent{
      parent_ref: ref,
      controller_name: ctx.controller_name,
      accepted?: accepted?,
      accepted_reason: reason,
      resolved_refs?: is_nil(unresolved),
      resolved_reason: Backend.reason_name(unresolved && unresolved.reason)
    }

    %{route | parents: route.parents ++ [parent]}
  end
end
