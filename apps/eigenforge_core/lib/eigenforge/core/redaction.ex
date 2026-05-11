defmodule Eigenforge.Core.Redaction do
  @moduledoc """
  Shared redaction helpers for secrets that may surface in logs, dashboard data,
  or other read-only views.
  """

  @redacted "[REDACTED]"
  @env_secret_pattern ~r/(^|_)(TOKEN|SECRET|PASSWORD|KEY)($|_)/i
  @field_secret_pattern ~r/(^|_)(TOKEN|SECRET|PASSWORD)($|_)/i
  @qualified_key_pattern ~r/(^|_)(API_KEY|ACCESS_KEY|PRIVATE_KEY|HMAC_SECRET|HOME_ASSISTANT_TOKEN)($|_)/i
  @safe_lowercase_key_names MapSet.new([
    "capability_key",
    "effect_key",
    "idempotency_key",
    "pending_effect_key"
  ])

  @spec redact(term(), keyword()) :: term()
  def redact(value, opts \\ []) do
    secrets = opts |> Keyword.get(:secrets, []) |> Enum.reject(&blank?/1)
    do_redact(value, secrets)
  end

  defp do_redact(map, secrets) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if sensitive_key?(key) do
        {key, @redacted}
      else
        {key, do_redact(value, secrets)}
      end
    end)
  end

  defp do_redact(list, secrets) when is_list(list), do: Enum.map(list, &do_redact(&1, secrets))

  defp do_redact(value, secrets) when is_binary(value) do
    Enum.reduce(secrets, value, fn secret, acc ->
      String.replace(acc, secret, @redacted)
    end)
  end

  defp do_redact(value, _secrets), do: value

  defp sensitive_key?(key) do
    key = to_string(key)
    lowercase = String.downcase(key)

    cond do
      MapSet.member?(@safe_lowercase_key_names, lowercase) ->
        false

      key == String.upcase(key) and Regex.match?(@env_secret_pattern, key) ->
        true

      Regex.match?(@field_secret_pattern, key) ->
        true

      Regex.match?(@qualified_key_pattern, key) ->
        true

      true ->
        false
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
