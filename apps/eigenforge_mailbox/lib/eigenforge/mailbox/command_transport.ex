defmodule Eigenforge.Mailbox.CommandTransport do
  @moduledoc """
  Behaviour for publishing mailbox command deliveries.
  """

  @callback publish_command(envelope :: map(), receipt :: map(), opts :: keyword()) ::
              {:ok, delivery_evidence :: map()} | {:error, reason :: term()}
end
