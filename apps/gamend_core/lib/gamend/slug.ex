defmodule Gamend.Slug do
  @moduledoc """
  A name that is also its URL, unique per account: a group's
  (`Gamend.Groups`, `<owner>/<slug>`), and in a host a project's or a store
  account's (Forge's `/projects/<owner>/<name>`).

  Lowercase letters and digits of any script (`crimson-order`, `红色军团`),
  joined by single `-` or `_`. A letter carries at most three combining marks,
  as a username's does, and is spelled as a username is
  (`Gamend.Accounts.Username.normalize/1`). Unique per account, by a unique
  index the changeset names.

  A leaderboard's and a tournament's slug is looser (`validate_loose/2`), since
  seasons and editions share one and `__` and a leading `_` were always allowed:
  the same letters, with `-` and `_` anywhere but a leading `-`.
  """

  import Ecto.Changeset

  # Every letter category but the two with a lowercase form to prefer.
  @char "[\\p{Ll}\\p{Lm}\\p{Lo}\\p{Nd}]\\p{M}{0,3}"
  @format Regex.compile!("\\A#{@char}(?:[-_]?#{@char})*\\z", "u")
  @loose_format Regex.compile!("\\A(?:#{@char}|_)(?:#{@char}|[-_])*\\z", "u")

  @message "lowercase letters and digits, joined by - or _"

  # `random/0`'s words.
  @adjectives ~w(
    brave bright calm clever cosmic crimson daring dusty eager electric fierce
    frosty gentle golden happy hidden icy jolly lucky lunar mighty misty nimble
    noble quick quiet rapid rusty silent silver sly snowy solar spicy stormy
    sunny swift tiny wild windy witty
  )
  @nouns ~w(
    badger bard comet dragon falcon fox gecko golem griffin hawk knight lion
    lynx mage moose otter owl panda phoenix pirate raven rogue shark sparrow
    sprite tiger titan toad troll viking walrus wizard wolf yeti
  )

  @doc "The format a slug has to have."
  @spec format() :: Regex.t()
  def format, do: @format

  @doc "The format `validate_loose/2` checks."
  @spec loose_format() :: Regex.t()
  def loose_format, do: @loose_format

  @doc """
  Two random words, `swift-otter`: a name to start from, for a form that
  offers one before anything is typed (a new group's, and in a host a new
  server's). Checked against nothing: about 1,500 of them.
  """
  @spec random() :: String.t()
  def random, do: "#{Enum.random(@adjectives)}-#{Enum.random(@nouns)}"

  @doc "The spelling a slug is stored and looked up under."
  @spec normalize(String.t()) :: String.t()
  defdelegate normalize(slug), to: Gamend.Accounts.Username

  @doc """
  The nearest slug to `text`: normalized, every run of anything else turned
  into one `-`, trimmed, at most 64 long, and `fallback` when nothing is
  left. `"My_Game.v2"` is `my_game-v2`, `"红色 军团"` is `红色-军团`.
  """
  @spec slugify(String.t() | nil, String.t()) :: String.t()
  def slugify(text, fallback)

  def slugify(text, fallback) when is_binary(text) do
    text
    |> normalize()
    |> String.replace(~r/[^\p{Ll}\p{Lm}\p{Lo}\p{Nd}\p{M}_-]+/u, "-")
    |> String.replace(~r/([-_])\p{M}+/u, "\\1")
    |> String.replace(~r/(\p{M}{3})\p{M}+/u, "\\1")
    |> String.replace(~r/[-_]{2,}/, "-")
    |> String.slice(0, 64)
    |> String.replace(~r/\A[-_\p{M}]+|[-_]+\z/u, "")
    |> case do
      "" -> fallback
      slug -> slug
    end
  end

  def slugify(_text, fallback), do: fallback

  @doc """
  `base`, or `base-2`, `base-3`… : the first one `taken?` says is free.
  """
  @spec free(String.t(), (String.t() -> boolean())) :: String.t()
  def free(base, taken?) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not taken?.(&1)))
  end

  @doc """
  Check `field` is a slug, at most `:max` long, and unique per account by
  the unique index `:index`.
  """
  @spec validate(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate(changeset, field, opts) do
    changeset
    |> validate_length(field, max: Keyword.fetch!(opts, :max))
    |> validate_format(field, @format, message: @message)
    |> unique_constraint(field, name: Keyword.fetch!(opts, :index), message: "is taken")
  end

  @doc "Normalize `field` and check it has `loose_format/0`."
  @spec validate_loose(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_loose(changeset, field) do
    changeset
    |> update_change(field, fn
      slug when is_binary(slug) -> normalize(slug)
      other -> other
    end)
    |> validate_format(field, @loose_format, message: @message)
  end
end
