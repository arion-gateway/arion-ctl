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

defmodule Arion.K8sController.Reconcile.InferenceTest do
  use ExUnit.Case, async: true

  alias Arion.ControlPlane.Helpers.Xds

  alias Arion.ControlPlane.Pb.Data.Extensions.{
    ExternalProcessor,
    ExtProcPerRoute,
    OverrideHost,
    ProcessingMode,
    UpstreamTlsContext
  }

  alias Arion.ControlPlane.Pb.Filter.HttpConnectionManager
  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Reconcile.{Resolver, Translator}

  @full_duplex %ProcessingMode{
    request_header_mode: :SEND,
    response_header_mode: :SEND,
    request_body_mode: :FULL_DUPLEX_STREAMED,
    response_body_mode: :FULL_DUPLEX_STREAMED,
    request_trailer_mode: :SEND,
    response_trailer_mode: :SEND
  }

  defp resolve_translate(objects) do
    objects
    |> Fixtures.snapshot()
    |> Resolver.resolve(Fixtures.controller_name())
    |> Translator.translate()
    |> Map.fetch!("gateway/default/demo")
  end

  defp hcm(listener) do
    [chain] = listener.filter_chains
    [filter] = chain.filters
    {:typed_config, any} = filter.config_type
    HttpConnectionManager.decode(any.value)
  end

  defp routes(hcm) do
    {:route_config, route_config} = hcm.route_specifier
    route_config.virtual_hosts |> Enum.flat_map(& &1.routes)
  end

  defp ext_proc_config(route) do
    route.typed_per_filter_config["envoy.filters.http.ext_proc"]
    |> then(&ExtProcPerRoute.decode(&1.value))
  end

  defp assignments(resources) do
    Map.new(Map.get(resources, :load_assignment, %{}), fn {name, assignment} ->
      [locality] = assignment.endpoints

      {name,
       for %{host_identifier: {:endpoint, endpoint}, health_status: :HEALTHY} <-
             locality.lb_endpoints do
         {:socket_address, socket} = endpoint.address.address
         {:port_value, port} = socket.port_specifier
         {socket.address, port}
       end}
    end)
  end

  defp assert_override_host(cluster) do
    assert cluster.cluster_discovery_type == {:type, :EDS}
    assert cluster.lb_config == nil
    assert [policy] = cluster.load_balancing_policy.policies
    assert policy.typed_extension_config.typed_config.type_url == Xds.type_url(:lb_override_host)

    override = OverrideHost.decode(policy.typed_extension_config.typed_config.value)
    assert [%{header: "x-gateway-destination-endpoint"}] = override.override_host_sources
    assert [fallback] = override.fallback_policy.policies
    assert fallback.typed_extension_config.typed_config.type_url == Xds.type_url(:lb_round_robin)
  end

  defp pool_objects(objects) do
    [
      Fixtures.gateway_class(),
      Fixtures.gateway(),
      Fixtures.service(name: "llm-epp", port: 9002) | objects
    ]
  end

  test "InferencePool routes produce an OverrideHost pool, EPP, listener ext_proc and per-route config" do
    resources =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.service(name: "llm-epp", port: 9002),
        Fixtures.inference_pool(failure_mode: "FailOpen"),
        Fixtures.http_route(),
        Fixtures.inference_http_route()
      ])

    assert_override_host(resources.cluster["inferencepool:default/llm-pool"])

    epp_cluster = resources.cluster["epp:default/llm-epp:9002"]
    assert epp_cluster.cluster_discovery_type == {:type, :STRICT_DNS}

    assert Map.has_key?(
             epp_cluster.typed_extension_protocol_options,
             "envoy.extensions.upstreams.http.v3.HttpProtocolOptions"
           )

    hcm = resources.listener["default-demo-80"] |> hcm()

    assert Enum.map(hcm.http_filters, & &1.name) == [
             "envoy.filters.http.ext_proc",
             "envoy.filters.http.router"
           ]

    route_by_name = hcm |> routes() |> Map.new(&{&1.name, &1})

    inference_route = route_by_name["default/infer"]
    assert {:route, action} = inference_route.action
    assert action.cluster_specifier == {:cluster, "inferencepool:default/llm-pool"}

    assert {:overrides, overrides} = ext_proc_config(inference_route).override
    assert overrides.processing_mode == @full_duplex
    assert {:envoy_grpc, envoy_grpc} = overrides.grpc_service.target_specifier
    assert envoy_grpc.cluster_name == "epp:default/llm-epp:9002"
    assert overrides.failure_mode_allow.value

    service_route = route_by_name["default/app"]
    assert {:disabled, true} = ext_proc_config(service_route).override
  end

  test "the listener ext_proc filter streams bodies full duplex and forwards envoy.lb metadata" do
    resources =
      resolve_translate(
        pool_objects([Fixtures.inference_pool(), Fixtures.inference_http_route()])
      )

    hcm = resources.listener["default-demo-80"] |> hcm()

    assert [%{name: "envoy.filters.http.ext_proc", config_type: {:typed_config, any}} | _] =
             hcm.http_filters

    ext_proc = ExternalProcessor.decode(any.value)
    assert ext_proc.processing_mode == @full_duplex
    assert ext_proc.send_body_without_waiting_for_header_response
    assert ext_proc.message_timeout == %Google.Protobuf.Duration{seconds: 1000}
    assert ext_proc.metadata_options.forwarding_namespaces.untyped == ["envoy.lb"]

    assert {:envoy_grpc, %{cluster_name: "epp:default/llm-epp:9002"}} =
             ext_proc.grpc_service.target_specifier
  end

  test "the EPP cluster speaks TLS without verification" do
    resources =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "llm-epp", port: 9002),
        Fixtures.inference_pool(),
        Fixtures.inference_pool(name: "h2c-pool", app_protocol: "kubernetes.io/h2c"),
        Fixtures.inference_http_route(),
        Fixtures.inference_http_route(name: "infer-h2c", pool_name: "h2c-pool")
      ])

    epp_cluster = resources.cluster["epp:default/llm-epp:9002"]
    assert epp_cluster.transport_socket.name == "envoy.transport_sockets.tls"
    assert {:typed_config, any} = epp_cluster.transport_socket.config_type

    assert any.type_url ==
             "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext"

    tls = UpstreamTlsContext.decode(any.value)
    assert tls.sni == "llm-epp.default.svc.cluster.local"
    assert tls.common_tls_context.alpn_protocols == []
    assert {:validation_context, validation} = tls.common_tls_context.validation_context_type
    assert validation.trust_chain_verification == :ACCEPT_UNTRUSTED
    assert {:inline_string, "-----BEGIN CERTIFICATE-----" <> _} = validation.trusted_ca.specifier

    assert Map.has_key?(
             epp_cluster.typed_extension_protocol_options,
             "envoy.extensions.upstreams.http.v3.HttpProtocolOptions"
           )

    assert resources.cluster["inferencepool:default/llm-pool"].transport_socket == nil
    assert resources.cluster["inferencepool:default/h2c-pool/h2"].transport_socket == nil
  end

  test "a weight-0 InferencePool does not pick endpoints for the other backends" do
    pool = %{
      "group" => "inference.networking.k8s.io",
      "kind" => "InferencePool",
      "name" => "llm-pool",
      "port" => 8000,
      "weight" => 0
    }

    rules = [
      %{
        "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
        "backendRefs" => [pool, %{"name" => "app-svc", "port" => 8080, "weight" => 1}]
      }
    ]

    resources =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "app-svc"),
        Fixtures.service(name: "llm-epp", port: 9002),
        Fixtures.inference_pool(),
        Fixtures.http_route(rules: rules)
      ])

    hcm = resources.listener["default-demo-80"] |> hcm()
    assert Enum.map(hcm.http_filters, & &1.name) == ["envoy.filters.http.router"]

    [route] = routes(hcm)
    assert {:route, action} = route.action
    assert action.cluster_specifier == {:cluster, "svc:default/app-svc:8080"}
    refute Map.has_key?(route.typed_per_filter_config, "envoy.filters.http.ext_proc")
  end

  test "h2c InferencePool routes configure the pool cluster for HTTP/2" do
    resources =
      resolve_translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(),
        Fixtures.service(name: "llm-epp", port: 9002),
        Fixtures.inference_pool(
          name: "h2c-pool",
          app_protocol: "kubernetes.io/h2c",
          target_ports: [%{"number" => 3001}]
        ),
        Fixtures.inference_http_route(pool_name: "h2c-pool"),
        Fixtures.pod(labels: %{"app" => "h2c-pool"})
      ])

    pool_cluster = resources.cluster["inferencepool:default/h2c-pool/h2"]
    assert_override_host(pool_cluster)

    assert Map.has_key?(
             pool_cluster.typed_extension_protocol_options,
             "envoy.extensions.upstreams.http.v3.HttpProtocolOptions"
           )

    assert assignments(resources) == %{
             "inferencepool:default/h2c-pool/h2" => [{"10.1.0.1", 3001}]
           }
  end

  test "a pool is assigned its ready selected pods once per targetPort" do
    resources =
      resolve_translate(
        pool_objects([
          Fixtures.inference_pool(target_ports: [%{"number" => 3000}, %{"number" => 3002}]),
          Fixtures.inference_http_route(),
          Fixtures.pod(name: "b", ip: "10.1.0.2"),
          Fixtures.pod(name: "a", ip: "10.1.0.1"),
          Fixtures.pod(name: "c", ip: "10.1.0.3", ready: false),
          Fixtures.pod(name: "d", ip: "10.1.0.4", deleting?: true),
          Fixtures.pod(name: "e", ip: "10.1.0.5", namespace: "other"),
          Fixtures.pod(name: "f", ip: "10.1.0.6", labels: %{"app" => "other"}),
          Fixtures.pod(name: "g", ip: nil)
        ])
      )

    assert assignments(resources) == %{
             "inferencepool:default/llm-pool" => [
               {"10.1.0.1", 3000},
               {"10.1.0.1", 3002},
               {"10.1.0.2", 3000},
               {"10.1.0.2", 3002}
             ]
           }
  end

  test "a multi-label selector requires every label" do
    selector = %{"app" => "llm", "tier" => "gpu"}

    resources =
      resolve_translate(
        pool_objects([
          Fixtures.inference_pool(selector: selector),
          Fixtures.inference_http_route(),
          Fixtures.pod(name: "all", ip: "10.1.0.1", labels: Map.put(selector, "extra", "x")),
          Fixtures.pod(name: "app-only", ip: "10.1.0.2", labels: %{"app" => "llm"}),
          Fixtures.pod(name: "tier-only", ip: "10.1.0.3", labels: %{"tier" => "gpu"})
        ])
      )

    assert assignments(resources) == %{"inferencepool:default/llm-pool" => [{"10.1.0.1", 8000}]}
  end

  test "an absent or empty selector selects no pods" do
    absent = Fixtures.inference_pool(name: "absent")

    resources =
      resolve_translate(
        pool_objects([
          Fixtures.inference_pool(),
          update_in(absent["spec"], &Map.delete(&1, "selector")),
          Fixtures.inference_pool(name: "empty", selector: %{}),
          Fixtures.inference_http_route(),
          Fixtures.inference_http_route(name: "absent", pool_name: "absent"),
          Fixtures.inference_http_route(name: "empty", pool_name: "empty"),
          Fixtures.pod()
        ])
      )

    assert Map.has_key?(resources.cluster, "inferencepool:default/absent")
    assert Map.has_key?(resources.cluster, "inferencepool:default/empty")
    assert assignments(resources) == %{"inferencepool:default/llm-pool" => [{"10.1.0.1", 8000}]}
  end

  test "a dual-stack pod uses its IPv4 address" do
    resources =
      resolve_translate(
        pool_objects([
          Fixtures.inference_pool(),
          Fixtures.inference_http_route(),
          Fixtures.pod(ip: "fd00::1", pod_ips: ["fd00::1", "10.1.0.1"])
        ])
      )

    assert assignments(resources) == %{"inferencepool:default/llm-pool" => [{"10.1.0.1", 8000}]}
  end

  test "a pool without ready pods keeps its cluster but gets no load assignment" do
    resources =
      resolve_translate(
        pool_objects([
          Fixtures.inference_pool(),
          Fixtures.inference_http_route(),
          Fixtures.pod(ready: false)
        ])
      )

    assert_override_host(resources.cluster["inferencepool:default/llm-pool"])
    refute Map.has_key?(resources, :load_assignment)
  end

  test "FailOpen and FailClose pools have the same cluster shape" do
    resources =
      resolve_translate(
        pool_objects([
          Fixtures.inference_pool(name: "open", failure_mode: "FailOpen"),
          Fixtures.inference_pool(name: "close", failure_mode: "FailClose"),
          Fixtures.inference_http_route(name: "open", pool_name: "open"),
          Fixtures.inference_http_route(name: "close", pool_name: "close")
        ])
      )

    open = resources.cluster["inferencepool:default/open"]
    assert_override_host(open)
    assert %{open | name: nil} == %{resources.cluster["inferencepool:default/close"] | name: nil}
  end

  test "pools selecting the same pods on different targetPorts get distinct assignments" do
    selector = %{"app" => "llm"}

    resources =
      resolve_translate(
        pool_objects([
          Fixtures.inference_pool(
            name: "http",
            selector: selector,
            target_ports: [%{"number" => 3000}]
          ),
          Fixtures.inference_pool(
            name: "h2c",
            selector: selector,
            target_ports: [%{"number" => 3001}]
          ),
          Fixtures.inference_http_route(name: "http", pool_name: "http"),
          Fixtures.inference_http_route(name: "h2c", pool_name: "h2c"),
          Fixtures.pod(labels: selector)
        ])
      )

    assert assignments(resources) == %{
             "inferencepool:default/http" => [{"10.1.0.1", 3000}],
             "inferencepool:default/h2c" => [{"10.1.0.1", 3001}]
           }
  end

  test "a GRPCRoute to a pool without appProtocol configures the pool cluster for HTTP/2" do
    pool_ref = %{
      "group" => "inference.networking.k8s.io",
      "kind" => "InferencePool",
      "name" => "grpc-pool",
      "port" => 8000
    }

    resources =
      resolve_translate(
        pool_objects([
          Fixtures.inference_pool(),
          Fixtures.inference_pool(name: "grpc-pool"),
          Fixtures.inference_http_route(),
          Fixtures.grpc_route(rules: [%{"backendRefs" => [pool_ref]}])
        ])
      )

    h2? = fn cluster ->
      Map.has_key?(
        cluster.typed_extension_protocol_options,
        "envoy.extensions.upstreams.http.v3.HttpProtocolOptions"
      )
    end

    assert h2?.(resources.cluster["inferencepool:default/grpc-pool/h2"])
    refute h2?.(resources.cluster["inferencepool:default/llm-pool"])
  end
end
