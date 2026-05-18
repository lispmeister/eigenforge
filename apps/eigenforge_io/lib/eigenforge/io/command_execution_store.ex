defmodule Eigenforge.IO.CommandExecutionStore do
  @moduledoc """
  Durable IO-local command execution store keyed by idempotency key.
  """

  use GenServer

  alias Eigenforge.Contracts

  @default_server __MODULE__
  @format_version "json-canonical-v1"
  @store_version 1
  @signature_version "hmac-sha256-v1"
  @manifest_kind "command_execution_store"
  @manifest_purpose "eigenforge:v1:command_execution_store"

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
  def already_executed?(server \\ @default_server, idempotency_key)
      when is_binary(idempotency_key) do
    GenServer.call(server, {:already_executed?, idempotency_key})
  end

  @spec record(GenServer.server(), map()) :: :ok | {:error, term()}
  def record(server \\ @default_server, attrs) when is_map(attrs) do
    GenServer.call(server, {:record, attrs})
  end

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    manifest_path = path <> ".manifest.json"

    state = %{
      path: path,
      manifest_path: manifest_path,
      secret: Keyword.get(opts, :secret),
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
      "adapter_attempt_id" =>
        Map.get(attrs, :adapter_attempt_id) || Map.get(attrs, "adapter_attempt_id"),
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
         {:ok, entries} <- load_or_initialize(state) do
      {:ok, %{state | entries: entries}}
    end
  end

  defp load_or_initialize(%{path: path, manifest_path: manifest_path} = state) do
    case {File.read(path), File.read(manifest_path)} do
      {{:error, :enoent}, {:error, :enoent}} ->
        persist(%{state | entries: %{}})
        |> case do
          {:ok, _next_state} -> {:ok, %{}}
          {:error, reason} -> {:error, reason}
        end

      {{:ok, body}, {:error, :enoent}} ->
        with {:ok, payload} <- decode_store(body),
             :ok <- migrate_legacy_store(state, payload["entries"]) do
          {:ok, payload["entries"]}
        else
          {:error, reason} -> {:error, reason}
        end

      {{:error, :enoent}, {:ok, _manifest}} ->
        {:error, :missing_command_execution_store}

      {{:ok, body}, {:ok, manifest_body}} ->
        with {:ok, payload} <- decode_store(body),
             {:ok, manifest} <- decode_manifest(manifest_body),
             :ok <- verify_manifest(payload, manifest, state.secret) do
          {:ok, payload["entries"]}
        else
          {:error, reason} -> {:error, reason}
        end

      {{:error, reason}, _} ->
        {:error, reason}

      {_, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp migrate_legacy_store(state, entries) when is_map(entries) do
    persist(%{state | entries: entries})
    |> case do
      {:ok, _next_state} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist(state) do
    payload = %{
      "format_version" => @format_version,
      "store_version" => @store_version,
      "entries" => state.entries
    }

    tmp_path = state.path <> ".tmp"
    tmp_manifest_path = state.manifest_path <> ".tmp"

    with {:ok, manifest} <- build_manifest(payload, state.secret),
         :ok <- File.write(tmp_path, Contracts.canonical_json(payload) <> "\n"),
         :ok <- File.write(tmp_manifest_path, Contracts.canonical_json(manifest) <> "\n"),
         :ok <- File.rename(tmp_path, state.path),
         :ok <- File.rename(tmp_manifest_path, state.manifest_path) do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_manifest(payload, secret) do
    if is_binary(secret) do
      payload_hash = Contracts.hash_canonical(payload)

      base = %{
        "format_version" => @format_version,
        "store_version" => @store_version,
        "manifest_kind" => @manifest_kind,
        "payload_hash" => payload_hash,
        "signature_version" => @signature_version,
        "signature" => ""
      }

      signature = Contracts.sign_hmac_excluding(base, secret, [:signature], @manifest_purpose)

      {:ok, Map.put(base, "signature", signature)}
    else
      {:error, :missing_command_execution_store_secret}
    end
  end

  defp decode_store(body) do
    with {:ok, decoded} <- Contracts.decode_json(body),
         %{
           "format_version" => @format_version,
           "store_version" => @store_version,
           "entries" => entries
         } = payload <- decoded,
         true <- is_map(entries) do
      {:ok, payload}
    else
      _ -> {:error, :invalid_command_execution_store}
    end
  end

  defp decode_manifest(body) do
    with {:ok, decoded} <- Contracts.decode_json(body),
         %{
           "format_version" => @format_version,
           "store_version" => @store_version,
           "manifest_kind" => @manifest_kind,
           "payload_hash" => payload_hash,
           "signature_version" => @signature_version,
           "signature" => signature
         } = manifest <- decoded,
         true <- is_binary(payload_hash) and payload_hash != "",
         true <- is_binary(signature) and signature != "" do
      {:ok, manifest}
    else
      _ -> {:error, :invalid_command_execution_manifest}
    end
  end

  defp verify_manifest(payload, manifest, secret) do
    if is_binary(secret) do
      cond do
        manifest["payload_hash"] != Contracts.hash_canonical(payload) ->
          {:error, :invalid_command_execution_manifest}

        not Contracts.verify_hmac(
          Map.drop(manifest, ["signature"]),
          secret,
          manifest["signature"],
          @manifest_purpose
        ) ->
          {:error, :invalid_command_execution_manifest}

        true ->
          :ok
      end
    else
      {:error, :missing_command_execution_store_secret}
    end
  end

  defp fetch(map, key) do
    Map.get(map, key) || Map.fetch!(map, Atom.to_string(key))
  end
end
