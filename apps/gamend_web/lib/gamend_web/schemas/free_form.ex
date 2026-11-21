defmodule GamendWeb.Schemas.FreeForm do
  @moduledoc """
  A schema for a value no schema can say, and why: a game's metadata, a
  plugin's arguments, a provider's webhook body. The reason rides in the
  document as `x-free-form`, which `mix gamend.contract.lint` reads: a
  free-form schema without one fails it. Use these, never a bare
  `%Schema{type: :object}`.
  """

  alias OpenApiSpex.Schema

  @doc "A JSON object whose keys and values are `reason`'s owner's."
  @spec object(String.t(), keyword()) :: Schema.t()
  def object(reason, opts \\ []) when is_binary(reason) do
    %Schema{
      type: :object,
      additionalProperties: true,
      description: Keyword.get(opts, :description, reason),
      nullable: Keyword.get(opts, :nullable),
      extensions: %{"x-free-form" => reason}
    }
  end

  @doc """
  A record's `metadata`: JSON the game defines and the server stores as it
  came (a host's schema can type it for its protobuf clients,
  `Gamend.Hooks.MetadataSchemas`).
  """
  @spec metadata(keyword()) :: Schema.t()
  def metadata(opts \\ []), do: object("metadata the game defines", opts)

  @doc "A key-value row's value: JSON the game stores under its key."
  @spec kv_value(keyword()) :: Schema.t()
  def kv_value(opts \\ []), do: object("the value a game stores under a key", opts)

  @doc "Any JSON value (a number, a string, a list, an object)."
  @spec value(String.t(), keyword()) :: Schema.t()
  def value(reason, opts \\ []) when is_binary(reason) do
    %Schema{
      description: Keyword.get(opts, :description, reason),
      nullable: Keyword.get(opts, :nullable),
      extensions: %{"x-free-form" => reason}
    }
  end
end
