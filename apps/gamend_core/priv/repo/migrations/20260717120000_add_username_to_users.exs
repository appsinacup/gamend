defmodule Gamend.Repo.Migrations.AddUsernameToUsers do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:users) do
      add :username, :string
    end

    create unique_index(:users, [:username])

    flush()
    backfill_usernames()

    # SQLite can't ALTER COLUMN; there the NOT NULL guarantee stays
    # app-level (username_changeset validate_required).
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      execute "ALTER TABLE users ALTER COLUMN username SET NOT NULL"
    end
  end

  def down do
    alter table(:users) do
      remove :username
    end
  end

  defp backfill_usernames do
    rows =
      repo().all(
        from(u in "users", where: is_nil(u.username), select: {u.id, u.display_name}),
        log: false
      )

    Enum.each(rows, fn {id, display_name} ->
      username = free_username(%{"display_name" => display_name})

      {1, _} =
        repo().update_all(from(u in "users", where: u.id == ^id), set: [username: username])
    end)
  end

  # The migration is the only writer, so a check-then-set is race-free here.
  defp free_username(attrs, attempt \\ 1) do
    candidate = generate(attrs, attempt)

    if repo().exists?(from(u in "users", where: u.username == ^candidate)) do
      free_username(attrs, attempt + 1)
    else
      candidate
    end
  end

  # ── Frozen ────────────────────────────────────────────────────────────────
  #
  # `Gamend.Accounts.UsernameGenerator.generate/2` and the rules it checks
  # (`Gamend.Accounts.Username`) as they were on 2026-11-13, copied so a later
  # change to them cannot change what this migration writes. Two things are
  # fixed at what they were then by default: the length limits
  # (`min_username` 3, `max_username` 32) and the rules, core's own
  # (`default_rules/1`): a migration runs no game hook.

  @min_username 3
  @max_username 32

  @words ~w(
    acorn alder alpaca amber antler apricot aspen aster auburn aurora
    badger bamboo barley basil bass beacon beaver beech birch bison
    bluebell boulder bramble breeze brook bumble burrow cactus canyon caper
    cardinal cascade cedar cherry chestnut chipmunk cider cinder citrus clover
    cobalt comet compass condor copper coral cosmos cougar cricket crystal
    cypress dahlia dapple deer delta dew dingo dolphin drake drift
    dune eagle ebony echo eland elk elm ember ermine falcon
    fawn fennel fern finch fjord flint fog forest fox foxglove
    gale garnet gecko geyser ginger glacier glade goose granite grove
    gull harbor hare hawk hazel heather hedgehog heron hickory holly
    ibis iris ivory jackal jade jasper juniper kestrel kiwi koala
    lagoon lark laurel lemur lichen lilac linden lotus lynx magpie
    mallow maple marigold marlin marmot meadow mesa mink minnow mistral
    moss moth myrtle nectar newt nimbus nutmeg oak ocelot olive
    onyx opal orchid oriole osprey otter owl panda pebble pecan
    pelican peony pepper petrel pine pistachio plover plum pond poppy
    prairie puffin quail quartz quince raccoon raven reed ridge river
    robin rowan saffron sage salmon sandpiper sapling seal sedge sequoia
    shale sheep shore sierra sparrow spruce squirrel starling stoat stone
    stork summit sunflower swallow swift sycamore tapir teal tern thicket
    thistle thrush tide topaz toucan trout tulip tundra turtle vale
    verbena violet vole walnut warbler willow winter wolf wren zephyr
  )

  @max_marks 3
  @format ~r/^[\p{L}\p{Nd}]\p{M}{0,#{@max_marks}}(?:[._-]?[\p{L}\p{Nd}]\p{M}{0,#{@max_marks}})*$/u
  @invisible ~r/\p{C}/u
  @mark_run ~r/([\p{Mn}\p{Me}])\1|[\p{Mn}\p{Me}]{5,}/u

  @scripts ~w(Latin Greek Cyrillic Armenian Hebrew Arabic Syriac Thaana Devanagari
              Bengali Gurmukhi Gujarati Oriya Tamil Telugu Kannada Malayalam Sinhala
              Thai Lao Tibetan Myanmar Georgian Hangul Ethiopic Khmer Mongolian
              Hiragana Katakana Bopomofo Han)

  @mixes [
    ~w(Latin Han Hiragana Katakana),
    ~w(Latin Han Bopomofo),
    ~w(Latin Han Hangul)
  ]

  defp generate(attrs, attempt) do
    rand = :rand.seed_s(:exsss)

    {base, rand} =
      case slug(attrs["display_name"]) do
        nil -> random_word(rand)
        slug -> {slug, rand}
      end

    digits = if attempt > 3, do: 6, else: 4

    base
    |> String.slice(0, @max_username - digits - 1)
    |> String.replace(~r/[._-]+$/, "")
    |> Kernel.<>("-" <> suffix(digits, rand))
  end

  defp slug(name) when is_binary(name) do
    ascii =
      name
      |> String.normalize(:nfkd)
      |> String.replace(~r/[^\x00-\x7F]/, "")
      |> String.downcase()
      |> tidy(~r/[^a-z0-9._-]+/)

    unicode =
      name
      |> String.normalize(:nfkc)
      |> String.downcase()
      |> String.normalize(:nfc)
      |> tidy(~r/[^\p{L}\p{M}\p{Nd}._-]+/u)

    cond do
      String.length(ascii) >= @min_username and valid?(ascii) -> ascii
      String.length(unicode) >= @min_username and valid?(unicode) -> unicode
      true -> nil
    end
  end

  defp slug(_name), do: nil

  defp tidy(slug, disallowed) do
    slug
    |> String.replace(disallowed, "-")
    |> String.replace(~r/[._-]{2,}/, "-")
    |> String.replace(~r/^[._-]+|[._-]+$/, "")
  end

  defp valid?(username) do
    not String.match?(username, @invisible) and String.match?(username, @format) and
      allowed_mix?(username) and not Regex.match?(@mark_run, String.normalize(username, :nfd))
  end

  defp allowed_mix?(username) do
    scripts =
      for <<cp::utf8 <- username>>,
          char = <<cp::utf8>>,
          String.match?(char, ~r/^\p{L}$/u),
          uniq: true,
          do: script(char)

    length(scripts) <= 1 or Enum.any?(@mixes, fn mix -> Enum.all?(scripts, &(&1 in mix)) end)
  end

  defp script(char) do
    Enum.find(@scripts, :other, &String.match?(char, Regex.compile!("^\\p{#{&1}}$", "u")))
  end

  defp random_word(rand) do
    {index, rand} = :rand.uniform_s(length(@words), rand)
    {Enum.at(@words, index - 1), rand}
  end

  defp suffix(digits, rand) do
    {n, _rand} = :rand.uniform_s(Integer.pow(10, digits), rand)

    (n - 1)
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end
end
