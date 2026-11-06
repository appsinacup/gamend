defmodule Gamend.ReportResolveRaceTest do
  @moduledoc """
  Two moderators closing the same open report at once.

  `Reports.resolve/3` decided "this closes an open report" from the struct
  each moderator had read, so both closes landed, and `after_report_resolved`
  fired and the reporter was told twice. The close is now a write made only
  while the report still has the status the caller read: one lands, the
  other answers `:status_changed` and sends nothing.

  Postgres only shows it; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Notifications.Notification
  alias Gamend.Reports
  alias Gamend.Reports.Notices
  alias Gamend.Reports.Report

  @reports 15

  defmodule CountingHooks do
    @moduledoc false
    def after_report_resolved(report) do
      send(:persistent_term.get({__MODULE__, :test_pid}), {:resolved, report.id})
      :ok
    end
  end

  setup do
    previous = Application.get_env(:gamend_core, :host_hook_modules)
    Application.put_env(:gamend_core, :host_hook_modules, [CountingHooks])
    :persistent_term.put({CountingHooks, :test_pid}, self())

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, :host_hook_modules, previous),
        else: Application.delete_env(:gamend_core, :host_hook_modules)

      :persistent_term.erase({CountingHooks, :test_pid})
    end)

    reports =
      unboxed(fn ->
        for i <- 1..@reports do
          user = AccountsFixtures.unconfirmed_user_fixture()

          {:ok, report} =
            Reports.create(
              %{
                "kind" => "page",
                "subject" => %{"path" => "/race/#{i}"},
                "description" => "It broke"
              },
              %{user_id: user.id}
            )

          report
        end
      end)

    report_ids = Enum.map(reports, & &1.id)
    user_ids = Enum.map(reports, & &1.user_id)

    cleanup(fn ->
      Repo.delete_all(from r in Report, where: r.id in ^report_ids)
      Repo.delete_all(from n in Notification, where: n.recipient_id in ^user_ids)
      Repo.delete_all(from u in User, where: u.id in ^user_ids)
    end)

    %{reports: reports}
  end

  test "an open report is closed once, and its reporter told once", %{reports: reports} do
    results =
      reports
      |> Enum.flat_map(fn report ->
        [
          fn -> Reports.resolve(report, "fixed", %{message: "Fixed."}) end,
          fn -> Reports.resolve(report, "duplicate", %{message: "A duplicate."}) end
        ]
      end)
      |> race()
      |> Enum.chunk_every(2)

    for {report, pair} <- Enum.zip(reports, results) do
      refute Enum.any?(pair, &match?({:raised, _}, &1)), "a close raised: #{inspect(pair)}"
      assert Enum.count(pair, &match?({:ok, %Report{}}, &1)) == 1, inspect(pair)
      assert Enum.count(pair, &(&1 == {:error, :status_changed})) == 1, inspect(pair)

      told =
        unboxed(fn ->
          from(n in Notification,
            where: n.recipient_id == ^report.user_id and n.title == ^Notices.reporter_title()
          )
          |> Repo.aggregate(:count)
        end)

      assert told == 1, "the reporter was told #{told} times"
    end

    resolved = for _ <- reports, do: assert_receive({:resolved, _id}, 1_000)
    assert length(Enum.uniq(resolved)) == @reports
    refute_receive {:resolved, _}, 200
  end
end
