defmodule Gamend.Repo.Migrations.AddSlugToGroups do
  @moduledoc """
  `groups.slug`: a group's name in its URL, `<owner>/<slug>` with its
  creator's username (`Gamend.Groups.full_slug/1`), unique per creator.
  Every group gets the nearest slug to its title (`Gamend.Slug.slugify/2`),
  oldest first, and a second of the same gets `-2`.

  The title stops being unique: the slug names a group, and a taken title
  would tell of a hidden group.
  """

  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:groups) do
      add :slug, :string
    end

    flush()
    backfill_slugs()

    create unique_index(:groups, [:creator_id, :slug])
    drop_if_exists unique_index(:groups, [:title])
    create index(:groups, [:title])
  end

  def down do
    drop_if_exists index(:groups, [:title])
    create unique_index(:groups, [:title])
    drop_if_exists index(:groups, [:creator_id, :slug])

    alter table(:groups) do
      remove :slug
    end
  end

  # The migration is the only writer, so the slugs taken so far are known.
  # The id is passed back as it was read, so it is the column's own type on
  # either database.
  defp backfill_slugs do
    from(g in "groups",
      order_by: [asc: g.inserted_at, asc: g.id],
      select: %{id: g.id, title: g.title, creator_id: g.creator_id}
    )
    |> repo().all(log: false)
    |> Enum.reduce(%{}, fn row, taken ->
      mine = Map.get(taken, row.creator_id, MapSet.new())
      slug = free(slugify(row.title, "group"), &MapSet.member?(mine, &1))

      {1, _} = repo().update_all(from(g in "groups", where: g.id == ^row.id), set: [slug: slug])

      Map.put(taken, row.creator_id, MapSet.put(mine, slug))
    end)
  end

  # `Gamend.Slug.slugify/2` and `free/2` as they were on 2026-11-13, copied so
  # a later change to them cannot change what this migration writes. A
  # database migrated before 243f1999b (2026-11-02) got the older, ASCII-only
  # slugify (`红色 军团` → `group`); one migrated since gets this one. Both
  # are valid slugs, so the drift is accepted.
  defp slugify(text, fallback) when is_binary(text) do
    text
    |> String.normalize(:nfkc)
    |> String.downcase()
    |> String.normalize(:nfc)
    |> String.replace(~r/[^\p{Ll}\p{Lm}\p{Lo}\p{Nd}\p{M}_-]+/u, "-")
    |> String.replace(~r/([-_])\p{M}+/u, "\\1")
    |> String.replace(~r/(\p{M}{3})\p{M}+/u, "\\1")
    |> String.replace(~r/[-_]{2,}/, "-")
    |> String.slice(0, 64)
    |> String.replace(~r/\A[-_\p{M}]+|[-_]+\z/u, "")
    |> case do
      "" -> fallback
      slug -> slug
    end
  end

  defp slugify(_text, fallback), do: fallback

  defp free(base, taken?) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not taken?.(&1)))
  end
end
