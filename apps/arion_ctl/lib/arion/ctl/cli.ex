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

defmodule Arion.Ctl.CLI do
  @moduledoc false

  alias Arion.ControlPlane.Service

  @usage "arionctl serve | shell | validate -f FILE | apply -f FILE | delete -f FILE | delete KIND NAME [--fleet FLEET] | get [--fleet FLEET] | status"

  # Run by bin/arionctl in a throwaway node of the release. Files are read and
  # validated here; the request then goes to the service over distribution.
  def main_from_env do
    args =
      System.fetch_env!("ARION_CTL_ARGS") |> Base.decode64!() |> String.split(<<0>>, trim: true)

    System.halt(main(args))
  end

  @doc "Runs one command; returns the exit status."
  def main(args) do
    case request(args) do
      {:local, result} -> print(result)
      {:remote, request} -> remote(request)
      {:error, message} -> fail(message)
    end
  end

  @doc false
  def request([action, "-f", path]) when action in ["validate", "apply", "delete"] do
    with {:ok, bytes} <- read(path), {:ok, entries} <- validate(path, bytes) do
      if action == "validate",
        do: {:local, %{valid: true, resources: length(entries)}},
        else: {:remote, %{"op" => action, "documents" => Enum.map(entries, & &1.manifest)}}
    end
  end

  def request(["delete", kind, name]),
    do: request(["delete", kind, name, "--fleet", Service.default_fleet()])

  def request(["delete", kind, name, "--fleet", fleet]),
    do: {:remote, %{"op" => "delete_name", "kind" => kind, "name" => name, "fleet" => fleet}}

  def request(["get"]), do: {:remote, %{"op" => "get", "fleet" => nil}}
  def request(["get", "--fleet", fleet]), do: {:remote, %{"op" => "get", "fleet" => fleet}}
  def request(["status"]), do: {:remote, %{"op" => "status"}}
  def request(_args), do: {:error, @usage}

  @doc false
  def execute(%{"op" => "apply", "documents" => docs}), do: Arion.Ctl.apply(docs)
  def execute(%{"op" => "delete", "documents" => docs}), do: Arion.Ctl.delete_documents(docs)

  def execute(%{"op" => "delete_name", "kind" => kind, "name" => name, "fleet" => fleet}),
    do: Arion.Ctl.delete(kind, name, fleet)

  def execute(%{"op" => "get", "fleet" => fleet}), do: {:ok, Arion.Ctl.get(fleet)}
  def execute(%{"op" => "status"}), do: {:ok, Arion.Ctl.status()}

  defp remote(request) do
    service = service_node()

    case :erpc.call(service, __MODULE__, :execute, [request]) do
      {:ok, value} -> print(value)
      {:error, message} -> fail(message)
    end
  catch
    :error, {:erpc, :noconnection} ->
      fail(
        "cannot reach #{service_node()}: is `arionctl serve` running with this RELEASE_NODE and cookie?"
      )

    kind, reason ->
      fail(Exception.format(kind, reason, []))
  end

  # The release's eval node is not distributed.
  defp service_node do
    {:ok, host} = :inet.gethostname()

    unless Node.alive?() do
      {:ok, _} =
        :net_kernel.start(:"arionctl_#{System.pid()}@#{host}", %{name_domain: :shortnames})

      Node.set_cookie(String.to_atom(System.fetch_env!("RELEASE_COOKIE")))
    end

    :"#{System.get_env("RELEASE_NODE", "arionctl")}@#{host}"
  end

  defp read(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, "#{path}: #{:file.format_error(reason)}"}
    end
  end

  defp validate(path, bytes) do
    case Arion.Ctl.validate(bytes) do
      {:ok, entries} -> {:ok, entries}
      {:error, message} -> {:error, "#{path}: #{message}"}
    end
  end

  defp print(value) do
    IO.puts(Jason.encode!(json_safe(value), pretty: true))
    0
  end

  defp fail(message) do
    IO.puts(:stderr, message)
    1
  end

  defp json_safe(value) when is_map(value),
    do:
      Map.new(value, fn {k, v} ->
        {if(is_pid(k), do: inspect(k), else: to_string(k)), json_safe(v)}
      end)

  defp json_safe(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_safe()
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(value), do: value
end
