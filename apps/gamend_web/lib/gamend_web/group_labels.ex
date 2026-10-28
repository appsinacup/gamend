defmodule GamendWeb.GroupLabels do
  @moduledoc """
  The words the website uses for a group's type: its name (Public, Private,
  Hidden), the options of a type select, limited to the types the host
  allows (`Gamend.Groups.types/0`), and what each one means. Each word is a
  literal message, so all are extracted and translated.
  """

  use Gettext, backend: GamendWeb.Gettext

  @doc "A type's word: Public, Private or Hidden."
  @spec type(String.t()) :: String.t()
  def type("public"), do: gettext("Public")
  def type("private"), do: gettext("Private")
  def type("hidden"), do: gettext("Hidden")
  def type(type), do: type

  @doc """
  A type select's options: the types the host allows (`Gamend.Groups.types/0`),
  and a group's own when it is not one of them any more (saving it unchanged
  keeps it).
  """
  @spec type_options([String.t()], String.t() | nil) :: [{String.t(), String.t()}]
  def type_options(types, current \\ nil) do
    for type <- Enum.uniq(types ++ List.wrap(current)), do: {type(type), type}
  end

  @doc "What each of these types means, a sentence each, for under a type select."
  @spec types_hint([String.t()]) :: String.t()
  def types_hint(types), do: Enum.map_join(types, " ", &type_hint/1)

  defp type_hint("public"), do: gettext("Public: listed, and anyone joins.")
  defp type_hint("private"), do: gettext("Private: listed, and people ask to join.")
  defp type_hint("hidden"), do: gettext("Hidden: only the people invited see it.")
  defp type_hint(_type), do: ""
end
