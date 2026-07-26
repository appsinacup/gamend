defmodule GameServer.Tournaments.Tournament do
  @moduledoc """
  A bracket tournament occurrence.

  Recurring tournaments share a `slug` (one row per occurrence, like
  leaderboard seasons); `recur` holds the cron expression that spawns the next
  occurrence. `team_size` is advisory — core only ever tracks entry leaders.
  A nil `starts_at` means manual start: registration stays open until an
  admin/game sets `starts_at` (the "draw now" force action does exactly that).

  `icon_url` is optional; when nil, clients show their default tournament
  icon (the web UI uses `GameServerWeb.Icons.default(:tournament)`).
  """

  use GameServer.Schema
  import Ecto.Changeset

  @states ~w(scheduled registration running finished cancelled)
  @deadline_policies ~w(forfeit_both advance_first_slot random)

  schema "tournaments" do
    field :slug, :string
    field :title, :string
    field :description, :string, default: ""
    field :icon_url, :string
    field :state, :string, default: "scheduled"
    field :registration_opens_at, :utc_datetime
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :recur, :string
    field :max_entries, :integer
    field :team_size, :integer, default: 1
    field :bracket_size, :integer, default: 8
    field :round_window_sec, :integer
    field :deadline_policy, :string, default: "forfeit_both"
    field :metadata, :map, default: %{}

    has_many :entries, GameServer.Tournaments.Entry

    timestamps(type: :utc_datetime)
  end

  def states, do: @states
  def deadline_policies, do: @deadline_policies

  @required ~w(slug title round_window_sec)a
  @optional ~w(description icon_url state registration_opens_at starts_at ends_at recur
               max_entries team_size bracket_size deadline_policy metadata)a

  def changeset(tournament, attrs) do
    tournament
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9_-]*$/,
      message: "only lowercase letters, digits, _ and -"
    )
    |> validate_length(:slug, min: 1, max: GameServer.Limits.get(:max_tournament_slug))
    |> validate_length(:title, min: 1, max: GameServer.Limits.get(:max_tournament_title))
    |> validate_length(:description, max: GameServer.Limits.get(:max_tournament_description))
    |> validate_length(:icon_url, max: GameServer.Limits.get(:max_profile_url))
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:deadline_policy, @deadline_policies)
    |> validate_number(:team_size, greater_than: 0)
    |> validate_number(:round_window_sec, greater_than: 0)
    |> validate_number(:max_entries,
      greater_than: 1,
      less_than_or_equal_to: GameServer.Limits.get(:max_tournament_entries)
    )
    |> validate_bracket_size()
    |> validate_recur_needs_starts_at()
    |> validate_windows()
    |> GameServer.Limits.validate_metadata_size(:metadata)
  end

  defp validate_bracket_size(changeset) do
    max = GameServer.Limits.get(:max_tournament_bracket_size)

    validate_change(changeset, :bracket_size, fn :bracket_size, size ->
      cond do
        not (is_integer(size) and size >= 2 and Bitwise.band(size, size - 1) == 0) ->
          [bracket_size: "must be a power of two >= 2"]

        size > max ->
          [bracket_size: "must be at most #{max}"]

        true ->
          []
      end
    end)
  end

  defp validate_recur_needs_starts_at(changeset) do
    if get_field(changeset, :recur) && get_field(changeset, :starts_at) == nil do
      add_error(changeset, :starts_at, "required for recurring tournaments")
    else
      changeset
    end
  end

  defp validate_windows(changeset) do
    reg = get_field(changeset, :registration_opens_at)
    starts = get_field(changeset, :starts_at)
    ends = get_field(changeset, :ends_at)

    cond do
      reg && starts && DateTime.compare(reg, starts) == :gt ->
        add_error(changeset, :registration_opens_at, "must not be after starts_at")

      starts && ends && DateTime.compare(starts, ends) != :lt ->
        add_error(changeset, :ends_at, "must be after starts_at")

      true ->
        changeset
    end
  end
end
