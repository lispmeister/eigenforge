defmodule Eigenforge.Core.SignedConfig do
  @moduledoc """
  Loaders for signed V1 runtime config artifacts.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CapabilityGrant
  alias Eigenforge.Contracts.DeviceInventory
  alias Eigenforge.Core.DetachedSignature
  alias Eigenforge.Core.RuntimeConfig

  @type load_error ::
          {:missing_file, Path.t()}
          | {:invalid_json, term()}
          | {:unsupported_schema, binary() | nil}
          | {:unsupported_schema_version, binary() | nil, term()}
          | {:unsupported_format_version, binary() | nil, term()}
          | {:invalid_signature, Path.t()}
          | {:active_room_error, term()}

  @type capability_lookup_key :: {String.t(), String.t(), String.t(), String.t()}

  @spec load_device_inventory(RuntimeConfig.t()) ::
          {:ok, %{inventory: DeviceInventory.t(), active_room: map()}} | {:error, load_error()}
  def load_device_inventory(%RuntimeConfig{} = config) do
    try do
      with {:ok, payload} <-
             read_and_verify(
               config.device_inventory_path,
               config.device_inventory_sig_path,
               config.hmac_secret
             ),
           %DeviceInventory{} = inventory <- DeviceInventory.new!(payload) do
        case RuntimeConfig.validate_active_room(payload) do
          {:ok, active_room} -> {:ok, %{inventory: inventory, active_room: active_room}}
          {:error, reason} -> {:error, {:active_room_error, reason}}
        end
      end
    rescue
      error in ArgumentError -> {:error, {:invalid_json, Exception.message(error)}}
    end
  end

  @spec load_capability_grants(RuntimeConfig.t()) ::
          {:ok, %{capability_lookup_key() => CapabilityGrant.t()}} | {:error, load_error()}
  def load_capability_grants(%RuntimeConfig{} = config) do
    try do
      json_paths =
        config.capability_grants_dir
        |> Path.join("*.json")
        |> Path.wildcard()
        |> Enum.reject(&String.ends_with?(&1, ".sig"))
        |> Enum.sort()

      Enum.reduce_while(json_paths, {:ok, %{}}, fn json_path, {:ok, acc} ->
        sig_path = json_path <> ".sig"

        case read_and_verify(json_path, sig_path, config.hmac_secret) do
          {:ok, payload} ->
            grant = CapabilityGrant.new!(payload)
            key = {grant.subject, grant.target, grant.action, grant.scope}
            {:cont, {:ok, Map.put(acc, key, grant)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    rescue
      error in ArgumentError -> {:error, {:invalid_json, Exception.message(error)}}
    end
  end

  defp read_and_verify(payload_path, sig_path, secret) do
    with {:ok, payload_body} <- read_file(payload_path),
         {:ok, sig_body} <- read_file(sig_path),
         {:ok, payload} <- decode(payload_body),
         {:ok, sidecar} <- decode(sig_body),
         :ok <- validate_schema(payload),
         :ok <- verify_sidecar(payload, sidecar, sig_path, secret) do
      {:ok, payload}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, :enoent} -> {:error, {:missing_file, path}}
      {:error, reason} -> {:error, {:invalid_json, {path, reason}}}
    end
  end

  defp decode(body) do
    case Contracts.decode_json(body) do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp validate_schema(%{
         "schema_id" => "eigenforge.device_inventory",
         "schema_version" => 1,
         "format_version" => "json-canonical-v1"
       }),
       do: :ok

  defp validate_schema(%{
         "schema_id" => "eigenforge.capability_grant",
         "schema_version" => 1,
         "format_version" => "json-canonical-v1"
       }),
       do: :ok

  defp validate_schema(%{"schema_id" => schema_id, "schema_version" => schema_version})
       when schema_id in ["eigenforge.device_inventory", "eigenforge.capability_grant"] and
              schema_version != 1 do
    {:error, {:unsupported_schema_version, schema_id, schema_version}}
  end

  defp validate_schema(%{"schema_id" => schema_id, "format_version" => format_version})
       when schema_id in ["eigenforge.device_inventory", "eigenforge.capability_grant"] and
              format_version != "json-canonical-v1" do
    {:error, {:unsupported_format_version, schema_id, format_version}}
  end

  defp validate_schema(payload) do
    {:error, {:unsupported_schema, payload["schema_id"]}}
  end

  defp verify_sidecar(payload, sidecar, sig_path, secret) do
    expected_hash = Contracts.hash_canonical(payload)

    expected_signature =
      Contracts.sign_hmac_excluding(
        sidecar,
        secret,
        [:signature],
        purpose_for_payload(payload)
      )

    cond do
      sidecar["payload_hash"] != expected_hash -> {:error, {:invalid_signature, sig_path}}
      sidecar["signature_version"] != DetachedSignature.signature_version() -> {:error, {:invalid_signature, sig_path}}
      sidecar["signature"] != expected_signature -> {:error, {:invalid_signature, sig_path}}
      true -> :ok
    end
  end

  defp purpose_for_payload(%{"schema_id" => "eigenforge.capability_grant"}),
    do: "eigenforge:v1:capability_grant"

  defp purpose_for_payload(_payload), do: "eigenforge:v1:config_sidecar"
end
