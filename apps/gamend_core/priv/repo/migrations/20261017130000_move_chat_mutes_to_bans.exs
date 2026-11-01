defmodule Gamend.Repo.Migrations.MoveChatMutesToBans do
  @moduledoc """
  Chat mutes become bans of kind `chat` (`Gamend.Bans`): `bans` gains the
  mute's reach, `scope` (`global`, `lobby`, `group`, `party`) and
  `scope_ref_id` (the room), and every `chat_mutes` row is copied over, then
  the table is dropped. The source is told from who muted: none is a plugin,
  an admin is an admin, anyone else a room's own authority.
  """

  # The rows the copy writes, typed so ids and times dump as the adapter stores
  # them. Defined before `use Ecto.Migration`, whose `timestamps/1` would clash
  # with the schema's inside a nested module.
  defmodule BanRow do
    @moduledoc false
    use Gamend.Schema

    schema "bans" do
      field(:kind, :string)
      field(:subject, :string)
      field(:user_id, Ecto.UUID)
      field(:scope, :string)
      field(:scope_ref_id, Ecto.UUID)
      field(:expires_at, :utc_datetime)
      field(:reason, :string)
      field(:source, :string)
      field(:banned_by, Ecto.UUID)
      field(:lifted_at, :utc_datetime)
      timestamps(type: :utc_datetime)
    end
  end

  defmodule MuteRow do
    @moduledoc false
    use Gamend.Schema

    schema "chat_mutes" do
      field(:user_id, Ecto.UUID)
      field(:scope, :string)
      field(:scope_ref_id, Ecto.UUID)
      field(:expires_at, :utc_datetime)
      field(:reason, :string)
      field(:muted_by, Ecto.UUID)
      timestamps(type: :utc_datetime)
    end
  end

  defmodule UserRow do
    @moduledoc false
    use Gamend.Schema

    schema "users" do
      field(:is_admin, :boolean)
    end
  end

  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:bans) do
      add :scope, :string
      # Polymorphic (lobby, group or party), so it cannot be a references/2.
      add :scope_ref_id, :binary_id
    end

    flush()

    admins = MapSet.new(repo().all(from(u in UserRow, where: u.is_admin == true, select: u.id)))

    rows =
      for mute <- repo().all(MuteRow) do
        %{
          id: mute.id,
          kind: "chat",
          subject: mute.user_id,
          user_id: mute.user_id,
          scope: mute.scope,
          scope_ref_id: mute.scope_ref_id,
          expires_at: mute.expires_at,
          reason: mute.reason,
          source: source(mute.muted_by, admins),
          banned_by: mute.muted_by,
          inserted_at: mute.inserted_at,
          updated_at: mute.updated_at
        }
      end

    rows |> Enum.chunk_every(500) |> Enum.each(&repo().insert_all(BanRow, &1))

    drop table(:chat_mutes)
  end

  def down do
    create table(:chat_mutes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :scope, :string, null: false, default: "global"
      add :scope_ref_id, :binary_id
      add :expires_at, :utc_datetime
      add :reason, :string
      add :muted_by, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chat_mutes, [:user_id, :scope, :scope_ref_id],
             name: :chat_mutes_user_scope_ref_index
           )

    create unique_index(:chat_mutes, [:user_id, :scope],
             name: :chat_mutes_user_global_index,
             where: "scope_ref_id IS NULL"
           )

    create index(:chat_mutes, [:user_id])
    create index(:chat_mutes, [:expires_at])
    create index(:chat_mutes, [:scope, :scope_ref_id])

    flush()

    now = DateTime.utc_now(:second)

    # The mutes still in force go back; ended ones were never kept there.
    rows =
      from(b in BanRow, where: b.kind == "chat" and is_nil(b.lifted_at))
      |> repo().all()
      |> Enum.filter(&(is_nil(&1.expires_at) or DateTime.after?(&1.expires_at, now)))
      |> Enum.map(fn ban ->
        %{
          id: ban.id,
          user_id: ban.user_id,
          scope: ban.scope,
          scope_ref_id: ban.scope_ref_id,
          expires_at: ban.expires_at,
          reason: ban.reason,
          muted_by: ban.banned_by,
          inserted_at: ban.inserted_at,
          updated_at: ban.updated_at
        }
      end)
      |> Enum.uniq_by(&{&1.user_id, &1.scope, &1.scope_ref_id})

    rows |> Enum.chunk_every(500) |> Enum.each(&repo().insert_all(MuteRow, &1))

    repo().delete_all(from(b in "bans", where: b.kind == "chat"))

    alter table(:bans) do
      remove :scope
      remove :scope_ref_id
    end
  end

  defp source(nil, _admins), do: "plugin"

  defp source(muted_by, admins),
    do: if(MapSet.member?(admins, muted_by), do: "admin", else: "room")
end
