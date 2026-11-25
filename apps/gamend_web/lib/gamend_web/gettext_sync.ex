defmodule GamendWeb.GettextSync do
  @moduledoc false

  # A host serving fewer languages than the catalogue holds, e.g. `["en"]`:
  # with one, there is nothing to switch and no switcher is drawn.
  # Chosen at compile time, so the function holds no branch the build can
  # never take (dialyzer's pattern_match_cov on a `case` of the constant).
  @site_locales Application.compile_env(:gamend_web, :locales)

  @spec known_locales() :: [String.t()]
  if @site_locales do
    def known_locales,
      do: Enum.filter(Gettext.known_locales(GamendWeb.Gettext), &(&1 in @site_locales))
  else
    def known_locales, do: Gettext.known_locales(GamendWeb.Gettext)
  end

  @spec normalize_locale(term()) :: String.t() | nil
  def normalize_locale(locale) when is_binary(locale) do
    key =
      locale
      |> String.trim()
      |> String.replace("-", "_")
      |> String.downcase()

    Map.get(locale_index(), key)
  end

  def normalize_locale(_locale), do: nil

  @locale_index_key {__MODULE__, :locale_index}

  # Downcased locale -> the canonical spelling, built once.
  #
  # This is on the layout's hot path, not a cold one: every nav and footer
  # link calls `HostLayouts.strip_locale_prefix/2`, which lands here, so a
  # rendered page runs it ~100 times. A linear scan downcasing *every* known
  # locale on *every* call would be ~6,000 `String.downcase/1` calls per
  # request, the single largest cost in rendering a vocabulary page.
  #
  # An empty map is not cached: `known_locales/0` is empty until the backend is
  # loaded, and caching that would make every locale unrecognized for the life
  # of the node.
  defp locale_index do
    case :persistent_term.get(@locale_index_key, nil) do
      %{} = index ->
        index

      nil ->
        case known_locales() do
          [] ->
            %{}

          locales ->
            index = Map.new(locales, &{String.downcase(&1), &1})
            :persistent_term.put(@locale_index_key, index)
            index
        end
    end
  end

  @spec put_locale(String.t()) :: :ok
  def put_locale(locale) when is_binary(locale) do
    Enum.each(backends(), &Gettext.put_locale(&1, locale))
  end

  @spec current_locale() :: String.t() | nil
  def current_locale do
    Gettext.get_locale(host_backend())
  end

  @spec host_backend() :: module()
  def host_backend do
    backend = Application.get_env(:gamend_web, :host_gettext_backend, GamendWeb.Gettext)

    if Code.ensure_loaded?(backend) do
      backend
    else
      GamendWeb.Gettext
    end
  end

  defp backends do
    backend = host_backend()

    if backend == GamendWeb.Gettext do
      [GamendWeb.Gettext]
    else
      [GamendWeb.Gettext, backend]
    end
  end
end
