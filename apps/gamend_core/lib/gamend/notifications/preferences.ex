defmodule Gamend.Notifications.Preferences do
  @moduledoc """
  Which notifications a user wants, and how: per GROUP (a row on the
  settings page: "Friends and groups", a host's "Streak about to end") and
  per CHANNEL (`in_app`, `email`, `push`), plus three switches that win over
  everything: all email off, all push off, everything off.

  ## Groups

  Core declares its own; a host adds its own in config:

      config :gamend_core, :notification_groups, [
        %{key: "streak", label: "Streak about to end",
          defaults: %{"in_app" => true, "email" => false, "push" => false},
          types: ["streak_ending"], signup: true}
      ]

  A group's `defaults` apply until the user chooses. `configurable` is the
  channels the user may change (default: all three); a channel they may not
  change always uses its default. `types` are the notification types
  (`Gamend.Notifications.Types`) that belong to the group. `signup: true`
  offers its email on the registration form, unticked: an email nobody asked
  for is spam, so the user opts in. The "account" group — sign-in links, email
  changes — is email that cannot be turned off: it is how the account works.
  `admin: true` is a group for the site's admins only (a queue to work
  through): nobody else sees its row (`groups_for/1`) or gets it
  (`enabled?/3`).

  Which channel a group defaults to follows one rule (2026-10-28):

    * **email on**: what the person asked for and waits on, a queue an admin
      must work through, or what they lose if they miss it: "Your reports"
      (a report's answer, a moderator's warning), "Reports to review";
    * **email off, theirs to turn on**: news and nudges ("Friends and
      groups", a host's streak reminder);
    * **on the site only**: what comes often and matters in the moment
      ("Chat messages", "Quests and rewards").

  Stored in the user's private preferences (`Gamend.Accounts.Preferences`)
  under `"notifications"`:

      %{"off_all" => bool, "off_email" => bool, "off_push" => bool,
        "groups" => %{group => %{channel => bool}}}
  """

  alias Gamend.Accounts.Preferences
  alias Gamend.Accounts.User

  @channels ~w(in_app email push)
  @key "notifications"

  @core_groups [
    %{
      key: "account",
      label: "Account and security",
      defaults: %{"in_app" => false, "email" => true, "push" => false},
      configurable: [],
      types: [],
      signup: false,
      admin: false
    },
    # The answer to a report the user filed (`Gamend.Reports`, chat's), and
    # a moderator's warning or mute: each an answer someone waits for, or a
    # change to what they may do.
    %{
      key: "reports",
      label: "Your reports",
      defaults: %{"in_app" => true, "email" => true, "push" => true},
      configurable: ~w(email push),
      types: ~w(report_resolved chat_report_resolved chat_warning chat_mute),
      signup: false,
      admin: false
    },
    # The admins' queues: a report, a chat report waiting for review.
    %{
      key: "moderation",
      label: "Reports to review",
      defaults: %{"in_app" => true, "email" => true, "push" => true},
      configurable: ~w(email push),
      types: ~w(report chat_report),
      signup: false,
      admin: true
    },
    %{
      key: "social",
      label: "Friends and groups",
      defaults: %{"in_app" => true, "email" => false, "push" => true},
      configurable: ~w(email push),
      types: [],
      signup: false,
      admin: false
    },
    %{
      key: "chat",
      label: "Chat messages",
      defaults: %{"in_app" => true, "email" => false, "push" => true},
      configurable: ~w(push),
      types: [],
      signup: false,
      admin: false
    },
    # On the site: a quest finishes while the user is playing, and an email
    # an hour later tells them nothing they did not see.
    %{
      key: "quests",
      label: "Quests and rewards",
      defaults: %{"in_app" => true, "email" => false, "push" => false},
      configurable: ~w(push),
      types: [],
      signup: false,
      admin: false
    }
  ]

  @doc "The channels, in the order the settings page shows them."
  @spec channels() :: [String.t()]
  def channels, do: @channels

  @doc """
  Every group, core's first then the host's: `%{key, label, defaults,
  configurable, types, signup, admin}`, `configurable` a list of channels.
  """
  @spec groups() :: [map()]
  def groups do
    host =
      :gamend_core
      |> Application.get_env(:notification_groups, [])
      |> Enum.map(&normalize_group/1)

    @core_groups ++ host
  end

  @doc "The groups `user` may get: every one but the admins' (`admin: true`) for anyone else."
  @spec groups_for(User.t() | nil) :: [map()]
  def groups_for(user), do: Enum.filter(groups(), &can_receive_group?(user, &1))

  # An admins' group (`admin: true`) is an admin's only.
  defp can_receive_group?(user, %{admin: true}), do: match?(%User{is_admin: true}, user)
  defp can_receive_group?(_user, _group), do: true

  @doc "The groups whose email the registration form offers (`signup: true`)."
  @spec signup_groups() :: [map()]
  def signup_groups, do: Enum.filter(groups(), &(&1.signup and not &1.admin))

  @doc "One group, or nil."
  @spec group(String.t()) :: map() | nil
  def group(key), do: Enum.find(groups(), &(&1.key == key))

  @doc """
  The group a notification TYPE (`Gamend.Notifications.Types`) belongs to, so
  a friend request or a chat message follows the user's choices for its row.
  nil for a type in no group (a moderator's notice), which is always sent.
  """
  @spec group_for_type(term()) :: String.t() | nil
  def group_for_type("chat_" <> kind) when kind in ~w(friend group lobby party), do: "chat"
  def group_for_type("friend_" <> _), do: "social"
  def group_for_type("group_" <> _), do: "social"
  def group_for_type("party_" <> _), do: "social"
  def group_for_type("lobby_kicked"), do: "social"
  def group_for_type("quest_completed"), do: "quests"

  def group_for_type(type) when is_binary(type) do
    Enum.find_value(groups(), fn group -> if type in group.types, do: group.key end)
  end

  def group_for_type(_type), do: nil

  defp normalize_group(group) do
    group = Map.new(group, fn {k, v} -> {to_atom_key(k), v} end)

    %{
      key: to_string(group[:key]),
      label: to_string(group[:label] || group[:key]),
      defaults: Map.new(group[:defaults] || %{}, fn {k, v} -> {to_string(k), v == true} end),
      configurable: Enum.map(group[:configurable] || @channels, &to_string/1),
      types: Enum.map(group[:types] || [], &to_string/1),
      signup: group[:signup] == true and "email" in (group[:configurable] || @channels),
      admin: group[:admin] == true
    }
  end

  defp to_atom_key(key) when is_atom(key), do: key
  defp to_atom_key("key"), do: :key
  defp to_atom_key("label"), do: :label
  defp to_atom_key("defaults"), do: :defaults
  defp to_atom_key("configurable"), do: :configurable
  defp to_atom_key("types"), do: :types
  defp to_atom_key("signup"), do: :signup
  defp to_atom_key("admin"), do: :admin
  defp to_atom_key(other), do: other

  @doc "A user's stored choices (see the moduledoc's shape)."
  @spec stored(User.t() | nil) :: map()
  def stored(user), do: Preferences.get(user)[@key] || %{}

  @doc """
  Whether `user` gets `group` through `channel`. A channel the group does not
  let the user change is its default; otherwise the switches win (everything
  off, then all email / all push off), then the user's own choice, then the
  default. An unknown group is off, and so is an admins' group for anyone
  else.
  """
  @spec enabled?(User.t() | nil, String.t(), String.t()) :: boolean()
  def enabled?(user, group_key, channel) when channel in @channels do
    case group(group_key) do
      nil ->
        false

      group ->
        default = Map.get(group.defaults, channel, false)
        prefs = stored(user)

        cond do
          not can_receive_group?(user, group) ->
            false

          channel not in group.configurable ->
            default

          prefs["off_all"] == true ->
            false

          channel == "email" and prefs["off_email"] == true ->
            false

          channel == "push" and prefs["off_push"] == true ->
            false

          is_boolean(get_in(prefs, ["groups", group_key, channel])) ->
            prefs["groups"][group_key][channel]

          true ->
            default
        end
    end
  end

  def enabled?(_user, _group, _channel), do: false

  @doc "Set one group's channel. A channel the group does not let users change is refused."
  @spec put(User.t(), String.t(), String.t(), boolean()) :: {:ok, User.t()} | {:error, term()}
  def put(%User{} = user, group_key, channel, on?) when is_boolean(on?) do
    case group(group_key) do
      nil ->
        {:error, :unknown_group}

      %{admin: true} when user.is_admin != true ->
        {:error, :unknown_group}

      %{configurable: configurable} ->
        if channel in configurable,
          do: update(user, &put_choice(&1, group_key, channel, on?)),
          else: {:error, :not_configurable}
    end
  end

  # A switch (all email off, everything off) still wins over a choice:
  # turning one back on is `turn_on/2`, said in so many words.
  defp put_choice(prefs, group_key, channel, on?) do
    groups = prefs["groups"] || %{}
    choices = Map.put(groups[group_key] || %{}, channel, on?)
    Map.put(prefs, "groups", Map.put(groups, group_key, choices))
  end

  @doc "Turn off all email, all push, or everything (`:email | :push | :all`)."
  @spec turn_off(User.t(), :email | :push | :all) :: {:ok, User.t()} | {:error, term()}
  def turn_off(%User{} = user, :all), do: update(user, &Map.put(&1, "off_all", true))
  def turn_off(%User{} = user, :email), do: update(user, &Map.put(&1, "off_email", true))
  def turn_off(%User{} = user, :push), do: update(user, &Map.put(&1, "off_push", true))

  @doc "Undo `turn_off/2`: each group's own choices apply again."
  @spec turn_on(User.t(), :email | :push | :all) :: {:ok, User.t()} | {:error, term()}
  def turn_on(%User{} = user, :all), do: update(user, &Map.delete(&1, "off_all"))
  def turn_on(%User{} = user, :email), do: update(user, &Map.delete(&1, "off_email"))
  def turn_on(%User{} = user, :push), do: update(user, &Map.delete(&1, "off_push"))

  @doc ~s(Whether a switch is on: `"off_all"`, `"off_email"`, `"off_push"`.)
  @spec off?(User.t() | nil, String.t()) :: boolean()
  def off?(user, switch), do: stored(user)[switch] == true

  defp update(user, fun),
    do: Preferences.update(user, fn prefs -> Map.put(prefs, @key, fun.(prefs[@key] || %{})) end)
end
