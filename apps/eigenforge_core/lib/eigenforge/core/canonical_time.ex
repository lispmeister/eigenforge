defmodule Eigenforge.Core.CanonicalTime do
  @moduledoc """
  Strict V1 UTC timestamp helpers.

  Signed and ledger-relevant V1 timestamps use exactly millisecond precision and
  a trailing `Z`, for example `2026-05-10T12:34:56.789Z`.
  """

  @canonical_regex ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
  @trace_start "2026-05-08T12:00:00.000Z"

  @spec trace_start() :: String.t()
  def trace_start, do: @trace_start

  @spec parse(String.t()) :: {:ok, DateTime.t()} | {:error, :noncanonical_timestamp}
  def parse(timestamp) when is_binary(timestamp) do
    if Regex.match?(@canonical_regex, timestamp) do
      case DateTime.from_iso8601(timestamp) do
        {:ok, datetime, 0} -> {:ok, DateTime.truncate(datetime, :millisecond)}
        _ -> {:error, :noncanonical_timestamp}
      end
    else
      {:error, :noncanonical_timestamp}
    end
  end

  def parse(_timestamp), do: {:error, :noncanonical_timestamp}

  @spec parse!(String.t()) :: DateTime.t()
  def parse!(timestamp) do
    case parse(timestamp) do
      {:ok, datetime} ->
        datetime

      {:error, reason} ->
        raise ArgumentError, "invalid V1 timestamp #{inspect(timestamp)}: #{reason}"
    end
  end

  @spec format(DateTime.t()) :: String.t()
  def format(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:millisecond)
    |> Calendar.strftime("%Y-%m-%dT%H:%M:%S.%3fZ")
  end

  @spec add_ms(String.t(), integer()) :: String.t()
  def add_ms(timestamp, milliseconds) when is_integer(milliseconds) do
    timestamp
    |> parse!()
    |> DateTime.add(milliseconds, :millisecond)
    |> format()
  end
end
