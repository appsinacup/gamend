defmodule GamendWeb.Plugs.DevCodeReloader do
  @moduledoc """
  `Phoenix.CodeReloader`, run only when a reloadable app's source changed
  since the last reload that compiled (`GamendWeb.DevWatch`). A compile error
  is not marked, so every request shows it until it is fixed. With nothing
  watched it runs on every request, as Phoenix's does.
  """

  @behaviour Plug

  alias GamendWeb.DevWatch

  @impl Plug
  def init(opts), do: Phoenix.CodeReloader.init(opts)

  @impl Plug
  def call(conn, opts) do
    case DevWatch.stale(:code) do
      :fresh ->
        conn

      {:stale, count} ->
        conn = Phoenix.CodeReloader.call(conn, opts)
        unless conn.halted, do: DevWatch.checked(:code, count)
        conn
    end
  end
end
