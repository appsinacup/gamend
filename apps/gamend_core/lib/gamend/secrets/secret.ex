defmodule Gamend.Secrets.Secret do
  @moduledoc """
  One encrypted value, and the metadata a person needs to manage something
  they can never read back.

  The struct is safe to hand to a template: it holds ciphertext, not a secret.
  `Gamend.Secrets.fetch/3` is the only thing that opens one.
  """

  use Gamend.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "secrets" do
    field :scope, :string
    field :scope_id, :string
    field :name, :string

    field :ciphertext, :binary
    field :iv, :binary
    field :tag, :binary
    field :key_id, :string

    field :kind, :string
    field :byte_size, :integer
    field :expires_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec
    field :created_by_id, Ecto.UUID

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(secret, attrs) do
    secret
    |> cast(attrs, [
      :scope,
      :scope_id,
      :name,
      :ciphertext,
      :iv,
      :tag,
      :key_id,
      :kind,
      :byte_size,
      :expires_at,
      :created_by_id
    ])
    |> validate_required([:scope, :scope_id, :name, :ciphertext, :iv, :tag, :key_id])
    |> validate_length(:scope, max: 60)
    |> validate_length(:scope_id, max: 60)
    |> validate_length(:name, max: 60)
    # `scope/scope_id/name` is what gets authenticated: a `/` in either of the
    # first two would let two different owners spell the same bytes.
    |> validate_format(:scope, ~r/\A[^\/]+\z/, message: "must not contain /")
    |> validate_format(:scope_id, ~r/\A[^\/]+\z/, message: "must not contain /")
    # The name is half the additional authenticated data, so it has to be the
    # same bytes going in as coming out. A name that needs a newline is not a
    # name, and one that differs only by trailing whitespace is a support call.
    |> validate_format(:name, ~r/\A[a-z0-9_]+\z/,
      message: "must be lowercase letters, digits and underscores"
    )
    |> unique_constraint([:scope, :scope_id, :name], name: :secrets_scope_scope_id_name_index)
  end

  @doc """
  Whether this secret has passed the expiry it was given.

  Nothing enforces it — a certificate that expired yesterday still decrypts,
  and the signer will fail with whatever the platform's tooling says. This is
  for telling somebody *before* that happens.
  """
  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(secret, now \\ DateTime.utc_now())
  def expired?(%__MODULE__{expires_at: nil}, _now), do: false

  def expired?(%__MODULE__{expires_at: expires_at}, now),
    do: DateTime.compare(expires_at, now) != :gt
end
