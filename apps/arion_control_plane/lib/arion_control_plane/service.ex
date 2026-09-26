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

defmodule Arion.ControlPlane.Service do
  @moduledoc """
  Programs the control plane one fleet at a time.

  A fleet is the resource set a proxy selects with its xDS `node.cluster`. The
  leading fleet argument defaults to `"arion"`, the cluster in the bundled
  bootstraps, so single-fleet use can omit it:

      Arion.ControlPlane.Service.push(:cluster, cluster)            # "arion"
      Arion.ControlPlane.Service.push("fleet-a", :cluster, cluster) # explicit

  Each fleet is an `Arion.ControlPlane.Fleet` process started on first use by
  `ensure/1` and stopped by `retire/1`. Resources are checked, named and
  encoded in the caller before the fleet is started or messaged, so a malformed
  one raises `ArgumentError` there and leaves the fleet as it was.
  """

  alias Arion.ControlPlane.{Fleet, ResourceCache}
  alias Arion.ControlPlane.Xds.ResourceTypes

  @default "arion"

  @doc "The fleet used when a caller does not name one."
  def default_fleet, do: @default

  @doc """
  Replaces a fleet's complete desired state synchronously with `{kind, resource}`
  pairs. Changed resources and removals are queued to subscribed streams before
  returning; proxy ACKs are reported separately through `acks/1`.
  """
  def replace(fleet \\ @default, resources) when is_list(resources) do
    cache =
      Enum.reduce(resources, ResourceCache.new(), fn {kind, resource}, cache ->
        ResourceCache.add(cache, kind, resource)
      end)

    GenServer.call(ensure(fleet), {:replace, cache}, :infinity)
  end

  @doc "Adds or replaces one resource asynchronously."
  def push(fleet \\ @default, kind, resource) do
    entry = ResourceCache.entry(kind, resource)
    GenServer.cast(ensure(fleet), {:push, kind, entry})
  end

  @doc "Removes one resource asynchronously."
  def drop(fleet \\ @default, kind, name) when is_binary(name) and name != "" do
    ResourceTypes.discovery_kind!(kind)
    GenServer.cast(ensure(fleet), {:drop, kind, name})
  end

  @doc "The fleet's resources as given, `%{kind => %{name => resource}}`; empty for a fleet that is not running."
  def resources(fleet \\ @default),
    do: call(fleet, :resources, ResourceCache.resources(ResourceCache.new()))

  @doc "Per subscribed stream, what it was sent and how it answered; empty for a fleet that is not running."
  def acks(fleet \\ @default), do: call(fleet, :acks, %{})

  @doc "The fleets with a running process."
  def list_fleets,
    do: Registry.select(Arion.ControlPlane.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])

  @doc """
  Empties `fleet` and stops its process once no proxy is subscribed to it.
  Returns `:kept` or `:stopped`, and never starts a process.

  For the fleet's owner, which publishes its desired state: a push or drop that
  reaches the process after it has been retired is lost.
  """
  def retire(fleet), do: call(fleet, :retire, :stopped)

  @doc "The pid for `fleet`, started under `Arion.ControlPlane.FleetSupervisor` if needed."
  def ensure(fleet) do
    case Registry.lookup(Arion.ControlPlane.Registry, fleet) do
      [{pid, _}] ->
        pid

      [] ->
        case DynamicSupervisor.start_child(Arion.ControlPlane.FleetSupervisor, {Fleet, fleet}) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
    end
  end

  @doc false
  def subscribe(client, fleet, type_url, initial_versions) do
    pid = ensure(fleet)
    GenServer.cast(pid, {:subscribe, client, type_url, initial_versions})
    pid
  end

  defp call(fleet, request, default) do
    case Registry.lookup(Arion.ControlPlane.Registry, fleet) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, request, :infinity)
        catch
          :exit, _ -> default
        end

      [] ->
        default
    end
  end
end
