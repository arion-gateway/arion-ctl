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

defmodule Arion.Ctl.MixProject do
  use Mix.Project

  def project do
    [
      app: :arion_ctl,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      releases: [arion_ctl: [include_executables_for: [:unix], overlays: ["rel/overlays"]]],
      deps: [{:arion_control_plane, path: "../arion_control_plane"}, {:yaml_elixir, "~> 2.11"}]
    ]
  end

  def application, do: [extra_applications: [:logger], mod: {Arion.Ctl.Application, []}]
end
