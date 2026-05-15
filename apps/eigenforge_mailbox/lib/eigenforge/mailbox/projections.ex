defmodule Eigenforge.Mailbox.Projections do
  @moduledoc """
  Read-only projections over mailbox receipt state.
  """

  alias Eigenforge.Mailbox.ReceiptStore

  @default_store ReceiptStore

  @spec pending_commands(GenServer.server() | nil, keyword()) :: {:ok, [map()]} | {:error, term()}
  def pending_commands(store \\ @default_store, opts \\ []) do
    with {:ok, entries} <- ReceiptStore.entries(store) do
      room_id = Keyword.get(opts, :room_id)

      pending =
        entries
        |> Map.values()
        |> Enum.filter(fn entry ->
          entry["delivery_phase"] != "io_accepted" and
            (is_nil(room_id) or get_in(entry, ["receipt", "room_id"]) == room_id)
        end)

      {:ok, pending}
    end
  end

  @spec delivery_status(GenServer.server() | nil, String.t()) :: {:ok, map() | nil}
  def delivery_status(store \\ @default_store, receipt_id) when is_binary(receipt_id) do
    ReceiptStore.fetch(store, receipt_id)
  end

  @spec receipts_for_command(GenServer.server() | nil, String.t()) :: {:ok, [map()]}
  def receipts_for_command(store \\ @default_store, command_id) when is_binary(command_id) do
    ReceiptStore.entries_for_command(store, command_id)
  end
end
