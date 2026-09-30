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

defmodule Arion.K8sController.Reconcile.EndpointsTest do
  @moduledoc """
  Service backends are EDS clusters assigned the Service's ready EndpointSlice
  endpoints on the port its targetPort resolves to.
  """
  use ExUnit.Case, async: true

  alias Arion.ControlPlane.Pb.Cluster.Cluster
  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Reconcile.{Resolver, Translator}

  test "a Service backend is an EDS cluster assigned its ready endpoints on the target port" do
    ports = [
      %{"name" => "http", "port" => 8080, "targetPort" => "web"},
      %{"name" => "metrics", "port" => 9090}
    ]

    resources =
      translate([
        Fixtures.service(ports: ports),
        Fixtures.endpoint_slice(
          name: "app-svc-a",
          ports: [%{"name" => "metrics", "port" => 9090}, %{"name" => "http", "port" => 3000}],
          endpoints: [
            Fixtures.endpoint("10.0.0.2"),
            Fixtures.endpoint("10.0.0.3", false),
            %{"addresses" => ["10.0.0.1"]}
          ]
        ),
        # The named targetPort is another number on these pods.
        Fixtures.endpoint_slice(
          name: "app-svc-b",
          ports: [%{"name" => "http", "port" => 3001}],
          addresses: ["10.0.0.4"]
        ),
        # An endpoint moving between slices is listed in both.
        Fixtures.endpoint_slice(
          name: "app-svc-c",
          ports: [%{"name" => "http", "port" => 3000}],
          addresses: ["10.0.0.2"]
        ),
        Fixtures.endpoint_slice(service: "other-svc", addresses: ["10.0.1.1"]),
        Fixtures.endpoint_slice(namespace: "elsewhere", addresses: ["10.0.2.1"]),
        route([%{"name" => "app-svc", "port" => 8080}])
      ])

    assert %Cluster{cluster_discovery_type: {:type, :EDS}, eds_cluster_config: nil} =
             resources.cluster["svc:default/app-svc:8080"]

    assert assignments(resources) == %{
             "svc:default/app-svc:8080" => [
               {"10.0.0.1", 3000},
               {"10.0.0.2", 3000},
               {"10.0.0.4", 3001}
             ]
           }
  end

  test "an unnamed Service port uses the unnamed EndpointSlice port" do
    resources =
      translate([
        Fixtures.service(ports: [%{"port" => 8080, "targetPort" => 3000}]),
        Fixtures.endpoint_slice(ports: [%{"name" => "", "port" => 3000, "protocol" => "TCP"}]),
        route([%{"name" => "app-svc", "port" => 8080}])
      ])

    assert assignments(resources) == %{"svc:default/app-svc:8080" => [{"10.0.0.1", 3000}]}
  end

  test "the backendRef port selects the Service's TCP port" do
    ports = [
      %{"name" => "dns", "port" => 53, "protocol" => "UDP"},
      %{"name" => "dns-tcp", "port" => 53, "protocol" => "TCP"}
    ]

    slice_ports = [
      %{"name" => "dns", "port" => 5353, "protocol" => "UDP"},
      %{"name" => "dns-tcp", "port" => 5354, "protocol" => "TCP"}
    ]

    resources =
      translate([
        Fixtures.service(ports: ports),
        Fixtures.endpoint_slice(ports: slice_ports),
        route([%{"name" => "app-svc", "port" => 53}])
      ])

    assert assignments(resources) == %{"svc:default/app-svc:53" => [{"10.0.0.1", 5354}]}
  end

  # Mirrors the HTTPRouteServiceTypes conformance test.
  test "headless and manually sliced Services reach their target port" do
    names = ["headless", "manual-endpointslices", "headless-manual-endpointslices"]
    ports = [%{"name" => "first-port", "protocol" => "TCP", "port" => 8080, "targetPort" => 3000}]
    slice_ports = [%{"name" => "first-port", "port" => 3000, "protocol" => "TCP"}]

    services = [
      Fixtures.service(name: "headless", ports: ports)
      |> put_in(["spec", "clusterIP"], "None")
      |> put_in(["spec", "selector"], %{"app" => "infra-backend-v1"}),
      Fixtures.service(name: "manual-endpointslices", ports: ports),
      Fixtures.service(name: "headless-manual-endpointslices", ports: ports)
      |> put_in(["spec", "clusterIP"], "None")
    ]

    slices =
      for name <- names, {family, endpoints} <- [{"IPv4", ["10.244.0.5"]}, {"IPv6", []}] do
        Fixtures.endpoint_slice(
          service: name,
          name: "#{name}-#{family}",
          address_type: family,
          ports: slice_ports,
          addresses: endpoints
        )
      end

    resources =
      translate(
        services ++ slices ++ [route(for name <- names, do: %{"name" => name, "port" => 8080})]
      )

    assert assignments(resources) ==
             Map.new(names, &{"svc:default/#{&1}:8080", [{"10.244.0.5", 3000}]})
  end

  test "IPv6 endpoints are used only when there are no IPv4 ones" do
    resources =
      translate([
        Fixtures.service(name: "dual"),
        Fixtures.endpoint_slice(service: "dual", name: "dual-4", addresses: ["10.0.0.1"]),
        Fixtures.endpoint_slice(
          service: "dual",
          name: "dual-6",
          address_type: "IPv6",
          addresses: ["fd00::1"]
        ),
        Fixtures.service(name: "v6"),
        Fixtures.endpoint_slice(service: "v6", address_type: "IPv6", addresses: ["fd00::2"]),
        Fixtures.service(name: "fqdn"),
        Fixtures.endpoint_slice(service: "fqdn", address_type: "FQDN", addresses: ["a.example"]),
        route(for name <- ["dual", "v6", "fqdn"], do: %{"name" => name, "port" => 8080})
      ])

    assert assignments(resources) == %{
             "svc:default/dual:8080" => [{"10.0.0.1", 8080}],
             "svc:default/v6:8080" => [{"fd00::2", 8080}]
           }

    assert Map.has_key?(resources.cluster, "svc:default/fqdn:8080")
  end

  test "a Service without ready endpoints on the port has a cluster but no assignment" do
    resources =
      translate([
        Fixtures.service(name: "none"),
        Fixtures.service(name: "not-ready"),
        Fixtures.endpoint_slice(
          service: "not-ready",
          endpoints: [Fixtures.endpoint("10.0.0.1", false)]
        ),
        route([
          %{"name" => "none", "port" => 8080},
          %{"name" => "not-ready", "port" => 8080}
        ])
      ])

    assert Map.keys(resources.cluster) == ["svc:default/none:8080", "svc:default/not-ready:8080"]
    refute Map.has_key?(resources, :load_assignment)
  end

  defp route(backend_refs), do: Fixtures.http_route(rules: [%{"backendRefs" => backend_refs}])

  defp translate(objects) do
    [Fixtures.gateway_class(), Fixtures.gateway() | objects]
    |> Fixtures.snapshot()
    |> Resolver.resolve(Fixtures.controller_name())
    |> Translator.translate()
    |> Map.fetch!("gateway/default/demo")
  end

  defp assignments(resources) do
    Map.new(Map.get(resources, :load_assignment, %{}), fn {name, assignment} ->
      [locality] = assignment.endpoints

      {name,
       for %{host_identifier: {:endpoint, endpoint}} <- locality.lb_endpoints do
         {:socket_address, socket} = endpoint.address.address
         {:port_value, port} = socket.port_specifier
         {socket.address, port}
       end}
    end)
  end
end
