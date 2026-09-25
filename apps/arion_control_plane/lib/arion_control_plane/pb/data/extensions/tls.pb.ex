defmodule Arion.ControlPlane.Pb.Data.Extensions.TlsParameters.TlsProtocol do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.TlsParameters.TlsProtocol",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :TLS_AUTO, 0
  field :TLSv1_2, 3
  field :TLSv1_3, 4
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.CertificateValidationContext.TrustChainVerification do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.CertificateValidationContext.TrustChainVerification",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :VERIFY_TRUST_CHAIN, 0
  field :ACCEPT_UNTRUSTED, 1
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.SubjectAltNameMatcher.SanType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "data.extensions.SubjectAltNameMatcher.SanType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :SAN_TYPE_UNSPECIFIED, 0
  field :EMAIL, 1
  field :DNS, 2
  field :URI, 3
  field :IP_ADDRESS, 4
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.TlsParameters do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.TlsParameters",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :tls_minimum_protocol_version, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.TlsParameters.TlsProtocol,
    json_name: "tlsMinimumProtocolVersion",
    enum: true

  field :tls_maximum_protocol_version, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.TlsParameters.TlsProtocol,
    json_name: "tlsMaximumProtocolVersion",
    enum: true
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.TlsCertificate do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.TlsCertificate",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :certificate_chain, 1,
    type: Arion.ControlPlane.Pb.Data.DataSource,
    json_name: "certificateChain"

  field :private_key, 2, type: Arion.ControlPlane.Pb.Data.DataSource, json_name: "privateKey"
  field :pkcs12, 8, type: Arion.ControlPlane.Pb.Data.DataSource
  field :password, 3, type: Arion.ControlPlane.Pb.Data.DataSource
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.SdsSecretConfig do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.SdsSecretConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :sds_config, 2, type: Arion.ControlPlane.Pb.Data.ConfigSource, json_name: "sdsConfig"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.Secret do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.Secret",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :type, 0

  field :name, 1, type: :string

  field :tls_certificate, 2,
    type: Arion.ControlPlane.Pb.Data.Extensions.TlsCertificate,
    json_name: "tlsCertificate",
    oneof: 0

  field :validation_context, 4,
    type: Arion.ControlPlane.Pb.Data.Extensions.CertificateValidationContext,
    json_name: "validationContext",
    oneof: 0
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.CertificateValidationContext do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.CertificateValidationContext",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :trusted_ca, 1, type: Arion.ControlPlane.Pb.Data.DataSource, json_name: "trustedCa"

  field :trust_chain_verification, 10,
    type:
      Arion.ControlPlane.Pb.Data.Extensions.CertificateValidationContext.TrustChainVerification,
    json_name: "trustChainVerification",
    enum: true

  field :match_typed_subject_alt_names, 15,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.SubjectAltNameMatcher,
    json_name: "matchTypedSubjectAltNames"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.SubjectAltNameMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.SubjectAltNameMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :san_type, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.SubjectAltNameMatcher.SanType,
    json_name: "sanType",
    enum: true

  field :matcher, 2, type: Arion.ControlPlane.Pb.Data.StringMatcher
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.CommonTlsContext do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.CommonTlsContext",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :validation_context_type, 0

  field :tls_params, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.TlsParameters,
    json_name: "tlsParams"

  field :tls_certificates, 2,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.TlsCertificate,
    json_name: "tlsCertificates"

  field :tls_certificate_sds_secret_configs, 6,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.Extensions.SdsSecretConfig,
    json_name: "tlsCertificateSdsSecretConfigs"

  field :validation_context, 3,
    type: Arion.ControlPlane.Pb.Data.Extensions.CertificateValidationContext,
    json_name: "validationContext",
    oneof: 0

  field :validation_context_sds_secret_config, 7,
    type: Arion.ControlPlane.Pb.Data.Extensions.SdsSecretConfig,
    json_name: "validationContextSdsSecretConfig",
    oneof: 0

  field :alpn_protocols, 4, repeated: true, type: :string, json_name: "alpnProtocols"
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.UpstreamTlsContext do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.UpstreamTlsContext",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :common_tls_context, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.CommonTlsContext,
    json_name: "commonTlsContext"

  field :sni, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Data.Extensions.DownstreamTlsContext do
  @moduledoc false

  use Protobuf,
    full_name: "data.extensions.DownstreamTlsContext",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :common_tls_context, 1,
    type: Arion.ControlPlane.Pb.Data.Extensions.CommonTlsContext,
    json_name: "commonTlsContext"

  field :require_client_certificate, 2,
    type: Google.Protobuf.BoolValue,
    json_name: "requireClientCertificate"
end
