defmodule GamendWeb.PayloadContract do
  @moduledoc """
  The one check of a client's payload against its declared keys, for the
  messages no OpenAPI operation describes: a channel command
  (`GamendWeb.ChannelContract`, declared in `GamendWeb.RealtimeCommands`) and
  a LiveView event (`GamendWeb.LiveEvents`). An API request is held to its
  operation by `GamendWeb.Plugs.RequestContract`.

  A declaration is each key with its type, required unless
  `{:optional, type}`. The payload must be a map; a required key present with
  its type; an optional key absent, `nil` or its type. Keys it does not name
  are left alone (a click carries `"value"`, a form `"_target"`).

  The types are what a browser or an SDK sends:

    * `:string` — a string.
    * `:uuid` — a string that is a UUID (a row's id: anything else would
      raise in the query that reads it).
    * `:id` — a string or an integer: an id the page drew itself (a word's,
      a card's, a city's), which the handler looks up.
    * `:integer` — an integer, or its digits as a string (`phx-value-*` and a
      query string send every value as text).
    * `:boolean` — `true`/`false`, or `"true"`, `"false"`, `"on"` (a
      checkbox).
    * `{:in, values}` — one of `values` (a tab, a sort, a section).
    * `{:or_blank, type}` — `type`, or `""`: a form's field left empty, which
      a changeset reads as nil.
    * `[key: type, ...]` — an object with those keys, checked the same way
      (a form's `user[email]` is `user: [email: :string]`).
    * `{:schema, module}` — an object with an Ecto schema's fields, each
      optional and typed from the schema (a form over a changeset):
      `quest: {:schema, Gamend.Quests.Quest}`.
    * `{:list, type}` — an array of `type`.
    * `{:map_of, type}` — an object whose keys are the client's (an id, a
      name) and whose values are each `type`.
    * `{:free, reason}` — anything, the handler's to read. Only for what no
      schema can say (a plugin's arguments, a game's metadata), and the
      reason says which: `mix gamend.contract.lint` reads it.

  There is no bare `:map`, `:list` or `:any`: a value is typed, or it says
  why it cannot be. A nested key's error is named by its path:
  `"user.email"`.
  """

  @type type ::
          :string
          | :uuid
          | :id
          | :integer
          | :boolean
          | {:in, [term()]}
          | {:or_blank, type()}
          | {:schema, module()}
          | {:list, type()}
          | {:map_of, type()}
          | {:free, String.t()}
          | declaration()
  @type declaration :: [{atom() | String.t(), type() | {:optional, type()}}]
  @type errors :: %{String.t() => [String.t()]}

  @scalars [:string, :uuid, :id, :integer, :boolean]

  @doc "The scalar types a declaration may name."
  @spec scalars() :: [atom()]
  def scalars, do: @scalars

  @doc "Whether `spec` is a type a declaration may give a key."
  @spec valid_type?(term()) :: boolean()
  def valid_type?({:optional, type}), do: valid_type?(type)
  def valid_type?({:in, values}), do: is_list(values) and values != []
  def valid_type?({:or_blank, type}), do: valid_type?(type)
  def valid_type?({:schema, module}), do: is_atom(module)
  def valid_type?({:list, type}), do: valid_type?(type)
  def valid_type?({:map_of, type}), do: valid_type?(type)
  def valid_type?({:free, reason}), do: is_binary(reason) and String.trim(reason) != ""
  def valid_type?(type) when type in @scalars, do: true

  def valid_type?(keys) when is_list(keys) do
    Enum.all?(keys, fn
      {key, type} when is_atom(key) or is_binary(key) -> valid_type?(type)
      _ -> false
    end)
  end

  def valid_type?(_), do: false

  @doc """
  The free-form values in `declaration`, as `{path, reason}`: what
  `mix gamend.contract.lint` lists, so each one is seen with its reason.
  """
  @spec free_values(declaration(), String.t()) :: [{String.t(), String.t()}]
  def free_values(declaration, path \\ "") when is_list(declaration) do
    Enum.flat_map(declaration, fn {key, spec} -> free_in(spec, join(path, key)) end)
  end

  defp free_in({:optional, type}, path), do: free_in(type, path)
  defp free_in({:or_blank, type}, path), do: free_in(type, path)
  defp free_in({:free, reason}, path), do: [{path, reason}]
  defp free_in({:list, type}, path), do: free_in(type, path <> "[]")
  defp free_in({:map_of, type}, path), do: free_in(type, path <> "{}")
  defp free_in(keys, path) when is_list(keys), do: free_values(keys, path)
  defp free_in(_type, _path), do: []

  defp join("", key), do: to_string(key)
  defp join(path, key), do: "#{path}.#{key}"

  @doc "`:ok`, or the errors per key, for `payload` against `declaration`."
  @spec check(declaration(), term()) :: :ok | {:error, errors()}
  def check(declaration, payload) do
    case errors(declaration, payload, nil) do
      [] -> :ok
      errors -> {:error, Enum.group_by(errors, &elem(&1, 0), &elem(&1, 1))}
    end
  end

  defp errors(_declaration, payload, path) when not is_map(payload),
    do: [{path || "payload", "must be an object"}]

  defp errors(declaration, payload, path) do
    Enum.flat_map(declaration, fn {key, spec} ->
      name = if path, do: "#{path}.#{key}", else: to_string(key)
      {required?, type} = split(spec)

      case {Map.fetch(payload, to_string(key)), required?} do
        {:error, true} -> [{name, "is required"}]
        {:error, false} -> []
        {{:ok, nil}, false} -> []
        {{:ok, value}, _} -> value_errors(value, type, name)
      end
    end)
  end

  defp value_errors(value, keys, name) when is_list(keys), do: errors(keys, value, name)
  defp value_errors("", {:or_blank, _type}, _name), do: []
  defp value_errors(value, {:or_blank, type}, name), do: value_errors(value, type, name)

  defp value_errors(value, {:schema, module}, name),
    do: errors(schema_declaration(module), value, name)

  defp value_errors(value, {:list, type}, name) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} -> value_errors(item, type, "#{name}.#{index}") end)
  end

  defp value_errors(_value, {:list, _type}, name), do: [{name, "must be an array"}]

  defp value_errors(value, {:map_of, type}, name) when is_map(value) do
    Enum.flat_map(value, fn {key, item} -> value_errors(item, type, "#{name}.#{key}") end)
  end

  defp value_errors(_value, {:map_of, _type}, name), do: [{name, "must be an object"}]

  defp value_errors(value, type, name),
    do: if(typed?(value, type), do: [], else: [{name, message(type)}])

  defp split({:optional, type}), do: {false, type}
  defp split(type), do: {true, type}

  @doc """
  An Ecto schema's fields as a declaration, each optional: what a form over
  its changeset may send. A field the changeset reads as JSON (`:map`) is
  free-form, the schema's own.
  """
  @spec schema_declaration(module()) :: declaration()
  def schema_declaration(module) do
    for field <- module.__schema__(:fields),
        field not in [:inserted_at, :updated_at] do
      {field, {:optional, form_type(ecto_type(module.__schema__(:type, field)))}}
    end
  end

  # A form sends an untouched number, checkbox or picker as "": nil to the
  # changeset, so it is a value here too.
  defp form_type(type) when type in [:integer, :boolean], do: {:or_blank, type}
  # A UUID typed into a text field is text: the changeset casts it and answers
  # its own error ("must be a valid user ID"), where a refusal would say nothing.
  defp form_type(:uuid), do: :string
  defp form_type(type), do: type

  defp ecto_type(type) when type in [:string, :binary], do: :string
  defp ecto_type(type) when type in [:integer, :id], do: :integer
  defp ecto_type(:boolean), do: :boolean
  defp ecto_type(type) when type in [:binary_id, Ecto.UUID], do: :uuid
  defp ecto_type({:array, type}), do: {:list, ecto_type(type)}
  defp ecto_type({:map, type}), do: {:map_of, ecto_type(type)}
  defp ecto_type(:map), do: {:free, "a JSON field of the schema"}
  # Dates, times, decimals, enums, custom types: what a form sends is text,
  # and the changeset casts it (or answers its error).
  defp ecto_type(_type), do: :string

  @doc "Whether `value` is of the scalar or enumerated `type`."
  @spec typed?(term(), type()) :: boolean()
  def typed?(_value, {:free, _reason}), do: true
  def typed?(value, :string), do: is_binary(value)
  def typed?(value, :uuid), do: is_binary(value) and match?({:ok, _}, Ecto.UUID.cast(value))
  def typed?(value, :id), do: is_binary(value) or is_integer(value)
  def typed?(value, :integer) when is_integer(value), do: true
  def typed?(value, :integer) when is_binary(value), do: Regex.match?(~r/\A-?\d{1,18}\z/, value)
  def typed?(value, :boolean) when is_boolean(value), do: true
  def typed?(value, :boolean), do: value in ["true", "false", "on"]
  def typed?(value, {:in, values}), do: value in values
  def typed?(_value, _type), do: false

  defp message(:string), do: "must be a string"
  defp message(:uuid), do: "must be a UUID"
  defp message(:id), do: "must be a string or an integer"
  defp message(:integer), do: "must be an integer"
  defp message(:boolean), do: "must be a boolean"
  defp message({:in, values}), do: "must be one of: " <> Enum.map_join(values, ", ", &to_string/1)
end
