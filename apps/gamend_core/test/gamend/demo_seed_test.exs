defmodule Gamend.DemoSeedTest do
  @moduledoc """
  `mix demo.seed` and a release's `gamend demo.seed` both run
  `Gamend.DemoSeed.run/1`. A small count covers every set; `--clean` has to
  take all of it away again.
  """
  use Gamend.DataCase, async: false

  import ExUnit.CaptureIO
  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.DemoSeed
  alias Gamend.Leaderboards.Leaderboard
  alias Gamend.Repo

  test "seeds every set, and --clean removes what it seeded" do
    output = capture_io(fn -> assert DemoSeed.run(["--count", "3"]) == :ok end)

    assert output =~ "done"
    assert demo_users() > 0
    assert Repo.exists?(from(l in Leaderboard, where: like(l.slug, "demo_seed%")))

    capture_io(fn -> assert DemoSeed.run(["--clean"]) == :ok end)

    assert demo_users() == 0
    refute Repo.exists?(from(l in Leaderboard, where: like(l.slug, "demo_seed%")))
  end

  test "an unknown set is an ArgumentError naming the known ones" do
    error = assert_raise ArgumentError, fn -> DemoSeed.run(["--only", "nope"]) end

    assert Exception.message(error) =~ "unknown set(s): nope"
    assert Exception.message(error) =~ "leaderboard"
  end

  defp demo_users do
    Repo.aggregate(from(u in User, where: like(u.device_id, "demo-seed-%")), :count)
  end
end
