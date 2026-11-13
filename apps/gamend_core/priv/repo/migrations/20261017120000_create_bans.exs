defmodule Gamend.Repo.Migrations.CreateBans do
  @moduledoc """
  `bans`: every ban in one table (`Gamend.Bans`), an IP address or an account,
  with who placed it, why, and when it ended. Replaces `ip_bans`, whose rows are
  copied over as IP bans placed by an admin.

  An ended ban keeps its row (`lifted_at`, or an `expires_at` in the past), so a
  target's history is its rows; retention deletes ended rows after `bans_days`.
  """
  # The rows the data copy writes, typed so ids and times dump as the adapter
  # stores them. Defined before `use Ecto.Migration`, whose `timestamps/1`
  # would clash with the schema's inside a nested module. The keys are what
  # `use Gamend.Schema` set on 2026-11-13, written out so a change to it cannot
  # change this migration; every id is given (`id/0`).
  defmodule Row do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, Ecto.UUID, autogenerate: false}
    @foreign_key_type Ecto.UUID

    schema "bans" do
      field(:kind, :string)
      field(:subject, :string)
      field(:expires_at, :utc_datetime)
      field(:source, :string)
      timestamps(type: :utc_datetime)
    end
  end

  defmodule IpRow do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, Ecto.UUID, autogenerate: false}
    @foreign_key_type Ecto.UUID

    schema "ip_bans" do
      field(:ip, :string)
      field(:expires_at, :utc_datetime)
      timestamps(type: :utc_datetime)
    end
  end

  use Ecto.Migration

  import Ecto.Query

  def up do
    create table(:bans) do
      add :kind, :string, null: false
      # The address (an IPv6 one as its /64), or the user id.
      add :subject, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :expires_at, :utc_datetime
      add :reason, :text
      add :source, :string, null: false, default: "admin"
      add :banned_by, references(:users, on_delete: :nilify_all)
      add :lifted_at, :utc_datetime
      add :lifted_by, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # The active ban on a target, and its history.
    create index(:bans, [:kind, :subject])
    create index(:bans, [:user_id])
    # The boot load reads the bans not lifted; retention reads the ended ones.
    create index(:bans, [:lifted_at, :expires_at])

    flush()

    rows =
      repo().all(
        from(b in "ip_bans",
          select: %{
            subject: b.ip,
            expires_at: type(b.expires_at, :utc_datetime),
            inserted_at: type(b.inserted_at, :utc_datetime),
            updated_at: type(b.updated_at, :utc_datetime)
          }
        )
      )

    rows =
      Enum.map(rows, &Map.merge(&1, %{id: id(), kind: "ip", source: "admin"}))

    if rows != [], do: repo().insert_all(Row, rows)

    drop table(:ip_bans)
  end

  def down do
    create table(:ip_bans) do
      add :ip, :string, null: false
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ip_bans, [:ip])

    flush()

    now = DateTime.utc_now(:second)

    rows =
      repo().all(
        from(b in "bans",
          where:
            b.kind == "ip" and is_nil(b.lifted_at) and
              (is_nil(b.expires_at) or b.expires_at > type(^now, :utc_datetime)),
          select: %{
            ip: b.subject,
            expires_at: type(b.expires_at, :utc_datetime),
            inserted_at: type(b.inserted_at, :utc_datetime),
            updated_at: type(b.updated_at, :utc_datetime)
          }
        )
      )

    rows = rows |> Enum.uniq_by(& &1.ip) |> Enum.map(&Map.put(&1, :id, id()))
    if rows != [], do: repo().insert_all(IpRow, rows)

    drop table(:bans)
  end

  # `Gamend.UUIDv7.generate/0` as it was on 2026-11-13.
  defp id, do: Ecto.UUID.generate(version: 7, precision: :monotonic)
end
