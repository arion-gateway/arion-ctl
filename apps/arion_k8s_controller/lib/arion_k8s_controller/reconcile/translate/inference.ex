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

defmodule Arion.K8sController.Reconcile.Translate.Inference do
  @moduledoc """
  Builds xDS resources for Gateway API Inference Extension routes.

  A pool's cluster lists its ready pods and routes to the endpoint the EPP names in
  `x-gateway-destination-endpoint`; a comma-separated list fails over in order. A
  missing header or one naming no pool endpoint goes round robin across the pool,
  which serves FailOpen when the EPP is unavailable.

  The EPP picks from the request body and answers the request headers only after the
  whole body, so ext_proc streams bodies full duplex, as in the GIE reference config.
  It forwards `envoy.lb` metadata, where the proxy reports the served endpoint.
  """

  alias Arion.ControlPlane.Helpers.{Cluster, ExtProc, Route, Tls, Xds}
  alias Arion.K8sController.Ir
  alias Arion.K8sController.Reconcile.Translate.Backend

  @destination_header "x-gateway-destination-endpoint"
  @filter_name "envoy.filters.http.ext_proc"

  def pool_cluster(%Ir.Backend{} = backend) do
    backend
    |> Backend.eds_cluster()
    |> Cluster.lb({:override_host_header, @destination_header, :round_robin})
  end

  # The EPP serves gRPC over TLS with a self-signed, SAN-less certificate by default
  # (--secure-serving) and InferencePool v1 has no TLS settings, so the certificate is not
  # verified, as in the GIE reference config. ALPN h2 follows from the HTTP/2 options.
  def epp_cluster(%Ir.Backend{epp: epp}) do
    epp.cluster_name
    |> Cluster.strict_dns(epp.dns_name, [epp.port])
    |> Cluster.put_http_protocol_options(Cluster.http2_options())
    |> Cluster.put_transport_socket(Tls.upstream_accept_untrusted(epp.dns_name))
  end

  def ext_proc_filter(base_epp_cluster_name) do
    ExtProc.filter(
      @filter_name,
      ExtProc.processor(
        Xds.grpc_service(:envoy, base_epp_cluster_name),
        processing_mode: processing_mode(),
        message_timeout: 1000,
        send_body_without_waiting_for_header_response: true,
        metadata_options: ExtProc.metadata_options(forwarding_untyped: ["envoy.lb"])
      )
    )
  end

  def per_route_enable(route, %Ir.Backend{epp: epp}) do
    Route.put_per_filter_config(
      route,
      @filter_name,
      :ext_proc_per_route,
      ExtProc.per_route_overrides(
        grpc_service: Xds.grpc_service(:envoy, epp.cluster_name),
        processing_mode: processing_mode(),
        failure_mode_allow: epp.failure_mode == "FailOpen"
      )
    )
  end

  def per_route_disable(route) do
    Route.put_per_filter_config(
      route,
      @filter_name,
      :ext_proc_per_route,
      ExtProc.per_route_disabled()
    )
  end

  defp processing_mode do
    ExtProc.processing_mode(
      request_header_mode: :SEND,
      response_header_mode: :SEND,
      request_body_mode: :FULL_DUPLEX_STREAMED,
      response_body_mode: :FULL_DUPLEX_STREAMED,
      request_trailer_mode: :SEND,
      response_trailer_mode: :SEND
    )
  end
end
