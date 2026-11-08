defmodule GamendWeb.ChangesetErrors do
  @moduledoc """
  The one way a controller answers a failed changeset.

  Imported into every controller by `use GamendWeb, :controller`, so the answer
  is `unprocessable(conn, changeset)` and there is nothing to look up.

  ## Why this exists

  Forty-six call sites serialized changeset errors by hand, in three different
  payload shapes under three different envelope keys. A client could not write
  one error handler:

    * `traverse_errors(cs, & &1)` — seventeen sites — left the raw
      `{msg, opts}` tuple in the payload. `Jason` has no encoder for tuples, so
      every one of those raised `Protocol.UndefinedError` and the request came
      back **500**, on endpoints whose own OpenAPI operation documented a 422.
      Nothing caught it because not one of those branches had a test.
    * `traverse_errors(cs, fn {msg, _opts} -> msg end)` — twenty-two sites —
      shipped the raw msgid, so a client read the literal
      `"should be at most %{count} character(s)"` with the count still in it.
    * Seven sites interpolated with a hand-rolled `Regex.replace/3` and were
      correct, but untranslated.

  The envelope varied independently: `errors:` on twenty-three, `error:` on
  nine, `details:` on one.

  ## The shape

      %{error: "validation_failed", errors: %{field => [message, ...]}}

  Messages are interpolated **and** translated, through
  `GamendWeb.CoreComponents.translate_error/1` — the same function the
  LiveView forms use, so an API client and a form reader are told the same
  thing in the same language. Gettext falls back to the msgid when a locale has
  no translation, so English is unaffected.

  `mix gamend.api.lint` (R10) rejects a new hand-rolled `traverse_errors` in a
  controller.
  """

  import Plug.Conn, only: [put_status: 2]

  alias Ecto.Changeset
  alias GamendWeb.CoreComponents

  @validation_failed "validation_failed"

  @doc """
  Replies 422 with the standard validation payload.

      {:error, %Ecto.Changeset{} = changeset} -> unprocessable(conn, changeset)
  """
  @spec unprocessable(Plug.Conn.t(), Changeset.t() | %{atom() => String.t() | [String.t()]}) ::
          Plug.Conn.t()
  def unprocessable(conn, %Changeset{} = changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> Phoenix.Controller.json(%{error: @validation_failed, errors: errors(changeset)})
  end

  # A validation that is not a changeset (a push message) reports per-field
  # messages the same way: each field's value is a list.
  def unprocessable(conn, errors) when is_map(errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> Phoenix.Controller.json(%{
      error: @validation_failed,
      errors: Map.new(errors, fn {field, messages} -> {field, List.wrap(messages)} end)
    })
  end

  @doc """
  Replies to a changeset whose table has a unique index: 409 with the standard
  validation payload when that index is what failed (a group slug already
  taken), where the conflict is the point rather than the input; 422 otherwise,
  as `unprocessable/2` does.

      {:error, %Ecto.Changeset{} = changeset} -> unprocessable_or_conflict(conn, changeset)

  A changeset with no `unique_constraint/3` or `unsafe_validate_unique/4`
  never answers 409, so it uses `unprocessable/2`.
  """
  @spec unprocessable_or_conflict(Plug.Conn.t(), Changeset.t()) :: Plug.Conn.t()
  def unprocessable_or_conflict(conn, %Changeset{} = changeset) do
    if taken?(changeset) do
      conn
      |> put_status(:conflict)
      |> Phoenix.Controller.json(%{error: @validation_failed, errors: errors(changeset)})
    else
      unprocessable(conn, changeset)
    end
  end

  # `unique_constraint/3` tags its error `constraint: :unique`,
  # `unsafe_validate_unique/4` tags its `validation: :unsafe_unique`.
  defp taken?(%Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} ->
      opts[:constraint] == :unique or opts[:validation] == :unsafe_unique
    end)
  end

  @doc """
  The `%{field => [message]}` map on its own, for a caller that needs to put it
  somewhere other than the standard envelope.
  """
  @spec errors(Changeset.t()) :: %{atom() => [String.t()]}
  def errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, &CoreComponents.translate_error/1)
  end
end
