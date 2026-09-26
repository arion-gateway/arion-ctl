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

defmodule Arion.ControlPlane.Helpers.RouteConfig do
  @moduledoc """
  Route configurations: the virtual hosts served inline by an HCM or by name
  over RDS. `add_virtual_host/2` appends in call order and `put_virtual_hosts/2`
  replaces the list. Header mutations accumulate like a route's.
  """

  alias Arion.ControlPlane.Helpers.Route
  alias Arion.ControlPlane.Pb.Route.{RouteConfiguration, VirtualHost}

  @type route_config :: RouteConfiguration.t()

  @spec new(String.t()) :: route_config
  def new(name), do: %RouteConfiguration{name: name}

  @spec add_virtual_host(route_config, VirtualHost.t()) :: route_config
  def add_virtual_host(%RouteConfiguration{virtual_hosts: hosts} = route_config, host),
    do: %{route_config | virtual_hosts: hosts ++ [host]}

  @spec put_virtual_hosts(route_config, [VirtualHost.t()]) :: route_config
  def put_virtual_hosts(%RouteConfiguration{} = route_config, hosts) when is_list(hosts),
    do: %{route_config | virtual_hosts: hosts}

  @spec most_specific_header_mutations_wins(route_config, boolean()) :: route_config
  def most_specific_header_mutations_wins(%RouteConfiguration{} = route_config, value \\ true),
    do: %{route_config | most_specific_header_mutations_wins: value}

  defdelegate add_request_header(route_config, update), to: Route
  defdelegate add_response_header(route_config, update), to: Route
  defdelegate remove_request_header(route_config, name), to: Route
  defdelegate remove_response_header(route_config, name), to: Route
end
