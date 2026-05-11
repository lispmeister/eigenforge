defmodule Eigenforge.Mailbox.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    hmac_secret =
      System.get_env("EIGENFORGE_HMAC_SECRET") ||
        Application.get_env(:eigenforge_mailbox, :hmac_secret, "replace_me")

    receipt_store_path =
      System.get_env("EIGENFORGE_MAILBOX_RECEIPT_STORE_PATH") ||
        Application.get_env(:eigenforge_mailbox, :receipt_store_path, "log/mailbox_receipts.json")

    Supervisor.start_link(
      [
        {Registry, keys: :duplicate, name: Eigenforge.Mailbox.Registry},
        {Eigenforge.Mailbox.ReceiptStore,
         path: receipt_store_path, secret: hmac_secret, name: Eigenforge.Mailbox.ReceiptStore}
      ],
      strategy: :one_for_one,
      name: Eigenforge.Mailbox.Supervisor
    )
  end
end
