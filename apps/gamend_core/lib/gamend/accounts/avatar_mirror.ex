defmodule Gamend.Accounts.AvatarMirror do
  @moduledoc """
  Oban worker that mirrors a user's external (OAuth provider) avatar into our
  own object storage, so avatars render from our storage/CDN instead of
  hotlinking the provider.

  Enqueued on sign-in whenever a user's avatar is still an external URL (see
  `Gamend.Accounts.maybe_mirror_avatar/1`). Once mirrored the stored URL
  lives under our own `avatars/<user_id>/` prefix, so the check short-circuits
  and we never re-fetch an avatar we already host.

  A *failed* mirror is a different matter from a finished one. Provider CDNs
  rate-limit (Google answers 429 readily), so the download is retried with
  backoff, and a run that exhausts its attempts does not poison the user
  forever — the next sign-in enqueues a fresh job. Until one succeeds the
  provider URL stays as the fallback, which is why an un-mirrored avatar can
  still 429 in the browser.
  """
  use Oban.Worker, queue: :storage, max_attempts: 5

  require Logger

  alias Gamend.Accounts
  alias Gamend.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "source_url" => source_url}}) do
    case Accounts.get_user(user_id) do
      # Mirror only while the stored avatar is still exactly the provider URL we
      # were asked to mirror. If the user has since uploaded or changed it, or is
      # gone, there is nothing to do and nothing to retry.
      %{profile_url: ^source_url} = user -> mirror(user, source_url)
      _ -> :ok
    end
  rescue
    e ->
      Logger.warning("avatar mirror crashed user=#{user_id}: #{inspect(e)}")
      {:error, e}
  end

  defp mirror(user, source_url) do
    # `:avatar_mirror_req_options` lets tests inject a Req.Test plug; empty in prod.
    req_opts = Application.get_env(:gamend_core, :avatar_mirror_req_options, [])

    with {:ok, %Req.Response{status: 200} = resp} <- fetch(source_url, req_opts),
         body when is_binary(body) <- resp.body,
         content_type <- content_type(resp, source_url),
         :ok <- Storage.validate_upload(content_type, byte_size(body)),
         key <- Storage.build_key("avatars", user.id, "avatar#{extension(content_type)}"),
         {:ok, ^key} <- Storage.put(key, body, content_type: content_type) do
      attach(user, key)
    else
      # Rate limits and provider hiccups are worth another go; Oban backs off.
      {:ok, %Req.Response{status: status}} when status in [408, 429] or status >= 500 ->
        Logger.info("avatar mirror retrying user=#{user.id}: HTTP #{status}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.info("avatar mirror retrying user=#{user.id}: #{inspect(reason)}")
        {:error, reason}

      # A 404, an image type we refuse, a body that is not binary: retrying
      # changes nothing, so stop and leave the provider URL as the fallback.
      other ->
        Logger.info("avatar mirror gave up user=#{user.id}: #{inspect(other)}")
        {:cancel, other}
    end
  end

  # The object is written before the row that points at it, so every way of
  # failing here leaves bytes in storage that nothing references. The download
  # takes long enough for the account to be deleted while it runs, and
  # `Accounts.delete_user/1` has already dropped this user's storage prefix by
  # then — so an object written afterwards would outlive the account. Delete what
  # we just wrote instead of leaving it for the retention sweep to notice hours
  # later; a deleted row raises `Ecto.StaleEntryError` rather than returning an
  # error changeset, which is why both are handled.
  defp attach(user, key) do
    case Accounts.update_user_avatar(user, Storage.url(key)) do
      {:ok, _updated} ->
        _ = Accounts.prune_user_avatars(user.id, key)
        :ok

      {:error, changeset} ->
        _ = Storage.delete(key)
        Logger.info("avatar mirror discarded user=#{user.id}: #{inspect(changeset.errors)}")
        {:cancel, :avatar_not_saved}
    end
  rescue
    Ecto.StaleEntryError ->
      _ = Storage.delete(key)
      Logger.info("avatar mirror discarded user=#{user.id}: account deleted mid-mirror")
      {:cancel, :user_deleted}
  end

  defp fetch(source_url, req_opts) do
    Gamend.HTTP.get(source_url, [decode_body: false] ++ req_opts)
  rescue
    e -> {:error, e}
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
