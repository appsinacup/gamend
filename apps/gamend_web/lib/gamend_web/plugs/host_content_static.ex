defmodule GamendWeb.HostContentStatic do
  @moduledoc """
  Serves host-owned content images directly from the endpoint plug pipeline.
  """

  @behaviour Plug

  alias Gamend.Content

  require Gamend.HttpHeader, as: HttpHeader

  @changelog "changelog"
  @blog "blog"
  @content "content"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: [@content, type | rest]} = conn, _opts)
      when type in [@blog, @changelog] do
    relative = Path.join(rest)

    case Content.asset_path(type, relative) do
      nil ->
        conn

      abs_path ->
        content_type = MIME.from_path(abs_path)

        conn
        |> Plug.Conn.put_resp_header(HttpHeader.cache_control(), "public, max-age=604800")
        |> Plug.Conn.put_resp_content_type(content_type, nil)
        |> Plug.Conn.send_file(200, abs_path)
        |> Plug.Conn.halt()
    end
  end

  def call(conn, _opts), do: conn
end
