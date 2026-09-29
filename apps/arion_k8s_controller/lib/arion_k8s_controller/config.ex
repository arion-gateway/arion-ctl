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

defmodule Arion.K8sController.Config do
  @moduledoc """
  Resolved controller configuration, loaded once and passed through the
  supervision tree. The struct holds the defaults; the application environment
  (see `config/runtime.exs`) overrides them.
  """

  # The defaults name the documented Helm release, `arion-ctl` in `arion-system`.
  defstruct controller_name: "arion.io/gateway-controller",
            in_cluster?: false,
            kubeconfig: nil,
            resync_interval_ms: 5 * 60 * 1000,
            debounce_ms: 200,
            debounce_max_ms: 2_000,
            control_plane_port: 50051,
            # Enables clustering and one status/deploy leader.
            leader_election?: false,
            cluster_selector:
              "app.kubernetes.io/name=arion-ctl,app.kubernetes.io/instance=arion-ctl," <>
                "service.kubernetes.io/headless",
            cluster_namespace: "arion-system",
            cluster_pod_basename: "arion",
            # Defaults for provisioned Arion data planes.
            arion_image: "ghcr.io/arion-gateway/arion:0.1.0",
            ads_service: "arion-ctl-controller-ads",
            ads_namespace: "arion-system"

  def load, do: struct(__MODULE__, Application.get_all_env(:arion_k8s_controller))
end
