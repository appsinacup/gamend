defmodule Gamend.Repo.Migrations.StableStorageUrls do
  @moduledoc """
  Rewrite stored object URLs that were signed S3 links to `/storage/<key>`.

  On an S3 bucket with no `GAMEND_STORAGE_PUBLIC_URL`, `Gamend.Storage.url/1`
  used to answer a link signed for an hour, and that link is what avatar and
  icon uploads saved. Every such image stopped loading an hour after it was
  uploaded. The URL handed out now is `/storage/<key>`, which redirects to a
  fresh signed link; this puts the rows already written on it.

  Only values carrying an S3 signature are touched, and the key is found by
  its `<prefix>/<id>/` segment, the way it was built. No-op on a deployment
  that never had a private bucket.
  """
  use Ecto.Migration

  import Ecto.Query

  @columns [
    {"users", :profile_url, "avatars"},
    {"groups", :icon_url, "icons/groups"},
    {"quests", :icon_url, "icons/quests"},
    {"leaderboards", :icon_url, "icons/leaderboards"},
    {"tournaments", :icon_url, "icons/tournaments"}
  ]

  def up do
    for {table, column, prefix} <- @columns do
      rows =
        repo().all(
          from(r in table,
            where: like(field(r, ^column), "%X-Amz-Signature=%"),
            select: {type(r.id, :binary_id), field(r, ^column)}
          ),
          log: false
        )

      for {id, url} <- rows, key = storage_key(url, "#{prefix}/#{id}/") do
        repo().update_all(
          from(r in table, where: r.id == type(^id, :binary_id)),
          [set: [{column, "/storage/" <> key}]],
          log: false
        )
      end
    end
  end

  def down, do: :ok

  defp storage_key(url, segment) do
    case :binary.match(url, segment) do
      {pos, _len} ->
        url |> binary_part(pos, byte_size(url) - pos) |> String.split("?", parts: 2) |> hd()

      :nomatch ->
        nil
    end
  end
end
