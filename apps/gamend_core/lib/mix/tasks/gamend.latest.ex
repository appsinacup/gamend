defmodule Mix.Tasks.Gamend.Latest do
  @shortdoc "Raises this app's Gamend floor to the newest release on Hex"

  @moduledoc """
  Sets `@gamend_min` in the app's `mix.exs` to Gamend's newest release on Hex.

      mix gamend.latest

  An app's lock holds no Gamend entry, and Docker keeps its `mix deps.get`
  layer until `mix.exs` or `mix.lock` changes, which a release does not do. So
  a deploy goes on building the release that layer first resolved. Run from an
  app's `precommit`, this moves `mix.exs`, and the build that commit reaches
  takes the release.

  It only raises. With Hex out of reach it warns and changes nothing, so a
  commit can be prepared offline.
  """

  use Mix.Task

  @url "https://hex.pm/api/packages/gamend_core"
  @floor ~r/@gamend_min "([^"]+)"/

  @impl true
  def run(_argv) do
    {:ok, _started} = Application.ensure_all_started(:req)
    source = File.read!("mix.exs")

    current =
      case Regex.run(@floor, source) do
        [_whole, version] -> version
        nil -> Mix.raise(~s(mix.exs has no @gamend_min "<version>"))
      end

    case latest() do
      {:ok, latest} -> raise_floor(source, current, latest)
      {:error, reason} -> Mix.shell().error("Gamend's newest release is unknown: #{reason}")
    end
  end

  defp raise_floor(source, current, latest) do
    if Version.compare(latest, current) == :gt do
      File.write!("mix.exs", Regex.replace(@floor, source, ~s(@gamend_min "#{latest}")))
      Mix.shell().info("@gamend_min #{current} -> #{latest}")
    else
      Mix.shell().info("@gamend_min #{current} is the newest")
    end
  end

  defp latest do
    case Req.get(@url, retry: false, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"latest_stable_version" => version}}} -> {:ok, version}
      {:ok, %{status: status}} -> {:error, "Hex answered #{status}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end
end
