defmodule Gamend.Sent.SentKind do
  @moduledoc """
  What a sent email or push was (`Gamend.Sent`): the account's own emails, a
  notification, a digest of them, an admin's test, or a push a plugin sent
  (`other`).
  """

  use Gamend.Names,
      ~w(login_link confirm_account change_email login_code password_code deletion_warning account_approved notification digest test other)
end
