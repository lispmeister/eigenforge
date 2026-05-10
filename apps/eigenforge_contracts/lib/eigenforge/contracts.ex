defmodule Eigenforge.Contracts do
  @moduledoc """
  Shared runtime helpers for Eigenforge V1 contract modules.

  Generated contract modules delegate validation, canonical JSON encoding,
  payload hashing, and HMAC signing here so the same rules are used by config,
  command envelopes, ledger events, and golden traces.
  """

  @type validation_error ::
          {:missing_required, atom()}
          | {:invalid_type, atom(), atom()}
          | {:schema_error, term()}
  @signed_int_min -9_223_372_036_854_775_808
  @signed_int_max 9_223_372_036_854_775_807
  @canonical_timestamp_regex ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
  @timestamp_candidate_regex ~r/^\d{4}-\d{2}-\d{2}T/
  @generic_purpose "eigenforge:v1:contract"
  @purpose_labels %{
    "eigenforge.device_inventory" => "eigenforge:v1:config_sidecar",
    "eigenforge.capability_grant" => "eigenforge:v1:capability_grant",
    "eigenforge.command_envelope" => "eigenforge:v1:command_envelope",
    "eigenforge.delivery_receipt" => "eigenforge:v1:delivery_receipt",
    "eigenforge.ledger_event" => "eigenforge:v1:ledger_event"
  }

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
    |> canonical_iodata()
    |> IO.iodata_to_binary()
  end

  @doc """
  Decodes JSON while rejecting duplicate object keys.
  """
  @spec decode_json(binary()) :: {:ok, term()} | {:error, term()}
  def decode_json(binary) when is_binary(binary) do
    decoders = [
      object_start: fn _old_acc -> {[], MapSet.new()} end,
      object_push: fn key, value, {pairs, seen_keys} ->
        if MapSet.member?(seen_keys, key) do
          throw({:duplicate_key, key})
        else
          {[{key, value} | pairs], MapSet.put(seen_keys, key)}
        end
      end,
      object_finish: fn {pairs, _seen_keys}, old_acc -> {Map.new(Enum.reverse(pairs)), old_acc} end
    ]

    case JSON.decode(binary, nil, decoders) do
      {decoded, _acc, ""} -> {:ok, decoded}
      {_decoded, _acc, rest} -> {:error, {:trailing_data, rest}}
      {:error, reason} -> {:error, reason}
    end
  catch
    {:duplicate_key, key} -> {:error, {:duplicate_key, key}}
  end

  @spec decode_json!(binary()) :: term()
  def decode_json!(binary) when is_binary(binary) do
    case decode_json(binary) do
      {:ok, decoded} -> decoded
      {:error, reason} -> raise ArgumentError, "invalid JSON: #{inspect(reason)}"
    end
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
  @spec sign_hmac(struct() | map(), binary(), binary() | nil) :: binary()
  def sign_hmac(value, secret, purpose_override \\ nil) when is_binary(secret) do
    message =
      value
      |> signable_map()
      |> hmac_message(purpose_override)

    :crypto.mac(:hmac, :sha256, secret, message)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Signs canonical JSON after dropping selected fields.
  """
  @spec sign_hmac_excluding(struct() | map(), binary(), [atom() | binary()], binary() | nil) ::
          binary()
  def sign_hmac_excluding(value, secret, fields, purpose_override \\ nil)
      when is_binary(secret) and is_list(fields) do
    message =
      value
      |> drop_fields(fields)
      |> hmac_message(purpose_override)

    :crypto.mac(:hmac, :sha256, secret, message)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Verifies an HMAC-SHA256 signature using constant-time comparison.
  """
  @spec verify_hmac(struct() | map(), binary(), binary(), binary() | nil) :: boolean()
  def verify_hmac(value, secret, signature, purpose_override \\ nil)
      when is_binary(secret) and is_binary(signature) do
    expected = sign_hmac(value, secret, purpose_override)
    secure_compare(expected, String.downcase(signature))
  end

  @doc """
  Returns the inferred HMAC purpose label for a contract payload.
  """
  @spec purpose_label(struct() | map()) :: binary()
  def purpose_label(value) do
    value
    |> schema_id_for_value()
    |> then(&Map.get(@purpose_labels, &1, @generic_purpose))
  end

  defp validate_map(module, attrs) do
    errors =
      []
      |> missing_required_errors(module, attrs)
      |> type_errors(module, attrs)
      |> schema_errors(module, attrs)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp missing_required_errors(errors, module, attrs) do
    Enum.reduce(module.required_fields(), errors, fn field, acc ->
      if Map.has_key?(attrs, field), do: acc, else: [{:missing_required, field} | acc]
    end)
  end

  defp type_errors(errors, module, attrs) do
    Enum.reduce(module.field_types(), errors, fn {field, type}, acc ->
      value = Map.get(attrs, field)

      if Map.has_key?(attrs, field) and not is_nil(value) and not valid_type?(value, type) do
        [{:invalid_type, field, type} | acc]
      else
        acc
      end
    end)
  end

  defp schema_errors(errors, module, attrs) do
    payload = stringify_keys(attrs)

    case load_schema(module) do
      {:ok, schema} ->
        case validate_schema(payload, schema, "$") do
          [] -> errors
          schema_failures -> Enum.reduce(schema_failures, errors, &[{:schema_error, &1} | &2])
        end

      {:error, reason} ->
        [{:schema_error, reason} | errors]
    end
  end

  defp valid_type?(value, :string), do: is_binary(value)
  defp valid_type?(value, :integer), do: is_integer(value)
  defp valid_type?(value, :number), do: is_number(value)
  defp valid_type?(value, :boolean), do: is_boolean(value)
  defp valid_type?(value, :object), do: is_map(value)
  defp valid_type?(value, :array), do: is_list(value)
  defp valid_type?(_value, :any), do: true

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {existing_atom_or_string(key), value}
      {key, value} when is_atom(key) -> {key, value}
    end)
  end

  defp existing_atom_or_string(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp load_schema(module) do
    module
    |> schema_path()
    |> File.read()
    |> case do
      {:ok, body} -> {:ok, decode_json!(body)}
      {:error, reason} -> {:error, {:schema_unavailable, module, reason}}
    end
  end

  defp schema_path(module) do
    schema_file =
      module.schema_id()
      |> String.replace_prefix("eigenforge.", "")
      |> Kernel.<>(".schema.json")

    Path.expand("../../priv/schemas/#{schema_file}", __DIR__)
  end

  defp validate_schema(value, %{"const" => const}, path) do
    if value == const, do: [], else: [{:const_mismatch, path, const, value}]
  end

  defp validate_schema(value, schema, path) when is_map(schema) do
    type_errors = validate_schema_type(value, schema, path)

    if type_errors != [] do
      type_errors
    else
      validate_schema_by_type(value, schema, path)
    end
  end

  defp validate_schema_type(value, %{"type" => types}, path) when is_list(types) do
    if Enum.any?(types, &matches_schema_type?(value, &1)),
      do: [],
      else: [{:type_mismatch, path, types, value}]
  end

  defp validate_schema_type(value, %{"type" => type}, path) when is_binary(type) do
    if matches_schema_type?(value, type), do: [], else: [{:type_mismatch, path, type, value}]
  end

  defp validate_schema_type(_value, _schema, _path), do: []

  defp validate_schema_by_type(value, %{"enum" => enum}, path) do
    if value in enum, do: [], else: [{:enum_mismatch, path, enum, value}]
  end

  defp validate_schema_by_type(value, %{"properties" => properties} = schema, path) when is_map(value) do
    additional_errors =
      if Map.get(schema, "additionalProperties", true) == false do
        allowed = Map.keys(properties) |> MapSet.new()

        value
        |> Map.keys()
        |> Enum.reject(&MapSet.member?(allowed, &1))
        |> Enum.map(&{:unexpected_property, path, &1})
      else
        []
      end

    required_errors =
      schema
      |> Map.get("required", [])
      |> Enum.reject(&Map.has_key?(value, &1))
      |> Enum.map(&{:missing_property, path, &1})

    nested_errors =
      Enum.flat_map(properties, fn {key, property_schema} ->
        if Map.has_key?(value, key) do
          validate_schema(Map.get(value, key), property_schema, "#{path}.#{key}")
        else
          []
        end
      end)

    additional_errors ++ required_errors ++ nested_errors
  end

  defp validate_schema_by_type(value, %{"items" => item_schema}, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> validate_schema(item, item_schema, "#{path}[#{index}]") end)
  end

  defp validate_schema_by_type(_value, _schema, _path), do: []

  defp matches_schema_type?(nil, "null"), do: true
  defp matches_schema_type?(value, "string"), do: is_binary(value)
  defp matches_schema_type?(value, "integer"), do: is_integer(value)
  defp matches_schema_type?(value, "number"), do: is_number(value)
  defp matches_schema_type?(value, "boolean"), do: is_boolean(value)
  defp matches_schema_type?(value, "object"), do: is_map(value)
  defp matches_schema_type?(value, "array"), do: is_list(value)
  defp matches_schema_type?(_value, _type), do: false

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp canonical_iodata(%_module{} = struct), do: struct |> Map.from_struct() |> canonical_iodata()

  defp canonical_iodata(map) when is_map(map) do
    validate_canonical!(map)

    entries =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, value} ->
        [JSON.encode!(to_string(key)), ?:, canonical_iodata(value)]
      end)

    [?{, Enum.intersperse(entries, ?,), ?}]
  end

  defp canonical_iodata(list) when is_list(list) do
    validate_canonical!(list)
    [?[, Enum.intersperse(Enum.map(list, &canonical_iodata/1), ?,), ?]]
  end

  defp canonical_iodata(value) when is_binary(value) do
    validate_canonical!(value)
    JSON.encode!(value)
  end

  defp canonical_iodata(value) when is_integer(value) do
    validate_canonical!(value)
    Integer.to_string(value)
  end

  defp canonical_iodata(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp canonical_iodata(nil), do: "null"

  defp canonical_iodata(value) do
    raise ArgumentError, "unsupported canonical JSON value: #{inspect(value)}"
  end

  defp hmac_message(value, purpose_override) do
    purpose = purpose_override || purpose_label(value)
    "#{purpose}\n#{canonical_json(value)}"
  end

  defp schema_id_for_value(%module{}) when is_atom(module) do
    if function_exported?(module, :schema_id, 0), do: module.schema_id(), else: nil
  end

  defp schema_id_for_value(map) when is_map(map) do
    map
    |> normalize_keys()
    |> Map.get(:schema_id)
  end

  defp schema_id_for_value(_value), do: nil

  defp validate_canonical!(%_module{} = struct), do: validate_canonical!(Map.from_struct(struct))

  defp validate_canonical!(map) when is_map(map) do
    Enum.each(map, fn
      {key, value} when is_binary(key) or is_atom(key) ->
        validate_canonical!(value)

      {key, _value} ->
        raise ArgumentError, "canonical JSON object keys must be strings or atoms, got: #{inspect(key)}"
    end)
  end

  defp validate_canonical!(list) when is_list(list), do: Enum.each(list, &validate_canonical!/1)

  defp validate_canonical!(value) when is_integer(value) do
    if value < @signed_int_min or value > @signed_int_max do
      raise ArgumentError, "canonical JSON integer out of signed 64-bit range: #{inspect(value)}"
    end
  end

  defp validate_canonical!(value) when is_float(value) do
    raise ArgumentError, "canonical JSON floats are not allowed in signed payloads: #{inspect(value)}"
  end

  defp validate_canonical!(value) when is_binary(value) do
    if Regex.match?(@timestamp_candidate_regex, value) and
         not Regex.match?(@canonical_timestamp_regex, value) do
      raise ArgumentError, "noncanonical V1 timestamp: #{inspect(value)}"
    end
  end

  defp validate_canonical!(value) when is_boolean(value) or is_nil(value), do: value

  defp validate_canonical!(value) do
    raise ArgumentError, "unsupported canonical JSON value: #{inspect(value)}"
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  end

  defp secure_compare(_left, _right), do: false

  defp drop_fields(%_module{} = struct, fields),
    do: struct |> Map.from_struct() |> drop_fields(fields)

  defp drop_fields(map, fields) when is_map(map) do
    fields = Enum.flat_map(fields, fn field -> [field, to_string(field)] end)

    map
    |> normalize_keys()
    |> Map.drop(fields)
  end
end
