defmodule Eigenforge.Core.TraceIdentity do
  @moduledoc """
  Deterministic identity helpers for V1 golden traces.
  """

  @spec stable_id(String.t(), [term()]) :: String.t()
  def stable_id(kind, parts) when is_binary(kind) and is_list(parts) do
    hash =
      parts
      |> Enum.map_join(":", &to_string/1)
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "#{kind}-#{hash}"
  end

  @spec source_observation_id(String.t(), String.t()) :: String.t()
  def source_observation_id(snapshot_id, source) do
    stable_id("source-observation", [snapshot_id, source])
  end

  @spec receive_seq(pos_integer(), String.t()) :: pos_integer()
  def receive_seq(snapshot_seq, _source) when is_integer(snapshot_seq) and snapshot_seq > 0 do
    snapshot_seq
  end

  @spec receive_monotonic_ms(non_neg_integer()) :: non_neg_integer()
  def receive_monotonic_ms(ordinal) when is_integer(ordinal) and ordinal >= 0 do
    ordinal
  end
end
