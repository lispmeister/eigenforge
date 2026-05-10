defmodule Eigenforge.Mailbox.CommandPublisher do
  @moduledoc """
  Minimal V1 mailbox publisher for command envelopes.
  """

  @default_registry Eigenforge.Mailbox.Registry

  @spec publish(String.t(), map() | struct(), keyword()) :: :ok
  def publish(topic, command, opts \\ []) when is_binary(topic) do
    registry = Keyword.get(opts, :registry_name, @default_registry)

    Registry.dispatch(registry, topic, fn entries ->
      Enum.each(entries, fn {pid, _value} -> send(pid, {:mailbox_command, topic, command}) end)
    end)

    :ok
  end

  @spec subscribe(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def subscribe(topic, opts \\ []) when is_binary(topic) do
    registry = Keyword.get(opts, :registry_name, @default_registry)
    Registry.register(registry, topic, [])
  end
end
