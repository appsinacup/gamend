defmodule GamendWeb.NotificationsLive.Sections do
  @moduledoc """
  How `/notifications` arranges a user's notifications: one section per
  notification group (the rows of the notification settings), and inside a
  section, the notifications of one `metadata["type"]` in one stack.

  Everything keeps the order of the list it is given, newest first, so the
  section and the stack holding the latest notice come first. A notification
  with no type stacks with nothing, and one in no group goes in `other/0`.
  """

  alias Gamend.Notifications
  alias Gamend.Notifications.Notification
  alias Gamend.Notifications.Types

  @other "other"

  @type stack :: %{
          key: String.t(),
          description: String.t() | nil,
          notifications: [Notification.t(), ...]
        }

  @type section :: %{key: String.t(), count: pos_integer(), stacks: [stack(), ...]}

  @doc "The key of the section for notifications in no group."
  @spec other() :: String.t()
  def other, do: @other

  @doc "The sections of `notifications`, which come newest first."
  @spec build([Notification.t()]) :: [section()]
  def build(notifications) do
    descriptions = Types.all()

    notifications
    |> group_in_order(&section_key/1)
    |> Enum.map(fn {key, rows} ->
      %{key: key, count: length(rows), stacks: stacks(key, rows, descriptions)}
    end)
  end

  @doc "The ids of every notification in the section `key`."
  @spec section_ids([section()], String.t()) :: [Ecto.UUID.t()]
  def section_ids(sections, key) do
    sections
    |> Enum.filter(&(&1.key == key))
    |> Enum.flat_map(& &1.stacks)
    |> Enum.flat_map(&notification_ids/1)
  end

  @doc "The ids of every notification in the stack `key`."
  @spec stack_ids([section()], String.t()) :: [Ecto.UUID.t()]
  def stack_ids(sections, key) do
    sections
    |> Enum.flat_map(& &1.stacks)
    |> Enum.filter(&(&1.key == key))
    |> Enum.flat_map(&notification_ids/1)
  end

  defp section_key(notification), do: Notifications.group_of(notification) || @other

  # A key unique across sections: a `notify/3` notice can put one type in
  # another group.
  defp stacks(section_key, rows, descriptions) do
    rows
    |> group_in_order(&(&1.metadata["type"] || &1.id))
    |> Enum.map(fn {stack_key, notifications} ->
      %{
        key: section_key <> "-" <> stack_key,
        description: descriptions[stack_key],
        notifications: notifications
      }
    end)
  end

  # `Enum.group_by/2` answers a map, which forgets which key came first.
  defp group_in_order(items, key_fun) do
    groups = Enum.group_by(items, key_fun)

    items
    |> Enum.map(key_fun)
    |> Enum.uniq()
    |> Enum.map(&{&1, Map.fetch!(groups, &1)})
  end

  defp notification_ids(stack), do: Enum.map(stack.notifications, & &1.id)
end
