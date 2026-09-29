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

defmodule Arion.K8sController.Status.Claim do
  @moduledoc """
  Ownership predicates for GatewayClass, Gateway, and Route parent refs.

  They scope both xDS translation and status write-back to this controller.
  """

  def owns_class?(%{"spec" => %{"controllerName" => name}}, controller_name),
    do: name == controller_name

  def owns_class?(_object, _controller_name), do: false

  def owned_class_names(classes, controller_name) do
    for class <- classes, owns_class?(class, controller_name), into: MapSet.new() do
      get_in(class, ["metadata", "name"])
    end
  end

  def owns_gateway?(%{"spec" => %{"gatewayClassName" => class}}, owned_classes),
    do: MapSet.member?(owned_classes, class)

  def owns_gateway?(_object, _owned_classes), do: false
end
