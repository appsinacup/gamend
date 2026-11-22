defmodule Gamend.Leaderboards.Leaderboard do
  @moduledoc """
  Ecto schema for the `leaderboards` table.

  A leaderboard is a self-contained scoreboard that can be permanent or time-limited.
  Each leaderboard has its own settings for sort order and score operator.

  ## Slug
  The `slug` is a human-readable identifier (e.g., "weekly_kills") that can be reused
  across multiple leaderboard instances (seasons). Use the slug to always target the
  currently active leaderboard, or use the integer `id` for a specific instance.

  ## Hidden
  A hidden board is ranked and read like any other — by id, by slug, its
  records — but no public listing shows it (the leaderboards page, the API
  index). A host that shows a board on its own pages hides it.

  ## Icon
  `icon_url` is optional; when nil, clients show their default leaderboard
  icon (the web UI uses `GamendWeb.Icons.default(:leaderboard)`).

  ## User metadata keys
  `user_metadata_keys` names what of each player's `users.metadata` the
  board's rows carry, read when the row is (`user_metadata/2`): a top-level
  key (`"rank"`) or a dotted path into it (`"player.pass_level"`), so one
  value goes out and the rest of its map stays private. The rows are
  public, so a key named here is world-readable. Empty, the default, sends
  none; `payments` is never sent.

  ## Sort Order
  - `:desc` — Higher scores rank first (default)
  - `:asc` — Lower scores rank first (e.g., fastest time)

  ## Operators
  - `:set` — Always replace with new score
  - `:best` — Only update if new score is better (default)
  - `:incr` — Add to existing score
  - `:decr` — Subtract from existing score
  """
  use Gamend.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type sort_order :: :desc | :asc
  @type operator :: :set | :best | :incr | :decr

  @sort_orders ~w(desc asc)a
  @operators ~w(set best incr decr)a

  schema "leaderboards" do
    field :slug, :string
    field :title, :string
    field :description, :string, default: ""
    field :icon_url, :string
    field :sort_order, Ecto.Enum, values: @sort_orders, default: :desc
    field :operator, Ecto.Enum, values: @operators, default: :best
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :metadata, :map, default: %{}
    field :hidden, :boolean, default: false
    field :user_metadata_keys, {:array, :string}, default: []

    has_many :records, Gamend.Leaderboards.Record

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(slug title)a
  @optional_fields ~w(description icon_url sort_order operator starts_at ends_at metadata hidden user_metadata_keys)a

  @doc """
  Changeset for creating a new leaderboard.
  """
  def changeset(leaderboard, attrs) do
    leaderboard
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> Gamend.Slug.validate_loose(:slug)
    |> validate_required(@required_fields)
    |> validate_length(:slug, min: 1, max: Gamend.Limits.get(:max_leaderboard_slug))
    |> validate_length(:icon_url, max: Gamend.Limits.get(:max_profile_url))
    |> validate_length(:title, min: 1, max: Gamend.Limits.get(:max_leaderboard_title))
    |> validate_inclusion(:sort_order, @sort_orders)
    |> validate_inclusion(:operator, @operators)
    |> validate_length(:description, max: Gamend.Limits.get(:max_leaderboard_description))
    |> Gamend.Limits.validate_metadata_size(:metadata)
    |> validate_user_metadata_keys()
  end

  @doc """
  Changeset for updating an existing leaderboard.
  Does not allow changing slug, sort_order, or operator after creation.
  """
  def update_changeset(leaderboard, attrs) do
    leaderboard
    |> cast(attrs, [
      :title,
      :description,
      :icon_url,
      :starts_at,
      :ends_at,
      :metadata,
      :hidden,
      :user_metadata_keys
    ])
    |> validate_length(:icon_url, max: Gamend.Limits.get(:max_profile_url))
    |> validate_length(:title, min: 1, max: Gamend.Limits.get(:max_leaderboard_title))
    |> validate_length(:description, max: Gamend.Limits.get(:max_leaderboard_description))
    |> Gamend.Limits.validate_metadata_size(:metadata)
    |> validate_user_metadata_keys()
  end

  # Each a key or a dotted path of non-empty keys, none twice, none into
  # `payments` (never sent: `User.shared_metadata/1`).
  defp validate_user_metadata_keys(changeset) do
    changeset
    |> update_change(:user_metadata_keys, fn keys ->
      keys |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
    end)
    |> validate_length(:user_metadata_keys,
      max: Gamend.Limits.get(:max_leaderboard_user_metadata_keys)
    )
    |> validate_change(:user_metadata_keys, fn :user_metadata_keys, keys ->
      if Enum.all?(keys, &metadata_path?/1),
        do: [],
        else: [user_metadata_keys: "must be keys or dotted paths, outside payments"]
    end)
  end

  defp metadata_path?(path) do
    segments = String.split(path, ".")

    byte_size(path) <= 255 and Enum.all?(segments, &(&1 != "")) and
      hd(segments) != "payments"
  end

  @doc """
  What of `user`'s metadata the board's rows carry: the values at its
  `user_metadata_keys`, each in its place (`"player.pass_level"` answers
  `%{"player" => %{"pass_level" => 7}}`). A path the user has no value at
  is left out. `%{}` for a board that names none, or no user.
  """
  @spec user_metadata(t(), term()) :: map()
  def user_metadata(%__MODULE__{user_metadata_keys: [_ | _] = keys}, %{metadata: %{} = metadata}) do
    metadata = Map.delete(metadata, "payments")

    Enum.reduce(keys, %{}, fn path, acc ->
      segments = String.split(path, ".")

      case fetch_path(metadata, segments) do
        {:ok, value} -> put_path(acc, segments, value)
        :error -> acc
      end
    end)
  end

  def user_metadata(_leaderboard, _user), do: %{}

  defp fetch_path(value, []), do: {:ok, value}
  defp fetch_path(%{} = map, [key | rest]), do: map |> Map.fetch(key) |> fetch_rest(rest)
  defp fetch_path(_value, _segments), do: :error

  defp fetch_rest({:ok, value}, rest), do: fetch_path(value, rest)
  defp fetch_rest(:error, _rest), do: :error

  defp put_path(acc, [key], value), do: Map.put(acc, key, value)

  defp put_path(acc, [key | rest], value) do
    inner =
      case Map.get(acc, key) do
        %{} = map -> map
        _ -> %{}
      end

    Map.put(acc, key, put_path(inner, rest, value))
  end

  @doc """
  Returns true if the leaderboard is currently active (not ended).
  """
  def active?(%__MODULE__{ends_at: nil}), do: true

  def active?(%__MODULE__{ends_at: ends_at}),
    do: DateTime.compare(ends_at, DateTime.utc_now()) == :gt

  @doc """
  Returns true if the leaderboard has ended.
  """
  def ended?(%__MODULE__{} = lb), do: not active?(lb)
end

# Hand-written rather than @derive so optional strings encode as "" instead of
# null — game clients (Godot) choke on null where they expect a string.
defimpl Jason.Encoder, for: Gamend.Leaderboards.Leaderboard do
  def encode(lb, opts) do
    Gamend.SchemaJSON.encode(
      lb,
      [
        :id,
        :slug,
        :title,
        :description,
        :icon_url,
        :sort_order,
        :operator,
        :starts_at,
        :ends_at,
        :metadata,
        :hidden,
        :user_metadata_keys,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
