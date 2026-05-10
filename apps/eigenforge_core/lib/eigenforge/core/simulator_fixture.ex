defmodule Eigenforge.Core.SimulatorFixture do
  @moduledoc """
  Validation and loading for unsigned simulator snapshot fixtures.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Core.SnapshotBuilder

  @fixture_schema_id "eigenforge.simulator_fixture"
  @fixture_schema_version 1
  @metadata_keys ~w(fixture_schema_id fixture_schema_version scenario_id fixture_intent)

  @spec load_file(Path.t()) :: {:ok, %{scenario_id: String.t(), snapshot: map(), intent: map() | nil}} | {:error, term()}
  def load_file(path) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Contracts.decode_json(body),
         {:ok, loaded} <- load(decoded) do
      {:ok, loaded}
    else
      {:error, :enoent} -> {:error, {:missing_fixture, path}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec load(map()) :: {:ok, %{scenario_id: String.t(), snapshot: map(), intent: map() | nil}} | {:error, term()}
  def load(%{} = fixture) do
    with :ok <- validate_fixture_metadata(fixture),
         :ok <- validate_fixture_intent(fixture),
         snapshot_attrs <- Map.drop(fixture, @metadata_keys),
         {:ok, snapshot} <- SnapshotBuilder.build(snapshot_attrs) do
      {:ok,
       %{
         scenario_id: fixture["scenario_id"],
         snapshot:
           snapshot
           |> Contracts.signable_map()
           |> Map.drop(["format_version", "schema_id", "schema_version"]),
         intent: fixture["fixture_intent"]
       }}
    end
  end

  defp validate_fixture_metadata(fixture) do
    cond do
      fixture["fixture_schema_id"] != @fixture_schema_id ->
        {:error, {:unsupported_fixture_schema_id, fixture["fixture_schema_id"]}}

      fixture["fixture_schema_version"] != @fixture_schema_version ->
        {:error, {:unsupported_fixture_schema_version, fixture["fixture_schema_version"]}}

      not is_binary(fixture["scenario_id"]) or fixture["scenario_id"] == "" ->
        {:error, :missing_scenario_id}

      true ->
        :ok
    end
  end

  defp validate_fixture_intent(fixture) do
    malformed_statuses = ~w(malformed missing unknown unavailable)

    co2_status =
      fixture
      |> Map.get("source_status", %{})
      |> Map.get("co2")

    intent = fixture["fixture_intent"]

    if co2_status in malformed_statuses do
      case intent do
        %{"field" => field, "kind" => kind}
            when is_binary(field) and field != "" and is_binary(kind) and kind != "" ->
          :ok

        _ ->
          {:error, :missing_malformed_fixture_intent}
      end
    else
      :ok
    end
  end
end
