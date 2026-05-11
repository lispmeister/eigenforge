defmodule Eigenforge.Mailbox.ReceiptStore do
  @moduledoc """
  Durable receipt store for V1 mailbox delivery metadata.
  """

  use GenServer

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.DeliveryReceipt

  @default_server __MODULE__
  @signature_version "hmac-sha256-v1"
  @manifest_kind "mailbox_receipt_store"
  @store_version 1
  @format_version "json-canonical-v1"
  @initial_phase "receipt_stored"
  @allowed_phases MapSet.new(~w(receipt_stored publish_attempted io_accepted))

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
    %{
      id: Keyword.get(opts, :name, @default_server),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec store_receipt(GenServer.server(), String.t(), map(), keyword()) ::
          {:ok, DeliveryReceipt.t()} | {:error, term()}
  def store_receipt(server \\ @default_server, topic, command, opts)
      when is_binary(topic) and is_map(command) and is_list(opts) do
    GenServer.call(server, {:store_receipt, topic, command, opts})
  end

  @spec mark_phase(GenServer.server(), String.t(), String.t(), map()) :: :ok | {:error, term()}
  def mark_phase(server \\ @default_server, receipt_id, phase, metadata \\ %{})
      when is_binary(receipt_id) and is_binary(phase) and is_map(metadata) do
    GenServer.call(server, {:mark_phase, receipt_id, phase, metadata})
  end

  @spec fetch(GenServer.server(), String.t()) :: {:ok, map() | nil}
  def fetch(server \\ @default_server, receipt_id) when is_binary(receipt_id) do
    GenServer.call(server, {:fetch, receipt_id})
  end

  @spec entries(GenServer.server()) :: {:ok, map()}
  def entries(server \\ @default_server) do
    GenServer.call(server, :entries)
  end

  @spec entries_for_command(GenServer.server(), String.t()) :: {:ok, [map()]}
  def entries_for_command(server \\ @default_server, command_id) when is_binary(command_id) do
    GenServer.call(server, {:entries_for_command, command_id})
  end

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    secret = Keyword.fetch!(opts, :secret)

    state = %{
      path: path,
      manifest_path: path <> ".manifest.json",
      secret: secret,
      degraded?: false,
      receipts: %{}
    }

    case bootstrap(state) do
      {:ok, state} -> {:ok, state}
      {:error, _reason} -> {:ok, %{state | degraded?: true, receipts: %{}}}
    end
  end

  @impl true
  def handle_call({:store_receipt, _topic, _command, _opts}, _from, %{degraded?: true} = state) do
    {:reply, {:error, :receipt_store_unavailable}, state}
  end

  def handle_call({:store_receipt, topic, command, opts}, _from, state) do
    receipt =
      build_receipt(
        topic,
        command,
        Keyword.fetch!(opts, :ledger_sequence),
        Keyword.fetch!(opts, :ledger_event_hash),
        Keyword.fetch!(opts, :decision_event_id),
        state.secret
      )

    entry = %{
      "receipt" => wire_map(receipt),
      "delivery_phase" => @initial_phase,
      "phase_metadata" => %{
        "receipt_stored_at" => receipt.delivered_at
      }
    }

    receipts = Map.put(state.receipts, receipt.receipt_id, entry)

    case persist(%{state | receipts: receipts}) do
      {:ok, next_state} -> {:reply, {:ok, receipt}, next_state}
      {:error, reason} -> {:reply, {:error, reason}, %{state | degraded?: true}}
    end
  end

  def handle_call({:mark_phase, _receipt_id, _phase, _metadata}, _from, %{degraded?: true} = state) do
    {:reply, {:error, :receipt_store_unavailable}, state}
  end

  def handle_call({:mark_phase, receipt_id, phase, metadata}, _from, state) do
    cond do
      not MapSet.member?(@allowed_phases, phase) ->
        {:reply, {:error, {:invalid_phase, phase}}, state}

      not Map.has_key?(state.receipts, receipt_id) ->
        {:reply, {:error, :unknown_receipt}, state}

      true ->
        existing = Map.fetch!(state.receipts, receipt_id)
        phase_metadata = Map.merge(existing["phase_metadata"] || %{}, stringify_keys(metadata))
        entry = %{existing | "delivery_phase" => phase, "phase_metadata" => phase_metadata}
        receipts = Map.put(state.receipts, receipt_id, entry)

        case persist(%{state | receipts: receipts}) do
          {:ok, next_state} -> {:reply, :ok, next_state}
          {:error, reason} -> {:reply, {:error, reason}, %{state | degraded?: true}}
        end
    end
  end

  def handle_call({:fetch, receipt_id}, _from, state) do
    {:reply, {:ok, Map.get(state.receipts, receipt_id)}, state}
  end

  def handle_call(:entries, _from, state) do
    {:reply, {:ok, state.receipts}, state}
  end

  def handle_call({:entries_for_command, command_id}, _from, state) do
    entries =
      state.receipts
      |> Map.values()
      |> Enum.filter(&(get_in(&1, ["receipt", "command_id"]) == command_id))

    {:reply, {:ok, entries}, state}
  end

  defp bootstrap(state) do
    with :ok <- File.mkdir_p(Path.dirname(state.path)),
         :ok <- ensure_manifest(state),
         {:ok, receipts} <- load_receipts(state.path, state.secret) do
      {:ok, %{state | receipts: receipts}}
    end
  end

  defp ensure_manifest(%{manifest_path: manifest_path} = state) do
    case File.read(manifest_path) do
      {:ok, body} ->
        with {:ok, manifest} <- Contracts.decode_json(body),
             :ok <- verify_manifest(manifest, state.secret) do
          :ok
        end

      {:error, :enoent} ->
        manifest = build_manifest(state.secret)
        File.write(manifest_path, Contracts.canonical_json(manifest) <> "\n")

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_receipts(path, secret) do
    case File.read(path) do
      {:ok, body} ->
        with {:ok, decoded} <- Contracts.decode_json(body),
             %{"format_version" => @format_version, "store_version" => @store_version, "receipts" => receipts} <- decoded,
             :ok <- verify_receipts(receipts, secret) do
          {:ok, receipts}
        else
          {:error, reason} -> {:error, reason}
          _ -> {:error, :invalid_receipt_store}
        end

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_receipts(receipts, secret) when is_map(receipts) do
    Enum.reduce_while(receipts, :ok, fn {_receipt_id, entry}, :ok ->
      case verify_receipt_entry(entry, secret) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp verify_receipts(_receipts, _secret), do: {:error, :invalid_receipt_entries}

  defp verify_receipt_entry(
         %{
           "receipt" => %{
             "signature" => signature
           } = receipt,
           "delivery_phase" => phase
         },
         secret
       )
       when is_binary(signature) and is_binary(phase) do
    cond do
      not MapSet.member?(@allowed_phases, phase) ->
        {:error, {:invalid_receipt_phase, phase}}

      not Contracts.verify_hmac(receipt, secret, signature, "eigenforge:v1:delivery_receipt") ->
        {:error, :invalid_receipt_signature}

      true ->
        :ok
    end
  end

  defp verify_receipt_entry(_entry, _secret), do: {:error, :invalid_receipt_entry}

  defp persist(state) do
    payload = %{
      "format_version" => @format_version,
      "store_version" => @store_version,
      "receipts" => state.receipts
    }

    tmp_path = state.path <> ".tmp"

    with :ok <- File.write(tmp_path, Contracts.canonical_json(payload) <> "\n"),
         :ok <- File.rename(tmp_path, state.path) do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_receipt(topic, command, ledger_sequence, ledger_event_hash, decision_event_id, secret) do
    delivered_at = timestamp()

    base = %{
      receipt_id: receipt_id(command, ledger_event_hash),
      command_id: command["command_id"],
      decision_event_id: decision_event_id,
      ledger_sequence: ledger_sequence,
      ledger_event_hash: ledger_event_hash,
      delivered_topic: topic,
      delivered_at: delivered_at,
      signature_version: @signature_version,
      signature: ""
    }

    unsigned_receipt = DeliveryReceipt.new!(base)

    signature =
      Contracts.sign_hmac(unsigned_receipt, secret, "eigenforge:v1:delivery_receipt")

    %{unsigned_receipt | signature: signature}
  end

  defp build_manifest(secret) do
    base = %{
      "format_version" => @format_version,
      "store_kind" => @manifest_kind,
      "store_version" => @store_version,
      "created_at" => timestamp(),
      "signature_version" => @signature_version,
      "signature" => ""
    }

    signature =
      Contracts.sign_hmac_excluding(
        base,
        secret,
        ["signature"],
        "eigenforge:v1:mailbox_receipt_manifest"
      )

    Map.put(base, "signature", signature)
  end

  defp verify_manifest(
         %{
           "format_version" => @format_version,
           "store_kind" => @manifest_kind,
           "store_version" => @store_version,
           "signature_version" => @signature_version,
           "signature" => signature
         } = manifest,
         secret
       ) do
    expected =
      Contracts.sign_hmac_excluding(
        manifest,
        secret,
        ["signature"],
        "eigenforge:v1:mailbox_receipt_manifest"
      )

    if signature == expected, do: :ok, else: {:error, :invalid_manifest_signature}
  end

  defp verify_manifest(_manifest, _secret), do: {:error, :invalid_manifest}

  defp receipt_id(command, ledger_event_hash) do
    "receipt:v1:" <>
      Contracts.hash_canonical(%{
        "command_id" => command["command_id"],
        "decision_event_id" => command["decision_event_id"],
        "ledger_event_hash" => ledger_event_hash
      })
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp wire_map(%_module{} = struct) do
    struct
    |> Map.from_struct()
    |> stringify_keys()
  end
end
