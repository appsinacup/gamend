defmodule Mix.Tasks.Gamend.Github.App do
  @shortdoc "Register the server's GitHub App from a manifest"

  @moduledoc """
  Register the server's GitHub App (`Gamend.GitHub`), with every URL right,
  in one click.

      mix gamend.github.app --host https://example.org
      mix gamend.github.app --host https://example.org --org my-org
      mix gamend.github.app --host https://example.org --env .env

  GitHub has no API for creating an App or editing its callback URLs; the
  manifest flow is the closest thing. This task serves one page on localhost
  holding the manifest (`Gamend.GitHub.Manifest`, which the host names and
  gives its webhook and permissions), opens it in the browser, and waits.
  Pressing the button posts the manifest to github.com, where the signed-in
  person confirms once; GitHub sends a code back to localhost, and the task
  trades it for the App's id, slug, client pair, webhook secret and private
  key.

  The settings are printed, or appended to the file `--env` names. The App's
  own page on GitHub is where they can be looked up again, except the client
  secret and the private key, which GitHub shows once; a lost one is replaced
  there, not recovered.

  Run it from any machine with a browser; nothing here needs the server.
  `--org` registers the App under an organisation the person administers
  rather than their own account. `--name` if the default is taken: App names
  are global on GitHub. `--port` moves the localhost listener; `--no-open`
  prints the URL instead of opening it.
  """

  use Mix.Task

  alias Gamend.GitHub.Manifest

  @open "open"

  @impl true
  def run(argv) do
    {opts, _rest} =
      OptionParser.parse!(argv,
        strict: [
          host: :string,
          name: :string,
          org: :string,
          port: :integer,
          env: :string,
          open: :boolean
        ]
      )

    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:req)

    host =
      Keyword.get(opts, :host) ||
        Mix.raise(
          "--host is required: the App's URLs are built from it (--host https://example.org)"
        )

    port = Keyword.get(opts, :port, 4777)
    state = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    manifest =
      Manifest.build(host,
        name: Keyword.get(opts, :name, Manifest.default_name()),
        redirect_url: "http://localhost:#{port}/callback"
      )

    org = Keyword.get(opts, :org)

    plug =
      {GamendWeb.GitHubManifestPage,
       owner: self(),
       state: state,
       manifest: manifest,
       org: org,
       action: Manifest.form_action(org, state)}

    {:ok, _server} = Bandit.start_link(plug: plug, port: port, ip: :loopback, startup_log: false)

    # Where the App will live is the one thing the form cannot undo, so it is
    # said here and on the page before anything is pressed.
    Mix.shell().info(
      "Registering #{manifest["name"]} under " <>
        if(org,
          do: "the organisation #{org}.",
          else: "your personal account. Pass --org <name> to register it under an organisation."
        )
    )

    url = "http://localhost:#{port}/"
    Mix.shell().info("Open #{url} and press the button; waiting for GitHub to call back.")
    if Keyword.get(opts, :open, true), do: open_browser(url)

    code =
      receive do
        {:manifest_code, code} -> code
      after
        600_000 -> Mix.raise("GitHub did not call back within ten minutes")
      end

    case Manifest.convert(code) do
      {:ok, app} ->
        deliver(app, Keyword.get(opts, :env))

      {:error, reason} ->
        Mix.raise(
          "GitHub refused the conversion: #{inspect(reason)}. The code is good once; run the task again."
        )
    end
  end

  defp deliver(app, nil) do
    Mix.shell().info("""

    Registered #{app.slug}: #{app.html_url || "github.com/apps/#{app.slug}"}

    Add to .env on the server, then restart the app:

    #{Enum.join(Manifest.env_lines(app), "\n")}
    """)
  end

  defp deliver(app, path) do
    lines = Manifest.env_lines(app)

    File.write!(
      path,
      Enum.join(
        ["", "# GitHub App #{app.slug}, registered by mix gamend.github.app" | lines],
        "\n"
      ) <>
        "\n",
      [:append]
    )

    Mix.shell().info("""

    Registered #{app.slug}: #{app.html_url || "github.com/apps/#{app.slug}"}
    Appended #{length(lines)} settings to #{path}. Restart the app to read them.
    """)
  end

  defp open_browser(url) do
    cmd =
      case :os.type() do
        {:unix, :darwin} -> @open
        {:unix, _} -> "xdg-open"
        _ -> nil
      end

    if cmd && System.find_executable(cmd) do
      System.cmd(cmd, [url], stderr_to_stdout: true)
    end

    :ok
  end
end
