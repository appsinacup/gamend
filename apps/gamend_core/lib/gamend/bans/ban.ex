defmodule Gamend.Bans.Ban do
  @moduledoc """
  One ban: an IP address, an account or a chat sender kept out until
  `expires_at` (`nil` is permanent), or until someone lifts it.

  A row is kept after it ends, lifted or expired, so a target's history reads
  as its rows; retention deletes ended rows after `bans_days`. A ban is active
  while `lifted_at` is nil and `expires_at` is nil or still ahead.

    * `kind` — `:ip` (`subject` is the address, an IPv6 one as its /64),
      `:account` (`subject` is the user id, also in `user_id`) or `:chat`, a
      mute (`subject` and `user_id` are the muted player).
    * `scope` / `scope_ref_id` — a chat ban's reach: `"global"` (every chat,
      friend DMs included; no room id) or `"lobby"`, `"group"` or `"party"`
      with that room's id. Nil for the other kinds.
    * `reason` — why, in the words the banned player is shown.
    * `source` — who placed it: `:admin` (the admin pages), `:api` (the admin
      API), `:room` (a lobby host, group admin or party leader, in their own
      room), `:plugin` (a game hook) or `:system`.
    * `banned_by` / `lifted_by` — the person who placed or lifted it, when one did.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User

  @kinds [:ip, :account, :chat]
  @sources [:admin, :api, :room, :plugin, :system]
  @scopes ~w(global lobby group party)

  @type kind :: :ip | :account | :chat
  @type t :: %__MODULE__{}

  schema "bans" do
    field :kind, Ecto.Enum, values: @kinds
    field :subject, :string
    field :scope, :string
    field :scope_ref_id, Ecto.UUID
    field :expires_at, :utc_datetime
    field :reason, :string
    field :source, Ecto.Enum, values: @sources, default: :admin
    field :lifted_at, :utc_datetime

    belongs_to :user, User
    belongs_to :banned_by_user, User, foreign_key: :banned_by
    belongs_to :lifted_by_user, User, foreign_key: :lifted_by

    timestamps(type: :utc_datetime)
  end

  @doc "The kinds of ban."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "Who may place a ban."
  @spec sources() :: [atom()]
  def sources, do: @sources

  @doc "The reaches a chat ban may have."
  @spec scopes() :: [String.t()]
  def scopes, do: @scopes

  @doc """
  The key a ban is cached and replaced under: `{kind, subject, scope}`, the
  scope nil for an IP or account ban, `"global"` or `{room_kind, room_id}` for
  a chat ban.
  """
  @spec target(kind(), String.t(), String.t() | nil, String.t() | nil) :: tuple()
  def target(:chat, subject, "global", _ref), do: {:chat, subject, "global"}
  def target(:chat, subject, scope, ref), do: {:chat, subject, {scope, ref}}
  def target(kind, subject, _scope, _ref), do: {kind, subject, nil}

  @doc "`target/4` of a ban."
  @spec target(t()) :: tuple()
  def target(%__MODULE__{} = ban), do: target(ban.kind, ban.subject, ban.scope, ban.scope_ref_id)

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(ban, attrs) do
    ban
    |> cast(attrs, [
      :kind,
      :subject,
      :scope,
      :scope_ref_id,
      :user_id,
      :expires_at,
      :reason,
      :source,
      :banned_by
    ])
    |> validate_required([:kind, :subject, :source])
    |> validate_length(:subject, max: 64)
    |> validate_length(:reason, max: Gamend.Limits.get(:max_ban_reason))
    |> validate_scope()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:banned_by)
  end

  # A chat ban reaches every chat or one room; the other kinds have no scope.
  defp validate_scope(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :scope),
          get_field(changeset, :scope_ref_id)} do
      {:chat, "global", nil} ->
        changeset

      {:chat, "global", _ref} ->
        add_error(changeset, :scope_ref_id, "must be nil for a global mute")

      {:chat, scope, ref} when scope in @scopes ->
        if ref,
          do: changeset,
          else: add_error(changeset, :scope_ref_id, "is required for a scoped mute")

      {:chat, _scope, _ref} ->
        add_error(changeset, :scope, "is invalid")

      {_kind, nil, nil} ->
        changeset

      {_kind, _scope, _ref} ->
        add_error(changeset, :scope, "is only for a chat ban")
    end
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# Gamend.SchemaJSON: game clients choke on null), for a plugin that returns one.
defimpl Jason.Encoder, for: Gamend.Bans.Ban do
  def encode(ban, opts) do
    Gamend.SchemaJSON.encode(
      ban,
      [
        :id,
        :kind,
        :subject,
        :user_id,
        :scope,
        :scope_ref_id,
        :expires_at,
        :reason,
        :source,
        :banned_by,
        :lifted_at,
        :lifted_by,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
