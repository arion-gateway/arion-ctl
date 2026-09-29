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

defmodule Arion.K8sController.Application do
  use Application

  alias Arion.K8sController.{Config, Runtime}

  @moduledoc """
  Boots the live controller tree only when `:autostart` is enabled.

  Dev and test use an empty supervisor so they never contact a cluster unless
  `Arion.K8sController.start_runtime/0` is called explicitly.
  """

  @impl true
  def start(_type, _args) do
    children =
      if autostart?() do
        [{Runtime, Config.load()}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: Arion.K8sController.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp autostart?, do: Application.get_env(:arion_k8s_controller, :autostart, false)
end
