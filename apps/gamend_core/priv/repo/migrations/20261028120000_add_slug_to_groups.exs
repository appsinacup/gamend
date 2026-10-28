defmodule Gamend.Repo.Migrations.AddSlugToGroups do
  @moduledoc """
  `groups.slug`: a group's name in its URL, `<owner>/<slug>` with its
  creator's username (`Gamend.Groups.full_slug/1`), unique per creator.
  Every group gets the nearest slug to its title (`Gamend.Slug.slugify/2`),
  oldest first, and a second of the same gets `-2`.

  The title stops being unique in the database: the `unique_titles` setting
  checks it in the changeset instead, so a host whose groups are hidden can
  turn it off and a taken title tells no one that a hidden group exists.
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
      slug = Gamend.Slug.free(Gamend.Slug.slugify(row.title, "group"), &MapSet.member?(mine, &1))

      {1, _} = repo().update_all(from(g in "groups", where: g.id == ^row.id), set: [slug: slug])

      Map.put(taken, row.creator_id, MapSet.put(mine, slug))
    end)
  end
end
