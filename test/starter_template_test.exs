defmodule GamendHost.StarterTemplateTest do
  @moduledoc """
  `gamend starter` copies `priv/starter/default` into a new project, which is
  then all a downloaded release knows about the site. The template has to
  render as it ships: a theme that fails to decode, or a home page the theme
  code rejects, would greet every new project with an empty site.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Gamend.Theme.JSONConfig

  @endpoint GamendWeb.Endpoint
  @template Path.expand("../priv/starter/default", __DIR__)

  setup do
    previous = Application.get_env(:gamend_core, Gamend.ContentSettings)

    Application.put_env(:gamend_core, Gamend.ContentSettings,
      theme_config: Path.join(@template, "theme/config.json")
    )

    JSONConfig.reload()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, Gamend.ContentSettings, previous),
        else: Application.delete_env(:gamend_core, Gamend.ContentSettings)

      JSONConfig.reload()
    end)

    :ok
  end

  test "the template's theme is the one the home page renders" do
    assert JSONConfig.raw_theme()["title"] == "My Game"

    html = build_conn() |> get("/") |> html_response(200)

    assert html =~ "My Game"
    assert html =~ "theme/config.json"
  end

  test "the template ships every part of a project folder" do
    for path <- ~w(theme/config.json CHANGELOG.md ROADMAP.md blog priv/docs static
                   modules/plugins/hello .gitignore README.md) do
      assert File.exists?(Path.join(@template, path)), "#{path} is missing from the template"
    end
  end
end
