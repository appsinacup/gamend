defmodule GamendWeb.CLI.Starter do
  @moduledoc """
  `gamend starter`: copies a starter project into the working directory.

  A project folder is everything a release reads relative to where it runs:
  `.env`, `theme/config.json`, the markdown content (`CHANGELOG.md`,
  `ROADMAP.md`, `blog/`, `priv/docs/`), `static/` and `modules/plugins/`. A
  starter is one of those, ready to edit. None of it is required: a release
  runs from an empty folder, with no theme and no content.

  The template is a name under the host's `priv/starter/` (`default` when none
  is given), or a `.tar.gz` of a project folder, by path or http(s) URL. The
  name `website` is the Gamend website itself, published next to each release.

  An existing file is never overwritten unless `--force` is given, so running
  it again on a project only fills in what is missing. A missing `.env` is
  written with a fresh `GAMEND_AUTH_SECRET_KEY_BASE`, which is all a release
  needs to start.
  """

  @website_base "https://github.com/appsinacup/gamend/releases/download"

  @spec run([String.t()]) :: non_neg_integer()
  def run(args) do
    {opts, rest, _invalid} = OptionParser.parse(args, strict: [force: :boolean])
    template = List.first(rest) || "default"
    target = File.cwd!()

    with_template(template, fn source ->
      {copied, skipped} = copy_tree(source, target, opts[:force] || false)
      env = write_env(target)

      report(template, copied, skipped, env)
      0
    end)
  end

  defp with_template("http" <> _ = url, fun), do: with_download(url, fun)

  defp with_template("website", fun), do: with_download(website_url(), fun)

  defp with_template(template, fun) do
    cond do
      String.ends_with?(template, [".tar.gz", ".tgz"]) and File.regular?(template) ->
        with_archive(File.read!(template), fun)

      dir = template_dir(template) ->
        fun.(dir)

      File.dir?(template) ->
        fun.(Path.expand(template))

      true ->
        IO.puts(:stderr, "No starter template named #{inspect(template)}.")
        IO.puts(:stderr, "Known templates: #{Enum.join(["website" | known_templates()], ", ")}")
        1
    end
  end

  defp template_dir(name) do
    with root when is_binary(root) <- templates_root(),
         dir = Path.join(root, Path.basename(name)),
         true <- File.dir?(dir) do
      dir
    else
      _missing -> nil
    end
  end

  defp known_templates do
    case templates_root() && File.ls(templates_root()) do
      {:ok, names} -> Enum.sort(names)
      _missing -> []
    end
  end

  defp templates_root do
    app = GamendWeb.host_app()

    case :code.priv_dir(app) do
      dir when is_list(dir) -> Path.join(to_string(dir), "starter")
      {:error, _not_loaded} -> nil
    end
  end

  # The website ships with each published release; a build without a version
  # of its own (the mix.exs default) takes the rolling one.
  defp website_url do
    app = GamendWeb.host_app()
    Application.load(app)

    tag =
      case Application.spec(app, :vsn) do
        vsn when vsn in [nil, ~c"1.0.0"] -> "server-latest"
        vsn -> "server-v#{vsn}"
      end

    "#{@website_base}/#{tag}/gamend-website.tar.gz"
  end

  defp with_download(url, fun) do
    IO.puts("Downloading #{url}")
    {:ok, _started} = Application.ensure_all_started(:req)

    case Req.get(url, decode_body: false, retry: :transient) do
      {:ok, %{status: 200, body: body}} ->
        with_archive(body, fun)

      {:ok, %{status: status}} ->
        IO.puts(:stderr, "Download failed: HTTP #{status}")
        1

      {:error, reason} ->
        IO.puts(:stderr, "Download failed: #{Exception.message(reason)}")
        1
    end
  end

  # Unpacked into a scratch directory first, so what lands in the project goes
  # through the same no-overwrite copy as a bundled template, and an archive
  # entry can never write outside the project. The system `tar` reads what
  # macOS's writes (extended attributes as pax records, which :erl_tar
  # rejects); :erl_tar covers a machine without one.
  defp with_archive(bytes, fun) do
    tmp = Path.join(System.tmp_dir!(), "gamend-starter-#{System.unique_integer([:positive])}")
    archive = tmp <> ".tar.gz"
    File.mkdir_p!(tmp)
    File.write!(archive, bytes)

    try do
      case extract(archive, tmp) do
        :ok ->
          fun.(archive_root(tmp))

        {:error, reason} ->
          IO.puts(:stderr, "Not a .tar.gz project: #{reason}")
          1
      end
    after
      File.rm_rf(tmp)
      File.rm(archive)
    end
  end

  defp extract(archive, dir) do
    with tar when is_binary(tar) <- System.find_executable("tar"),
         {_output, 0} <- System.cmd(tar, ["-xzf", archive, "-C", dir], stderr_to_stdout: true) do
      :ok
    else
      nil ->
        case :erl_tar.extract(String.to_charlist(archive), [
               :compressed,
               {:cwd, String.to_charlist(dir)}
             ]) do
          :ok -> :ok
          {:error, reason} -> {:error, inspect(reason)}
        end

      {output, _status} ->
        {:error, String.trim(output)}
    end
  end

  # An archive made with `tar czf x.tar.gz my-game/` holds one top directory;
  # its contents are the project.
  defp archive_root(dir) do
    case File.ls!(dir) do
      [only] -> if File.dir?(Path.join(dir, only)), do: Path.join(dir, only), else: dir
      _many -> dir
    end
  end

  defp copy_tree(source, target, force?) do
    source
    |> files()
    |> Enum.reduce({[], []}, fn relative, {copied, skipped} ->
      from = Path.join(source, relative)
      to = Path.join(target, relative)

      if File.exists?(to) and not force? do
        {copied, [relative | skipped]}
      else
        File.mkdir_p!(Path.dirname(to))
        File.cp!(from, to)
        {[relative | copied], skipped}
      end
    end)
    |> then(fn {copied, skipped} -> {Enum.reverse(copied), Enum.reverse(skipped)} end)
  end

  # Relative paths of every regular file under `dir`, dotfiles included, in a
  # stable order. Symlinks are skipped: a template has no business pointing
  # outside itself.
  defp files(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&regular_file?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.sort()
  end

  defp regular_file?(path) do
    match?({:ok, %File.Stat{type: :regular}}, File.lstat(path))
  end

  # A missing .env is written with a new secret; an existing one only gains a
  # secret when it has none, and is otherwise left exactly as it is.
  defp write_env(target) do
    path = Path.join(target, ".env")
    secret = 64 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)

    cond do
      not File.exists?(path) ->
        File.write!(path, """
        # Written by `gamend starter`. Every setting, with its default, is in
        # .env.example; real environment variables win over this file.
        GAMEND_AUTH_SECRET_KEY_BASE=#{secret}
        """)

        :created

      File.read!(path) =~ ~r/^\s*GAMEND_AUTH_SECRET_KEY_BASE=/m ->
        :kept

      true ->
        existing = File.read!(path)
        separator = if existing == "" or String.ends_with?(existing, "\n"), do: "", else: "\n"
        File.write!(path, separator <> "GAMEND_AUTH_SECRET_KEY_BASE=#{secret}\n", [:append])
        :appended
    end
  end

  defp report(template, copied, skipped, env) do
    IO.puts("Starter #{inspect(template)} in #{File.cwd!()}")
    Enum.each(copied, &IO.puts("  created  #{&1}"))
    Enum.each(skipped, &IO.puts("  kept     #{&1} (exists; --force overwrites)"))

    case env do
      :created -> IO.puts("  created  .env (with a new secret key)")
      :appended -> IO.puts("  updated  .env (added a secret key)")
      :kept -> :ok
    end

    IO.puts("\nNext: gamend start")
  end
end
