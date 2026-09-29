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

defmodule Arion.K8sController.Kube.WatchSupervisor do
  @moduledoc """
  Supervises one `Watcher` per watched GVK.

  `:one_for_one` restarts only the failed watch stream, which then re-lists and
  resumes.
  """

  use Supervisor

  alias Arion.K8sController.Kube.{Gvk, Watcher}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Makes every running watcher list again, when the supervisor is running."
  def relist do
    if pid = Process.whereis(__MODULE__) do
      for {_id, watcher, _type, _modules} <- Supervisor.which_children(pid),
          is_pid(watcher),
          do: Watcher.relist(watcher)
    end

    :ok
  end

  @impl true
  def init(opts) do
    conn = Keyword.fetch!(opts, :conn)
    store = Keyword.fetch!(opts, :store)

    children =
      for gvk <- Gvk.all() do
        Supervisor.child_spec({Watcher, gvk: gvk, conn: conn, store: store}, id: {Watcher, gvk})
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
