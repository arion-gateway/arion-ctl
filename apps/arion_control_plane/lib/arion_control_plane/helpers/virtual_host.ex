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

defmodule Arion.ControlPlane.Helpers.VirtualHost do
  @moduledoc """
  Virtual hosts: the routes of a set of domains. Routes are tried in order, so
  `add_route/2` appends in call order and `put_routes/2` replaces the list.
  Header mutations accumulate like a route's.
  """

  alias Arion.ControlPlane.Helpers.Route
  alias Arion.ControlPlane.Pb.Route.VirtualHost

  @type virtual_host :: VirtualHost.t()

  @spec new(String.t(), [String.t()]) :: virtual_host
  def new(name, domains \\ ["*"]), do: %VirtualHost{name: name, domains: domains}

  @spec add_route(virtual_host, Route.route()) :: virtual_host
  def add_route(%VirtualHost{routes: routes} = virtual_host, route),
    do: %{virtual_host | routes: routes ++ [route]}

  @spec put_routes(virtual_host, [Route.route()]) :: virtual_host
  def put_routes(%VirtualHost{} = virtual_host, routes) when is_list(routes),
    do: %{virtual_host | routes: routes}

  @doc "The retry policy of routes without their own; see `Route.retry_policy/2`."
  @spec retry(virtual_host, struct() | nil) :: virtual_host
  def retry(%VirtualHost{} = virtual_host, retry_policy),
    do: %{virtual_host | retry_policy: retry_policy}

  defdelegate add_request_header(virtual_host, update), to: Route
  defdelegate add_response_header(virtual_host, update), to: Route
  defdelegate remove_request_header(virtual_host, name), to: Route
  defdelegate remove_response_header(virtual_host, name), to: Route
end
