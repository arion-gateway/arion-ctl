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

defmodule Arion.K8sController.ChartTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.Kube.Gvk

  @rbac Path.expand("../../../charts/arion-ctl/templates/rbac.yaml", __DIR__)

  test "the chart's ClusterRole lets the controller list and watch every watched kind" do
    rules =
      @rbac
      |> File.read!()
      |> String.replace(~r/{{.*?}}/, "x")
      |> YamlElixir.read_all_from_string!()
      |> Enum.find(&(&1["kind"] == "ClusterRole"))
      |> Map.fetch!("rules")

    for {group, _version, kind} <- Gvk.all() do
      resource = resource(kind)

      assert Enum.any?(rules, fn rule ->
               group in rule["apiGroups"] and resource in rule["resources"] and
                 ["list", "watch"] -- rule["verbs"] == []
             end),
             "#{group} #{resource}"
    end
  end

  defp resource(kind) do
    name = String.downcase(kind)

    cond do
      String.ends_with?(name, "ss") -> name <> "es"
      String.ends_with?(name, "s") -> name
      true -> name <> "s"
    end
  end
end
