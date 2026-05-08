defmodule Eigenforge.Contracts do
  @moduledoc """
  Shared runtime helpers for Eigenforge V1 contract modules.

  Generated contract modules delegate validation, canonical JSON encoding,
  payload hashing, and HMAC signing here so the same rules are used by config,
  command envelopes, ledger events, and golden traces.
  """

  @type validation_error :: {:missing_required, atom()} | {:invalid_type, atom(), atom()}

  @doc """
  Builds a contract struct after validating required fields and basic JSON types.
  """
  @spec new(module(), map()) :: {:ok, struct()} | {:error, [validation_error()]}
  def new(module, attrs) when is_atom(module) and is_map(attrs) do
    normalized = normalize_keys(attrs)

    normalized =
      normalized
      |> Map.put_new(:format_version, module.format_version())
      |> Map.put_new(:schema_id, module.schema_id())
      |> Map.put_new(:schema_version, module.schema_version())

    case validate_map(module, normalized) do
      :ok -> {:ok, struct(module, Map.take(normalized, module.fields()))}
      {:error, errors} -> {:error, errors}
    end
  end

  @doc """
  Raises on invalid data and returns a contract struct.
  """
  @spec new!(module(), map()) :: struct()
  def new!(module, attrs) do
    case new(module, attrs) do
      {:ok, struct} -> struct
      {:error, errors} -> raise ArgumentError, "invalid #{inspect(module)}: #{inspect(errors)}"
    end
  end

  @doc """
  Validates a contract struct or map against generated field metadata.
  """
  @spec validate(module(), struct() | map()) :: :ok | {:error, [validation_error()]}
  def validate(module, %module{} = struct), do: validate_map(module, Map.from_struct(struct))
  def validate(module, attrs) when is_map(attrs), do: validate_map(module, normalize_keys(attrs))

  @doc """
  Returns the signable map for a contract.

  Signature fields are intentionally excluded from the signable body. Hash
  fields remain part of the body when present because command and ledger
  contracts carry explicit payload hashes.
  """
  @spec signable_map(struct() | map()) :: map()
  def signable_map(%_module{} = struct), do: struct |> Map.from_struct() |> signable_map()

  def signable_map(map) when is_map(map) do
    map
    |> normalize_keys()
    |> Map.drop([:signature])
    |> stringify_keys()
  end

  @doc """
  Encodes a map or struct as V1 canonical JSON.
  """
  @spec canonical_json(struct() | map() | list() | binary() | number() | boolean() | nil) ::
          binary()
  def canonical_json(value) do
    value
    |> normalize_for_json()
    |> JSON.encode!()
  end

  @doc """
  Computes a SHA-256 hash over canonical JSON and returns lowercase hex.
  """
  @spec payload_hash(struct() | map()) :: binary()
  def payload_hash(value) do
    :crypto.hash(:sha256, canonical_json(signable_map(value)))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Computes a SHA-256 hash over canonical JSON after dropping selected fields.
  """
  @spec hash_excluding(struct() | map(), [atom() | binary()]) :: binary()
  def hash_excluding(value, fields) when is_list(fields) do
    value
    |> drop_fields(fields)
    |> hash_canonical()
  end

  @doc """
  Computes a SHA-256 hash over canonical JSON without contract signature rules.
  """
  @spec hash_canonical(term()) :: binary()
  def hash_canonical(value) do
    :crypto.hash(:sha256, canonical_json(value))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Signs a contract or map with HMAC-SHA256 and returns lowercase hex.
  """
  @spec sign_hmac(struct() | map(), binary()) :: binary()
  def sign_hmac(value, secret) when is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, canonical_json(signable_map(value)))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Signs canonical JSON after dropping selected fields.
  """
  @spec sign_hmac_excluding(struct() | map(), binary(), [atom() | binary()]) :: binary()
  def sign_hmac_excluding(value, secret, fields) when is_binary(secret) and is_list(fields) do
    :crypto.mac(:hmac, :sha256, secret, canonical_json(drop_fields(value, fields)))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Verifies an HMAC-SHA256 signature using constant-time comparison.
  """
  @spec verify_hmac(struct() | map(), binary(), binary()) :: boolean()
  def verify_hmac(value, secret, signature) when is_binary(secret) and is_binary(signature) do
    expected = sign_hmac(value, secret)
    secure_compare(expected, String.downcase(signature))
  end

  defp validate_map(module, attrs) do
    errors =
      []
      |> missing_required_errors(module, attrs)
      |> type_errors(module, attrs)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp missing_required_errors(errors, module, attrs) do
    Enum.reduce(module.required_fields(), errors, fn field, acc ->
      if present?(Map.get(attrs, field)), do: acc, else: [{:missing_required, field} | acc]
    end)
  end

  defp type_errors(errors, module, attrs) do
    Enum.reduce(module.field_types(), errors, fn {field, type}, acc ->
      value = Map.get(attrs, field)

      if present?(value) and not valid_type?(value, type) do
        [{:invalid_type, field, type} | acc]
      else
        acc
      end
    end)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp valid_type?(value, :string), do: is_binary(value)
  defp valid_type?(value, :integer), do: is_integer(value)
  defp valid_type?(value, :number), do: is_number(value)
  defp valid_type?(value, :boolean), do: is_boolean(value)
  defp valid_type?(value, :object), do: is_map(value)
  defp valid_type?(value, :array), do: is_list(value)
  defp valid_type?(_value, :any), do: true

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} when is_atom(key) -> {key, value}
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_for_json(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {to_string(key), normalize_for_json(value)} end)
  end

  defp normalize_for_json(list) when is_list(list), do: Enum.map(list, &normalize_for_json/1)
  defp normalize_for_json(value), do: value

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  end

  defp secure_compare(_left, _right), do: false

  defp drop_fields(%_module{} = struct, fields), do: struct |> Map.from_struct() |> drop_fields(fields)

  defp drop_fields(map, fields) when is_map(map) do
    fields = Enum.flat_map(fields, fn field -> [field, to_string(field)] end)

    map
    |> normalize_keys()
    |> Map.drop(fields)
  end
end
