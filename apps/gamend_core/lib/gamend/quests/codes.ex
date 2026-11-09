defmodule Gamend.Quests.Codes do
  @moduledoc """
  Redemption codes: making them, finding them, stopping them.

  A code is a way to finish a `code_only` quest; the quest holds everything
  about what the code gives. Redeeming one is `Gamend.Quests.redeem_code/2`,
  which uses the engine's private steps. Public API is re-exported by
  `Gamend.Quests`.
  """

  import Ecto.Query, warn: false

  alias Gamend.Accounts.User
  alias Gamend.Quests.Quest
  alias Gamend.Quests.QuestCode
  alias Gamend.Quests.QuestProgress
  alias Gamend.Repo

  require Gamend.Quests.QuestCodeStatus, as: QuestCodeStatus

  # Each chunk is its own statement, so SQLite's write lock is released
  # between them and a big run does not stall every other write.
  @chunk 500

  # Crockford base32: no I, L, O or U, the letters people misread.
  @alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  # 16 symbols of 5 bits: guessing one is not realistic.
  @token_bytes 10

  @doc "A code by id, or nil."
  @spec get(Ecto.UUID.t()) :: QuestCode.t() | nil
  def get(id), do: Repo.get_uuid(QuestCode, id)

  @doc """
  The code what a player typed stands for, its quest preloaded, or nil.
  Says nothing about whether it still works.
  """
  @spec find(String.t()) :: QuestCode.t() | nil
  def find(raw) when is_binary(raw) do
    with true <- QuestCode.plausible?(raw),
         lookup when lookup != "" <- QuestCode.normalize(raw) do
      from(c in QuestCode, where: c.lookup == ^lookup, preload: :quest) |> Repo.one()
    else
      _ -> nil
    end
  end

  @doc """
  Makes one code with a chosen token. A token another code already has, even
  on another quest, fails on `:token`.
  """
  @spec create(Quest.t(), map()) ::
          {:ok, QuestCode.t()} | {:error, :not_code_only | Ecto.Changeset.t()}
  def create(%Quest{code_only: true} = quest, attrs) do
    %QuestCode{quest_key: quest.key}
    |> QuestCode.changeset(Gamend.Parse.string_keys(attrs))
    |> Repo.insert()
  end

  def create(%Quest{}, _attrs), do: {:error, :not_code_only}

  @doc """
  Makes `count` random codes, shown as `XXXX-XXXX-XXXX-XXXX`, and answers how
  many it made. Capped at `max_codes_per_generate`, so a run finishes inside
  one request; to have more, run it again.

  ## Options
  - `:max_uses` — default `1`, `nil` for every player once
  - `:metadata` — copied onto each player's progress row
  """
  @spec generate(Quest.t(), integer(), keyword()) ::
          {:ok, non_neg_integer()}
          | {:error, :not_code_only | :invalid_count | :too_many_codes | Ecto.Changeset.t()}
  def generate(quest, count, opts \\ [])

  def generate(%Quest{code_only: true} = quest, count, opts) when is_integer(count) do
    # The options go through the same rules as a code made by hand.
    template =
      QuestCode.changeset(%QuestCode{quest_key: quest.key}, %{
        "token" => new_token(),
        "max_uses" => Keyword.get(opts, :max_uses, 1),
        "metadata" => Keyword.get(opts, :metadata, %{})
      })

    cond do
      count < 1 -> {:error, :invalid_count}
      count > Gamend.Limits.get(:max_codes_per_generate) -> {:error, :too_many_codes}
      not template.valid? -> {:error, template}
      true -> {:ok, insert_batches(Ecto.Changeset.apply_changes(template), count, 0)}
    end
  end

  def generate(%Quest{}, _count, _opts), do: {:error, :not_code_only}

  # A collision is dropped by `on_conflict` and topped up by the next batch.
  # A batch that inserted nothing stops the run instead of spinning.
  defp insert_batches(_template, 0, inserted), do: inserted

  defp insert_batches(template, left, inserted) do
    rows = for _ <- 1..min(left, @chunk), do: row(template)

    case Repo.insert_all(QuestCode, rows, on_conflict: :nothing, conflict_target: :lookup) do
      {0, _} -> inserted
      {count, _} -> insert_batches(template, left - count, inserted + count)
    end
  end

  # `insert_all` runs no autogenerate.
  defp row(%QuestCode{} = template) do
    now = DateTime.utc_now(:second)
    token = new_token()

    %{
      id: Gamend.UUIDv7.generate(),
      quest_key: template.quest_key,
      token: token,
      lookup: QuestCode.normalize(token),
      max_uses: template.max_uses,
      status: QuestCodeStatus.active(),
      metadata: template.metadata,
      inserted_at: now,
      updated_at: now
    }
  end

  defp new_token do
    for(<<value::5 <- :crypto.strong_rand_bytes(@token_bytes)>>, do: Enum.at(@alphabet, value))
    |> Enum.chunk_every(4)
    |> Enum.map_join("-", &List.to_string/1)
  end

  @doc """
  One quest's codes, newest first.

  ## Options
  - `:search` — the exact code, typed any way a player could type it
  - `:page` / `:page_size`
  """
  @spec list(String.t(), keyword()) :: [QuestCode.t()]
  def list(quest_key, opts \\ []) when is_binary(quest_key) do
    quest_key
    |> codes_query(opts)
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> Gamend.Query.page(opts)
    |> Repo.all()
  end

  @doc "How many codes match (same filters as `list/2`)."
  @spec count(String.t(), keyword()) :: non_neg_integer()
  def count(quest_key, opts \\ []) when is_binary(quest_key) do
    quest_key |> codes_query(opts) |> Repo.aggregate(:count, :id)
  end

  @doc "Every code of a quest, oldest first: what an export writes."
  @spec all(String.t()) :: [QuestCode.t()]
  def all(quest_key) when is_binary(quest_key) do
    from(c in QuestCode,
      where: c.quest_key == ^quest_key,
      order_by: [asc: c.inserted_at, asc: c.id]
    )
    |> Repo.all()
  end

  defp codes_query(quest_key, opts) do
    query = from(c in QuestCode, where: c.quest_key == ^quest_key)

    case Keyword.get(opts, :search) do
      term when is_binary(term) and term != "" ->
        where(query, [c], c.lookup == ^QuestCode.normalize(term))

      _ ->
        query
    end
  end

  @doc """
  The first few players who redeemed a code, with how many there are in the
  `uses` column for the rest. A public code can have millions.
  """
  @spec used_by(Ecto.UUID.t(), pos_integer()) :: [User.t()]
  def used_by(code_id, limit \\ 3) when is_binary(code_id) do
    from(p in QuestProgress,
      join: u in assoc(p, :user),
      where: p.code_id == ^code_id,
      order_by: [asc: p.completed_at, asc: p.id],
      limit: ^limit,
      select: u
    )
    |> Repo.all()
  end

  @doc """
  Revokes a code or restores it. Stopping every code of a quest at once is
  unticking the quest's `active`.
  """
  @spec set_status(Ecto.UUID.t(), String.t()) ::
          {:ok, QuestCode.t()} | {:error, :code_not_found | :invalid_state}
  def set_status(code_id, status)
      when is_binary(code_id) and status in [QuestCodeStatus.active(), QuestCodeStatus.revoked()] do
    with {:ok, id} <- Ecto.UUID.cast(code_id),
         {:ok, code} <-
           from(c in QuestCode, where: c.id == ^id)
           |> Repo.compare_and_set(set: [status: status, updated_at: DateTime.utc_now(:second)]) do
      {:ok, code}
    else
      _ -> {:error, :code_not_found}
    end
  end

  def set_status(_code_id, _status), do: {:error, :invalid_state}
end
