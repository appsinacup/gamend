defmodule Gamend.Payments.Notices do
  @moduledoc """
  Telling a user about an entitlement given to them on purpose: a trial
  lengthened by support, a reward. Only when the grant asks for it (`notify:
  true` on `Gamend.Payments.grant_entitlement/3` or `extend_entitlement/3`, the
  "Tell user" box on Admin > Payments).

  An entitlement is written far more often than anyone wants to hear about it
  (each Stripe renewal, a host's own bookkeeping in its metadata), so
  `after_entitlement_changed` is not the place for this, and a write that did
  not ask says nothing.

  It goes out through `Gamend.Notifications.notify/3`, in core's `"payments"`
  group, so the user's choices for that group, its unsubscribe link and its
  limits hold: one row per title, refreshed rather than stacked, and one email
  per subject an hour. The `before_entitlement_notice/2` hook can change the
  words, the link or the group, or refuse to send it. It cannot go around
  those limits, since it only answers what to send.
  """

  require Logger

  alias Gamend.Hooks
  alias Gamend.Notifications
  alias Gamend.Notifications.Preferences
  alias Gamend.Payments.Entitlement
  alias Gamend.Repo

  require Gamend.Notifications.PreferenceGroup, as: PreferenceGroup

  @payments_tab "/users/settings?tab=payments"

  @doc "Tell the owner of `entitlement`, in the background: a grant never fails for this."
  @spec entitlement_given(Entitlement.t()) :: :ok
  def entitlement_given(%Entitlement{} = entitlement),
    do: Gamend.Async.run(fn -> send_notice(entitlement) end)

  defp send_notice(%Entitlement{user_id: user_id} = entitlement) do
    case Hooks.internal_call(:before_entitlement_notice, [entitlement, notice(entitlement)]) do
      {:ok, %{} = notice} ->
        {group, attrs} = Map.pop(notice, "group")
        deliver(user_id, group, attrs)

      other ->
        Logger.info("entitlement notice to #{user_id} not sent: #{inspect(other)}")
    end
  end

  # An unknown group would go out on no channel and say nothing about it.
  defp deliver(user_id, group, attrs) do
    case Preferences.group(group) && Notifications.notify(user_id, group, attrs) do
      {:ok, _channels} ->
        :ok

      other ->
        Logger.warning(
          "entitlement notice to #{user_id} in group #{inspect(group)}: #{inspect(other)}"
        )
    end
  end

  defp notice(%Entitlement{} = entitlement) do
    %{
      "group" => PreferenceGroup.payments(),
      "title" => "#{name(entitlement)} is yours",
      "content" => until(entitlement.expires_at),
      "url" => @payments_tab
    }
  end

  defp until(%DateTime{} = ends),
    do: "You have it until #{Calendar.strftime(ends, "%B %-d, %Y")}."

  defp until(nil), do: "You have it with no end date."

  # What the owner's Payments tab calls it.
  defp name(%Entitlement{} = entitlement) do
    product = Repo.preload(entitlement, :product).product

    Enum.find([product && product.title, (entitlement.metadata || %{})["title"]], &named?/1) ||
      entitlement.key
  end

  defp named?(name), do: is_binary(name) and name != ""
end
