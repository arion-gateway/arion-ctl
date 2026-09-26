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

defmodule Arion.ControlPlane.Helpers.TcpProxy do
  @moduledoc "The TCP proxy network filter forwarding to one or to weighted clusters."

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Filter.TcpProxy

  def filter(cluster_name, stat_prefix \\ "tcp_proxy"),
    do: build(stat_prefix, {:cluster, cluster_name})

  def weighted(distribution, stat_prefix \\ "tcp_proxy") do
    clusters =
      for {name, weight} <- distribution,
          do: %TcpProxy.WeightedCluster.ClusterWeight{name: name, weight: weight}

    build(stat_prefix, {:weighted_clusters, %TcpProxy.WeightedCluster{clusters: clusters}})
  end

  defp build(stat_prefix, cluster_specifier) do
    config = %TcpProxy{stat_prefix: stat_prefix, cluster_specifier: cluster_specifier}
    Xds.network_filter("envoy.filters.network.tcp_proxy", :tcp_proxy, config)
  end
end
