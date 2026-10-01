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

defmodule Arion.K8sController.Cluster do
  @moduledoc """
  libcluster topology for controller replicas.

  Pods join as `<basename>@<pod-ip>` through the headless Service endpoints,
  found by the Service labels that the Endpoints object carries.
  Highlander uses the formed BEAM cluster to run one leader process.
  """

  alias Arion.K8sController.Config

  def topologies(%Config{} = config) do
    [
      arion: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :ip,
          kubernetes_ip_lookup_mode: :endpoints,
          kubernetes_selector: config.cluster_selector,
          kubernetes_namespace: config.cluster_namespace,
          kubernetes_node_basename: config.cluster_pod_basename,
          polling_interval: 5_000
        ]
      ]
    ]
  end
end
