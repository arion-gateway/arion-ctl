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

defmodule Arion.K8sController.Reconcile.ListenerIsolationTest do
  use ExUnit.Case, async: true

  alias Arion.ControlPlane.Pb.Filter.HttpConnectionManager
  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Reconcile.{Resolver, Translator}

  defp resolve_translate(objects) do
    objects
    |> Fixtures.snapshot()
    |> Resolver.resolve(Fixtures.controller_name())
    |> Translator.translate()
  end

  defp listener_vhosts(xds, listener_name) do
    %{"gateway/default/demo" => resources} = xds
    listener = resources.listener[listener_name]

    for chain <- listener.filter_chains, into: %{} do
      [filter] = chain.filters
      {:typed_config, any} = filter.config_type
      {:route_config, config} = HttpConnectionManager.decode(any.value).route_specifier
      {chain.name, config.virtual_hosts}
    end
  end

  defp http_listener(name, hostname) do
    %{
      "name" => name,
      "port" => 80,
      "protocol" => "HTTP",
      "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
    }
    |> then(&if hostname, do: Map.put(&1, "hostname", hostname), else: &1)
  end

  defp route(name, section, hostnames, path) do
    Fixtures.http_route(
      name: name,
      parent_refs: [%{"name" => "demo", "sectionName" => section}],
      hostnames: hostnames,
      rules: [
        %{
          "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => path}}],
          "backendRefs" => [%{"name" => "app-svc", "port" => 8080}]
        }
      ]
    )
  end

  defp vhost(vhosts, domain), do: Enum.find(vhosts, &(&1.domains == [domain]))
  defp route_names(vhost), do: Enum.map(vhost.routes, & &1.name)
  defp direct_status(vhost), do: elem(hd(vhost.routes).action, 1).status

  test "a broad listener does not serve domains a more specific sibling owns" do
    gateway =
      Fixtures.gateway(
        listeners: [
          http_listener("empty", nil),
          http_listener("wildcard", "*.example.com"),
          http_listener("exact", "abc.example.com")
        ]
      )

    objects = [
      Fixtures.gateway_class(),
      gateway,
      Fixtures.service(name: "app-svc"),
      route("on-empty", "empty", ["bar.com", "*.example.com"], "/empty"),
      route("on-wildcard", "wildcard", [], "/wildcard")
    ]

    %{"main" => vhosts} =
      objects
      |> resolve_translate()
      |> listener_vhosts("default-demo-80")
      |> Map.new(fn {_k, v} -> {"main", v} end)

    assert route_names(vhost(vhosts, "bar.com")) == ["default/on-empty"]
    assert route_names(vhost(vhosts, "*.example.com")) == ["default/on-wildcard"]
    assert direct_status(vhost(vhosts, "abc.example.com")) == 404
    refute vhost(vhosts, "*")
  end

  test "https chains answer 421 for hosts outside their hostname" do
    listeners = [
      %{
        "name" => "a",
        "port" => 443,
        "protocol" => "HTTPS",
        "hostname" => "a.example.com",
        "tls" => %{"mode" => "Terminate", "certificateRefs" => [%{"name" => "app-cert"}]},
        "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
      },
      %{
        "name" => "b",
        "port" => 443,
        "protocol" => "HTTPS",
        "hostname" => "b.example.com",
        "tls" => %{"mode" => "Terminate", "certificateRefs" => [%{"name" => "app-cert"}]},
        "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
      }
    ]

    objects = [
      Fixtures.gateway_class(),
      Fixtures.gateway(listeners: listeners),
      Fixtures.tls_secret(name: "app-cert"),
      Fixtures.service(name: "app-svc"),
      route("on-a", "a", [], "/")
    ]

    chains = objects |> resolve_translate() |> listener_vhosts("default-demo-443")

    a_vhosts = chains["default-demo-443-a"]
    assert route_names(vhost(a_vhosts, "a.example.com")) == ["default/on-a"]
    assert direct_status(vhost(a_vhosts, "*")) == 421

    b_vhosts = chains["default-demo-443-b"]
    assert direct_status(vhost(b_vhosts, "b.example.com")) == 404
    assert direct_status(vhost(b_vhosts, "*")) == 421
  end
end
