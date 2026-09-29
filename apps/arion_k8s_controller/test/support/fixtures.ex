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

defmodule Arion.K8sController.Fixtures do
  @moduledoc """
  Gateway API fixtures as decoded Kubernetes object maps.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Reconcile.Translate.Http

  @controller "arion.io/gateway-controller"

  def controller_name, do: @controller

  def gateway_class(opts \\ []) do
    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "GatewayClass",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "arion"),
        "generation" => Keyword.get(opts, :generation, 1)
      },
      "spec" =>
        %{"controllerName" => Keyword.get(opts, :controller_name, @controller)}
        |> maybe_put("parametersRef", Keyword.get(opts, :params_ref))
    }
  end

  def gateway(opts \\ []) do
    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "Gateway",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "demo"),
        "namespace" => Keyword.get(opts, :namespace, "default"),
        "generation" => Keyword.get(opts, :generation, 1)
      },
      "spec" => %{
        "gatewayClassName" => Keyword.get(opts, :class_name, "arion"),
        "listeners" =>
          Keyword.get(opts, :listeners, [
            %{
              "name" => "http",
              "port" => 80,
              "protocol" => "HTTP",
              "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
            }
          ])
      }
    }
  end

  def service(opts \\ []) do
    %{
      "apiVersion" => "v1",
      "kind" => "Service",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "app-svc"),
        "namespace" => Keyword.get(opts, :namespace, "default")
      },
      "spec" => %{
        "ports" => Keyword.get(opts, :ports, [%{"port" => Keyword.get(opts, :port, 8080)}])
      }
    }
  end

  def endpoint_slice(opts \\ []) do
    service = Keyword.get(opts, :service, "app-svc")
    ready = for address <- Keyword.get(opts, :addresses, ["10.0.0.1"]), do: endpoint(address)

    %{
      "apiVersion" => "discovery.k8s.io/v1",
      "kind" => "EndpointSlice",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "#{service}-abcde"),
        "namespace" => Keyword.get(opts, :namespace, "default"),
        "labels" => %{"kubernetes.io/service-name" => service}
      },
      "addressType" => Keyword.get(opts, :address_type, "IPv4"),
      "ports" =>
        Keyword.get(opts, :ports, [%{"name" => "", "port" => 8080, "protocol" => "TCP"}]),
      "endpoints" => Keyword.get(opts, :endpoints, ready)
    }
  end

  def endpoint(address, ready \\ true),
    do: %{"addresses" => [address], "conditions" => %{"ready" => ready}}

  def inference_pool(opts \\ []) do
    name = Keyword.get(opts, :name, "llm-pool")
    namespace = Keyword.get(opts, :namespace, "default")
    epp_name = Keyword.get(opts, :epp_name, "llm-epp")
    epp_port = Keyword.get(opts, :epp_port, 9002)

    %{
      "apiVersion" => "inference.networking.k8s.io/v1",
      "kind" => "InferencePool",
      "metadata" => %{
        "name" => name,
        "namespace" => namespace,
        "generation" => Keyword.get(opts, :generation, 1)
      },
      "spec" =>
        %{
          "selector" => %{"matchLabels" => Keyword.get(opts, :selector, %{"app" => name})},
          "targetPorts" => Keyword.get(opts, :target_ports, [%{"number" => 8000}]),
          "endpointPickerRef" =>
            Keyword.get(opts, :endpoint_picker_ref, %{
              "name" => epp_name,
              "port" => %{"number" => epp_port},
              "failureMode" => Keyword.get(opts, :failure_mode, "FailClose")
            })
        }
        |> maybe_put("appProtocol", Keyword.get(opts, :app_protocol))
    }
  end

  def pod(opts \\ []) do
    ip = Keyword.get(opts, :ip, "10.1.0.1")
    ready = if Keyword.get(opts, :ready, true), do: "True", else: "False"
    deleted_at = if Keyword.get(opts, :deleting?, false), do: "2026-01-01T00:00:00Z"

    %{
      "apiVersion" => "v1",
      "kind" => "Pod",
      "metadata" =>
        %{
          "name" => Keyword.get(opts, :name, "llm-pod"),
          "namespace" => Keyword.get(opts, :namespace, "default"),
          "labels" => Keyword.get(opts, :labels, %{"app" => "llm-pool"})
        }
        |> maybe_put("deletionTimestamp", deleted_at),
      "status" =>
        %{
          "conditions" => [%{"type" => "Ready", "status" => ready}],
          "podIPs" => for(ip <- Keyword.get(opts, :pod_ips, List.wrap(ip)), do: %{"ip" => ip})
        }
        |> maybe_put("podIP", ip)
    }
  end

  def namespace(opts \\ []) do
    name = Keyword.get(opts, :name, "default")

    %{
      "apiVersion" => "v1",
      "kind" => "Namespace",
      "metadata" => %{
        "name" => name,
        "labels" => Keyword.get(opts, :labels, %{})
      }
    }
  end

  def provisioned_service(opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")
    gw = Keyword.get(opts, :gateway, "demo")

    %{
      "apiVersion" => "v1",
      "kind" => "Service",
      "metadata" => %{"name" => "gateway-#{ns}-#{gw}", "namespace" => ns},
      "spec" => %{"type" => "LoadBalancer"},
      "status" => %{
        "loadBalancer" => %{
          "ingress" => Keyword.get(opts, :ingress, [%{"ip" => "203.0.113.5"}])
        }
      }
    }
  end

  def provisioned_deployment(opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")
    gw = Keyword.get(opts, :gateway, "demo")

    %{
      "apiVersion" => "apps/v1",
      "kind" => "Deployment",
      "metadata" => %{"name" => "gateway-#{ns}-#{gw}", "namespace" => ns},
      "status" => %{"readyReplicas" => Keyword.get(opts, :ready_replicas, 1)}
    }
  end

  def gateway_params(opts \\ []) do
    %{
      "apiVersion" => "arion.io/v1alpha1",
      "kind" => "ArionGatewayParameters",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "arion-params"),
        "namespace" => Keyword.get(opts, :namespace, "default")
      },
      "spec" => Keyword.get(opts, :spec, %{})
    }
  end

  # One EC P-256 pair per compile keeps fixtures deterministic; the key is SEC1.
  %{cert: cert_der, key: key} =
    :public_key.pkix_test_root_cert(~c"app", [{:key, {:namedCurve, :secp256r1}}])

  @cert_pem :public_key.pem_encode([{:Certificate, cert_der, :not_encrypted}])
  @key_pem :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, key)])

  def tls_secret(opts \\ []) do
    data = %{
      "tls.crt" => Base.encode64(Keyword.get(opts, :cert, @cert_pem)),
      "tls.key" => Base.encode64(Keyword.get(opts, :key, @key_pem))
    }

    %{
      "apiVersion" => "v1",
      "kind" => "Secret",
      "type" => "kubernetes.io/tls",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "app-cert"),
        "namespace" => Keyword.get(opts, :namespace, "default")
      },
      "data" => Keyword.get(opts, :data, data)
    }
  end

  def https_gateway(opts \\ []) do
    listener = %{
      "name" => "https",
      "port" => 443,
      "protocol" => "HTTPS",
      "hostname" => "app.example.com",
      "tls" => %{
        "mode" => "Terminate",
        "certificateRefs" => Keyword.get(opts, :certificate_refs, [%{"name" => "app-cert"}])
      },
      "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
    }

    gateway(Keyword.merge([listeners: [listener]], opts))
  end

  def grpc_route(opts \\ []) do
    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "GRPCRoute",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "grpc"),
        "namespace" => Keyword.get(opts, :namespace, "default"),
        "generation" => 1,
        "creationTimestamp" => "2026-01-01T00:00:00Z"
      },
      "spec" => %{
        "parentRefs" => Keyword.get(opts, :parent_refs, [%{"name" => "demo"}]),
        "hostnames" => Keyword.get(opts, :hostnames, ["grpc.example.com"]),
        "rules" =>
          Keyword.get(opts, :rules, [
            %{
              "matches" => [
                %{"method" => %{"service" => "echo.Echo", "method" => "Ping"}}
              ],
              "backendRefs" => [%{"name" => "echo-svc", "port" => 9000}]
            }
          ])
      }
    }
  end

  def tcp_gateway(opts \\ []) do
    gateway(
      Keyword.merge(
        [
          listeners: [
            %{
              "name" => "tcp",
              "port" => 5432,
              "protocol" => "TCP",
              "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
            }
          ]
        ],
        opts
      )
    )
  end

  def tcp_route(opts \\ []) do
    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "TCPRoute",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "db"),
        "namespace" => "default",
        "generation" => 1,
        "creationTimestamp" => "2026-01-01T00:00:00Z"
      },
      "spec" => %{
        "parentRefs" => [%{"name" => "demo"}],
        "rules" => [%{"backendRefs" => [%{"name" => "db-svc", "port" => 5432}]}]
      }
    }
  end

  def tls_passthrough_gateway(opts \\ []) do
    gateway(
      Keyword.merge(
        [
          listeners: [
            %{
              "name" => "tls",
              "port" => 443,
              "protocol" => "TLS",
              "tls" => %{"mode" => "Passthrough"},
              "allowedRoutes" => %{"namespaces" => %{"from" => "Same"}}
            }
          ]
        ],
        opts
      )
    )
  end

  def tls_route(opts \\ []) do
    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "TLSRoute",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "sni"),
        "namespace" => "default",
        "generation" => 1,
        "creationTimestamp" => "2026-01-01T00:00:00Z"
      },
      "spec" => %{
        "parentRefs" => [%{"name" => "demo"}],
        "hostnames" => Keyword.get(opts, :hostnames, ["secure.example.com"]),
        "rules" => [%{"backendRefs" => [%{"name" => "tls-svc", "port" => 8443}]}]
      }
    }
  end

  def reference_grant(opts \\ []) do
    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "ReferenceGrant",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "grant"),
        "namespace" => Keyword.get(opts, :namespace, "backends")
      },
      "spec" => %{
        "from" => [
          %{
            "group" => Keyword.get(opts, :from_group, "gateway.networking.k8s.io"),
            "kind" => Keyword.get(opts, :from_kind, "HTTPRoute"),
            "namespace" => Keyword.get(opts, :from_namespace, "default")
          }
        ],
        "to" => Keyword.get(opts, :to, [%{"group" => "", "kind" => "Service"}])
      }
    }
  end

  def http_route(opts \\ []) do
    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "HTTPRoute",
      "metadata" => %{
        "name" => Keyword.get(opts, :name, "app"),
        "namespace" => Keyword.get(opts, :namespace, "default"),
        "generation" => Keyword.get(opts, :generation, 1),
        "creationTimestamp" => Keyword.get(opts, :creation_ts, "2026-01-01T00:00:00Z")
      },
      "spec" => %{
        "parentRefs" => Keyword.get(opts, :parent_refs, [%{"name" => "demo"}]),
        "hostnames" => Keyword.get(opts, :hostnames, ["app.example.com"]),
        "rules" =>
          Keyword.get(opts, :rules, [
            %{
              "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}],
              "backendRefs" => [%{"name" => "app-svc", "port" => 8080}]
            }
          ])
      }
    }
  end

  def inference_http_route(opts \\ []) do
    pool_name = Keyword.get(opts, :pool_name, "llm-pool")
    pool_namespace = Keyword.get(opts, :pool_namespace)

    backend =
      %{
        "group" => "inference.networking.k8s.io",
        "kind" => "InferencePool",
        "name" => pool_name,
        "port" => Keyword.get(opts, :pool_port, 8000)
      }
      |> maybe_put("namespace", pool_namespace)

    http_route(
      Keyword.merge(
        [
          name: "infer",
          rules: [
            %{
              "matches" => [%{"path" => %{"type" => "PathPrefix", "value" => "/infer"}}],
              "backendRefs" => [backend]
            }
          ]
        ],
        opts
      )
    )
  end

  @doc "A Store snapshot of the objects: `%{{gvk, namespace, name} => object}`."
  def snapshot(objects) do
    Map.new(objects, fn obj ->
      meta = obj["metadata"]
      {{gvk(obj), meta["namespace"], meta["name"]}, obj}
    end)
  end

  def gvk(%{"apiVersion" => api_version, "kind" => kind}) do
    case String.split(api_version, "/", parts: 2) do
      [version] -> {"", version, kind}
      [group, version] -> {group, version, kind}
    end
  end

  @doc "The route config of one HTTP listener serving `attached_routes` on `listener` ({scheme, port})."
  def route_config(attached_routes, listener \\ {"http", 80}) do
    Http.http_config("cfg", [%Ir.Listener{attached_routes: attached_routes}], listener)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
