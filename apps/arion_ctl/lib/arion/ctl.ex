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

defmodule Arion.Ctl do
  @moduledoc "Durable operator API shared by arionctl and remote IEx."

  alias Arion.ControlPlane.Service
  alias Arion.ControlPlane.Xds.ResourceTypes
  alias Arion.Ctl.{Manifest, Store}

  @doc "Decodes documents without committing them: `{:ok, entries}` or `{:error, message}`."
  def validate(documents), do: Manifest.decode(documents)

  @doc "Validates the complete input, then merges its resources into the desired state."
  def apply(documents) do
    with {:ok, entries} <- Manifest.decode(documents), do: Store.apply(entries)
  end

  @doc """
  Applies resources built with the library helpers, as `{kind, payload}` or
  `{kind, {name, payload}}` pairs, to the `:fleet` option (default `"arion"`).
  They become manifest documents and go through `apply/1`, so an invalid
  pair, duplicate identity or disagreeing payload name rejects the whole batch
  with `{:error, message}` before anything is saved or published.
  """
  @spec apply_resources([{atom(), term()}], fleet: String.t()) ::
          {:ok, %{resources: non_neg_integer()}} | {:error, String.t()}
  def apply_resources(resources, opts \\ []) when is_list(resources) do
    fleet = Keyword.get(opts, :fleet, Service.default_fleet())
    with {:ok, documents} <- Manifest.from_resources(fleet, resources), do: apply(documents)
  end

  def apply_file(path) do
    with {:ok, bytes} <- read(path), do: apply(bytes)
  end

  def delete_file(path) do
    with {:ok, bytes} <- read(path), do: delete_documents(bytes)
  end

  @doc "Validates the documents, then deletes their identities."
  def delete_documents(documents) do
    with {:ok, entries} <- Manifest.decode(documents),
         do: Store.delete(Enum.map(entries, & &1.id))
  end

  @doc "Deletes one identity by manifest kind, such as `\"Listener\"`."
  def delete(api_kind, name, fleet \\ Service.default_fleet()) do
    case ResourceTypes.kind_for_api_kind(api_kind) do
      {:ok, kind} -> Store.delete([{fleet, kind, name}])
      :error -> {:error, "unsupported kind #{inspect(api_kind)}"}
    end
  end

  @doc "The saved resource documents, optionally of one fleet."
  def get(fleet \\ nil) do
    Enum.filter(Store.resources(), &(fleet == nil or &1["metadata"]["fleet"] == fleet))
  end

  @doc "Per running fleet: its saved resource count and the state of each connected stream."
  def status do
    counts = Enum.frequencies_by(Store.resources(), & &1["metadata"]["fleet"])

    Map.new(
      Service.list_fleets(),
      &{&1, %{resources: Map.get(counts, &1, 0), clients: Service.acks(&1)}}
    )
  end

  defp read(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, "#{path}: #{:file.format_error(reason)}"}
    end
  end
end
