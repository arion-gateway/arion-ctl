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

defmodule Arion.K8sController.Reconcile.Resolve.Listener do
  @moduledoc """
  Listener policy: protocol, TLS certificates, allowed routes and the
  compatibility of the listeners sharing a port.

  `parse/3` turns a Gateway's listener specs into `Ir.Listener`s with their
  `conflict`, `overlapping_tls?` and `resolved_reason` set; attachment fills
  their `attached_routes` afterwards.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Reconcile.Certificate
  alias Arion.K8sController.Reconcile.Resolve.{Hostname, Reference}

  def parse(listeners, gateway_ns, ctx),
    do: listeners |> Enum.map(&parse_listener(&1, gateway_ns, ctx)) |> mark_conflicts()

  defp parse_listener(l, gateway_ns, ctx) do
    protocol = protocol(l["protocol"], l["tls"])
    {tls, tls_reason} = parse_tls(l["tls"], gateway_ns, ctx)
    {kinds, kinds_reason} = route_kinds(get_in(l, ["allowedRoutes", "kinds"]), protocol)

    %Ir.Listener{
      name: l["name"],
      port: l["port"],
      protocol: protocol,
      hostname: l["hostname"],
      tls: tls,
      # A certificate reason wins: it also explains a listener that is not Programmed.
      resolved_reason: if(tls_reason == "ResolvedRefs", do: kinds_reason, else: tls_reason),
      allowed_routes: %{namespaces: route_namespaces(l["allowedRoutes"]), kinds: kinds}
    }
  end

  defp protocol("HTTP", _tls), do: :http
  defp protocol("HTTPS", _tls), do: :https
  defp protocol("TLS", %{"mode" => "Passthrough"}), do: :tls_passthrough
  # The CRD defaults the mode to Terminate.
  defp protocol("TLS", _tls), do: :tls_terminate
  defp protocol("TCP", _tls), do: :tcp
  defp protocol("UDP", _tls), do: :udp
  defp protocol(_other, _tls), do: :unknown

  defp parse_tls(nil, _ns, _ctx), do: {nil, "ResolvedRefs"}
  defp parse_tls(%{"mode" => "Passthrough"}, _ns, _ctx), do: {nil, "ResolvedRefs"}

  defp parse_tls(tls, gateway_ns, ctx) do
    results = Enum.map(tls["certificateRefs"] || [], &resolve_certificate(&1, gateway_ns, ctx))
    reasons = for {:error, reason} <- results, do: reason
    # RefNotPermitted wins: InvalidCertificateRef is only for permitted refs.
    reason =
      Enum.find(["RefNotPermitted", "InvalidCertificateRef"], "ResolvedRefs", &(&1 in reasons))

    {%Ir.Tls{certificates: for({:ok, cert} <- results, do: cert)}, reason}
  end

  defp resolve_certificate(ref, gateway_ns, ctx) do
    {ns, name} = {ref["namespace"] || gateway_ns, ref["name"]}
    {group, kind} = {ref["group"] || "", ref["kind"] || "Secret"}

    cond do
      not Reference.permitted?(ctx.grants, {"Gateway", gateway_ns}, {group, kind, ns, name}) ->
        {:error, "RefNotPermitted"}

      group != "" or kind != "Secret" ->
        {:error, "InvalidCertificateRef"}

      true ->
        with %{"data" => data} <- ctx.secrets[{ns, name}],
             {:ok, cert_pem, key_pem} <- Certificate.parse(data) do
          {:ok, %{sds_name: "secret:#{ns}/#{name}", cert_pem: cert_pem, key_pem: key_pem}}
        else
          _ -> {:error, "InvalidCertificateRef"}
        end
    end
  end

  defp route_namespaces(allowed) do
    case get_in(allowed, ["namespaces", "from"]) do
      "All" -> :all
      "Selector" -> {:selector, get_in(allowed, ["namespaces", "selector"])}
      _ -> :same
    end
  end

  defp route_kinds(requested, protocol) when requested in [nil, []],
    do: {supported_kinds(protocol), "ResolvedRefs"}

  defp route_kinds(requested, protocol) do
    {valid, invalid} =
      Enum.split_with(requested, fn kind ->
        (kind["group"] || Gvk.gateway_group()) == Gvk.gateway_group() and
          kind["kind"] in supported_kinds(protocol)
      end)

    reason = if invalid == [], do: "ResolvedRefs", else: "InvalidRouteKinds"
    {Enum.map(valid, & &1["kind"]), reason}
  end

  defp supported_kinds(protocol) when protocol in [:http, :https], do: ["HTTPRoute", "GRPCRoute"]
  defp supported_kinds(:tls_passthrough), do: ["TLSRoute"]
  defp supported_kinds(:tls_terminate), do: ["TLSRoute"]
  defp supported_kinds(:tcp), do: ["TCPRoute"]
  defp supported_kinds(:udp), do: ["UDPRoute"]
  defp supported_kinds(_protocol), do: []

  # Listeners on one port share one proxy listener, so they must be compatible:
  # one TCP listener, only HTTP listeners, or only HTTPS and TLS listeners with
  # distinct hostnames. No conflicting listener wins.
  defp mark_conflicts(listeners) do
    by_port = listeners |> Enum.filter(&Ir.Listener.supported?/1) |> Enum.group_by(& &1.port)

    Enum.map(listeners, fn l ->
      peers = Map.get(by_port, l.port, [])
      %{l | conflict: conflict(l, peers), overlapping_tls?: overlapping_tls?(l, peers)}
    end)
  end

  defp conflict(listener, peers) do
    cond do
      not Ir.Listener.supported?(listener) -> nil
      peers |> Enum.uniq_by(&port_family/1) |> length() > 1 -> "ProtocolConflict"
      Enum.count(peers, &(&1.hostname == listener.hostname)) > 1 -> "HostnameConflict"
      true -> nil
    end
  end

  # The proxy tells TLS listeners apart by SNI but cannot mix plaintext with TLS.
  defp port_family(%Ir.Listener{protocol: :tls_passthrough}), do: :https
  defp port_family(%Ir.Listener{protocol: :tls_terminate}), do: :https
  defp port_family(%Ir.Listener{protocol: protocol}), do: protocol

  defp overlapping_tls?(%Ir.Listener{protocol: :https} = l, peers) do
    Enum.any?(peers, fn p ->
      p.protocol == :https and p.name != l.name and Hostname.overlap?(l.hostname, p.hostname)
    end)
  end

  defp overlapping_tls?(_listener, _peers), do: false
end
