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

alias Arion.ControlPlane.Service

alias Arion.ControlPlane.Helpers.{
  Cluster,
  FilterChain,
  Hcm,
  Listener,
  Route,
  RouteConfig,
  VirtualHost
}

# These variables configure this example only.
ads_port = String.to_integer(System.get_env("ARION_DOCS_ADS_PORT", "15051"))
http_port = String.to_integer(System.get_env("ARION_DOCS_HTTP_PORT", "18080"))
backend_port = String.to_integer(System.get_env("ARION_DOCS_BACKEND_PORT", "18081"))

{:ok, _pid} = Arion.ControlPlane.start_link(serve?: false)

cluster = Cluster.static("backend", "127.0.0.1", [backend_port])
route = Route.new("all") |> Route.match_prefix("/") |> Route.to_cluster("backend")
host = VirtualHost.new("all", ["*"]) |> VirtualHost.add_route(route)
routes = RouteConfig.new("http-routes") |> RouteConfig.add_virtual_host(host)
hcm = Hcm.new(codec_type: :HTTP1) |> Hcm.route_config(routes)
chain = FilterChain.new("http") |> FilterChain.add_hcm(hcm)

listener =
  Listener.new("http", Listener.local_address(http_port, "127.0.0.1"))
  |> Listener.add_filter_chain(chain)

:ok = Service.replace("arion", [{:cluster, cluster}, {:listener, listener}])
:ok = Arion.ControlPlane.serve(port: ads_port)
IO.puts("Fleet arion is ready on ADS port #{ads_port}; start the backend and proxy.")
