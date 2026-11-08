defmodule GamendWeb.ErrorResponse do
  @moduledoc """
  Sends the real error page from a controller or a plug.

  `render_errors` only catches errors that reach the endpoint as an exception —
  a route that never matched, or something that raised. Code which decides for
  itself that a request is a 404 and answers with `text("Not Found")` never
  goes near it, so a reader got nine bytes of plain text while the error
  template sat unused. That is what `/ads` did.

  Rendering to a string rather than going through `put_view` keeps this usable
  from a plug, where there is no view or layout to configure, and guarantees
  the page is byte-identical to the one `render_errors` produces.
  """

  import Plug.Conn

  @html "html"

  @doc """
  Replies 404 with the standard error page and halts.

  Pass the conn through so the page picks up the reader's locale and theme.
  """
  @spec not_found(Plug.Conn.t()) :: Plug.Conn.t()
  def not_found(conn), do: send_error(conn, 404)

  @doc "Replies with the standard error page for `status` and halts."
  @spec send_error(Plug.Conn.t(), pos_integer()) :: Plug.Conn.t()
  def send_error(conn, status) when is_integer(status) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, render(conn, status))
    |> halt()
  end

  defp render(conn, status) do
    Phoenix.Template.render_to_string(
      GamendWeb.ErrorHTML,
      "#{status}.html",
      @html,
      %{conn: conn}
    )
  end
end
