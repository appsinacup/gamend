defmodule GamendWeb.I18n.NotificationTypesCatalog do
  @moduledoc false

  # This module exists only so `mix gettext.extract` can discover the
  # descriptions of `Gamend.Notifications.Types`, which core holds and
  # `GamendWeb.NotificationsLive` translates at runtime as a stack's heading.
  # A new type's description goes here too; a test fails otherwise.

  use Gettext, backend: GamendWeb.Gettext

  def msgids do
    [
      dgettext("notifications", "Someone sent a friend request"),
      dgettext("notifications", "A friend request was accepted"),
      dgettext("notifications", "A friend request was rejected"),
      dgettext("notifications", "Invited to a group"),
      dgettext("notifications", "A group invite was accepted"),
      dgettext("notifications", "A group invite was declined"),
      dgettext("notifications", "Someone asked to join a group you administer"),
      dgettext("notifications", "A group join request was approved"),
      dgettext("notifications", "A group join request was rejected"),
      dgettext("notifications", "Removed from a group"),
      dgettext("notifications", "A group you were in was deleted"),
      dgettext("notifications", "Promoted within a group"),
      dgettext("notifications", "Demoted within a group"),
      dgettext("notifications", "Invited to a party"),
      dgettext("notifications", "A party invite was accepted"),
      dgettext("notifications", "A party invite was declined"),
      dgettext("notifications", "Removed from a party"),
      dgettext("notifications", "Removed from a lobby"),
      dgettext("notifications", "New direct messages from friends"),
      dgettext("notifications", "New messages in a group chat"),
      dgettext("notifications", "New messages in your lobby chat"),
      dgettext("notifications", "New messages in your party chat"),
      dgettext("notifications", "A chat report is waiting for a moderator"),
      dgettext("notifications", "A report you filed was reviewed"),
      dgettext("notifications", "A moderator sent a warning"),
      dgettext("notifications", "Muted in chat"),
      dgettext("notifications", "A quest or achievement was completed"),
      dgettext("notifications", "A report is waiting for review")
    ]
  end
end
