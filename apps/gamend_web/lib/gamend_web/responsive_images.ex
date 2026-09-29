defmodule GamendWeb.ResponsiveImages do
  @moduledoc """
  Cuts the width variants a theme image's `"widths"` asks for.

  `"widths": [480, 960]` on a `theme/config.json` image makes the renderer offer
  `<base>-480.<ext>` and `<base>-960.<ext>` in a srcset, for the ones that exist
  (`GamendWeb.PresentationPage` drops a width whose file is missing, so a
  missing variant costs bytes, never a broken image). Two things write them:

    * `mix host.responsive_images`, at build time, into `priv/static`;
    * this process, at runtime, into a project's static overlay
      (`GamendWeb.ProjectStatic`): once at boot and again after every
      `Gamend.Theme.JSONConfig.reload/0` (the `[:gamend, :theme, :reload]`
      telemetry event), for each image whose original lives in a writable
      overlay directory, next to the original. `refresh/0` asks for a pass by
      hand, for a host whose theme module emits no event.

  A reload also runs `GamendWeb.ProjectStatic.reload/0` first, so a static
  folder created, or a file replaced, since boot is served and linked with its
  new hash. That happens in this process too: the telemetry handler only sends
  a message, so whoever called `reload/0` never waits on it and never sees it
  fail.

  The runtime pass only fills in what is missing. It never writes inside the
  release, and it does its work in its own process, so a slow cut or a failure
  delays and breaks nothing else.

  Both need ImageMagick: `magick`, or `convert` and `identify` outside Windows,
  where `convert` is a system tool. Without it the runtime pass logs once at
  `:info` that variants are skipped and does nothing more; the pages still
  serve the full-size originals.
  """

  use GenServer

  require Logger

  alias GamendWeb.ProjectStatic

  @webp_quality "80"
  @png_quality "82-96"
  @reload_event [:gamend, :theme, :reload]

  @typedoc "`{source_url, variant_url, width}`: one variant a `widths` list implies."
  @type planned :: {String.t(), String.t(), pos_integer()}

  @typedoc "An ImageMagick install: v7's `magick`, or v6's `convert` and `identify`."
  @type tool :: {:magick, String.t()} | {:legacy, String.t(), String.t()}

  @typedoc "What happened to one variant, with its path relative to the static root."
  @type result ::
          {:generated
           | :current
           | :stale
           | :missing_source
           | :skipped_upscale
           | :skipped_bigger
           | {:failed, String.t()}, String.t()}

  ## Process

  @doc """
  Starts the runtime cutter. Options: `:name` (default `#{inspect(__MODULE__)}`,
  `nil` for none) and `:tool` (default: found on `PATH`; `nil` means none).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "Asks the running cutter for another pass. A no-op when it is not running."
  @spec refresh(GenServer.server()) :: :ok
  def refresh(server \\ __MODULE__) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> send(pid, :refresh)
      _ -> :ok
    end

    :ok
  end

  @doc false
  def handle_theme_reload(_event, _measurements, _metadata, pid), do: send(pid, :refresh)

  @impl GenServer
  def init(opts) do
    attach_reload_handler()
    # The first pass runs after `init/1` has returned, so the supervisor, and
    # with it the boot, never waits on ImageMagick.
    {:ok, %{opts: opts, told_no_tool?: false}, {:continue, :refresh}}
  end

  @impl GenServer
  def handle_continue(:refresh, state), do: {:noreply, run_pass(state)}

  @impl GenServer
  def handle_info(:refresh, state) do
    # A burst of reloads is one pass: whatever queued behind this one is
    # covered by it.
    drain_refreshes()
    # Here rather than in the telemetry handler, which runs in the process that
    # called `reload/0`: that caller gets nothing slow and nothing that raises.
    ProjectStatic.reload()
    {:noreply, run_pass(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # One handler per process, and a restarted process sweeps up the handlers of
  # the ones before it rather than trapping exits to detach its own.
  defp attach_reload_handler do
    for %{id: {__MODULE__, pid} = id} <- :telemetry.list_handlers(@reload_event),
        not Process.alive?(pid),
        do: :telemetry.detach(id)

    :telemetry.attach(
      {__MODULE__, self()},
      @reload_event,
      &__MODULE__.handle_theme_reload/4,
      self()
    )
  end

  defp drain_refreshes do
    receive do
      :refresh -> drain_refreshes()
    after
      0 -> :ok
    end
  end

  defp run_pass(state) do
    case cut_overlay(state.opts) do
      {:ok, results} ->
        announce(results)
        state

      {:error, :no_imagemagick} ->
        unless state.told_no_tool? do
          Logger.info(
            "Responsive images: ImageMagick (magick) not found, so the theme's \"widths\" " <>
              "variants are not cut for the project's static files. Pages serve the " <>
              "full-size images; install ImageMagick and restart to have them cut."
          )
        end

        %{state | told_no_tool?: true}
    end
  rescue
    error ->
      Logger.error("Responsive images: " <> Exception.format(:error, error, __STACKTRACE__))
      state
  catch
    kind, reason ->
      Logger.error("Responsive images: #{inspect({kind, reason})}")
      state
  end

  defp announce([]), do: :ok

  defp announce(results) do
    Enum.each(results, fn
      {{{:failed, output}, rel}, _url} ->
        Logger.warning("Responsive images: could not cut #{rel}: #{String.trim(output)}")

      _ ->
        :ok
    end)

    generated = for {{:generated, _rel}, url} <- results, do: url

    if generated != [] do
      # The pages were rendered, and their `?v=` hashes taken, while these
      # files did not exist.
      ProjectStatic.bump_generation()
      Logger.info("Responsive images: cut #{length(generated)} variant(s) in the static dir")
    end

    :ok
  end

  ## Runtime pass

  @doc """
  Cuts the variants missing from the project's static overlay, for the theme's
  images whose originals live there.

  Answers `{:ok, [{result, variant_url}]}`, empty when there is nothing to do,
  or `{:error, :no_imagemagick}` when there is work and no tool to do it.
  Options: `:tool` (default: `find_tool/0`) and `:theme` (default: the current
  theme config, untranslated).
  """
  @spec cut_overlay(keyword()) ::
          {:ok, [{result(), String.t()}]} | {:error, :no_imagemagick}
  def cut_overlay(opts \\ []) do
    overlay = ProjectStatic.dirs() |> Enum.filter(&writable_project_dir?/1)
    theme = Keyword.get_lazy(opts, :theme, &current_theme/0)

    case missing_in(planned_variants(theme), overlay) do
      [] -> {:ok, []}
      work -> cut(work, Keyword.get_lazy(opts, :tool, &find_tool/0))
    end
  end

  defp cut(_work, nil), do: {:error, :no_imagemagick}

  defp cut(work, tool) do
    {:ok,
     Enum.map(work, fn {{_source, variant, _width} = planned, root} ->
       {resolve(planned, root, tool: tool), variant}
     end)}
  end

  # Each variant whose original the overlay serves, and which that same
  # directory does not have yet. A variant somewhere else is no use: the
  # renderer only offers one from the original's own directory.
  defp missing_in(_planned, []), do: []

  defp missing_in(planned, overlay) do
    for {source, variant, _width} = item <- planned,
        {root, _file} <- [ProjectStatic.lookup(source)],
        root in overlay,
        not File.regular?(Path.join(root, variant)),
        do: {item, root}
  end

  # Never inside the release's own files (`lib/`, where every app's priv is,
  # `releases/`, `erts-*`): a deploy replaces them, and they may not be the
  # project's to change. A `static/` a project keeps beside `bin/`, in a
  # release unpacked into the project folder, is the project's. The apps' own
  # priv dirs are already left out of the overlay; this is for a
  # GAMEND_CONTENT_STATIC_DIRS entry pointed somewhere below one.
  defp writable_project_dir?(dir) do
    root = Path.expand(to_string(:code.root_dir()))

    inside_release? =
      String.starts_with?(dir, Path.join(root, "erts-")) or
        Enum.any?([to_string(:code.lib_dir()), Path.join(root, "releases")], fn release_dir ->
          release_dir = Path.expand(release_dir)
          dir == release_dir or String.starts_with?(dir, release_dir <> "/")
        end)

    not inside_release? and
      match?(
        {:ok, %File.Stat{type: :directory, access: access}} when access in [:read_write, :write],
        File.stat(dir)
      )
  end

  defp current_theme do
    theme_mod = Application.get_env(:gamend_web, :theme_module, Gamend.Theme.JSONConfig)

    cond do
      not Code.ensure_loaded?(theme_mod) -> %{}
      function_exported?(theme_mod, :raw_theme, 0) -> theme_mod.raw_theme()
      function_exported?(theme_mod, :get_theme, 0) -> theme_mod.get_theme()
      true -> %{}
    end
  end

  ## Shared with `mix host.responsive_images`

  @doc """
  Every `{source, variant, width}` the config's `widths` declarations imply.

  Takes the JSON text or the decoded map. Pure, so it can be checked against a
  config without touching disk.
  """
  @spec planned_variants(String.t() | map()) :: [planned()]
  def planned_variants(json) when is_binary(json),
    do: json |> Jason.decode!() |> planned_variants()

  def planned_variants(config) when is_map(config) do
    config
    |> collect_images()
    |> Enum.flat_map(fn image ->
      widths =
        image |> Map.get("widths", []) |> List.wrap() |> Enum.filter(&(is_integer(&1) and &1 > 0))

      for path <- Enum.filter([image["light"], image["dark"]], &(is_binary(&1) and &1 != "")),
          width <- Enum.uniq(widths),
          do: {path, variant_path(path, width), width}
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Walks the whole config rather than the known page shapes: hero and section
  # images live at different depths, and a new block that carries an "image" is
  # picked up without touching this.
  defp collect_images(value) when is_map(value) do
    own = if is_map(value["image"]), do: [value["image"]], else: []
    own ++ Enum.flat_map(Map.values(value), &collect_images/1)
  end

  defp collect_images(value) when is_list(value), do: Enum.flat_map(value, &collect_images/1)
  defp collect_images(_value), do: []

  defp variant_path(path, width) do
    ext = Path.extname(path)
    String.replace_suffix(path, ext, "-#{width}#{ext}")
  end

  @doc """
  The ImageMagick to cut with: `magick` (v7) when it is on `PATH`, else v6's
  `convert` and `identify` outside Windows, whose own `convert.exe` formats
  disks. `nil` when there is none.
  """
  @spec find_tool() :: tool() | nil
  def find_tool do
    case System.find_executable("magick") do
      nil -> legacy_tool(:os.type())
      magick -> {:magick, magick}
    end
  end

  defp legacy_tool({:win32, _}), do: nil

  defp legacy_tool(_os) do
    with convert when is_binary(convert) <- System.find_executable("convert"),
         identify when is_binary(identify) <- System.find_executable("identify") do
      {:legacy, convert, identify}
    end
  end

  @doc """
  Brings one variant up to date under `static_root` and says what it did.

  Options: `:check` (only report whether the variant exists, write nothing)
  and `:tool` (required unless checking, or unless the source is missing).
  A variant is never wider than its source, never older than it, and never
  heavier: a cut that weighs more than the original is deleted.
  """
  @spec resolve(planned(), Path.t(), keyword()) :: result()
  def resolve({source, variant, width}, static_root, opts \\ []) do
    check? = Keyword.get(opts, :check, false)
    source_file = Path.join(static_root, source)
    variant_file = Path.join(static_root, variant)

    cond do
      not File.regular?(source_file) ->
        {:missing_source, variant}

      check? ->
        if File.regular?(variant_file), do: {:current, variant}, else: {:stale, variant}

      # Never upscale: a variant wider than the source is the source, and
      # writing it anyway would put a bigger file behind a smaller descriptor.
      width >= source_width(source_file, Keyword.fetch!(opts, :tool)) ->
        {:skipped_upscale, variant}

      fresh?(source_file, variant_file) ->
        {:current, variant}

      true ->
        generate(source_file, variant_file, width, static_root, Keyword.fetch!(opts, :tool))
    end
  end

  defp fresh?(source_file, variant_file) do
    with {:ok, %{mtime: variant_mtime}} <- File.stat(variant_file, time: :posix),
         {:ok, %{mtime: source_mtime}} <- File.stat(source_file, time: :posix) do
      variant_mtime >= source_mtime
    else
      _ -> false
    end
  end

  defp generate(source_file, variant_file, width, static_root, tool) do
    File.mkdir_p!(Path.dirname(variant_file))
    rel = Path.relative_to(variant_file, static_root)

    args =
      case Path.extname(variant_file) do
        ".webp" ->
          [
            source_file,
            "-resize",
            "#{width}x",
            "-quality",
            @webp_quality,
            "-define",
            "webp:method=6",
            variant_file
          ]

        _ ->
          [source_file, "-resize", "#{width}x", "-strip", variant_file]
      end

    {exe, prefix} = convert_command(tool)

    case System.cmd(exe, prefix ++ args, stderr_to_stdout: true) do
      {_output, 0} ->
        shrink_png(variant_file)
        verify_smaller(source_file, variant_file, rel)

      {output, _status} ->
        {{:failed, output}, rel}
    end
  end

  # ImageMagick writes truecolor PNG, but the sources are pngquant palettes —
  # so a naive 960-wide cut of a 1440 capture came out 25% BIGGER than the
  # original. Requantise to the same recipe host.optimize_images uses.
  defp shrink_png(variant_file) do
    if Path.extname(variant_file) == ".png" do
      pngquant = System.find_executable("pngquant")
      optipng = System.find_executable("optipng")
      tmp = variant_file <> ".quant.png"

      if pngquant do
        case System.cmd(
               pngquant,
               [
                 "--quality",
                 @png_quality,
                 "--speed",
                 "1",
                 "--force",
                 "--output",
                 tmp,
                 variant_file
               ],
               stderr_to_stdout: true
             ) do
          {_output, 0} -> File.rename!(tmp, variant_file)
          _ -> File.rm(tmp)
        end
      end

      if optipng, do: System.cmd(optipng, ["-quiet", "-o3", "-strip", "all", variant_file])
    end

    :ok
  end

  # A narrower cut that weighs more than the full-size original is worse than
  # having no variant at all: the browser would pick it on a small screen and
  # download more than it would have. Drop it rather than ship it.
  defp verify_smaller(source_file, variant_file, rel) do
    if File.stat!(variant_file).size < File.stat!(source_file).size do
      {:generated, rel}
    else
      File.rm!(variant_file)
      {:skipped_bigger, rel}
    end
  end

  defp source_width(source_file, tool) do
    {exe, prefix} = identify_command(tool)

    case System.cmd(exe, prefix ++ ["-format", "%w", source_file], stderr_to_stdout: true) do
      {output, 0} ->
        case Integer.parse(String.trim(output)) do
          {width, _rest} -> width
          :error -> 0
        end

      _ ->
        0
    end
  end

  defp convert_command({:magick, magick}), do: {magick, []}
  defp convert_command({:legacy, convert, _identify}), do: {convert, []}

  defp identify_command({:magick, magick}), do: {magick, ["identify"]}
  defp identify_command({:legacy, _convert, identify}), do: {identify, []}
end
