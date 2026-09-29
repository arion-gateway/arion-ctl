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

defmodule Arion.K8sController.Kube.Gvk do
  @moduledoc """
  Kubernetes Group/Version/Kind keys watched by the controller.

  Gateway API standard-channel kinds are `gateway.networking.k8s.io/v1`.
  """

  @gateway_group "gateway.networking.k8s.io"

  @gateway_class {@gateway_group, "v1", "GatewayClass"}
  @gateway {@gateway_group, "v1", "Gateway"}
  @http_route {@gateway_group, "v1", "HTTPRoute"}
  @grpc_route {@gateway_group, "v1", "GRPCRoute"}
  @reference_grant {@gateway_group, "v1", "ReferenceGrant"}
  @tls_route {@gateway_group, "v1", "TLSRoute"}
  @tcp_route {@gateway_group, "v1", "TCPRoute"}
  @udp_route {@gateway_group, "v1", "UDPRoute"}
  @inference_pool {"inference.networking.k8s.io", "v1", "InferencePool"}
  @namespace {"", "v1", "Namespace"}
  @service {"", "v1", "Service"}
  @pod {"", "v1", "Pod"}
  @secret {"", "v1", "Secret"}
  @deployment {"apps", "v1", "Deployment"}
  @endpoint_slice {"discovery.k8s.io", "v1", "EndpointSlice"}
  @params {"arion.io", "v1alpha1", "ArionGatewayParameters"}

  @all [
    @gateway_class,
    @gateway,
    @http_route,
    @grpc_route,
    @reference_grant,
    @tls_route,
    @tcp_route,
    @udp_route,
    @inference_pool,
    @namespace,
    @service,
    @pod,
    @secret,
    @deployment,
    @endpoint_slice,
    @params
  ]

  @route_kinds [
    http: @http_route,
    grpc: @grpc_route,
    tls: @tls_route,
    tcp: @tcp_route,
    udp: @udp_route
  ]

  def all, do: @all

  def gateway_class, do: @gateway_class
  def gateway, do: @gateway
  def http_route, do: @http_route
  def grpc_route, do: @grpc_route
  def reference_grant, do: @reference_grant
  def tls_route, do: @tls_route
  def tcp_route, do: @tcp_route
  def udp_route, do: @udp_route
  def inference_pool, do: @inference_pool
  def namespace, do: @namespace
  def service, do: @service
  def pod, do: @pod
  def secret, do: @secret
  def deployment, do: @deployment
  def endpoint_slice, do: @endpoint_slice
  def params, do: @params

  def gateway_group, do: @gateway_group

  @doc "Route kinds as `{ir_kind, gvk}` pairs."
  def route_kinds, do: @route_kinds

  def route(kind), do: Keyword.fetch!(@route_kinds, kind)

  def route_kind_name(kind), do: kind(route(kind))

  def api_version({"", version, _kind}), do: version
  def api_version({group, version, _kind}), do: "#{group}/#{version}"

  def kind({_group, _version, kind}), do: kind

  def namespaced?(@gateway_class), do: false
  def namespaced?(@namespace), do: false
  def namespaced?(_gvk), do: true
end
