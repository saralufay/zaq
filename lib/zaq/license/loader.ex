defmodule Zaq.License.Loader do
  @moduledoc """
  Reads, validates, and loads a .zaq-license package.
  Extracts license data, verifies signature, decrypts BEAM modules,
  and loads them into the BEAM VM.
  """

  alias Zaq.License.{Verifier, BeamDecryptor, FeatureStore}

  require Logger

  @doc """
  Loads a .zaq-license file from the given path.
  Returns {:ok, license_data} or {:error, reason}.
  """
  def load(license_path) do
    with {:ok, files} <- extract_package(license_path),
         {:ok, payload, signature} <- parse_license_dat(files),
         :ok <- Verifier.verify(payload, signature),
         {:ok, license_data} <- decode_payload(payload),
         :ok <- check_expiry(license_data),
         key <- BeamDecryptor.derive_key(payload),
         {:ok, loaded_modules} <- decrypt_and_load_modules(files, key) do
      FeatureStore.store(license_data, loaded_modules)
      Logger.info("License loaded successfully: #{license_data["license_key"]}")
      {:ok, license_data}
    else
      {:error, reason} = error ->
        Logger.error("License loading failed: #{inspect(reason)}")
        error
    end
  end

  defp extract_package(path) do
    case :erl_tar.extract(String.to_charlist(path), [:memory, :compressed]) do
      {:ok, files} ->
        file_map =
          Enum.into(files, %{}, fn {name, content} ->
            {List.to_string(name), content}
          end)

        {:ok, file_map}

      {:error, reason} ->
        {:error, {:extract_failed, reason}}
    end
  end

  defp parse_license_dat(files) do
    case Map.fetch(files, "license.dat") do
      {:ok, dat} ->
        case String.split(to_string(dat), ".") do
          [payload_b64, signature_b64] ->
            with {:ok, payload} <- Base.decode64(payload_b64),
                 {:ok, signature} <- Base.decode64(signature_b64) do
              {:ok, payload, signature}
            else
              :error -> {:error, :invalid_license_dat_encoding}
            end

          _ ->
            {:error, :invalid_license_dat_format}
        end

      :error ->
        {:error, :missing_license_dat}
    end
  end

  defp decode_payload(payload) do
    case Jason.decode(payload) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, :invalid_payload_json}
    end
  end

  defp check_expiry(license_data) do
    case Map.fetch(license_data, "expires_at") do
      {:ok, expires_str} ->
        case DateTime.from_iso8601(expires_str) do
          {:ok, expires_at, _} ->
            if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
              :ok
            else
              {:error, :license_expired}
            end

          _ ->
            {:error, :invalid_expires_at}
        end

      :error ->
        {:error, :missing_expires_at}
    end
  end

  defp decrypt_and_load_modules(files, key) do
    enc_files =
      files
      |> Enum.filter(fn {name, _} -> String.starts_with?(name, "modules/") end)

    results =
      Enum.reduce_while(enc_files, {:ok, []}, fn {name, content}, {:ok, acc} ->
        module_name =
          name
          |> String.replace_prefix("modules/", "")
          |> String.replace_suffix(".beam.enc", "")

        case BeamDecryptor.decrypt(content, key) do
          {:ok, beam_binary} ->
            module_atom = String.to_atom(module_name)

            case :code.load_binary(module_atom, ~c"#{module_name}.beam", beam_binary) do
              {:module, ^module_atom} ->
                {:cont, {:ok, [module_atom | acc]}}

              {:error, reason} ->
                {:halt, {:error, {:load_failed, module_name, reason}}}
            end

          {:error, reason} ->
            {:halt, {:error, {:decrypt_failed, module_name, reason}}}
        end
      end)

    case results do
      {:ok, modules} -> {:ok, Enum.reverse(modules)}
      error -> error
    end
  end
end
