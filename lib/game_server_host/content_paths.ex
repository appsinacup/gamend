defmodule GameServerHost.ContentPaths do
  @moduledoc false

  alias GameServer.Content

  @default_candidates [
    changelog: ["CHANGELOG.md"],
    roadmap: ["ROADMAP.md"],
    blog: ["blog"],
    docs: ["priv/docs"]
  ]

  @spec register_defaults() :: :ok
  def register_defaults do
    config = Application.get_env(:game_server_core, Content, []) || []

    Content.register_path(:changelog,
      kind: :file,
      candidates: candidates(config, :changelog)
    )

    Content.register_path(:roadmap,
      kind: :file,
      candidates: candidates(config, :roadmap)
    )

    Content.register_path(:blog,
      kind: :dir,
      candidates: candidates(config, :blog)
    )

    Content.register_path(:docs,
      kind: :dir,
      candidates: candidates(config, :docs)
    )
  end

  defp candidates(config, name) do
    Keyword.get(config, candidate_key(name), Keyword.fetch!(@default_candidates, name))
  end

  defp candidate_key(name), do: String.to_atom("#{name}_candidates")
end
