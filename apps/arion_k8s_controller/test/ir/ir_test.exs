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

defmodule Arion.K8sController.IrTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.Ir

  test "fleet is one per Gateway, across namespaces" do
    assert Ir.Gateway.fleet("default", "demo") == "gateway/default/demo"
    assert Ir.Gateway.fleet?("gateway/default/demo")
    refute Ir.Gateway.fleet?("arion")

    assert Ir.Gateway.fleet("default", "a-b") != Ir.Gateway.fleet("default-a", "b")
  end

  test "object_name is a Kubernetes name, hashed when sanitizing changed it" do
    assert Ir.Gateway.object_name("default", "demo") == "gateway-default-demo"
    assert Ir.Gateway.object_name("default", "a-b") == "gateway-default-a-b"
    assert Ir.Gateway.object_name("default", "a.b") == "gateway-default-a-b-e10bb70e34"
  end

  test "long Gateway names fit Kubernetes' 63 characters, keeping a stable hash" do
    ns = "gateway-conformance-infra"
    name = "gateway-with-infrastructure-metadata"

    assert Ir.Gateway.object_name(ns, name) ==
             "gateway-gateway-conformance-infra-gateway-with-infra-4bcd60aeae"

    assert Ir.Gateway.object_name(ns, name <> "-2") ==
             "gateway-gateway-conformance-infra-gateway-with-infra-b2c58828b3"

    long_name = String.duplicate("very-long-gateway-name.", 3) <> "x"
    assert Ir.Gateway.name_label(%Ir.Gateway{name: "demo"}) == "demo"

    assert Ir.Gateway.name_label(%Ir.Gateway{name: long_name}) ==
             "very-long-gateway-name.very-long-gateway-name.very-l-5f52b95009"
  end

  test "only accepted listeners are programmed, and HTTPS also needs a certificate" do
    cert = %{sds_name: "secret:default/app-cert", cert_pem: "CERT", key_pem: "KEY"}
    https = %Ir.Listener{protocol: :https, tls: %Ir.Tls{certificates: [cert]}}
    conflicted = %{https | conflict: "ProtocolConflict"}

    assert Ir.Listener.programmed?(https)
    assert Ir.Listener.accepted?(%{https | tls: %Ir.Tls{}})
    refute Ir.Listener.programmed?(%{https | tls: %Ir.Tls{}})
    refute Ir.Listener.programmed?(%{https | tls: nil})

    assert Ir.Listener.supported?(conflicted)
    refute Ir.Listener.accepted?(conflicted)
    refute Ir.Listener.programmed?(conflicted)

    assert Ir.Listener.programmed?(%Ir.Listener{protocol: :tcp})
    refute Ir.Listener.supported?(%Ir.Listener{protocol: :udp})
    refute Ir.Listener.programmed?(%Ir.Listener{protocol: :udp})
  end
end
