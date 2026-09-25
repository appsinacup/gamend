defmodule Gamend.SchedulingSettingsTest do
  @moduledoc """
  The periodic work whose cadence and batch size became settings, and the
  provider modules that now call out through `Gamend.HTTP`.

  A GenServer's `handle_info/2` is called here in the test process, so the
  timer it sets lands in this mailbox: a one-second interval is observed as
  the message arriving. An interval of an hour or more (the full retention
  sweep) cannot be waited out in a test, so that one is checked as the value
  the timer is set from.
  """
  # Settings are global Application config.
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.UserToken
  alias Gamend.AccountsFixtures
  alias Gamend.OAuth.Exchanger
  alias Gamend.OAuth.GoogleIDToken
  alias Gamend.Payments.Providers.Steam
  alias Gamend.Retention
  alias Gamend.SettingsHelpers
  alias Gamend.Tournaments.Ticker

  defp put(app \\ :gamend_core, module, key, value) do
    SettingsHelpers.put(app, module, key, value)
    on_exit(fn -> SettingsHelpers.delete(app, module, key) end)
  end

  describe "tournament ticker" do
    test "ticks again after tick_interval_seconds" do
      put(Ticker, :tick_interval_seconds, 1)

      assert {:noreply, _} = Ticker.handle_info(:tick, %{})
      refute_received :tick
      assert_receive :tick, 1_500
    end
  end

  describe "retention cadence" do
    test "the live cycle comes round after live_interval_seconds" do
      put(Retention, :live_interval_seconds, 1)

      assert {:noreply, _} = Retention.handle_info(:prune_live, %{})
      assert_receive :prune_live, 1_500
    end

    test "a live interval of 0 schedules nothing" do
      put(Retention, :live_interval_seconds, 0)

      assert {:noreply, _} = Retention.handle_info(:prune_live, %{})
      refute_receive :prune_live, 1_200
    end

    test "the full sweep waits interval_hours, at least one" do
      assert Retention.sweep_interval_ms() == :timer.hours(6)

      put(Retention, :interval_hours, 24)
      assert Retention.sweep_interval_ms() == :timer.hours(24)

      put(Retention, :interval_hours, 0)
      assert Retention.sweep_interval_ms() == :timer.hours(1)
    end
  end

  describe "retention batch size" do
    # Counts the DELETE statements on `users_tokens` that `fun` issues.
    defp token_deletes(fun) do
      test = self()
      handler = "retention-batch-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:gamend, :repo, :query],
        fn _event, _measurements, %{query: sql}, _config ->
          if sql =~ ~r/^DELETE FROM "users_tokens"/, do: send(test, :token_delete)
        end,
        nil
      )

      try do
        result = fun.()
        {result, count_received(:token_delete, 0)}
      after
        :telemetry.detach(handler)
      end
    end

    defp count_received(message, count) do
      receive do
        ^message -> count_received(message, count + 1)
      after
        0 -> count
      end
    end

    test "rows are deleted batch_size at a time, and all of them" do
      put(Retention, :batch_size, 2)
      user = AccountsFixtures.user_fixture()

      for _ <- 1..5 do
        token = Accounts.generate_user_session_token(user)
        AccountsFixtures.offset_user_token(token, -30, :day)
      end

      assert Repo.aggregate(UserToken.expired_query(), :count) == 5

      # 2 + 2 + 1
      assert {%{expired_user_tokens: 5}, 3} = token_deletes(&Retention.prune_all/0)
      assert Repo.aggregate(UserToken.expired_query(), :count) == 0
    end
  end

  describe "provider calls go through Gamend.HTTP" do
    setup do
      put(Gamend.HTTP, :req_options, plug: {Req.Test, __MODULE__})
      :ok
    end

    test "Google ID-token checks" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.host == "oauth2.googleapis.com"
        Req.Test.json(conn, %{"sub" => "g1", "aud" => "web", "iss" => "accounts.google.com"})
      end)

      assert {:ok, %{"sub" => "g1"}} =
               GoogleIDToken.verify("token", expected_auds: ["web"])
    end

    test "OAuth code exchanges" do
      Req.Test.stub(__MODULE__, fn
        %{method: "POST"} = conn -> Req.Test.json(conn, %{"access_token" => "at"})
        conn -> Req.Test.json(conn, %{"id" => "d1", "username" => "duser"})
      end)

      assert {:ok, %{"id" => "d1"}} =
               Exchanger.exchange_discord_code(
                 "code",
                 "id",
                 "secret",
                 "https://x/cb"
               )
    end

    test "payment provider calls" do
      put(Gamend.OAuth.Providers, :steam_api_key, "key")
      put(Gamend.Payments.Settings, :steam_app_id, "480")

      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path =~ "QueryTxn"
        Req.Test.json(conn, %{"response" => %{"result" => 1, "params" => %{"orderid" => "7"}}})
      end)

      assert {:ok, %{"response" => %{"params" => %{"orderid" => "7"}}}} =
               Steam.query_transaction(%{"order_id" => "7"})
    end
  end
end
