defmodule Eigenforge.Mailbox.SignedProposalPublisher do
  @moduledoc """
  Topic publisher for signed proposal deliveries.
  """

  alias Eigenforge.Mailbox.ChannelManager

  @default_registry Eigenforge.Mailbox.Registry

  @spec publish(String.t(), map() | struct(), keyword()) :: :ok | {:error, term()}
  def publish(topic, proposal, opts \\ []) when is_binary(topic) do
    proposal = wire_map(proposal)

    with {:ok, _delivered_to} <-
           ChannelManager.dispatch_signed_proposal(
             topic,
             proposal,
             registry_name: Keyword.get(opts, :registry_name, @default_registry)
           ) do
      :ok
    end
  end

  defp wire_map(%_module{} = struct) do
    struct
    |> Map.from_struct()
    |> wire_map()
  end

  defp wire_map(map) when is_map(map), do: stringify_keys(map)

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
