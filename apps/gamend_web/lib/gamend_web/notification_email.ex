defmodule GamendWeb.NotificationEmail do
  @moduledoc """
  What the web side adds to a notification email
  (`Gamend.Notifications.notify/3`): the words for a group and a channel,
  the signed unsubscribe link, and the email's body.

  The unsubscribe token is `Phoenix.Token`-signed `{user, group}` and never
  expires: a link in an old email must still work. All it can do is turn
  emails off, so a leaked one costs nothing worth a revocation list.
  """

  # :html for the host's catalogue (as every page) and verified routes.
  use GamendWeb, :html

  alias Gamend.Notifications.Preferences

  @salt "notification unsubscribe"

  @doc "A group's name as the reader sees it (core's in the catalogue, a host's through its own)."
  @spec group_label(map() | String.t()) :: String.t()
  def group_label(key) when is_binary(key),
    do: key |> Preferences.group() |> Kernel.||(%{key: key, label: key}) |> group_label()

  def group_label(%{key: "account"}), do: gettext("Account and security")
  def group_label(%{key: "social"}), do: gettext("Friends and groups")
  def group_label(%{key: "chat"}), do: gettext("Chat messages")
  def group_label(%{key: "quests"}), do: gettext("Quests and rewards")
  def group_label(%{key: "reports"}), do: gettext("Your reports")
  def group_label(%{label: label}), do: GamendWeb.HostLayouts.translate(label)

  @doc "A channel's name."
  @spec channel_label(String.t()) :: String.t()
  def channel_label("in_app"), do: gettext("On the site")
  def channel_label("email"), do: gettext("Email")
  def channel_label("push"), do: gettext("Phone")

  @doc "The token behind an unsubscribe link."
  @spec token(String.t(), String.t()) :: String.t()
  def token(user_id, group),
    do: Phoenix.Token.sign(GamendWeb.Endpoint, @salt, %{"u" => user_id, "g" => group})

  @doc "`{:ok, {user_id, group}}` for a good token."
  @spec verify(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, atom()}
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(GamendWeb.Endpoint, @salt, token, max_age: :infinity) do
      {:ok, %{"u" => user_id, "g" => group}} when is_binary(user_id) and is_binary(group) ->
        {:ok, {user_id, group}}

      {:ok, _other} ->
        {:error, :invalid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify(_token), do: {:error, :invalid}

  @doc "The one-click unsubscribe URL for a user and group."
  @spec unsubscribe_url(String.t(), String.t()) :: String.t()
  def unsubscribe_url(user_id, group),
    do: url(~p"/notifications/unsubscribe/#{token(user_id, group)}")

  @doc """
  The body: the notification's text, its link, then why the reader gets it
  and how to stop it.
  """
  @spec body(String.t(), String.t(), String.t(), String.t() | nil) :: String.t()
  def body(user_id, group, text, path) do
    link =
      if is_binary(path) and String.starts_with?(path, "/"),
        do: String.trim_trailing(url(~p"/"), "/") <> path

    [
      text,
      link,
      "--",
      gettext("You get this email because you turned on emails for: %{group}.",
        group: group_label(group)
      ),
      gettext("Stop these emails: %{url}", url: unsubscribe_url(user_id, group)),
      gettext("Choose what we send you: %{url}", url: url(~p"/users/settings?tab=notifications"))
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end
end
