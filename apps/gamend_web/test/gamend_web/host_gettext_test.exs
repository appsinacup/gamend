defmodule GamendWeb.HostGettextTest do
  # A host's backend (`GamendWeb.HostGettext`): its own catalogue first, then
  # core's, in the same locale, so setting `host_gettext_backend` never puts
  # core's own pages back into English.
  use ExUnit.Case, async: true

  alias GamendWeb.HostGettextFixture, as: Host

  defp in_german(fun), do: Gettext.with_locale(Host, "de", fun)

  test "a host's own string comes from its catalogue" do
    assert in_german(fn -> Gettext.gettext(Host, "Only the host says this") end) ==
             "Nur der Host sagt das"
  end

  test "a string the host does not hold is core's" do
    assert in_german(fn -> Gettext.gettext(Host, "Save") end) == "Speichern"
  end

  test "the host's entry wins over core's" do
    assert in_german(fn -> Gettext.gettext(Host, "Cancel") end) == "Lieber nicht"
  end

  test "a string neither holds is the msgid, interpolated" do
    assert in_german(fn -> Gettext.gettext(Host, "Hello %{name}", name: "Ana") end) ==
             "Hello Ana"
  end
end
