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

defmodule Arion.K8sController.MixProject do
  use Mix.Project

  def project do
    [
      app: :arion_k8s_controller,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      releases: releases(),
      deps: deps()
    ]
  end

  # Node name and distribution port are set in rel/env.sh.eex.
  defp releases do
    [
      arion_k8s_controller: [
        include_executables_for: [:unix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :public_key],
      mod: {Arion.K8sController.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def deps do
    [
      {:arion_control_plane, path: "../arion_control_plane"},
      {:k8s, "~> 2.8"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:libcluster, "~> 3.5"},
      {:highlander, "~> 0.2"}
    ]
  end
end
