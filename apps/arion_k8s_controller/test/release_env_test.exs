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

defmodule Arion.K8sController.ReleaseEnvTest do
  use ExUnit.Case, async: true

  @env_sh Path.expand("../rel/env.sh.eex", __DIR__)

  # Evaluates the rendered env.sh the way bin/arion_k8s_controller sources it.
  defp env(command) do
    script = EEx.eval_file(@env_sh, assigns: [release: nil])

    {out, 0} =
      System.cmd(
        "sh",
        [
          "-c",
          ~s(eval "$ENV_SH"; printf '%s\\n%s\\n%s' "$RELEASE_DISTRIBUTION" "$RELEASE_NODE" "$ERL_AFLAGS")
        ],
        env: [
          {"ENV_SH", script},
          {"RELEASE_COMMAND", command},
          {"POD_IP", "10.0.0.7"},
          {"ERL_DIST_PORT", "9100"},
          {"ERL_AFLAGS", nil},
          {"RELEASE_NODE", nil}
        ]
      )

    [distribution, node, aflags] = String.split(out, "\n")
    %{distribution: distribution, node: node, aflags: aflags}
  end

  @pin "-kernel inet_dist_listen_min 9100 inet_dist_listen_max 9100"

  test "the booting node listens on the fixed distribution port" do
    for command <- ~w(start start_iex daemon daemon_iex) do
      assert %{distribution: "name", node: "arion@10.0.0.7", aflags: aflags} = env(command)
      assert aflags =~ @pin, command
    end
  end

  test "remote commands take an ephemeral port, since the node holds the fixed one" do
    for command <- ~w(rpc remote eval stop restart pid version) ++ [""] do
      assert %{distribution: "name", node: "arion@10.0.0.7", aflags: aflags} = env(command)
      refute aflags =~ "inet_dist_listen", command
    end
  end
end
