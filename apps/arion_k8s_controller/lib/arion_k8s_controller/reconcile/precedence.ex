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

defmodule Arion.K8sController.Reconcile.Precedence do
  @moduledoc """
  Orders route candidates by Gateway API match precedence.

  The proxy is first-match-wins, so sorting applies Gateway API precedence:
  for HTTPRoute exact path, longest prefix, method, most headers, then most
  query params; for GRPCRoute longest service, longest method, then most
  headers. Creation time and namespace/name break ties. GRPCRoute and HTTPRoute
  matches on one hostname are not merged: gRPC ones come first.
  """

  def sort(candidates), do: Enum.sort_by(candidates, &key/1)

  defp key(%{match: match} = candidate) do
    {
      is_nil(match["grpc"]),
      specificity(match),
      candidate.creation_ts,
      candidate.namespace,
      candidate.name
    }
  end

  defp specificity(%{"grpc" => method} = match) do
    {
      -String.length(method["service"] || ""),
      -String.length(method["method"] || ""),
      -count(match["headers"])
    }
  end

  defp specificity(match) do
    {type_rank, neg_len} = path_key(match["path"])

    {
      type_rank,
      neg_len,
      -has_method(match["method"]),
      -count(match["headers"]),
      -count(match["queryParams"])
    }
  end

  defp path_key(%{"type" => "Exact"}), do: {0, 0}
  defp path_key(%{"type" => "RegularExpression"}), do: {2, 0}
  defp path_key(%{"type" => "PathPrefix", "value" => value}), do: {1, -String.length(value)}
  defp path_key(%{"value" => value}), do: {1, -String.length(value)}
  defp path_key(_), do: {1, -1}

  defp count(nil), do: 0
  defp count(list), do: length(list)

  defp has_method(nil), do: 0
  defp has_method(_), do: 1
end
