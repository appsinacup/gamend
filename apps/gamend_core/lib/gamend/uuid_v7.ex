defmodule Gamend.UUIDv7 do
  @moduledoc """
  The id of every row: a UUIDv7 (RFC 9562), made by `Ecto.UUID`.

  A UUIDv7 holds a 48-bit unix-millisecond timestamp in its most significant
  bits, so freshly inserted rows sort (and index) in insertion order like the
  old integer ids did, while remaining unguessable — random ids prevent
  enumeration of API resources.

  `Gamend.Schema` makes a schema's id with `generate/0`, and a field holding
  an id is an `Ecto.UUID`. `Repo.insert_all/3` runs no autogenerate for such a
  key, so a row written that way sets `id: Gamend.UUIDv7.generate()` itself.
  """

  @doc """
  Generates an id. `:monotonic` keeps the time below a millisecond in the 12
  `rand_a` bits (RFC 9562 §6.2 method 3), so ids made on one node sort in the
  order they were made: code that orders by id (chat cursors, pagination,
  `Gamend.Results`) keeps working under bursts.

  Raises while the `:ecto` application is not started.
  """
  @spec generate() :: Ecto.UUID.t()
  def generate, do: Ecto.UUID.generate(version: 7, precision: :monotonic)

  @doc """
  Casts a value to a UUID string, returning `nil` when invalid.

  Convenience for boundary code (channel topics, URL params) that previously
  used `Integer.parse/1` to validate ids.
  """
  @spec cast_or_nil(term()) :: Ecto.UUID.t() | nil
  def cast_or_nil(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end
end
