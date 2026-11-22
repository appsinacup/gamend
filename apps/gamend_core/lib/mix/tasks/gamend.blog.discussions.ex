defmodule Mix.Tasks.Gamend.Blog.Discussions do
  @shortdoc "Lists blog posts not yet on GitHub Discussions, or posts them"

  @moduledoc """
  Mirrors the blog into a repository's GitHub Discussions, one discussion per
  post, through the `gh` CLI and its login.

      mix gamend.blog.discussions          # list the posts not posted yet
      mix gamend.blog.discussions --post   # post them, oldest first

  A post counts as posted when a discussion's body links to it
  (`<site>/blog/<slug>`), so one written by hand counts too. The listing never
  fails: without `gh`, a login or a network it says so and stops, which is what
  lets `precommit` run it. Posting is never automatic, since a post goes public
  the moment it is created.

  The host names where to post:

      config :gamend_core, :blog_discussions,
        repo: "appsinacup/gamend",
        site: "https://gamend.org",
        category: "Announcements",
        tagline: "One line added under every post."

  The body is the post's markdown made to read on GitHub: links and pictures
  absolute, hard-wrapped lines joined (GitHub keeps a newline as a break), and
  a clip shown as its poster linked to the mp4.
  """

  use Mix.Task

  alias Gamend.Content
  alias Gamend.Content.Frontmatter
  alias Gamend.Content.Markdown

  @config_key :blog_discussions
  @default_category "Announcements"
  @page_size 100
  @truncate_marker "<!-- truncate -->"

  @discussions_query """
  query($owner: String!, $name: String!, $endCursor: String) {
    repository(owner: $owner, name: $name) {
      discussions(first: #{@page_size}, after: $endCursor) {
        nodes { body }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
  """

  @ids_query """
  query($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      id
      discussionCategories(first: 50) { nodes { id name } }
    }
  }
  """

  @create_mutation """
  mutation($repo: ID!, $category: ID!, $title: String!, $body: String!) {
    createDiscussion(input: {repositoryId: $repo, categoryId: $category, title: $title, body: $body}) {
      discussion { url }
    }
  }
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")
    {opts, _rest} = OptionParser.parse!(argv, strict: [post: :boolean])

    with {:ok, config} <- config(),
         {:ok, bodies} <- discussion_bodies(config.repo) do
      config
      |> unposted(Content.list_blog_posts(), bodies)
      |> act(config, Keyword.get(opts, :post, false))
    else
      {:skip, reason} -> Mix.shell().info("Blog discussions: skipped, #{reason}")
    end
  end

  @doc "The posts no discussion body links to, oldest first."
  @spec unposted(map(), [map()], [String.t()]) :: [map()]
  def unposted(config, posts, bodies) do
    posts
    |> Enum.reject(fn post ->
      Enum.any?(bodies, &String.contains?(&1, post_url(config, post)))
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc "A post's markdown as a discussion body."
  @spec body(map(), map(), String.t()) :: String.t()
  def body(config, post, markdown) do
    rel_dir = post_dir(post)

    markdown
    |> Frontmatter.body()
    |> drop_title(post.title)
    |> String.replace(@truncate_marker, "\n\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> unwrap()
    |> clips(config.site)
    |> relative_images(rel_dir)
    |> absolute_links(config.site)
    |> String.trim()
    |> Kernel.<>("\n\n---\n\nRead it on the site: #{post_url(config, post)}\n")
    |> tagline(config)
  end

  defp act([], _config, _post?), do: Mix.shell().info("Blog discussions: every post is posted")

  defp act(posts, config, false) do
    Mix.shell().info(
      "Blog discussions: #{length(posts)} post(s) not on #{config.repo}; " <>
        "`mix gamend.blog.discussions --post` posts them"
    )

    Enum.each(posts, &Mix.shell().info("  #{&1.slug}: #{&1.title}"))
  end

  defp act(posts, config, true) do
    {repo_id, category_id} = ids!(config)

    Enum.each(posts, fn post ->
      url = create!(repo_id, category_id, post.title, body(config, post, File.read!(post.path)))
      Mix.shell().info("#{post.title} -> #{url}")
    end)
  end

  defp config do
    case Application.get_env(:gamend_core, @config_key) do
      nil ->
        {:skip, "no :blog_discussions config"}

      config ->
        {:ok,
         %{
           repo: Keyword.fetch!(config, :repo),
           site: config |> Keyword.fetch!(:site) |> String.trim_trailing("/"),
           category: Keyword.get(config, :category, @default_category),
           tagline: Keyword.get(config, :tagline)
         }}
    end
  end

  defp post_url(config, post), do: "#{config.site}/blog/#{post.slug}"

  defp post_dir(post) do
    with dir when is_binary(dir) <- Content.path(:blog),
         rel when rel != "" <- post.path |> Path.dirname() |> Path.relative_to(dir),
         :relative <- Path.type(rel) do
      rel
    else
      _outside_the_blog -> "."
    end
  end

  defp discussion_bodies(repo) do
    if System.find_executable("gh") do
      {owner, name} = split_repo(repo)

      case gh([
             "api",
             "graphql",
             "--paginate",
             "-f",
             "query=" <> @discussions_query,
             "-f",
             "owner=" <> owner,
             "-f",
             "name=" <> name,
             "--jq",
             ".data.repository.discussions.nodes[].body | tojson"
           ]) do
        {:ok, out} -> {:ok, out |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)}
        {:error, message} -> {:skip, "gh failed: #{message}"}
      end
    else
      {:skip, "no gh on PATH"}
    end
  end

  defp ids!(config) do
    {owner, name} = split_repo(config.repo)

    out =
      gh!([
        "api",
        "graphql",
        "-f",
        "query=" <> @ids_query,
        "-f",
        "owner=" <> owner,
        "-f",
        "name=" <> name
      ])

    repository = Jason.decode!(out)["data"]["repository"]

    category =
      Enum.find(repository["discussionCategories"]["nodes"], &(&1["name"] == config.category)) ||
        Mix.raise("#{config.repo} has no discussion category #{inspect(config.category)}")

    {repository["id"], category["id"]}
  end

  defp create!(repo_id, category_id, title, body) do
    gh!([
      "api",
      "graphql",
      "-f",
      "query=" <> @create_mutation,
      "-f",
      "repo=" <> repo_id,
      "-f",
      "category=" <> category_id,
      "-f",
      "title=" <> title,
      "-f",
      "body=" <> body,
      "--jq",
      ".data.createDiscussion.discussion.url"
    ])
    |> String.trim()
  end

  defp gh(args) do
    case System.cmd("gh", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _status} -> {:error, out |> String.trim() |> String.split("\n") |> List.last()}
    end
  end

  defp gh!(args) do
    case gh(args) do
      {:ok, out} -> out
      {:error, message} -> Mix.raise("gh failed: #{message}")
    end
  end

  defp split_repo(repo) do
    case String.split(repo, "/") do
      [owner, name] -> {owner, name}
      _ -> Mix.raise(":blog_discussions repo must be owner/name, got #{inspect(repo)}")
    end
  end

  # A post titled by its first heading would show the title twice.
  defp drop_title(markdown, title) do
    String.replace(markdown, ~r/\A\s*# #{Regex.escape(title)}\s*\n/, "")
  end

  @block_start ~r/^\s*([-*+] |\d+\. |#|\||>|!\[|\[!\[|<|```|---)/

  defp unwrap(markdown) do
    {lines, _fence?} =
      markdown
      |> String.split("\n")
      |> Enum.reduce({[], false}, &unwrap_line/2)

    lines |> Enum.reverse() |> Enum.join("\n")
  end

  defp unwrap_line(line, {acc, fence?}) do
    cond do
      String.starts_with?(String.trim_leading(line), "```") ->
        {[line | acc], not fence?}

      not fence? and joins?(acc, line) ->
        [previous | rest] = acc
        {[String.trim_trailing(previous) <> " " <> String.trim(line) | rest], fence?}

      true ->
        {[line | acc], fence?}
    end
  end

  defp joins?([previous | _], line) do
    String.trim(line) != "" and String.trim(previous) != "" and
      not Regex.match?(@block_start, line) and
      not String.starts_with?(String.trim_leading(previous), ["|", "```", "#"]) and
      not String.ends_with?(previous, "  ")
  end

  defp joins?([], _line), do: false

  @clip ~r/<figure class="clip"><video[^>]*?poster="([^"]+)"[^>]*?aria-label="([^"]*)"[^>]*>.*?<source src="([^"]+\.mp4)"[^>]*>.*?<\/video><\/figure>/s

  # GitHub drops a <video> whose source is not its own upload.
  defp clips(markdown, site) do
    Regex.replace(@clip, markdown, fn _all, poster, label, mp4 ->
      "[![#{label}](#{absolute(site, poster)})](#{absolute(site, mp4)})\n\n" <>
        "▶ Click the picture to play the clip."
    end)
  end

  defp relative_images(markdown, rel_dir) do
    Regex.replace(~r/(!\[[^\]]*\])\((?![a-z]+:|\/)([^)\s]+)\)/, markdown, fn _all, alt, src ->
      "#{alt}(#{Markdown.image_src(Path.join(rel_dir, src), Content.blog_render_opts())})"
    end)
  end

  defp absolute_links(markdown, site) do
    markdown
    |> then(&Regex.replace(~r/\]\((\/[^)\s]*)/, &1, fn _all, path -> "](#{site}#{path}" end))
    |> then(
      &Regex.replace(~r/(src|poster|href)="(\/[^"]*)"/, &1, fn _all, attr, path ->
        ~s(#{attr}="#{site}#{path}")
      end)
    )
  end

  defp absolute(site, "/" <> _ = path), do: site <> path
  defp absolute(_site, url), do: url

  defp tagline(body, %{tagline: nil}), do: body
  defp tagline(body, %{tagline: line}), do: body <> "\n" <> line <> "\n"
end
