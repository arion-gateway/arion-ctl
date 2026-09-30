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

defmodule Arion.K8sController.Status.Conditions do
  @moduledoc """
  Builds Gateway API status payloads for the StatusWriter.

  `now` is injectable so condition timestamps stay deterministic in tests.
  """

  alias Arion.K8sController.{Ir, Store}
  alias Arion.K8sController.Kube.Gvk

  defmodule StatusEntry do
    @enforce_keys [:gvk, :name, :status]
    defstruct [:gvk, :namespace, :name, :status]
  end

  # Alphabetical, as the GatewayClass status API requires.
  @supported_features [
    "Gateway",
    "GatewayHTTPListenerIsolation",
    "GatewayInfrastructurePropagation",
    "GatewayPort8080",
    "HTTPRoute",
    "HTTPRoute303RedirectStatusCode",
    "HTTPRoute307RedirectStatusCode",
    "HTTPRoute308RedirectStatusCode",
    "HTTPRouteBackendProtocolH2C",
    "HTTPRouteBackendProtocolWebSocket",
    "HTTPRouteBackendTimeout",
    "HTTPRouteCORS",
    "HTTPRouteMethodMatching",
    "HTTPRouteNamedRouteRule",
    "HTTPRouteParentRefPort",
    "HTTPRoutePathRedirect",
    "HTTPRoutePathRewrite",
    "HTTPRoutePortRedirect",
    "HTTPRouteQueryParamMatching",
    "HTTPRouteRequestTimeout",
    "HTTPRouteResponseHeaderModification",
    "HTTPRouteSchemeRedirect",
    "ReferenceGrant"
  ]

  def compute(%Ir.Graph{} = graph, now \\ iso_now()) do
    Enum.map(graph.classes, &class_entry(&1, now)) ++
      Enum.map(graph.gateways, &gateway_entry(&1, now)) ++
      Enum.map(graph.routes, &parents_entry(Gvk.route(&1.kind), &1, now)) ++
      Enum.map(graph.inference_pools, &parents_entry(Gvk.inference_pool(), &1, now))
  end

  @doc """
  Keeps the live `lastTransitionTime` of each condition whose status is
  unchanged and the live order of parents, and drops the entries whose object
  already has that status.
  """
  def changed(entries, snapshot) do
    for entry <- entries,
        object = Store.get(snapshot, entry.gvk, entry.namespace, entry.name) || %{},
        live = object["status"] || %{},
        status = keep_transition_times(entry.status, live),
        # A merge patch replaces each top-level status list; an absent one is empty.
        Enum.any?(status, fn {key, value} -> Map.get(live, key, []) != value end),
        do: %{entry | status: status}
  end

  defp keep_transition_times(status, live) do
    Map.new(status, fn
      {"conditions", conditions} ->
        by_type = Map.new(live["conditions"] || [], &{&1["type"], &1})
        {"conditions", Enum.map(conditions, &keep_transition_time(&1, by_type[&1["type"]]))}

      {"listeners", listeners} ->
        {"listeners", keep_nested(listeners, live["listeners"] || [], & &1["name"])}

      {"parents", parents} ->
        {"parents", keep_parents(parents, live["parents"] || [])}

      other ->
        other
    end)
  end

  # Other implementations may order a shared parents list differently; keeping
  # the live order stops each from reordering the other's write forever.
  defp keep_parents(parents, live_parents) do
    position = live_parents |> Enum.with_index() |> Map.new(fn {p, i} -> {parent_key(p), i} end)

    parents
    |> keep_nested(live_parents, &parent_key/1)
    |> Enum.sort_by(&Map.get(position, parent_key(&1), length(live_parents)))
  end

  defp keep_nested(items, live_items, key) do
    by_key = Map.new(live_items, &{key.(&1), &1})
    Enum.map(items, &keep_transition_times(&1, by_key[key.(&1)] || %{}))
  end

  defp parent_key(parent), do: {parent["parentRef"], parent["controllerName"]}

  defp keep_transition_time(%{"status" => status} = condition, %{"status" => status} = live),
    do: %{condition | "lastTransitionTime" => live["lastTransitionTime"]}

  defp keep_transition_time(condition, _live), do: condition

  defp class_entry(%Ir.GatewayClass{} = class, now) do
    accepted =
      case class.invalid_params do
        nil -> condition("Accepted", true, "Accepted", "Accepted by Arion")
        message -> condition("Accepted", false, "InvalidParameters", message)
      end

    status = %{
      "conditions" => [accepted],
      "supportedFeatures" => Enum.map(@supported_features, &%{"name" => &1})
    }

    entry(Gvk.gateway_class(), class, status, now)
  end

  defp gateway_entry(%Ir.Gateway{} = gw, now) do
    valid? = is_nil(gw.invalid_params) and Enum.any?(gw.listeners, &Ir.Listener.accepted?/1)

    status = %{
      "conditions" => [accepted_condition(gw, valid?), programmed_condition(gw, valid?)],
      "listeners" => Enum.map(gw.listeners, &listener_status(&1, valid?)),
      # Always written, so a Gateway whose Service lost its address loses it too.
      "addresses" => Enum.map(gw.addresses, &%{"type" => &1.type, "value" => &1.value})
    }

    entry(Gvk.gateway(), gw, status, now)
  end

  defp accepted_condition(%Ir.Gateway{invalid_params: message}, _valid?) when is_binary(message),
    do: condition("Accepted", false, "InvalidParameters", message)

  # The Gateway stays Accepted while at least one listener is.
  defp accepted_condition(%Ir.Gateway{} = gw, valid?) do
    case for(l <- gw.listeners, not Ir.Listener.accepted?(l), do: l.name) do
      [] ->
        condition("Accepted", true, "Accepted", "Accepted by Arion")

      invalid ->
        message = "Invalid listeners: #{Enum.join(invalid, ", ")}"
        condition("Accepted", valid?, "ListenersNotValid", message)
    end
  end

  defp programmed_condition(_gw, false),
    do: condition("Programmed", false, "Invalid", "Gateway not accepted")

  # Programmed follows readiness of the provisioned data-plane Deployment.
  defp programmed_condition(%Ir.Gateway{programmed?: true}, true),
    do: condition("Programmed", true, "Programmed", "Gateway programmed")

  defp programmed_condition(%Ir.Gateway{programmed?: false}, true),
    do: condition("Programmed", false, "Pending", "Waiting for data plane to become ready")

  defp listener_status(%Ir.Listener{} = l, gateway_accepted?) do
    %{
      "name" => l.name,
      "attachedRoutes" => length(l.attached_routes),
      "supportedKinds" =>
        Enum.map(l.allowed_routes.kinds, &%{"group" => Gvk.gateway_group(), "kind" => &1}),
      "conditions" => listener_conditions(l, gateway_accepted?) ++ overlapping_tls(l)
    }
  end

  # Negative polarity: never set when False.
  defp overlapping_tls(%Ir.Listener{overlapping_tls?: false}), do: []

  defp overlapping_tls(%Ir.Listener{}) do
    message = "Hostname overlaps another HTTPS listener on this port"
    [condition("OverlappingTLSConfig", true, "OverlappingHostnames", message)]
  end

  defp listener_conditions(%Ir.Listener{} = l, gateway_accepted?) do
    cond do
      not Ir.Listener.supported?(l) ->
        [
          condition("Accepted", false, "UnsupportedProtocol", "Protocol not supported by Arion"),
          condition("Programmed", false, "Invalid", "Listener not programmed")
        ]

      l.conflict ->
        message = "Cannot share port #{l.port} with the other listeners on it"

        [
          condition("Accepted", false, l.conflict, message),
          condition("Conflicted", true, l.conflict, message),
          resolved_refs(l),
          condition("Programmed", false, l.conflict, message)
        ]

      true ->
        [
          condition("Accepted", true, "Accepted", "Listener accepted"),
          resolved_refs(l),
          listener_programmed(l, gateway_accepted?)
        ]
    end
  end

  @resolved_messages %{
    "ResolvedRefs" => "References resolved",
    "RefNotPermitted" => "A certificateRef is not permitted by a ReferenceGrant",
    "InvalidCertificateRef" => "A certificateRef is missing, unsupported or malformed",
    "InvalidRouteKinds" => "An allowedRoutes kind is not supported on this listener"
  }

  defp resolved_refs(%Ir.Listener{resolved_reason: reason}) do
    message = Map.fetch!(@resolved_messages, reason)
    condition("ResolvedRefs", reason == "ResolvedRefs", reason, message)
  end

  defp listener_programmed(_l, false),
    do: condition("Programmed", false, "Invalid", "Gateway not accepted")

  defp listener_programmed(%Ir.Listener{} = l, true) do
    if Ir.Listener.programmed?(l) do
      condition("Programmed", true, "Programmed", "Listener programmed")
    else
      condition("Programmed", false, "Invalid", "No usable TLS certificate")
    end
  end

  # Other controllers' parents are written back as they are, so they join after stamping.
  defp parents_entry(gvk, %{parents: ours, other_parents: theirs} = object, now) do
    entry = entry(gvk, object, %{"parents" => Enum.map(ours, &parent_status/1)}, now)
    put_in(entry.status["parents"], theirs ++ entry.status["parents"])
  end

  @backend_messages %{
    "ResolvedRefs" => "References resolved",
    "RefNotPermitted" => "A backendRef is not permitted by a ReferenceGrant",
    "BackendNotFound" => "A backendRef names a missing Service, port or InferencePool",
    "InvalidKind" => "A backendRef kind is not supported",
    "UnsupportedProtocol" => "A backendRef port protocol is not supported"
  }

  defp parent_status(parent) do
    %{
      "parentRef" => parent.parent_ref,
      "controllerName" => parent.controller_name,
      "conditions" => [
        condition("Accepted", parent.accepted?, parent.accepted_reason, ""),
        condition(
          "ResolvedRefs",
          parent.resolved_refs?,
          parent.resolved_reason,
          Map.fetch!(@backend_messages, parent.resolved_reason)
        )
      ]
    }
  end

  defp condition(type, status, reason, message) do
    %{
      "type" => type,
      "status" => if(status, do: "True", else: "False"),
      "reason" => reason,
      "message" => message
    }
  end

  defp entry(gvk, object, status, now) do
    %StatusEntry{
      gvk: gvk,
      namespace: Map.get(object, :namespace),
      name: object.name,
      status: stamp(status, object.generation, now)
    }
  end

  # changed/2 keeps the live transition time where a condition's status is unchanged.
  defp stamp(status, gen, now) do
    Map.new(status, fn
      {"conditions", conditions} ->
        stamped = %{"observedGeneration" => gen, "lastTransitionTime" => now}
        {"conditions", Enum.map(conditions, &Map.merge(&1, stamped))}

      {key, items} when key in ["listeners", "parents"] ->
        {key, Enum.map(items, &stamp(&1, gen, now))}

      other ->
        other
    end)
  end

  def iso_now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
