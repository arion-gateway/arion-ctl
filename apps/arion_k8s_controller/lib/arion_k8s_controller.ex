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

defmodule Arion.K8sController do
  @moduledoc """
  Kubernetes Gateway API controller for the Arion control plane.

  In pods the OTP application starts the runtime automatically. For local
  development against a kind cluster, start it explicitly:

      iex> Arion.K8sController.start_runtime()
  """

  alias Arion.K8sController.{Config, Runtime}

  @doc """
  Starts the live controller tree when `:autostart` is off.
  """
  def start_runtime(config \\ Config.load()) do
    Supervisor.start_child(Arion.K8sController.Supervisor, {Runtime, config})
  end
end
