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

defmodule Arion.ControlPlane.Helpers.Endpoint do
  @moduledoc "Addresses, endpoints and the load assignments that group them by locality."

  import Arion.ControlPlane.Helpers.Xds, only: [uint32: 1]

  alias Arion.ControlPlane.Pb

  def socket_address(address, port),
    do: %Pb.Data.SocketAddress{address: address, port_specifier: {:port_value, port}}

  def address(address, port),
    do: %Pb.Data.Address{address: {:socket_address, socket_address(address, port)}}

  def lb(address, port, opts \\ []) do
    %Pb.Endpoint.LbEndpoint{
      host_identifier: {:endpoint, %Pb.Endpoint.Endpoint{address: address(address, port)}},
      load_balancing_weight: uint32(Keyword.get(opts, :weight, 1)),
      health_status: Keyword.get(opts, :health_status, :HEALTHY)
    }
  end

  def locality(endpoints, opts \\ []) when is_list(endpoints),
    do: %Pb.Endpoint.LocalityLbEndpoints{
      lb_endpoints: endpoints,
      priority: Keyword.get(opts, :priority, 0)
    }

  def assignment(cluster_name, endpoints) when is_list(endpoints),
    do: %Pb.Endpoint.ClusterLoadAssignment{
      cluster_name: cluster_name,
      endpoints: [locality(endpoints)]
    }

  def assignment(cluster_name, address, ports) when is_list(ports),
    do: assignment(cluster_name, Enum.map(ports, &lb(address, &1)))
end
