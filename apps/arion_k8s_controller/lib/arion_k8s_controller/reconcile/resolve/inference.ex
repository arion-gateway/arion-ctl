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

defmodule Arion.K8sController.Reconcile.Resolve.Inference do
  @moduledoc """
  Gateway API Inference Extension: InferencePool backends, their endpoint
  pickers and selected pods, and the pools' parent status.

  The backendRef port is ignored: a pool's targetPorts are the endpoint ports.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Resolve.{Backend, Reference, Route}

  def backend(route_kind, base, route_ns, ctx) do
    %Ir.Backend{namespace: ns, name: name} = base
    pool = ctx.pools[{ns, name}]
    protocol = Backend.protocol(route_kind, app_protocol(pool))
    from = {Gvk.route_kind_name(route_kind), route_ns}
    referent = {"inference.networking.k8s.io", "InferencePool", ns, name}

    {resolved?, reason, epp} =
      case Reference.check(ctx.grants, from, referent, ctx.pools, :pool_not_found) do
        :ok -> endpoint_picker(pool, ns, ctx)
        {:error, reason} -> {false, reason, nil}
      end

    %{
      base
      | protocol: protocol,
        cluster_name: Backend.cluster_name("inferencepool:#{ns}/#{name}", protocol),
        endpoints: endpoints(pool, ns, target_ports(pool), ctx),
        inference?: true,
        epp: epp,
        resolved?: resolved?,
        reason: reason
    }
  end

  @doc "The pools, each with a parent per Gateway of the accepted routes using it."
  def pools(routes, ctx) do
    refs =
      routes
      |> Enum.flat_map(&references/1)
      |> Enum.group_by(fn {key, _parent} -> key end, fn {_key, parent} -> parent end)

    for {{ns, name}, obj} <- ctx.pools do
      %Ir.InferencePool{
        namespace: ns,
        name: name,
        generation: get_in(obj, ["metadata", "generation"]) || 0,
        parents: refs |> Map.get({ns, name}, []) |> Enum.uniq_by(&parent_key/1),
        other_parents: Route.other_parents(obj, ctx.controller_name)
      }
    end
  end

  defp endpoint_picker(pool, pool_ns, ctx) do
    ref = get_in(pool, ["spec", "endpointPickerRef"]) || %{}
    group = ref["group"] || ""
    kind = ref["kind"] || "Service"
    name = ref["name"]
    port = port_number(ref["port"])

    cond do
      group != "" or kind != "Service" ->
        {false, :invalid_kind, nil}

      name == nil or port == nil or not Map.has_key?(ctx.services, {pool_ns, name}) ->
        {false, :epp_not_found, nil}

      true ->
        epp = %{
          cluster_name: "epp:#{pool_ns}/#{name}:#{port}",
          dns_name: "#{name}.#{pool_ns}.svc.cluster.local",
          port: port,
          failure_mode: ref["failureMode"] || "FailClose"
        }

        {true, nil, epp}
    end
  end

  defp app_protocol(nil), do: "http"
  defp app_protocol(pool), do: get_in(pool, ["spec", "appProtocol"]) || "http"

  defp target_ports(nil), do: []

  defp target_ports(pool) do
    case get_in(pool, ["spec", "targetPorts"]) do
      ports when is_list(ports) ->
        ports |> Enum.map(&port_number(&1["number"])) |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  # Pods ready as the EPP counts them; an empty selector selects nothing.
  defp endpoints(pool, ns, ports, ctx) do
    case get_in(pool, ["spec", "selector", "matchLabels"]) do
      selector when map_size(selector) > 0 ->
        endpoints =
          for pod <- Map.get(ctx.pods, ns, []),
              Enum.all?(selector, fn {k, v} -> get_in(pod, ["metadata", "labels", k]) == v end),
              pod_ready?(pod),
              ip = pod_ip(pod),
              port <- ports,
              uniq: true,
              do: {ip, port}

        Enum.sort(endpoints)

      _none ->
        []
    end
  end

  defp pod_ready?(pod) do
    conditions = get_in(pod, ["status", "conditions"]) || []

    is_nil(get_in(pod, ["metadata", "deletionTimestamp"])) and
      Enum.any?(conditions, &match?(%{"type" => "Ready", "status" => "True"}, &1))
  end

  # IPv4 when there is one, as the proxy rejects IPv6 endpoint addresses.
  defp pod_ip(pod) do
    ips = for %{"ip" => ip} <- get_in(pod, ["status", "podIPs"]) || [], do: ip
    Enum.find(ips, &ipv4?/1) || get_in(pod, ["status", "podIP"])
  end

  defp ipv4?(ip), do: match?({:ok, _}, :inet.parse_ipv4strict_address(String.to_charlist(ip)))

  defp port_number(%{"number" => number}), do: port_number(number)
  defp port_number(number) when is_integer(number), do: number

  defp port_number(number) when is_binary(number) do
    case Integer.parse(number) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp port_number(_), do: nil

  defp references(route) do
    parents = Enum.filter(route.parents, & &1.accepted?)

    for backend <- Ir.Route.backends(route), backend.inference?, parent <- parents do
      {{backend.namespace, backend.name}, parent(route, backend, parent)}
    end
  end

  defp parent(route, backend, %Ir.Parent{} = parent) do
    %Ir.Parent{
      parent_ref: gateway_parent_ref(parent.parent_ref, route.namespace),
      controller_name: parent.controller_name,
      resolved_refs?: backend.resolved?,
      resolved_reason: Backend.reason_name(backend.reason)
    }
  end

  # The InferencePool status parentRef has no sectionName or port.
  defp gateway_parent_ref(ref, route_ns) do
    %{
      "group" => ref["group"] || Gvk.gateway_group(),
      "kind" => ref["kind"] || "Gateway",
      "namespace" => ref["namespace"] || route_ns,
      "name" => ref["name"]
    }
  end

  defp parent_key(parent),
    do: {parent.controller_name, parent.parent_ref["namespace"], parent.parent_ref["name"]}
end
