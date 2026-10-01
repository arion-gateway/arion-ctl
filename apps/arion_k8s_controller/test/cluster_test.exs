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

defmodule Arion.K8sController.ClusterTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.{Cluster, Config}

  test "replicas find each other through the labelled Endpoints of the headless Service" do
    config = %Config{controller_name: "arion.io/gateway-controller", cluster_selector: "a=b"}
    [arion: topology] = Cluster.topologies(config)

    assert topology[:strategy] == Elixir.Cluster.Strategy.Kubernetes
    assert topology[:config][:kubernetes_ip_lookup_mode] == :endpoints
    # libcluster raises without a selector.
    assert Keyword.fetch!(topology[:config], :kubernetes_selector) == "a=b"
  end
end
