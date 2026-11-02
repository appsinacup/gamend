defmodule GamendWeb.I18n.ErrorsCatalog do
  @moduledoc false

  # This module exists only so `mix gettext.extract` can discover msgids
  # for changeset errors produced in `gamend_core`.
  #
  # Those errors are translated at runtime via:
  #   Gettext.dgettext(GamendWeb.Gettext, "errors", msg, opts)
  # in `GamendWeb.CoreComponents.translate_error/1`.
  #
  # By calling dgettext/2 here, we ensure the msgids are present in
  # `priv/gettext/errors.pot` and can be translated in `errors.po`.

  use Gettext, backend: GamendWeb.Gettext

  def msgids do
    [
      dgettext("errors", "cannot friend yourself"),
      dgettext("errors", "did not change"),
      dgettext("errors", "does not exist"),
      dgettext("errors", "has already been taken"),
      dgettext("errors", "lowercase letters and digits, joined by - or _"),
      dgettext("errors", "must have the @ sign and no spaces"),
      dgettext("errors", "does not match password")
    ]
  end
end
