defmodule GameServer.Accounts.AvatarMirror do
  @moduledoc """
  Oban worker that mirrors a user's external (OAuth provider) avatar into our
  own object storage, so avatars render from our storage/CDN instead of
  hotlinking the provider.

  Enqueued **once** — the first time a user gets a provider avatar while nothing
  is stored yet (see `GameServer.Accounts.maybe_mirror_avatar/2`). We never
  re-mirror: a repeated fetch is wasteful and can trip a provider's rate limits,
  so if the download fails the provider URL simply stays as the fallback.
  """
  use Oban.Worker, queue: :storage, max_attempts: 1

  require Logger

  alias GameServer.Accounts
  alias GameServer.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "source_url" => source_url}}) do
    case Accounts.get_user(user_id) do
      # Mirror only while the stored avatar is still exactly the provider URL we
      # were asked to mirror. If the user has since uploaded or changed it, or is
      # gone, leave things alone.
      %{profile_url: ^source_url} = user -> mirror(user, source_url)
      _ -> :ok
    end
  rescue
    e ->
      Logger.info("avatar mirror crashed user=#{user_id}: #{inspect(e)}")
      :ok
  end

  defp mirror(user, source_url) do
    # `:avatar_mirror_req_options` lets tests inject a Req.Test plug; empty in prod.
    req_opts = Application.get_env(:game_server_core, :avatar_mirror_req_options, [])

    with {:ok, %Req.Response{status: 200} = resp} <-
           Req.get(source_url, [decode_body: false] ++ req_opts),
         body when is_binary(body) <- resp.body,
         content_type <- content_type(resp, source_url),
         :ok <- Storage.validate_upload(content_type, byte_size(body)),
         key <- Storage.build_key("avatars", user.id, "avatar#{extension(content_type)}"),
         {:ok, ^key} <- Storage.put(key, body, content_type: content_type),
         {:ok, _updated} <- Accounts.update_user_avatar(user, Storage.url(key)) do
      _ = Accounts.prune_user_avatars(user.id, key)
      :ok
    else
      other ->
        # Keep the provider URL as the fallback; do not retry.
        Logger.info("avatar mirror skipped user=#{user.id}: #{inspect(other)}")
        :ok
    end
  end

  defp content_type(resp, url) do
    case Req.Response.get_header(resp, "content-type") do
      [ct | _] when is_binary(ct) -> ct |> String.split(";") |> List.first() |> String.trim()
      _ -> url |> URI.parse() |> Map.get(:path, "") |> to_string() |> MIME.from_path()
    end
  end

  defp extension(content_type) do
    case MIME.extensions(content_type) do
      [ext | _] -> "." <> ext
      _ -> ".png"
    end
  end
end
