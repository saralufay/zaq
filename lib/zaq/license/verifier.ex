defmodule Zaq.License.Verifier do
  @moduledoc """
  Verifies license payload signatures using an Ed25519 public key.
  Supports compile-time embedding and runtime loading from disk.
  """

  @keys_dir "priv/keys"
  @public_key_path Path.join(@keys_dir, "public.pem")

  @external_resource @public_key_path

  @compile_time_key (if File.exists?(@public_key_path) do
                       @public_key_path
                       |> File.read!()
                       |> String.trim()
                       |> String.replace("-----BEGIN ED25519 PUBLIC KEY-----", "")
                       |> String.replace("-----END ED25519 PUBLIC KEY-----", "")
                       |> String.replace(~r/\s+/, "")
                       |> Base.decode64!()
                     else
                       nil
                     end)

  @doc """
  Returns the public key — compile-time embedded or runtime loaded from disk.
  """
  def public_key do
    if Application.get_env(:zaq, :license_runtime_key, false) do
      load_public_key_from_disk()
    else
      case @compile_time_key do
        nil -> load_public_key_from_disk()
        key -> {:ok, key}
      end
    end
  end

  @doc """
  Verifies a payload against a signature using the public key.
  Returns :ok or {:error, reason}.
  """
  def verify(payload, signature) when is_binary(payload) and is_binary(signature) do
    case public_key() do
      {:ok, pub} ->
        case :crypto.verify(:eddsa, :none, payload, signature, [pub, :ed25519]) do
          true -> :ok
          false -> {:error, :invalid_signature}
        end

      error ->
        error
    end
  end

  @doc """
  Parses a raw PEM string into a 32-byte Ed25519 public key binary.
  """
  def parse_public_pem(pem) do
    pem
    |> String.trim()
    |> String.replace("-----BEGIN ED25519 PUBLIC KEY-----", "")
    |> String.replace("-----END ED25519 PUBLIC KEY-----", "")
    |> String.replace(~r/\s+/, "")
    |> Base.decode64!()
  end

  defp load_public_key_from_disk do
    case File.read(@public_key_path) do
      {:ok, pem} -> {:ok, parse_public_pem(pem)}
      {:error, :enoent} -> {:error, :no_public_key}
    end
  end
end
