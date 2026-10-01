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

defmodule Arion.K8sController.Deployer.Bootstrap do
  @moduledoc """
  Builds the bootstrap map for a provisioned Arion data plane.

  `node.cluster` is the Gateway's fleet; the only static resource is the
  HTTP/2 ADS cluster that fetches all dynamic config from the controller.
  """

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.K8sController.{Config, Ir}

  def build(%Ir.Gateway{} = gateway, %Config{} = config) do
    %{
      "node" => %{
        "id" => "arion/#{gateway.name}",
        "cluster" => Ir.Gateway.fleet(gateway)
      },
      "dynamic_resources" => %{
        "ads_config" => %{
          "grpc_services" => [
            %{"envoy_grpc" => %{"cluster_name" => "xds_cluster"}}
          ]
        }
      },
      "static_resources" => %{
        "clusters" => [
          %{
            "name" => "xds_cluster",
            "connect_timeout" => "1s",
            "type" => "STRICT_DNS",
            "lb_policy" => "ROUND_ROBIN",
            "typed_extension_protocol_options" => %{
              "envoy.extensions.upstreams.http.v3.HttpProtocolOptions" => %{
                "@type" => Xds.type_url(:http_protocol_options),
                "explicit_http_config" => %{"http2_protocol_options" => %{}}
              }
            },
            "load_assignment" => %{
              "cluster_name" => "xds_cluster",
              "endpoints" => [
                %{
                  "lb_endpoints" => [
                    %{
                      "endpoint" => %{
                        "address" => %{
                          "socket_address" => %{
                            "address" => ads_dns(config),
                            "port_value" => config.control_plane_port
                          }
                        }
                      }
                    }
                  ]
                }
              ]
            }
          }
        ]
      }
    }
  end

  defp ads_dns(%Config{ads_service: svc, ads_namespace: ns}),
    do: "#{svc}.#{ns}.svc.cluster.local"
end
