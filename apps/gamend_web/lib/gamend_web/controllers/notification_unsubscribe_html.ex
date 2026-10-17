defmodule GamendWeb.NotificationUnsubscribeHTML do
  @moduledoc "The page behind an email's unsubscribe link (`GamendWeb.NotificationUnsubscribeController`)."

  use GamendWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-narrow space-y-6 py-8">
        <h1 class="text-3xl font-black">{gettext("Email settings")}</h1>

        <p :if={@done == "group"} id="unsubscribe-done" class="alert alert-success">
          {gettext("Done. No more emails about: %{group}.", group: @group_label)}
        </p>
        <p :if={@done == "all"} id="unsubscribe-done" class="alert alert-success">
          {gettext("Done. We will not email you anything but account messages.")}
        </p>

        <div :if={is_nil(@done)} class="space-y-4">
          <p>{gettext("Emails about: %{group}", group: @group_label)}</p>

          <.form
            :if={not @group_off?}
            for={%{}}
            action={~p"/notifications/unsubscribe/#{@token}"}
            method="post"
          >
            <input type="hidden" name="scope" value="group" />
            <button type="submit" id="unsubscribe-group" class="btn btn-primary w-full">
              {gettext("Stop these emails")}
            </button>
          </.form>

          <.form
            :if={not @all_off?}
            for={%{}}
            action={~p"/notifications/unsubscribe/#{@token}"}
            method="post"
          >
            <input type="hidden" name="scope" value="all" />
            <button type="submit" id="unsubscribe-all" class="btn btn-outline w-full">
              {gettext("Stop all emails")}
            </button>
          </.form>

          <p :if={@group_off? and @all_off?}>{gettext("You get none of these emails.")}</p>
        </div>

        <p class="text-sm text-muted">
          {gettext("Account messages, such as sign-in links, are always sent.")}
          <.link navigate={~p"/users/settings?tab=notifications"} class="link">
            {gettext("Choose what we send you")}
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def invalid(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-narrow space-y-4 py-8">
        <h1 class="text-3xl font-black">{gettext("Email settings")}</h1>
        <p>{gettext("This link does not work. Sign in to choose what we send you.")}</p>
        <.link navigate={~p"/users/settings?tab=notifications"} class="btn btn-primary">
          {gettext("Settings")}
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
