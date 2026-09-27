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

defmodule Arion.ControlPlane.Helpers.Cors do
  @moduledoc "The CORS HTTP filter and the per-route policies it enforces."

  import Arion.ControlPlane.Helpers.Xds, only: [bool: 1]

  alias Arion.ControlPlane.Helpers.{Route, Xds}
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Ext

  def filter(name \\ "envoy.filters.http.cors"), do: Xds.http_filter(name, :cors, %Ext.Cors{})

  def policy(opts \\ []) do
    %Ext.CorsPolicy{
      allow_origin_string_match:
        Keyword.get(opts, :allow_origins, [Route.string_matcher(:exact, "*")]),
      allow_methods: csv(Keyword.get(opts, :allow_methods, ["GET", "POST", "OPTIONS"])),
      allow_headers: csv(Keyword.get(opts, :allow_headers, ["*"])),
      expose_headers: csv(Keyword.get(opts, :expose_headers, [])),
      max_age: to_string(Keyword.get(opts, :max_age, 86_400)),
      allow_credentials: bool(Keyword.get(opts, :allow_credentials)),
      forward_not_matching_preflights: bool(Keyword.get(opts, :forward_not_matching_preflights))
    }
  end

  @doc "Sets the route's CORS policy for the filter of that name."
  def per_route(route, filter_name, policy),
    do: Route.put_per_filter_config(route, filter_name, :cors_policy, policy)

  defp csv(value) when is_list(value), do: Enum.join(value, ",")
  defp csv(value), do: value
end
