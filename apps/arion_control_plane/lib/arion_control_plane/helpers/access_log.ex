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

defmodule Arion.ControlPlane.Helpers.AccessLog do
  @moduledoc "File and stdout access logs with substitution-format text formats."

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Ext

  def file(path, format, name \\ "envoy.access_loggers.file") do
    config = %Ext.FileAccessLog{path: path, access_log_format: {:log_format, format}}
    access_log(name, :file_access_log, config)
  end

  def stdout(format, name \\ "envoy.access_loggers.stdout") do
    config = %Ext.StdoutAccessLog{access_log_format: {:log_format, format}}
    access_log(name, :stdout_access_log, config)
  end

  def access_log(name, kind, config),
    do: %Ext.AccessLog{name: name, config_type: Xds.typed_config(kind, config)}

  def text_format(text),
    do: %Ext.SubstitutionFormatString{
      format: {:text_format_source, Xds.data_source(:inline_string, text)}
    }
end
