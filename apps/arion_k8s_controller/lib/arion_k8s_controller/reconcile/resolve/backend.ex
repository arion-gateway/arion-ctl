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

defmodule Arion.K8sController.Reconcile.Resolve.Backend do
  @moduledoc """
  Resolves a rule's backendRefs: Service backends here, InferencePool
  backends through `Inference`.

  A Service backend resolves in order of kind, ReferenceGrant, existence and
  the named port, so the first failure is the one reported. The port's name
  selects the EndpointSlice port, which is how a numeric or named targetPort
  resolves; its appProtocol and the route kind decide the upstream protocol.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Resolve.{Inference, Reference}

  def resolve(route_kind, ref, route_ns, ctx) do
    base = %Ir.Backend{
      namespace: ref["namespace"] || route_ns,
      name: ref["name"],
      port: ref["port"],
      weight: Map.get(ref, "weight", 1)
    }

    case {ref["group"] || "", ref["kind"] || "Service"} do
      {"inference.networking.k8s.io", "InferencePool"} ->
        Inference.backend(route_kind, base, route_ns, ctx)

      kind ->
        service(route_kind, base, kind, route_ns, ctx)
    end
  end

  @doc "gRPC and h2c backends are spoken to over HTTP/2, everything else over HTTP/1.1."
  def protocol(:grpc, _app_protocol), do: :http2
  def protocol(_route_kind, "kubernetes.io/h2c"), do: :http2
  def protocol(_route_kind, _app_protocol), do: :http1

  @doc "Cluster names carry the protocol, as HTTP/2 clusters are configured differently."
  def cluster_name(name, :http1), do: name
  def cluster_name(name, :http2), do: name <> "/h2"

  @doc "The Gateway API ResolvedRefs reason of an internal one; every reason needs a clause."
  def reason_name(nil), do: "ResolvedRefs"
  def reason_name(:ref_not_permitted), do: "RefNotPermitted"
  def reason_name(:backend_not_found), do: "BackendNotFound"
  def reason_name(:port_not_found), do: "BackendNotFound"
  def reason_name(:pool_not_found), do: "BackendNotFound"
  def reason_name(:epp_not_found), do: "BackendNotFound"
  def reason_name(:invalid_kind), do: "InvalidKind"
  def reason_name(:unsupported_port_protocol), do: "UnsupportedProtocol"

  defp service(route_kind, base, kind, route_ns, ctx) do
    %Ir.Backend{namespace: ns, name: name, port: number} = base
    from = {Gvk.route_kind_name(route_kind), route_ns}
    referent = {"", "Service", ns, name}

    with {"", "Service"} <- kind,
         :ok <- Reference.check(ctx.grants, from, referent, ctx.services, :backend_not_found),
         {:ok, port} <- select_port(get_in(ctx.services, [{ns, name}, "spec", "ports"]), number) do
      protocol = protocol(route_kind, port.app_protocol)

      %{
        base
        | protocol: protocol,
          cluster_name: cluster_name("svc:#{ns}/#{name}:#{number}", protocol),
          endpoints: ready_endpoints(Map.get(ctx.slices, {ns, name}, []), port.name)
      }
    else
      {:error, reason} -> %{base | resolved?: false, reason: reason}
      _other_kind -> %{base | resolved?: false, reason: :invalid_kind}
    end
  end

  # UDP and SCTP ports are not usable upstreams.
  defp select_port(ports, number) do
    case Enum.filter(ports || [], &(&1["port"] == number)) do
      [] ->
        {:error, :port_not_found}

      candidates ->
        case Enum.find(candidates, &((&1["protocol"] || "TCP") == "TCP")) do
          nil -> {:error, :unsupported_port_protocol}
          port -> {:ok, %{name: port["name"] || "", app_protocol: port["appProtocol"] || "http"}}
        end
    end
  end

  # A dual-stack Service lists each pod once per IP family, so one family is used:
  # IPv4 when there is any, as the proxy rejects IPv6 endpoint addresses.
  defp ready_endpoints(slices, port_name) do
    endpoints =
      for slice <- slices,
          %{"port" => port} when is_integer(port) <-
            [Enum.find(slice["ports"] || [], &((&1["name"] || "") == port_name))],
          endpoint <- slice["endpoints"] || [],
          get_in(endpoint, ["conditions", "ready"]) != false,
          [address | _] <- [endpoint["addresses"]],
          uniq: true,
          do: {slice["addressType"], {address, port}}

    family = if List.keymember?(endpoints, "IPv4", 0), do: "IPv4", else: "IPv6"
    Enum.sort(for {^family, endpoint} <- endpoints, do: endpoint)
  end
end
