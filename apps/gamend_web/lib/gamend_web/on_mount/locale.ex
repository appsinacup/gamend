defmodule GamendWeb.OnMount.Locale do
  @moduledoc """
  LiveView on_mount hook that sets the Gettext locale from the session.

  When the `LocalePath` plug stores a `:preferred_locale` in the session,
  this hook reads it so that LiveView renders use the correct locale.
  """

  require Gamend.LocaleCode, as: LocaleCode

  @session_key "preferred_locale"

  def on_mount(:default, _params, session, socket) do
    locale = GamendWeb.GettextSync.normalize_locale(session[@session_key]) || LocaleCode.en()
    GamendWeb.GettextSync.put_locale(locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
