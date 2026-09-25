defmodule Gamend.Accounts.LoginLockout do
  @moduledoc """
  Failed password sign-ins for one email address, and the lock they set.

  Fields:

  - `key_hash` – SHA-256 of the normalized address; the lookup key. The address
    itself is never stored
  - `failures` – failed attempts in the current window
  - `window_started_at` – when the current window's first failure happened
  - `locked_until` – nil, or when the lock the failures set runs out

  See `Gamend.Accounts.LoginLockouts`.
  """
  use Gamend.Schema

  schema "login_lockouts" do
    field :key_hash, :binary, redact: true
    field :failures, :integer, default: 0
    field :window_started_at, :utc_datetime
    field :locked_until, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @typedoc "A row of failed sign-ins for one address."
  @type t :: %__MODULE__{
          id: String.t() | nil,
          key_hash: binary() | nil,
          failures: non_neg_integer(),
          window_started_at: DateTime.t() | nil,
          locked_until: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
