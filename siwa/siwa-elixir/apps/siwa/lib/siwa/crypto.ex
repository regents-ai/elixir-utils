defmodule Siwa.Crypto do
  @moduledoc false

  @personal_prefix "\x19Ethereum Signed Message:\n"

  def random_bytes(size), do: :crypto.strong_rand_bytes(size)

  def random_secret(size \\ 32) do
    size |> random_bytes() |> Base.url_encode64(padding: false)
  end

  def generate_keypair do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256k1)

    {:ok,
     %{
       private_key: encode_hex(private_key),
       public_key: encode_hex(public_key),
       address: address_from_public_key(public_key)
     }}
  rescue
    error -> {:error, error}
  end

  def sign_personal_message(private_key_hex, message, _opts \\ []) do
    Siwa.EvmPersonalSign.sign_personal_signature(private_key_hex, message)
  end

  def verify_personal_message("0x" <> _ = signature, message) do
    with {:ok, address} <- Siwa.EvmPersonalSign.recover_personal_address(message, signature) do
      {:ok, %{address: address, signer_type: "eoa", signature: signature}}
    end
  end

  def verify_personal_message(signature, message) do
    digest = personal_hash(message)
    verify_digest(signature, digest)
  end

  def sign_raw(private_key_hex, payload, opts \\ []) do
    signer_type = Keyword.get(opts, :signer_type, "eoa")
    public_key_hex = Keyword.fetch!(opts, :public_key)
    public_key = decode_hex!(public_key_hex)
    private_key = decode_hex!(private_key_hex)
    digest = raw_hash(payload)
    sign_digest(private_key, public_key, digest, signer_type, :raw)
  end

  def verify_raw(signature, payload) do
    digest = raw_hash(payload)
    verify_digest(signature, digest)
  end

  def personal_hash(message) when is_binary(message) do
    payload = @personal_prefix <> Integer.to_string(byte_size(message)) <> message
    raw_hash(payload)
  end

  def raw_hash(payload) when is_binary(payload) do
    payload
    |> KeccakEx.hash_256()
    |> encode_hex()
  end

  def address_from_public_key(pubkey) when is_binary(pubkey) do
    stripped =
      case pubkey do
        <<4, rest::binary>> -> rest
        other -> other
      end

    digest = KeccakEx.hash_256(stripped)
    <<_::binary-size(12), address::binary-size(20)>> = digest
    "0x" <> Base.encode16(address, case: :lower)
  end

  def encode_hex(binary), do: "0x" <> Base.encode16(binary, case: :lower)

  def decode_hex!("0x" <> hex), do: Base.decode16!(String.upcase(hex), case: :mixed)
  def decode_hex!(hex), do: Base.decode16!(String.upcase(hex), case: :mixed)

  defp sign_digest(private_key, public_key, digest_hex, signer_type, purpose) do
    digest = decode_hex!(digest_hex)
    signature = :crypto.sign(:ecdsa, :sha256, digest, [private_key, :secp256k1])
    address = address_from_public_key(public_key)

    {:ok,
     %{
       purpose: purpose,
       signer_type: signer_type,
       digest: digest_hex,
       signature: encode_hex(signature),
       public_key: encode_hex(public_key),
       address: address
     }}
  rescue
    error -> {:error, error}
  end

  defp verify_digest(%{"signature" => _, "public_key" => _} = sig, digest_hex),
    do: verify_digest(atomize_signature(sig), digest_hex)

  defp verify_digest(
         %{signature: sig_hex, public_key: pub_hex, address: address} = signature,
         digest_hex
       ) do
    digest = decode_hex!(digest_hex)
    sig = decode_hex!(sig_hex)
    pub = decode_hex!(pub_hex)

    valid? = :crypto.verify(:ecdsa, :sha256, digest, sig, [pub, :secp256k1])
    derived_address = address_from_public_key(pub)

    if valid? and String.downcase(address) == String.downcase(derived_address) do
      {:ok, Map.put(signature, :derived_address, derived_address)}
    else
      {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp atomize_signature(signature) do
    %{
      purpose: Map.get(signature, "purpose"),
      signer_type: Map.get(signature, "signer_type", "eoa"),
      digest: Map.get(signature, "digest"),
      signature: Map.fetch!(signature, "signature"),
      public_key: Map.fetch!(signature, "public_key"),
      address: Map.fetch!(signature, "address")
    }
  end
end
