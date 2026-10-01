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

defmodule Arion.K8sController.Deployer.Params do
  @moduledoc """
  The provisioning plan of one Gateway data plane.

  The Resolver selects the Gateway's effective ArionGatewayParameters spec
  (`Ir.Gateway.params`); `plan/2` completes it with the controller defaults it
  is given and the Gateway's infrastructure labels and annotations.
  `selfManaged: true` disables provisioning.
  """

  alias Arion.K8sController.{Config, Ir}

  defstruct [
    :image,
    replicas: 1,
    service_type: "LoadBalancer",
    labels: %{},
    annotations: %{},
    resources: nil,
    self_managed?: false
  ]

  def plan(%Ir.Gateway{params: spec, infrastructure: infra}, %Config{} = config) do
    %__MODULE__{
      image: spec["image"] || config.arion_image,
      replicas: spec["replicas"] || 1,
      service_type: spec["serviceType"] || "LoadBalancer",
      labels: Map.merge(infra["labels"] || %{}, spec["labels"] || %{}),
      annotations: Map.merge(infra["annotations"] || %{}, spec["annotations"] || %{}),
      resources: spec["resources"],
      self_managed?: spec["selfManaged"] == true
    }
  end
end
