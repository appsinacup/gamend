defmodule GamendWeb.SpellingTest do
  @moduledoc """
  Core's English is American (2026-10-10): `canceled`, `color`, `organize`,
  `license`. Hosts render core's pages beside their own, and the Polyglot
  Pirates host holds its own msgids to the same list
  (`test/gamend_host/spelling_test.exs` there), so a British spelling here
  shows up as the odd one out on the same site.

  Checked: every msgid core's catalogues hold (`priv/gettext/*.pot`).
  """
  use ExUnit.Case, async: true

  @gettext Path.expand("../../priv/gettext", __DIR__)

  alias GamendWeb.CatalogChecks

  test "msgids use American spelling" do
    found = CatalogChecks.british_spellings([@gettext])

    assert found == [], "British spelling in a msgid:\n  " <> Enum.join(found, "\n  ")
  end

  test "the list finds what it is written for, and spares American words" do
    assert CatalogChecks.british_words("x", "Practise your colours, organised by kilometre.") !=
             []

    assert CatalogChecks.british_words(
             "x",
             "Exercise, advise, surprise, practice, analysis, realistic, `analyse`"
           ) == []
  end
end
