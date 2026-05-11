defmodule Eigenforge.IO.CommandExecutionStore do
  @moduledoc """
  Durable IO-local command execution store keyed by idempotency key.
  """

  use GenServer

  alias Eigenforge.Contracts

  @default_server __MODULE__
  @format_version "json-canonical-v1"
  @store_version 1

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name, @default_server)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      _ -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, @default_server), start: {__MODULE__, :start_link, [opts]}}
  end

  @spec already_executed?(GenServer.server(), String.t()) :: boolean()
  def already_executed?(server \\ @default_server, idempotency_key) when is_binary(idempotency_key) do
    GenServer.call(server, {:already_executed?, idempotency_key})
  end

  @spec record(GenServer.server(), map()) :: :ok | {:error, term()}
  def record(server \\ @default_server, attrs) when is_map(attrs) do
    GenServer.call(server, {:record, attrs})
  end

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)

    state = %{
      path: path,
      entries: %{},
      degraded?: false
    }

    case bootstrap(state) do
      {:ok, next_state} -> {:ok, next_state}
      {:error, _reason} -> {:ok, %{state | degraded?: true}}
    end
  end

  @impl true
  def handle_call({:already_executed?, _idempotency_key}, _from, %{degraded?: true} = state) do
    {:reply, true, state}
  end

  def handle_call({:already_executed?, idempotency_key}, _from, state) do
    {:reply, Map.has_key?(state.entries, idempotency_key), state}
  end

  def handle_call({:record, _attrs}, _from, %{degraded?: true} = state) do
    {:reply, {:error, :command_execution_store_unavailable}, state}
  end

  def handle_call({:record, attrs}, _from, state) do
    key = fetch(attrs, :idempotency_key)

    entry = %{
      "command_id" => fetch(attrs, :command_id),
      "effect_key" => fetch(attrs, :effect_key),
      "target" => fetch(attrs, :target),
      "requested_state" => fetch(attrs, :requested_state),
      "adapter_attempt_id" => Map.get(attrs, :adapter_attempt_id) || Map.get(attrs, "adapter_attempt_id"),
      "execution_status" => fetch(attrs, :execution_status),
      "recorded_at" => fetch(attrs, :recorded_at)
    }

    entries = Map.put(state.entries, key, entry)

    case persist(%{state | entries: entries}) do
      {:ok, next_state} -> {:reply, :ok, next_state}
      {:error, reason} -> {:reply, {:error, reason}, %{state | degraded?: true}}
    end
  end

  defp bootstrap(state) do
    with :ok <- File.mkdir_p(Path.dirname(state.path)),
         {:ok, entries} <- load_entries(state.path) do
      {:ok, %{state | entries: entries}}
    end
  end

  defp load_entries(path) do
    case File.read(path) do
      {:ok, body} ->
        with {:ok, decoded} <- Contracts.decode_json(body),
             %{"format_version" => @format_version, "store_version" => @store_version, "entries" => entries} <- decoded do
          {:ok, entries}
        else
          _ -> {:error, :invalid_command_execution_store}
        end

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist(state) do
    payload = %{
      "format_version" => @format_version,
      "store_version" => @store_version,
      "entries" => state.entries
    }

    tmp_path = state.path <> ".tmp"

    with :ok <- File.write(tmp_path, Contracts.canonical_json(payload) <> "\n"),
         :ok <- File.rename(tmp_path, state.path) do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch(map, key) do
    Map.get(map, key) || Map.fetch!(map, Atom.to_string(key))
  end
end
