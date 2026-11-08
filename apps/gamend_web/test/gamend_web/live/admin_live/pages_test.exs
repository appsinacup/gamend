defmodule GamendWeb.AdminLive.PagesTest do
  @moduledoc """
  The table every admin heading and tile reads: each entry opens a real page in
  a colour and an icon that exist, and no admin page is left out of it.
  """
  use ExUnit.Case, async: true

  alias GamendWeb.AdminComponents
  alias GamendWeb.AdminLive.Pages

  @paths Enum.map(Pages.all(), & &1.path)

  test "every entry is a route" do
    for path <- @paths do
      assert Phoenix.Router.route_info(GamendWeb.Router, "GET", path, "localhost") != :error,
             "#{path} has no route"
    end
  end

  # A tab or a detail view (`/admin/analytics/people`, `/admin/results/:id`)
  # wears the heading of the page it is under. A dependency's console
  # (LiveDashboard) brings its own.
  test "every admin LiveView is a page in the table or under one" do
    routes =
      for route <- Phoenix.Router.routes(GamendWeb.Router),
          String.starts_with?(route.path, "/admin/"),
          {view, _action, _opts, _session} <- [route.metadata[:phoenix_live_view]],
          match?(["GamendWeb" | _], Module.split(view)),
          do: route.path

    assert routes != []

    for route <- routes do
      assert route in @paths or Enum.any?(@paths, &String.starts_with?(route, &1 <> "/")),
             "#{route} is not in GamendWeb.AdminLive.Pages"
    end
  end

  test "every icon is a heroicon" do
    # The dependency is `sparse: "optimized"`, so its path already ends there.
    optimized = Mix.Project.deps_paths()[:heroicons]

    for %{icon: "hero-" <> name} <- Pages.all() do
      assert File.exists?(Path.join([optimized, "24/outline", name <> ".svg"])),
             "no heroicon named #{name}"
    end
  end

  test "every colour is one the components draw" do
    for page <- Pages.all() do
      assert page.color in AdminComponents.colors(), "#{page.path}: #{page.color}"
    end
  end

  test "a page has one tile" do
    links = Enum.flat_map(Pages.sections(), & &1.links)

    assert Enum.uniq_by(links, & &1.path) == links
  end
end
