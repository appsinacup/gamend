defmodule GamendWeb.Reply do
  @moduledoc """
  The four shapes an API response takes (docs/specs/api-conventions.md, R15),
  one function each. Imported into every controller next to
  `GamendWeb.ChangesetErrors.unprocessable/2`, which is the fifth: a failed
  changeset.

      reply_data(conn, lobby)                       # 200 {"data": lobby}
      reply_data(conn, :created, lobby)             # 201 {"data": lobby}
      reply_page(conn, rows, page, page_size, total) # 200 {"data": rows, "meta": ...}
      reply_ok(conn)                                # 200 {"ok": true}
      reply_error(conn, :not_found, "lobby_not_found")
      reply_error(conn, :forbidden, "device_auth_disabled", "Device login is off")

  `GamendWeb.ApiShapeTest` and `GamendWeb.ResponseContract` hold the document
  and the responses to the same shapes, so a controller that answers some
  other way fails the suite whether or not it uses these.
  """

  import Plug.Conn, only: [put_status: 2]

  alias GamendWeb.Pagination
  alias Phoenix.Controller

  @doc "`{\"data\": value}`, 200 unless a status is given (`:created` for a create)."
  @spec reply_data(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def reply_data(conn, value), do: Controller.json(conn, %{data: value})

  @spec reply_data(Plug.Conn.t(), atom() | pos_integer(), term()) :: Plug.Conn.t()
  def reply_data(conn, status, value),
    do: conn |> put_status(status) |> Controller.json(%{data: value})

  @doc "A page of rows under `data` with their `meta` window."
  @spec reply_page(Plug.Conn.t(), list(), pos_integer(), pos_integer(), non_neg_integer()) ::
          Plug.Conn.t()
  def reply_page(conn, rows, page, page_size, total_count) when is_list(rows),
    do: Controller.json(conn, Pagination.envelope(rows, page, page_size, total_count))

  @doc """
  Several lists in one answer, sharing one window: each list under `data` by
  name, one `meta` per list under `meta` by the same name.

      reply_pages(conn, %{incoming: {rows, total}, outgoing: {rows, total}}, page, page_size)
  """
  @spec reply_pages(
          Plug.Conn.t(),
          %{atom() => {list(), non_neg_integer()}},
          pos_integer(),
          pos_integer()
        ) ::
          Plug.Conn.t()
  def reply_pages(conn, lists, page, page_size) when is_map(lists) do
    Controller.json(conn, %{
      data: Map.new(lists, fn {name, {rows, _total}} -> {name, rows} end),
      meta:
        Map.new(lists, fn {name, {rows, total}} ->
          {name, Pagination.meta(page, page_size, length(rows), total)}
        end)
    })
  end

  @doc "`{\"ok\": true}`: a write with nothing to return."
  @spec reply_ok(Plug.Conn.t()) :: Plug.Conn.t()
  def reply_ok(conn), do: Controller.json(conn, %{ok: true})

  @doc """
  `{\"error\": code}`, with `message` when there is prose worth showing a
  person. `code` is `snake_case`; an atom is taken as its name.
  """
  @spec reply_error(Plug.Conn.t(), atom() | pos_integer(), atom() | String.t(), String.t() | nil) ::
          Plug.Conn.t()
  def reply_error(conn, status, code, message \\ nil) do
    body = %{error: to_string(code)}
    body = if message, do: Map.put(body, :message, message), else: body
    conn |> put_status(status) |> Controller.json(body)
  end

  @doc """
  403 `rejected`: a game hook vetoed the action. The hook's reason is the
  `message` — as written when it is a string, `inspect`ed otherwise.
  """
  @spec reply_rejected(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def reply_rejected(conn, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)
    reply_error(conn, :forbidden, "rejected", message)
  end

  @doc """
  The answer to an error reason no clause of the controller names: what is
  left after the reasons it answers its own way.

      {:error, :invalid} -> reply_error(conn, :forbidden, "captcha_invalid")
      {:error, reason} -> reply_reason(conn, reason)

  An atom answers with its name as the code and the status
  `GamendWeb.ErrorStatus` gives it; a failed changeset as
  `GamendWeb.ChangesetErrors.unprocessable_or_conflict/2` does; a game hook's
  veto (`{:hook_rejected, reason}`) as `reply_rejected/2`. Anything else
  raises `GamendWeb.UnmappedReason`: a reason the server has no answer for is
  a bug, and a 500 that names it beats a 400 that hides it.
  """
  @spec reply_reason(Plug.Conn.t(), atom() | Ecto.Changeset.t() | {:hook_rejected, term()}) ::
          Plug.Conn.t()
  def reply_reason(conn, %Ecto.Changeset{} = changeset),
    do: GamendWeb.ChangesetErrors.unprocessable_or_conflict(conn, changeset)

  def reply_reason(conn, {:hook_rejected, reason}), do: reply_rejected(conn, reason)

  def reply_reason(conn, reason) when is_atom(reason) and not is_nil(reason) do
    case GamendWeb.ErrorStatus.status(reason) do
      nil -> raise GamendWeb.UnmappedReason, reason: reason
      status -> reply_error(conn, status, reason)
    end
  end

  def reply_reason(_conn, reason), do: raise(GamendWeb.UnmappedReason, reason: reason)
end
