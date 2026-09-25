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

import Config

# In-cluster uses the service account; local uses kubeconfig.
config :arion_k8s_controller,
  in_cluster?: System.get_env("KUBERNETES_SERVICE_HOST") != nil,
  kubeconfig: System.get_env("KUBECONFIG"),
  # HA opt-in: one status/deploy leader.
  leader_election?: System.get_env("GATEWAY_LEADER_ELECTION") == "true"

for {env, key} <- [
      {"GATEWAY_CONTROLLER_NAME", :controller_name},
      {"GATEWAY_ARION_IMAGE", :arion_image},
      {"GATEWAY_ADS_SERVICE", :ads_service},
      {"GATEWAY_ADS_NAMESPACE", :ads_namespace},
      {"GATEWAY_CLUSTER_SELECTOR", :cluster_selector},
      {"GATEWAY_CLUSTER_NAMESPACE", :cluster_namespace},
      {"GATEWAY_CLUSTER_POD_BASENAME", :cluster_pod_basename}
    ],
    value = System.get_env(env) do
  config :arion_k8s_controller, [{key, value}]
end

for {env, key} <- [
      {"GATEWAY_RESYNC_INTERVAL_MS", :resync_interval_ms},
      {"GATEWAY_CONTROL_PLANE_PORT", :control_plane_port}
    ],
    value = System.get_env(env) do
  config :arion_k8s_controller, [{key, String.to_integer(value)}]
end
