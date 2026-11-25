defmodule Gamend.Analytics.TraitOptionsTest do
  # Not async: the host catalog is application env, read by every test.
  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Analytics

  # Core declares no traits; only a host's catalog makes `trait_options/2`
  # query anything. Without one, this query ran first on a production
  # Postgres (grouping_error 42803, 2026-11-25).
  defmodule Host do
    def overview, do: %{traits: [%{field: "device", label: "Device"}]}
  end

  @today ~D[2026-03-09]

  setup do
    original = Application.get_env(:gamend_core, :analytics_catalog)
    Application.put_env(:gamend_core, :analytics_catalog, Host)

    on_exit(fn ->
      if original,
        do: Application.put_env(:gamend_core, :analytics_catalog, original),
        else: Application.delete_env(:gamend_core, :analytics_catalog)

      Gamend.Cache.invalidate({:analytics, :trait_options, 30, @today})
    end)

    :ok
  end

  test "a trait's values, by distinct people, most first" do
    at = DateTime.new!(@today, ~T[12:00:00], "Etc/UTC")
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    for {user, device} <- [{a, "phone"}, {a, "phone"}, {b, "phone"}, {b, "desktop"}] do
      :ok = Analytics.track("web.page.viewed", %{device: device}, user_id: user.id, at: at)
    end

    # No value, and a visitor's, are not offered.
    :ok = Analytics.track("web.page.viewed", %{}, user_id: a.id, at: at)
    :ok = Analytics.track("web.page.viewed", %{device: "tablet"}, at: at)

    assert Analytics.trait_options(30, @today) == [
             %{field: "device", label: "Device", values: ["phone", "desktop"]}
           ]
  end
end
