defmodule Gamend.Accounts.UsernameGenerator do
  @moduledoc """
  Generates default usernames for new users.

  OAuth signups get a slug of the provider display name ("Dragoș" →
  `dragos-4821`); email and device signups get a random word from the
  embedded list below (`sheep-4821`) — never anything derived from the
  email address, which would let strangers guess it. The numeric suffix is
  random, not a sequential discriminator, so there is no counter to
  exhaust; callers retry with a higher `attempt` on collision, which widens
  the suffix.
  """

  alias Gamend.Accounts.Username

  # Curated list for generated handles: lowercase a-z only, short, neutral.
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

  @suffix_digits 4
  @wide_suffix_digits 6

  @doc """
  Generate a username candidate from registration attrs (string keys).

  Uses `attrs["display_name"]` when it slugs to something usable, a random
  word otherwise. Attempts beyond 3 widen the numeric suffix.

  Draws from a random state of its own, never the calling process's `:rand`
  state: a caller that seeded `:rand` for a repeatable draw and left it
  seeded made every account it created try the same names, and once those
  were taken registration gave up.
  """
  @spec generate(map(), pos_integer()) :: String.t()
  def generate(attrs \\ %{}, attempt \\ 1) do
    rand = :rand.seed_s(:exsss)

    {base, rand} =
      case slug(attrs["display_name"]) do
        nil -> random_word(rand)
        slug -> {slug, rand}
      end

    digits = if attempt > 3, do: @wide_suffix_digits, else: @suffix_digits
    max_base = Gamend.Limits.get(:max_username) - digits - 1

    base
    |> String.slice(0, max_base)
    |> String.replace(~r/[._-]+$/, "")
    |> Kernel.<>("-" <> suffix(digits, rand))
  end

  @doc """
  Best-effort slug of a display name in username format; `nil` when too
  little survives. A name that transliterates to ASCII keeps doing so
  (`Drágoș` -> `dragos`, easier to type); one that does not (`山田太郎`,
  `Дмитрий`) keeps its own script, as long as it is a valid handle.
  """
  @spec slug(term()) :: String.t() | nil
  def slug(name) when is_binary(name) do
    ascii =
      name
      |> String.normalize(:nfkd)
      |> String.replace(~r/[^\x00-\x7F]/, "")
      |> String.downcase()
      |> tidy(~r/[^a-z0-9._-]+/)

    unicode =
      name
      |> Username.normalize()
      |> tidy(~r/[^\p{L}\p{M}\p{Nd}._-]+/u)

    # No max-length check: `generate/2` slices the base to fit its suffix.
    min = Gamend.Limits.get(:min_username)

    cond do
      String.length(ascii) >= min and Username.validate(ascii) == :ok ->
        ascii

      String.length(unicode) >= min and Username.validate(unicode) == :ok ->
        unicode

      true ->
        nil
    end
  end

  def slug(_), do: nil

  defp tidy(slug, disallowed) do
    slug
    |> String.replace(disallowed, "-")
    |> String.replace(~r/[._-]{2,}/, "-")
    |> String.replace(~r/^[._-]+|[._-]+$/, "")
  end

  defp random_word(rand) do
    {index, rand} = :rand.uniform_s(length(@words), rand)
    {Enum.at(@words, index - 1), rand}
  end

  defp suffix(digits, rand) do
    limit = Integer.pow(10, digits)
    {n, _rand} = :rand.uniform_s(limit, rand)

    (n - 1)
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end
end
