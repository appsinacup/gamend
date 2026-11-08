defmodule Gamend.Chat.FilterWord do
  @moduledoc """
  Ecto schema for the `chat_filter_words` table — one entry of the chat word
  blocklist.

  ## Fields

    * `word` — the normalized form (see `Gamend.Chat.Moderation.Normalizer`)
    * `severity` — `"block"` rejects the message, `"mask"` replaces the hit with
      `***`, `"flag"` stores it verbatim and files a report
    * `match_mode` — `"substring"` matches anywhere, `"exact"` only a whole word
    * `lang` — provenance of a bundled-list import (`"en"`, `"de"`, …), `nil`
      for a hand-added word. Matching is language-agnostic; this only records
      where the row came from so a list can be removed in bulk.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Chat.Moderation.Normalizer

  require Gamend.Chat.FilterSeverity, as: FilterSeverity
  require Gamend.Chat.MatchMode, as: MatchMode

  @type t :: %__MODULE__{}

  @severities ~w(block mask flag)
  @match_modes ~w(substring exact)

  schema "chat_filter_words" do
    field :word, :string
    field :severity, :string, default: FilterSeverity.block()
    field :match_mode, :string, default: MatchMode.substring()
    field :lang, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The severities a filter word may have."
  @spec severities() :: [String.t()]
  def severities, do: @severities

  @doc "The match modes a filter word may have."
  @spec match_modes() :: [String.t()]
  def match_modes, do: @match_modes

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(word, attrs) do
    word
    |> cast(attrs, [:word, :severity, :match_mode, :lang])
    |> update_change(:word, &Normalizer.normalize/1)
    |> validate_required([:word, :severity, :match_mode])
    |> validate_length(:word, min: 1, max: Gamend.Limits.get(:max_chat_filter_word_len))
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:match_mode, @match_modes)
    |> validate_length(:lang, max: 16)
    |> unique_constraint(:word)
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# Gamend.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: Gamend.Chat.FilterWord do
  def encode(word, opts) do
    Gamend.SchemaJSON.encode(
      word,
      [:id, :word, :severity, :match_mode, :lang, :inserted_at, :updated_at],
      opts
    )
  end
end
