defmodule Gamend.Slug do
  @moduledoc """
  A name that is also its URL, unique per account: a group's
  (`Gamend.Groups`, `<owner>/<slug>`), and in a host a project's or a store
  account's (Forge's `/projects/<owner>/<name>`).

  Lowercase letters and digits, joined by single `-` or `_`, as a GitHub
  repository name reads once it is lowercased. Unique per account, by a
  unique index the changeset names.
  """

  import Ecto.Changeset

  @format ~r/\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/

  @doc "The format a slug has to have."
  @spec format() :: Regex.t()
  def format, do: @format

  @doc """
  The nearest slug to `text`: lowercased, every run of anything else turned
  into one `-`, trimmed, at most 64 long, and `fallback` when nothing is
  left. `"My_Game.v2"` is `my_game-v2`.
  """
  @spec slugify(String.t() | nil, String.t()) :: String.t()
  def slugify(text, fallback)

  def slugify(text, fallback) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.replace(~r/[-_]{2,}/, "-")
    |> String.slice(0, 64)
    |> String.replace(~r/\A[-_]+|[-_]+\z/, "")
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
    |> validate_format(field, @format, message: "lowercase letters and digits, joined by - or _")
    |> unique_constraint(field, name: Keyword.fetch!(opts, :index), message: "is taken")
  end
end
