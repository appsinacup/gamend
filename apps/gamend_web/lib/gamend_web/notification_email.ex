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

  alias Gamend.Mail.Message
  alias Gamend.Notifications.DigestItem
  alias Gamend.Notifications.Preferences

  require Gamend.Notifications.NotificationChannel, as: NotificationChannel
  require Gamend.Notifications.PreferenceGroup, as: PreferenceGroup
  require Gamend.UrlScheme, as: UrlScheme

  @salt "notification unsubscribe"

  @doc """
  A group's name as the reader sees it (core's in the catalogue, a host's
  through its own). A stored value that names no group reads "Other".
  """
  @spec group_label(term()) :: String.t()
  def group_label(key) when is_binary(key),
    do: key |> Preferences.group() |> Kernel.||(%{key: key, label: key}) |> group_label()

  def group_label(%{key: PreferenceGroup.account()}), do: gettext("Account")
  def group_label(%{key: PreferenceGroup.social()}), do: gettext("Friends")
  def group_label(%{key: PreferenceGroup.chat()}), do: gettext("Chat messages")
  def group_label(%{key: PreferenceGroup.quests()}), do: gettext("Quests")
  def group_label(%{key: PreferenceGroup.reports()}), do: gettext("Your reports")
  def group_label(%{key: PreferenceGroup.payments()}), do: gettext("Payments")

  def group_label(%{key: PreferenceGroup.announcements()}), do: gettext("News")

  def group_label(%{label: label}) when is_binary(label),
    do: GamendWeb.HostLayouts.translate(label)

  def group_label(_unknown), do: dgettext("notifications", "Other")

  @doc "A channel's name."
  @spec channel_label(String.t()) :: String.t()
  def channel_label(NotificationChannel.in_app()), do: gettext("On the site")
  def channel_label(NotificationChannel.email()), do: gettext("Email")
  def channel_label(NotificationChannel.push()), do: gettext("Phone")

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
  The email (`Gamend.Mail.Message`): the notification's title, its picture
  (`image`, a path on the site or a URL), its text, its link as the button,
  then why the reader gets it and how to stop it.
  """
  @spec body(String.t(), String.t(), map()) :: Message.t()
  def body(user_id, group, %{} = notice) do
    %Message{
      title: notice[:title] || group_label(group),
      paragraphs: paragraphs(notice[:text]),
      image: site_url(notice[:image]),
      button: open_button(notice[:url]),
      footer: footer(user_id, group)
    }
  end

  @doc "A digest's subject: a lone notice's own, else the group's."
  @spec digest_subject(String.t(), [DigestItem.t()]) :: String.t()
  def digest_subject(_group, [%DigestItem{subject: subject}]), do: subject

  def digest_subject(group, _items),
    do: gettext("%{group}: what is new", group: group_label(group))

  @doc "A digest's email: its notices, oldest first, each under its subject, then the footer."
  @spec digest_body(String.t(), String.t(), [DigestItem.t()]) :: Message.t()
  def digest_body(user_id, group, [%DigestItem{subject: subject, text: text, url: url}]),
    do: body(user_id, group, %{title: subject, text: text, url: url})

  def digest_body(user_id, group, items) do
    %Message{
      title: digest_subject(group, items),
      items: Enum.map(items, &%{title: &1.subject, text: &1.text, url: site_url(&1.url)}),
      footer: footer(user_id, group)
    }
  end

  defp paragraphs(text) when is_binary(text) and text != "",
    do: text |> String.split(~r/\n\s*\n/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp paragraphs(_none), do: []

  defp open_button(path) do
    case site_url(path) do
      nil -> nil
      url -> {gettext("Open"), url}
    end
  end

  @doc "Run `fun` in the reader's language: an email goes out from a job, with no page's."
  @spec in_locale(String.t() | nil, (-> result)) :: result when result: var
  def in_locale(locale, fun) when is_binary(locale),
    do: Gettext.with_locale(GamendWeb.GettextSync.host_backend(), locale, fun)

  def in_locale(_locale, fun), do: fun.()

  defp site_url("/" <> _ = path), do: String.trim_trailing(url(~p"/"), "/") <> path

  defp site_url(url) when is_binary(url) do
    if URI.parse(url).scheme in [UrlScheme.http(), UrlScheme.https()], do: url
  end

  defp site_url(_none), do: nil

  defp footer(user_id, group) do
    [
      gettext("Emails about: %{group}", group: group_label(group)),
      gettext("Stop these emails: %{url}", url: unsubscribe_url(user_id, group)),
      gettext("Choose what we send you: %{url}", url: url(~p"/users/settings?tab=notifications"))
    ]
  end
end
