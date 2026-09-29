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

defmodule Arion.K8sController.Reconcile.Certificate do
  @moduledoc """
  Validates the data of a TLS Secret and normalizes it for the proxy.

  The proxy loads only PKCS#8 private keys and rejects its whole port listener
  when a key does not match its certificate or has a type it cannot load, so the
  key is re-encoded as PKCS#8 and checked against the leaf. Its rustls/aws-lc-rs
  provider loads RSA keys of 2048 to 8192 bits, ECDSA keys on P-256, P-384 and
  P-521, and Ed25519 keys. SANs and the Secret type are not checked: conformance
  certificates carry only wildcard SANs and must resolve.
  """

  require Record

  @hrl "public_key/include/OTP-PUB-KEY.hrl"
  Record.defrecordp(
    :certificate,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: @hrl)
  )

  Record.defrecordp(
    :tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: @hrl)
  )

  Record.defrecordp(
    :public_key_info,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: @hrl)
  )

  Record.defrecordp(
    :public_key_algorithm,
    :PublicKeyAlgorithm,
    Record.extract(:PublicKeyAlgorithm, from_lib: @hrl)
  )

  @key_types [:RSAPrivateKey, :ECPrivateKey, :PrivateKeyInfo]
  @probe "arion"

  @rsa_encryption {1, 2, 840, 113_549, 1, 1, 1}
  @rsa_moduli Integer.pow(2, 2047)..(Integer.pow(2, 8192) - 1)
  @ecdsa_curves [{1, 2, 840, 10045, 3, 1, 7}, {1, 3, 132, 0, 34}, {1, 3, 132, 0, 35}]
  @ed25519 {1, 3, 101, 112}

  @doc """
  Returns the certificate chain PEM and the PKCS#8 key PEM of base64 Secret data.
  """
  def parse(%{"tls.crt" => crt, "tls.key" => key}) when is_binary(crt) and is_binary(key) do
    with {:ok, crt_pem} <- Base.decode64(crt),
         {:ok, key_pem} <- Base.decode64(key),
         [{:Certificate, leaf, :not_encrypted} | _] = chain <- certificates(crt_pem),
         [{_type, _der, :not_encrypted} = entry] <- private_keys(key_pem),
         private_key = :public_key.pem_entry_decode(entry),
         true <- matches_leaf?(private_key, leaf) do
      pkcs8 = :public_key.pem_entry_encode(:PrivateKeyInfo, private_key)
      {:ok, :public_key.pem_encode(chain), :public_key.pem_encode([pkcs8])}
    else
      _ -> :error
    end
  catch
    # The ASN.1 decoder exits on a malformed extension.
    _kind, _reason -> :error
  end

  def parse(_data), do: :error

  defp certificates(pem),
    do: for({:Certificate, _, _} = entry <- :public_key.pem_decode(pem), do: entry)

  defp private_keys(pem),
    do: for({type, _, _} = entry <- :public_key.pem_decode(pem), type in @key_types, do: entry)

  defp matches_leaf?(key, leaf) do
    certificate(tbsCertificate: tbs) = :public_key.pkix_decode_cert(leaf, :otp)

    public_key_info(algorithm: algorithm, subjectPublicKey: public_key) =
      tbs_certificate(tbs, :subjectPublicKeyInfo)

    with {digest, public_key} <- verify_key(public_key, algorithm) do
      :public_key.verify(@probe, digest, :public_key.sign(@probe, digest, key), public_key)
    end
  end

  defp verify_key(
         {:RSAPublicKey, modulus, _} = key,
         public_key_algorithm(algorithm: @rsa_encryption)
       )
       when modulus in @rsa_moduli,
       do: {:sha256, key}

  defp verify_key(point, public_key_algorithm(parameters: {:namedCurve, curve} = parameters))
       when curve in @ecdsa_curves,
       do: {:sha256, {point, parameters}}

  # EdDSA names the curve by the algorithm itself and signs the message unhashed.
  defp verify_key(point, public_key_algorithm(algorithm: @ed25519, parameters: :asn1_NOVALUE)),
    do: {:none, {point, {:namedCurve, @ed25519}}}

  defp verify_key(_public_key, _algorithm), do: nil
end
