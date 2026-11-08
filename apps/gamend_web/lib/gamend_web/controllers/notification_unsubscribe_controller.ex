defmodule GamendWeb.NotificationUnsubscribeController do
  @moduledoc """
  The link at the foot of every notification email
  (`GamendWeb.NotificationEmail`), no sign-in needed: the signed token says
  whose email and which group.

    * `GET` shows the page: stop this group's emails, or all email. It never
      changes anything itself, because mail scanners open every link.
    * `POST` makes the change. A mail client's own "Unsubscribe" button posts
      here too (RFC 8058, `List-Unsubscribe=One-Click`), which is why the
      route has no CSRF check: it cannot carry a token, and the signed link
      is the proof.
  """

  use GamendWeb, :controller

  alias Gamend.Accounts
  alias Gamend.Notifications.Preferences
  alias GamendWeb.NotificationEmail

  require GamendWeb.FilterValue, as: FilterValue
  require Gamend.Notifications.NotificationChannel, as: NotificationChannel
  require Gamend.Notifications.PreferenceSwitch, as: PreferenceSwitch

  @group "group"

  def show(conn, %{"token" => token} = params) do
    case load(token) do
      {:ok, user, group} ->
        conn
        |> assign(:page_title, gettext("Email settings"))
        |> assign(:token, token)
        |> assign(:group, group)
        |> assign(:group_label, NotificationEmail.group_label(group))
        |> assign(:group_off?, not Preferences.enabled?(user, group, NotificationChannel.email()))
        |> assign(
          :all_off?,
          Preferences.off?(user, PreferenceSwitch.off_email()) or
            Preferences.off?(user, PreferenceSwitch.off_all())
        )
        |> assign(:done, params["done"])
        |> render(:show)

      :error ->
        conn
        |> put_status(:not_found)
        |> assign(:page_title, gettext("Email settings"))
        |> render(:invalid)
    end
  end

  def create(conn, %{"token" => token} = params) do
    case load(token) do
      {:ok, user, group} ->
        scope =
          if params["scope"] == FilterValue.everything(),
            do: FilterValue.everything(),
            else: @group

        _ =
          if scope == FilterValue.everything(),
            do: Preferences.turn_off(user, :email),
            else: Preferences.put(user, group, NotificationChannel.email(), false)

        if params["List-Unsubscribe"] == "One-Click",
          do: send_resp(conn, 200, ""),
          else: redirect(conn, to: "/notifications/unsubscribe/#{token}?done=#{scope}")

      :error ->
        send_resp(conn, 404, "")
    end
  end

  defp load(token) do
    with {:ok, {user_id, group}} <- NotificationEmail.verify(token),
         %Accounts.User{} = user <- Accounts.get_user(user_id) do
      {:ok, user, group}
    else
      _ -> :error
    end
  end
end
