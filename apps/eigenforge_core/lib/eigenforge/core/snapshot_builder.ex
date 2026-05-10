defmodule Eigenforge.Core.SnapshotBuilder do
  @moduledoc """
  Normalized snapshot construction helpers shared by trace and simulator paths.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.NormalizedSnapshot

  @spec build(map()) :: {:ok, NormalizedSnapshot.t()} | {:error, term()}
  def build(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new("snapshot_hash", "")
      |> Map.put_new("humidity_basis_points", 4500)
      |> Map.put_new("temperature_millicelsius", 22_000)
      |> Map.put_new("source_entity_ids", %{})
      |> Map.put_new("source_observation_ids", %{})
      |> Map.put_new("source_observed_at", %{})
      |> Map.put_new("source_received_seq", %{})
      |> Map.put_new("source_received_monotonic_ms", %{})
      |> Map.put_new("source_status", %{})
      |> Map.put_new("normalized_at", "2026-05-08T12:00:00.000Z")
      |> Map.put_new("freshness", "fresh")

    snapshot_hash =
      attrs
      |> Map.put("snapshot_hash", nil)
      |> Contracts.hash_canonical()

    attrs
    |> Map.put("snapshot_hash", snapshot_hash)
    |> then(&{:ok, NormalizedSnapshot.new!(&1)})
  rescue
    error -> {:error, {:invalid_snapshot, Exception.message(error)}}
  end
end
