defmodule GamendWeb.ResponsiveImagesTest do
  @moduledoc """
  The runtime cutter fills in the `widths` variants of a project's own images,
  and without ImageMagick it says so once and changes nothing.

  Not async: the overlay is a global setting, cached, and one test turns the
  log level up.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Gamend.Theme.JSONConfig
  alias GamendWeb.ProjectStatic
  alias GamendWeb.ResponsiveImages

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = Application.get_env(:gamend_core, Gamend.ContentSettings)
    overlay = Path.join(tmp, "static")
    File.mkdir_p!(Path.join(overlay, "images"))

    Application.put_env(
      :gamend_core,
      Gamend.ContentSettings,
      Keyword.put(previous || [], :static_dirs, [overlay])
    )

    ProjectStatic.reset()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, Gamend.ContentSettings, previous),
        else: Application.delete_env(:gamend_core, Gamend.ContentSettings)

      ProjectStatic.reset()
    end)

    %{overlay: overlay}
  end

  defp theme(path, widths) do
    %{"pages" => %{"home" => %{"hero" => %{"image" => %{"light" => path, "widths" => widths}}}}}
  end

  test "planned_variants/1 finds every image at any depth, light and dark" do
    config = %{
      "pages" => %{
        "home" => %{
          "hero" => %{"image" => %{"light" => "/images/a.webp", "widths" => [480, 480, 0]}},
          "sections" => [
            %{
              "image" => %{
                "light" => "/images/b.png",
                "dark" => "/images/b_dark.png",
                "widths" => [320]
              }
            },
            %{"image" => %{"light" => "/images/c.webp"}}
          ]
        }
      }
    }

    assert ResponsiveImages.planned_variants(config) == [
             {"/images/a.webp", "/images/a-480.webp", 480},
             {"/images/b.png", "/images/b-320.png", 320},
             {"/images/b_dark.png", "/images/b_dark-320.png", 320}
           ]

    assert ResponsiveImages.planned_variants(Jason.encode!(config)) ==
             ResponsiveImages.planned_variants(config)
  end

  test "without ImageMagick nothing is written", %{overlay: overlay} do
    File.write!(Path.join(overlay, "images/pic.webp"), "not really a picture")

    assert {:error, :no_imagemagick} =
             ResponsiveImages.cut_overlay(tool: nil, theme: theme("/images/pic.webp", [4]))

    assert File.ls!(Path.join(overlay, "images")) == ["pic.webp"]
  end

  test "nothing to do asks for no tool at all", %{overlay: overlay} do
    # No widths, an original that is not the overlay's, a variant already cut:
    # none of it is work, so a server without ImageMagick has nothing to say.
    File.write!(Path.join(overlay, "images/done.webp"), "x")
    File.write!(Path.join(overlay, "images/done-4.webp"), "x")

    for theme <- [
          theme("/images/done.webp", []),
          theme("/images/not-in-overlay.webp", [4]),
          theme("/images/done.webp", [4])
        ] do
      assert ResponsiveImages.cut_overlay(tool: nil, theme: theme) == {:ok, []}
    end
  end

  test "without ImageMagick the running cutter says so once, at :info", %{overlay: overlay} do
    File.write!(Path.join(overlay, "images/pic.webp"), "x")
    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)

    log =
      capture_log([level: :info], fn ->
        pid =
          start_supervised!(
            {ResponsiveImages, name: nil, tool: nil, theme: theme("/images/pic.webp", [4])}
          )

        # The boot pass, then a theme reload and a manual refresh.
        :sys.get_state(pid)
        JSONConfig.reload()
        :sys.get_state(pid)
        send(pid, :refresh)
        :sys.get_state(pid)
      end)

    assert [_once] = Regex.scan(~r/ImageMagick \(magick\) not found/, log)
    assert File.ls!(Path.join(overlay, "images")) == ["pic.webp"]
  end

  test "a theme reload re-resolves the overlay and moves the static generation", %{
    tmp_dir: tmp
  } do
    pid = start_supervised!({ResponsiveImages, name: nil, tool: nil, theme: %{}})
    :sys.get_state(pid)

    # Cached: a new setting alone changes nothing yet.
    moved = Path.join(tmp, "moved")
    File.mkdir_p!(moved)
    settings = Application.get_env(:gamend_core, Gamend.ContentSettings)

    Application.put_env(
      :gamend_core,
      Gamend.ContentSettings,
      Keyword.put(settings, :static_dirs, [moved])
    )

    refute ProjectStatic.dirs() == [moved]
    generation = ProjectStatic.generation()

    # What `gamend reload` runs on the node. The caller only sends a message;
    # the work happens in the cutter's process.
    assert JSONConfig.reload() == :ok
    :sys.get_state(pid)

    assert ProjectStatic.dirs() == [moved]
    assert ProjectStatic.generation() > generation
  end

  @tag skip: is_nil(ResponsiveImages.find_tool()) && "ImageMagick is not installed"
  test "with ImageMagick the missing variant is cut next to its original", %{overlay: overlay} do
    {exe, prefix} =
      case ResponsiveImages.find_tool() do
        {:magick, magick} -> {magick, []}
        {:legacy, convert, _identify} -> {convert, []}
      end

    source = Path.join(overlay, "images/wide.webp")

    {_, 0} =
      System.cmd(exe, prefix ++ ["-size", "64x32", "plasma:", source], stderr_to_stdout: true)

    generation = ProjectStatic.generation()

    assert {:ok, [{{:generated, "images/wide-16.webp"}, "/images/wide-16.webp"}]} =
             ResponsiveImages.cut_overlay(theme: theme("/images/wide.webp", [16]))

    assert File.regular?(Path.join(overlay, "images/wide-16.webp"))
    # Cut once: the next pass finds nothing missing.
    assert ResponsiveImages.cut_overlay(theme: theme("/images/wide.webp", [16])) == {:ok, []}

    # The running cutter bumps the generation, so cached pages re-render.
    File.rm!(Path.join(overlay, "images/wide-16.webp"))

    pid =
      start_supervised!({ResponsiveImages, name: nil, theme: theme("/images/wide.webp", [16])})

    :sys.get_state(pid)
    assert ProjectStatic.generation() > generation
  end
end
