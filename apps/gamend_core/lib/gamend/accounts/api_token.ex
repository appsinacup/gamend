defmodule Gamend.Accounts.ApiToken do
  @moduledoc """
  A personal API token's row. The token itself is never stored.

  Fields:

  - `name` – what the owner called it, so they can tell two apart
  - `token_hash` – SHA-256 of the full token; the lookup key
  - `hint` – the first characters after the prefix, shown in lists so a token
    in a CI secret can be matched to its row without revealing it
  - `token_version` – the owner's `users.token_version` at creation; a later
    password or email change leaves this behind and the token stops working
  - `expires_at` – nil for a token that does not expire. `auth.api_token_max_days`
    can end a token sooner; `Gamend.Accounts.ApiTokens.expires_at/1` has the
    effective date
  - `last_used_at` – bumped at most once a minute
  """
  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User

  # Days a new token may be given when no cap is set, nil being "does not
  # expire". A cap keeps the ones below it and adds itself.
  @standard_choices [30, 90, 365, nil]

  schema "api_tokens" do
    belongs_to :user, User

    field :name, :string
    field :token_hash, :binary, redact: true
    field :hint, :string
    field :token_version, :integer, default: 0
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime

    field :expires_in_days, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @typedoc "A personal API token's row."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          user_id: String.t() | nil,
          name: String.t() | nil,
          token_hash: binary() | nil,
          hint: String.t() | nil,
          token_version: integer(),
          expires_at: DateTime.t() | nil,
          last_used_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  The lifetimes a token may be created with, in days; nil never expires. With
  `auth.api_token_max_days` set, the choices stop at the cap (which is itself
  one) and nil is gone.
  """
  @spec expiry_choices() :: [pos_integer() | nil]
  def expiry_choices do
    case max_days() do
      nil -> @standard_choices
      max -> Enum.sort([max | Enum.filter(@standard_choices, &(is_integer(&1) and &1 < max))])
    end
  end

  @doc "`auth.api_token_max_days`, or nil when a token may live forever."
  @spec max_days() :: pos_integer() | nil
  def max_days do
    case Gamend.Settings.get(Gamend.Accounts, :api_token_max_days) do
      days when is_integer(days) and days > 0 -> days
      _uncapped -> nil
    end
  end

  @doc """
  A new token's name and lifetime. `user_id`, `token_hash`, `hint` and
  `token_version` are set by `Gamend.Accounts.ApiTokens.create/2`, never cast.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :expires_in_days])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> validate_expiry()
    |> put_expiry()
  end

  # `validate_inclusion/3` skips a nil value, and nil ("never") is exactly what a
  # cap forbids, so that case is checked by hand.
  defp validate_expiry(changeset) do
    choices = expiry_choices()
    changeset = validate_inclusion(changeset, :expires_in_days, choices)

    if is_nil(get_field(changeset, :expires_in_days)) and nil not in choices do
      add_error(changeset, :expires_in_days, "can't be blank", validation: :required)
    else
      changeset
    end
  end

  defp put_expiry(changeset) do
    case get_field(changeset, :expires_in_days) do
      days when is_integer(days) ->
        at = DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.truncate(:second)
        put_change(changeset, :expires_at, at)

      _never ->
        changeset
    end
  end
end
