defmodule Eigenforge.Mailbox.CommandPublisher do
  @moduledoc """
  V1 mailbox publisher for signed command envelope deliveries.
  """

  alias Eigenforge.Mailbox.PubSubTransport
  alias Eigenforge.Mailbox.ReceiptStore

  @default_registry Eigenforge.Mailbox.Registry
  @default_store Eigenforge.Mailbox.ReceiptStore
  @default_transport PubSubTransport

  @spec publish(String.t(), map() | struct(), keyword()) :: :ok | {:error, term()}
  def publish(topic, command, opts \\ []) when is_binary(topic) do
    registry = Keyword.get(opts, :registry_name, @default_registry)
    store = Keyword.get(opts, :receipt_store, @default_store)
    transport = Keyword.get(opts, :transport, @default_transport)
    command = wire_map(command)

    with {:ok, receipt} <-
           ReceiptStore.store_receipt(store, topic, command,
             ledger_sequence: Keyword.fetch!(opts, :ledger_sequence),
             ledger_event_hash: Keyword.fetch!(opts, :ledger_event_hash),
             decision_event_id: Keyword.fetch!(opts, :decision_event_id)
           ),
         :ok <-
           ReceiptStore.mark_phase(store, receipt.receipt_id, "publish_attempted", %{
             published_at: receipt.delivered_at
           }),
         {:ok, _evidence} <-
           transport.publish_command(command, wire_map(receipt),
             registry_name: registry,
             topic: topic
           ) do
      :ok
    end
  end

  @spec subscribe(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def subscribe(topic, opts \\ []) when is_binary(topic) do
    registry = Keyword.get(opts, :registry_name, @default_registry)
    Registry.register(registry, topic, [])
  end

  @spec mark_io_accepted(String.t(), map(), keyword()) :: :ok | {:error, term()}
  def mark_io_accepted(receipt_id, metadata \\ %{}, opts \\ [])
      when is_binary(receipt_id) and is_map(metadata) and is_list(opts) do
    store = Keyword.get(opts, :receipt_store, @default_store)
    ReceiptStore.mark_phase(store, receipt_id, "io_accepted", metadata)
  end

  defp wire_map(%_module{} = struct) do
    struct
    |> Map.from_struct()
    |> stringify_keys()
  end

  defp wire_map(map) when is_map(map), do: stringify_keys(map)

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
