defmodule GamendWeb.Plugs.DevRepoStatus do
  @moduledoc """
  `Phoenix.Ecto.CheckRepoStatus`, run only when a migration folder changed
  since the last check that passed (`GamendWeb.DevWatch`). A pending
  migration raises before it is marked, so every request shows it until it
  is run. With nothing watched it runs on every request.
  """

  @behaviour Plug

  alias GamendWeb.DevWatch
  alias Phoenix.Ecto.CheckRepoStatus

  @impl Plug
  def init(opts), do: CheckRepoStatus.init(opts)

  @impl Plug
  def call(conn, opts) do
    case DevWatch.stale(:repo) do
      :fresh ->
        conn

      {:stale, count} ->
        conn = CheckRepoStatus.call(conn, opts)
        DevWatch.checked(:repo, count)
        conn
    end
  end
end
