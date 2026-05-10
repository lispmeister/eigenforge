defmodule Eigenforge.Core.DetachedSignature do
  @moduledoc """
  Helpers for V1 detached signature sidecars.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.CapabilityGrant
  alias Eigenforge.Contracts.DeviceInventory

  @signature_version "hmac-sha256-v1"

  @spec sign_payload(map(), binary()) :: %{payload_hash: binary(), signature: binary(), signature_version: binary()}
  def sign_payload(payload, secret) when is_map(payload) and is_binary(secret) do
    payload_hash = Contracts.hash_canonical(payload)

    sidecar = %{
      payload_hash: payload_hash,
      signature_version: @signature_version,
      signature: ""
    }

    signature =
      Contracts.sign_hmac_excluding(
        sidecar,
        secret,
        [:signature],
        purpose_for_payload(payload)
      )

    %{payload_hash: payload_hash, signature_version: @signature_version, signature: signature}
  end

  @spec canonical_sidecar_json(map(), binary()) :: binary()
  def canonical_sidecar_json(payload, secret) do
    payload
    |> sign_payload(secret)
    |> Contracts.canonical_json()
  end

  @spec validate_payload!(map()) :: struct()
  def validate_payload!(%{"schema_id" => "eigenforge.device_inventory"} = payload),
    do: DeviceInventory.new!(payload)

  def validate_payload!(%{"schema_id" => "eigenforge.capability_grant"} = payload),
    do: CapabilityGrant.new!(payload)

  def validate_payload!(%{schema_id: "eigenforge.device_inventory"} = payload),
    do: DeviceInventory.new!(payload)

  def validate_payload!(%{schema_id: "eigenforge.capability_grant"} = payload),
    do: CapabilityGrant.new!(payload)

  def validate_payload!(payload) do
    raise ArgumentError,
          "unsupported detached-signature payload schema_id: #{inspect(Map.get(payload, "schema_id") || Map.get(payload, :schema_id))}"
  end

  @spec signature_version() :: binary()
  def signature_version, do: @signature_version

  defp purpose_for_payload(%{"schema_id" => "eigenforge.capability_grant"}),
    do: "eigenforge:v1:capability_grant"

  defp purpose_for_payload(%{schema_id: "eigenforge.capability_grant"}),
    do: "eigenforge:v1:capability_grant"

  defp purpose_for_payload(_payload), do: "eigenforge:v1:config_sidecar"
end
