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

defmodule Arion.Ctl.Application do
  @moduledoc false

  use Application

  # The Store restores and publishes the snapshot before the xDS server binds,
  # so reconnecting proxies never see an empty fleet; rest_for_one keeps that
  # order across restarts.
  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:arion_ctl, :autostart, true) do
        [
          {Arion.ControlPlane, serve?: false},
          {Arion.Ctl.Store, state_dir: Application.fetch_env!(:arion_ctl, :state_dir)},
          Arion.ControlPlane.server_child(port: Application.fetch_env!(:arion_ctl, :port))
        ]
      else
        []
      end

    Supervisor.start_link(children, strategy: :rest_for_one, name: Arion.Ctl.Supervisor)
  end
end
