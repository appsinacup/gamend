defmodule Gamend.Quests.QuestCode do
  @moduledoc """
  Ecto schema for the `quest_codes` table: one redemption code of a
  `code_only` quest (`Gamend.Quests.redeem_code/2`).

  ## Fields

  - `token` — the code as people see it (`ABCD-EFGH-JKMN-PQRS`, `春节快乐`).
    Kept in plain text so an admin can export a batch again and read a public
    code
  - `lookup` — `normalize/1` of the token, unique across quests, and the only
    column a redeem reads by: the player types only the code, so nothing else
    can say which quest is meant
  - `max_uses` — `1` single-use, `N` the first N players, `nil` every player
    once
  - `uses` — how many players redeemed it, counted on the row for a capped
    code only (the cap is checked against it). An uncapped code's redeems
    would all update this one row, so it stays as it is and
    `Gamend.Quests.Codes` reads its count from `quest_progress`
  - `status` — `"active"` or `"revoked"`
  - `metadata` — copied onto each player's `quest_progress` row, so a hook can
    tell which channel a redemption came from. Players can read it there
  """

  use Gamend.Schema
  import Ecto.Changeset
  import Gamend.Limits, only: [validate_metadata_size: 2]

  require Gamend.Quests.QuestCodeStatus, as: QuestCodeStatus

  @type t :: %__MODULE__{}

  # A Postgres btree entry tops out near 2,700 bytes, and 512 four-byte
  # characters fit under that. `max_quest_code_token` cannot go past it.
  @token_ceiling 512

  # Spaces, dashes of every kind, and the control and zero-width characters a
  # paste brings along. NUL is one of those, and Postgres refuses it in text.
  @ignored ~r/[\s\p{Pd}\p{Cc}\p{Cf}]/u
  @invisible ~r/[\p{Cc}\p{Cf}]/u

  # What the `integer` column holds on Postgres.
  @max_uses_ceiling 2_147_483_647

  schema "quest_codes" do
    belongs_to :quest, Gamend.Quests.Quest,
      foreign_key: :quest_key,
      references: :key,
      type: :string

    field :token, :string
    field :lookup, :string
    field :max_uses, :integer
    field :uses, :integer, default: 0
    field :status, :string, default: QuestCodeStatus.active()
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  The form of a code redeems compare: full-width forms folded, spaces, dashes
  and case gone, so `ＡＢＣ－１２３`, `abc 123` and `ABC-123` are one code.
  In Elixir, so both adapters compare the same bytes with no collation.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(raw) when is_binary(raw) do
    raw
    |> String.normalize(:nfkc)
    |> String.replace(@ignored, "")
    |> String.downcase()
  end

  @doc """
  The lookups a typed code may stand for: its `normalize/1`, then the same
  with the letters people type for Crockford's look-alike digits folded in
  (`o` → `0`, `i` and `l` → `1`). A generated token has none of those
  letters, so `ABCD-0O1L` typed from a printed card still finds `ABCD-0011`;
  a token an admin chose keeps its own letters, and its exact form comes first.
  """
  @spec lookups(String.t()) :: [String.t()]
  def lookups(raw) when is_binary(raw) do
    lookup = normalize(raw)
    Enum.uniq([lookup, String.replace(lookup, ["o", "i", "l"], &fold/1)])
  end

  defp fold("o"), do: "0"
  defp fold(_i_or_l), do: "1"

  @doc "The longest a token may be, in characters of its normalized form."
  @spec max_token() :: pos_integer()
  def max_token, do: min(Gamend.Limits.get(:max_quest_code_token), @token_ceiling)

  @doc """
  Whether `raw` is short enough to normalize at all. NFKC can lengthen a
  string, so the real cap applies after it; this one refuses a megabyte before
  any work is done on it.
  """
  @spec plausible?(String.t()) :: boolean()
  def plausible?(raw) when is_binary(raw), do: byte_size(raw) <= 4 * max_token()

  @doc false
  def changeset(code, attrs) do
    code
    |> cast(attrs, [:token, :max_uses, :metadata])
    |> update_change(:token, &clean_token/1)
    |> validate_required([:token, :metadata])
    |> validate_number(:max_uses, greater_than: 0, less_than_or_equal_to: @max_uses_ceiling)
    |> validate_metadata_size(:metadata)
    |> put_lookup()
    |> foreign_key_constraint(:quest_key)
    |> unique_constraint(:token, name: :quest_codes_lookup_index)
  end

  defp clean_token(token), do: token |> String.replace(@invisible, "") |> String.trim()

  defp put_lookup(changeset) do
    case get_change(changeset, :token) do
      nil -> changeset
      token -> put_lookup(changeset, token)
    end
  end

  defp put_lookup(changeset, token) do
    max = max_token()

    if plausible?(token) do
      lookup = normalize(token)

      cond do
        lookup == "" ->
          add_error(changeset, :token, "has nothing but spaces and dashes")

        String.length(lookup) > max ->
          add_error(changeset, :token, "should be at most #{max} character(s)")

        true ->
          put_change(changeset, :lookup, lookup)
      end
    else
      add_error(changeset, :token, "should be at most #{max} character(s)")
    end
  end
end
