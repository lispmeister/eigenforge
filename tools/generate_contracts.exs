#!/usr/bin/env elixir

schemas_dir = Path.expand("../apps/eigenforge_contracts/priv/schemas", __DIR__)
out_dir = Path.expand("../apps/eigenforge_contracts/lib/eigenforge/contracts/generated", __DIR__)

File.mkdir_p!(out_dir)

type_spec = fn
  :string -> "String.t() | nil"
  :integer -> "integer() | nil"
  :number -> "number() | nil"
  :boolean -> "boolean() | nil"
  :object -> "map() | nil"
  :array -> "list() | nil"
  :any -> "term()"
end

schema_paths =
  schemas_dir
  |> Path.join("*.schema.json")
  |> Path.wildcard()
  |> Enum.sort()

if schema_paths == [] do
  IO.warn("no schemas found in #{schemas_dir}")
end

Enum.each(schema_paths, fn path ->
  schema = path |> File.read!() |> JSON.decode!()
  module = Map.fetch!(schema, "x-elixir-module")
  schema_id = Map.fetch!(schema, "$id")
  schema_version = Map.fetch!(schema, "x-schema-version")
  format_version = Map.get(schema, "x-format-version", "json-canonical-v1")
  properties = Map.fetch!(schema, "properties")
  required = Map.get(schema, "required", [])

  fields =
    properties
    |> Map.keys()
    |> Enum.sort()

  field_types =
    Enum.map(fields, fn field ->
      type =
        properties
        |> get_in([field, "type"])
        |> List.wrap()
        |> Enum.reject(&(&1 == "null"))
        |> List.first()
        |> case do
          "string" -> :string
          "integer" -> :integer
          "number" -> :number
          "boolean" -> :boolean
          "object" -> :object
          "array" -> :array
          _ -> :any
        end

      {String.to_atom(field), type}
    end)

  struct_defaults =
    fields
    |> Enum.map(fn field -> "    #{field}: nil" end)
    |> Enum.join(",\n")

  type_fields =
    field_types
    |> Enum.map(fn {field, type} -> "          #{field}: #{type_spec.(type)}" end)
    |> Enum.join(",\n")

  contents = """
  defmodule #{module} do
    @moduledoc \"\"\"
    Generated Eigenforge contract for `#{schema_id}`.

    Regenerate with:

        elixir tools/generate_contracts.exs
    \"\"\"

    @schema_id #{inspect(schema_id)}
    @schema_version #{inspect(schema_version)}
    @format_version #{inspect(format_version)}
    @fields #{inspect(Enum.map(fields, &String.to_atom/1))}
    @required_fields #{inspect(Enum.map(required, &String.to_atom/1))}
    @field_types #{inspect(field_types)}

    @enforce_keys []
    defstruct [
  #{struct_defaults}
    ]

    @type t :: %__MODULE__{
  #{type_fields}
          }

    def schema_id, do: @schema_id
    def schema_version, do: @schema_version
    def format_version, do: @format_version
    def fields, do: @fields
    def required_fields, do: @required_fields
    def field_types, do: @field_types

    def new(attrs), do: Eigenforge.Contracts.new(__MODULE__, attrs)
    def new!(attrs), do: Eigenforge.Contracts.new!(__MODULE__, attrs)
    def validate(value), do: Eigenforge.Contracts.validate(__MODULE__, value)
    def signable_map(value), do: Eigenforge.Contracts.signable_map(value)
    def canonical_json(value), do: Eigenforge.Contracts.canonical_json(signable_map(value))
    def payload_hash(value), do: Eigenforge.Contracts.payload_hash(value)
    def sign_hmac(value, secret), do: Eigenforge.Contracts.sign_hmac(value, secret)
    def verify_hmac(value, secret, signature), do: Eigenforge.Contracts.verify_hmac(value, secret, signature)
  end
  """

  file_name =
    module
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>(".ex")

  File.write!(Path.join(out_dir, file_name), contents)
  IO.puts("generated #{Path.relative_to_cwd(Path.join(out_dir, file_name))}")
end)
