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

defmodule Arion.K8sController.Reconcile.Resolve.Gateway do
  @moduledoc """
  Claims this controller's GatewayClasses and Gateways and resolves their
  ArionGatewayParameters references.

  A Gateway's parametersRef selects its whole parameters spec; without one the
  class's spec applies, and fields neither sets are controller defaults at
  provisioning time. A class or Gateway whose parametersRef cannot be used
  carries the reason in `invalid_params`, and a Gateway of such a class
  inherits it. The provisioned Service's addresses and Deployment's readiness
  feed the Gateway's status.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Resolve.Listener
  alias Arion.K8sController.Status.Claim

  def classes(objects, ctx) do
    for class <- objects, Claim.owns_class?(class, ctx.controller_name) do
      # A GatewayClass parametersRef names its namespace; there is no default.
      ref = get_in(class, ["spec", "parametersRef"])

      %Ir.GatewayClass{
        name: get_in(class, ["metadata", "name"]),
        controller_name: ctx.controller_name,
        generation: get_in(class, ["metadata", "generation"]) || 0,
        params: params_spec(ref, ref["namespace"], ctx.params),
        invalid_params: invalid_params(ref, ref["namespace"], ctx.params)
      }
    end
  end

  @doc "The Gateways of the claimed classes in `ctx.classes`, their listeners parsed."
  def gateways(objects, ctx) do
    owned = MapSet.new(Map.keys(ctx.classes))
    for obj <- objects, Claim.owns_gateway?(obj, owned), do: parse(obj, ctx)
  end

  defp parse(obj, ctx) do
    ns = get_in(obj, ["metadata", "namespace"])
    name = get_in(obj, ["metadata", "name"])
    provisioned = Ir.Gateway.object_name(ns, name)
    class = ctx.classes[get_in(obj, ["spec", "gatewayClassName"])]
    # An infrastructure parametersRef is local to the Gateway's namespace.
    params_ref = get_in(obj, ["spec", "infrastructure", "parametersRef"])

    %Ir.Gateway{
      namespace: ns,
      name: name,
      uid: get_in(obj, ["metadata", "uid"]),
      generation: get_in(obj, ["metadata", "generation"]) || 0,
      class_name: class.name,
      params: if(params_ref, do: params_spec(params_ref, ns, ctx.params), else: class.params),
      invalid_params: invalid_params(params_ref, ns, ctx.params) || class_invalid_params(class),
      infrastructure: get_in(obj, ["spec", "infrastructure"]) || %{},
      addresses: service_addresses(ctx.services[{ns, provisioned}]),
      programmed?: deployment_ready?(ctx.deployments[{ns, provisioned}]),
      listeners: Listener.parse(get_in(obj, ["spec", "listeners"]) || [], ns, ctx)
    }
  end

  defp params_spec(nil, _ns, _params), do: %{}
  defp params_spec(ref, ns, params), do: get_in(params, [{ns, ref["name"]}, "spec"]) || %{}

  defp invalid_params(nil, _ns, _params), do: nil

  defp invalid_params(ref, ns, params) do
    {group, _version, kind} = Gvk.params()

    cond do
      {ref["group"], ref["kind"]} != {group, kind} ->
        "parametersRef kind must be #{group}/#{kind}"

      is_nil(ns) ->
        "parametersRef must have a namespace"

      not Map.has_key?(params, {ns, ref["name"]}) ->
        "#{kind} #{ns}/#{ref["name"]} not found"

      true ->
        nil
    end
  end

  defp class_invalid_params(%Ir.GatewayClass{invalid_params: nil}), do: nil

  defp class_invalid_params(%Ir.GatewayClass{name: name, invalid_params: reason}),
    do: "GatewayClass #{name}: #{reason}"

  defp service_addresses(nil), do: []

  defp service_addresses(svc) do
    ingress = get_in(svc, ["status", "loadBalancer", "ingress"]) || []

    lb =
      for entry <- ingress, addr = entry["ip"] || entry["hostname"], addr != nil do
        %{type: if(entry["ip"], do: "IPAddress", else: "Hostname"), value: addr}
      end

    case lb do
      [] ->
        case get_in(svc, ["spec", "clusterIP"]) do
          ip when is_binary(ip) and ip != "" and ip != "None" -> [%{type: "IPAddress", value: ip}]
          _ -> []
        end

      addrs ->
        addrs
    end
  end

  defp deployment_ready?(nil), do: false
  defp deployment_ready?(dep), do: (get_in(dep, ["status", "readyReplicas"]) || 0) > 0
end
