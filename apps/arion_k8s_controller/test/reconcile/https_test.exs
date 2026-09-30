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

defmodule Arion.K8sController.Reconcile.HttpsTest do
  use ExUnit.Case, async: true

  alias Arion.ControlPlane.Pb.Data.Extensions.{DownstreamTlsContext, Secret}
  alias Arion.ControlPlane.Pb.Filter.HttpConnectionManager
  alias Arion.ControlPlane.Pb.Listener.Listener
  alias Arion.K8sController.Fixtures
  alias Arion.K8sController.Reconcile.{Resolver, Translator}

  defp translate(objects) do
    objects
    |> Fixtures.snapshot()
    |> Resolver.resolve(Fixtures.controller_name())
    |> Translator.translate()
  end

  defp resolve_listener(objects) do
    graph = objects |> Fixtures.snapshot() |> Resolver.resolve(Fixtures.controller_name())
    [%{listeners: [listener]}] = graph.gateways
    {listener, Translator.translate(graph)["gateway/default/demo"]}
  end

  defp secret_grant(opts) do
    [namespace: "certs", from_kind: "Gateway", to: [%{"group" => "", "kind" => "Secret"}]]
    |> Keyword.merge(opts)
    |> Fixtures.reference_grant()
  end

  defp tls_chain!(resources) do
    [chain] = resources.listener["default-demo-443"].filter_chains
    assert chain.transport_socket.name == "envoy.transport_sockets.tls"
    chain
  end

  defp redirect(listener) do
    [chain] = listener.filter_chains
    [filter] = chain.filters
    {:typed_config, any} = filter.config_type
    {:route_config, route_config} = HttpConnectionManager.decode(any.value).route_specifier

    [%{routes: [%{action: {:redirect, redirect}}]}] =
      Enum.filter(route_config.virtual_hosts, &(&1.domains != ["*"]))

    redirect
  end

  test "HTTPS listener produces an SDS secret and a TLS listener with an SNI chain" do
    tls_secret = Fixtures.tls_secret(name: "app-cert")
    cert_pem = Base.decode64!(tls_secret["data"]["tls.crt"])

    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.https_gateway(),
        tls_secret,
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route()
      ])["gateway/default/demo"]

    assert %{"secret:default/app-cert" => %Secret{} = secret} = resources.secret
    assert {:tls_certificate, cert} = secret.type
    assert {:inline_bytes, ^cert_pem} = cert.certificate_chain.specifier
    assert {:inline_bytes, "-----BEGIN PRIVATE KEY-----" <> _} = cert.private_key.specifier

    assert %{"default-demo-443" => %Listener{} = listener} = resources.listener
    assert [chain] = listener.filter_chains
    assert chain.filter_chain_match.server_names == ["app.example.com"]
    assert chain.transport_socket.name == "envoy.transport_sockets.tls"
    assert [_tls_inspector] = listener.listener_filters

    # The proxy NACKs a listener whose TLS context sets alpn_protocols.
    {:typed_config, any} = chain.transport_socket.config_type
    tls_context = DownstreamTlsContext.decode(any.value).common_tls_context
    assert [%{name: "secret:default/app-cert"}] = tls_context.tls_certificate_sds_secret_configs
    assert tls_context.alpn_protocols == []
  end

  test "a hostname redirect on an HTTPS listener keeps https and its default port" do
    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.https_gateway(),
        Fixtures.tls_secret(name: "app-cert"),
        Fixtures.http_route(
          rules: [
            %{
              "filters" => [
                %{
                  "type" => "RequestRedirect",
                  "requestRedirect" => %{"hostname" => "example.org"}
                }
              ]
            }
          ]
        )
      ])["gateway/default/demo"]

    redirect = redirect(resources.listener["default-demo-443"])
    assert redirect.scheme_rewrite_specifier == {:scheme_redirect, "https"}
    assert redirect.host_redirect == "example.org"
    assert redirect.port_redirect == 0
  end

  test "an HTTPS listener without a usable certificate is not translated" do
    assert translate([
             Fixtures.gateway_class(),
             Fixtures.https_gateway(),
             Fixtures.service(name: "app-svc"),
             Fixtures.http_route()
           ]) == %{}
  end

  test "HTTPS listeners sharing a port get chains only when they have a certificate" do
    https = fn name, hostname, cert ->
      %{
        "name" => name,
        "port" => 443,
        "protocol" => "HTTPS",
        "hostname" => hostname,
        "tls" => %{"certificateRefs" => [%{"name" => cert}]},
        "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
      }
    end

    resources =
      translate([
        Fixtures.gateway_class(),
        Fixtures.gateway(
          listeners: [
            https.("app", "app.example.com", "app-cert"),
            https.("other", "other.example.com", "missing-cert")
          ]
        ),
        Fixtures.tls_secret(name: "app-cert"),
        Fixtures.service(name: "app-svc"),
        Fixtures.http_route(hostnames: ["app.example.com", "other.example.com"])
      ])["gateway/default/demo"]

    assert Map.keys(resources.secret) == ["secret:default/app-cert"]
    assert [chain] = resources.listener["default-demo-443"].filter_chains
    assert chain.filter_chain_match.server_names == ["app.example.com"]
    assert chain.transport_socket.name == "envoy.transport_sockets.tls"
  end

  test "an HTTPS listener ships only the certificate it serves" do
    gateway =
      Fixtures.gateway(
        listeners: [
          %{
            "name" => "https",
            "port" => 443,
            "protocol" => "HTTPS",
            "tls" => %{"certificateRefs" => [%{"name" => "app-cert"}, %{"name" => "old-cert"}]}
          }
        ]
      )

    resources =
      translate([
        Fixtures.gateway_class(),
        gateway,
        Fixtures.tls_secret(name: "app-cert"),
        Fixtures.tls_secret(name: "old-cert")
      ])["gateway/default/demo"]

    assert Map.keys(resources.secret) == ["secret:default/app-cert"]
  end

  @cross_namespace_ref %{"name" => "app-cert", "namespace" => "certs"}

  test "a cross-namespace certificateRef needs a ReferenceGrant for the Secret" do
    objects = [
      Fixtures.gateway_class(),
      Fixtures.https_gateway(certificate_refs: [@cross_namespace_ref]),
      Fixtures.tls_secret(name: "app-cert", namespace: "certs")
    ]

    assert {%{resolved_reason: "RefNotPermitted"}, nil} = resolve_listener(objects)

    for to <- [%{"group" => "", "kind" => "Secret"}, %{"kind" => "Secret", "name" => "app-cert"}] do
      {listener, resources} = resolve_listener([secret_grant(to: [to]) | objects])
      assert listener.resolved_reason == "ResolvedRefs"
      assert Map.keys(resources.secret) == ["secret:certs/app-cert"]
      tls_chain!(resources)
    end
  end

  test "a ReferenceGrant wrong in any one field does not permit a certificateRef" do
    # Mirrors the grants of gateway-secret-invalid-reference-grant.yaml.
    for grant <- [
          secret_grant(namespace: "other"),
          secret_grant(from_group: "not-the-group"),
          secret_grant(from_group: nil),
          secret_grant(from_kind: "HTTPRoute"),
          secret_grant(from_namespace: "other"),
          secret_grant(to: [%{"group" => "not-the-group", "kind" => "Secret"}]),
          secret_grant(to: [%{"group" => "", "kind" => "Service"}]),
          secret_grant(to: [%{"group" => "", "kind" => "Secret", "name" => "other-cert"}])
        ] do
      assert {%{resolved_reason: "RefNotPermitted"}, nil} =
               resolve_listener([
                 Fixtures.gateway_class(),
                 Fixtures.https_gateway(certificate_refs: [@cross_namespace_ref]),
                 Fixtures.tls_secret(name: "app-cert", namespace: "certs"),
                 grant
               ])
    end
  end

  test "missing, unsupported and malformed certificateRefs are InvalidCertificateRef" do
    hello = Base.encode64("Hello world\n")

    # Mirrors gateway-invalid-tls-configuration.yaml.
    for ref <- [
          %{"name" => "nonexistent-certificate"},
          %{"group" => "wrong.group.company.io", "kind" => "Secret", "name" => "app-cert"},
          %{"group" => "", "kind" => "WrongKind", "name" => "app-cert"},
          %{"name" => "malformed-certificate"}
        ] do
      assert {%{resolved_reason: "InvalidCertificateRef"}, nil} =
               resolve_listener([
                 Fixtures.gateway_class(),
                 Fixtures.https_gateway(certificate_refs: [ref]),
                 Fixtures.tls_secret(name: "app-cert"),
                 Fixtures.tls_secret(
                   name: "malformed-certificate",
                   data: %{"tls.crt" => hello, "tls.key" => hello}
                 )
               ])
    end
  end

  test "a listener serves its usable certificate and reports RefNotPermitted over invalid refs" do
    {listener, resources} =
      resolve_listener([
        Fixtures.gateway_class(),
        Fixtures.https_gateway(
          certificate_refs: [
            %{"name" => "missing"},
            @cross_namespace_ref,
            %{"name" => "app-cert"}
          ]
        ),
        Fixtures.tls_secret(name: "app-cert", namespace: "certs"),
        Fixtures.tls_secret(name: "app-cert")
      ])

    assert listener.resolved_reason == "RefNotPermitted"
    assert Map.keys(resources.secret) == ["secret:default/app-cert"]
    tls_chain!(resources)
  end
end
