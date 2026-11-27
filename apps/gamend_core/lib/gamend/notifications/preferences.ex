defmodule Gamend.Notifications.Preferences do
  @moduledoc """
  Which notifications a user wants, and how: per GROUP (a row on the
  settings page: "Friends", a host's "Daily streak") and
  per CHANNEL (`in_app`, `email`, `push`), plus three switches that win over
  everything: all email off, all push off, everything off.

  ## Groups

  Core declares its own; a host adds its own in config:

      config :gamend_core, :notification_groups, [
        %{key: "streak", label: "Daily streak",
          defaults: %{"in_app" => true, "email" => false, "push" => false},
          types: ["streak_ending"]}
      ]

  A group's `defaults` apply until the user chooses. `configurable` is the
  channels the user may change (default: all three); a channel they may not
  change always uses its default. `types` are the notification types
  (`Gamend.Notifications.Types`) that belong to the group. The "account" group
  — sign-in links, email changes — is email that cannot be turned off: it is
  how the account works.
  `admin: true` is a group for the site's admins only (a queue to work
  through): nobody else sees its row (`groups_for/1`) or gets it
  (`enabled?/3`).

  `shown_to: {module, function}` shows a group's row only to a user for whom
  `module.function(user)` is true (a host's translators): everyone else's
  settings page leaves it out (`groups_for/1`). What is sent is not changed.

  A host entry with a core group's key changes that group's `defaults`
  (`%{key: "announcements", defaults: %{"email" => true}}`: news by email
  unless the player turns it off); its other fields are core's.

  `includes: ["payments"]` on a host's group folds core groups into it: their
  rows go, and a notice sent in one of them (`notify/3`) goes out in the host's
  group, under its choices (`group/1` answers the host's group for either key).

  `email_every` (`:day`, `:week`, `:month`) sends the group's email as a digest
  (`Gamend.Notifications.Digest`) rather than one per notice, for a group whose
  notices come in runs. The site's row and the push stay instant. `email_now`
  lists the types that keep their own email, for a notice that cannot wait
  (a moderator's warning); a `notify/3` call says so with `"email_now"`.

  Which channel a group defaults to follows one rule (2026-10-28):

    * **email on**: what the person asked for and waits on, a queue an admin
      must work through, or what they lose if they miss it: "Your reports"
      (a report's answer, a moderator's warning), "Reports to review";
    * **email off, theirs to turn on**: news and nudges ("Friends",
      "News", a host's streak reminder);
    * **on the site only**: what comes often and matters in the moment
      ("Chat messages", "Quests").

  Stored in the user's private preferences (`Gamend.Accounts.Preferences`)
  under `"notifications"`:

      %{"off_all" => bool, "off_email" => bool, "off_push" => bool,
        "groups" => %{group => %{channel => bool}}}
  """

  alias Gamend.Accounts.Preferences
  alias Gamend.Accounts.User

  require Gamend.Chat.ChatType, as: ChatType
  require Gamend.Notifications.NotificationChannel, as: NotificationChannel
  require Gamend.Notifications.NotificationType, as: NotificationType
  require Gamend.Notifications.PreferenceGroup, as: PreferenceGroup
  require Gamend.Notifications.PreferenceSwitch, as: PreferenceSwitch

  @month "month"
  @week "week"
  @day "day"
  @admin "admin"
  @key_field "key"
  @label "label"

  @channels ~w(in_app email push)
  @digest_every [:day, :week, :month]
  @key "notifications"

  @core_groups [
    %{
      key: "account",
      label: "Account",
      defaults: %{"in_app" => false, "email" => true, "push" => false},
      configurable: [],
      types: [],
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
      admin: false,
      email_every: :week,
      email_now: ~w(chat_warning chat_mute)
    },
    # The admins' queues: a report, a chat report waiting for review.
    %{
      key: "moderation",
      label: "Reports to review",
      defaults: %{"in_app" => true, "email" => true, "push" => true},
      configurable: ~w(email push),
      types: ~w(report chat_report),
      admin: true
    },
    # What someone gave the user on purpose (`Gamend.Payments.Notices`): more
    # time on a trial, a reward. Rare, and often what they were waiting for.
    %{
      key: "payments",
      label: "Payments",
      defaults: %{"in_app" => true, "email" => true, "push" => false},
      configurable: ~w(email push),
      types: [],
      admin: false
    },
    %{
      key: "social",
      label: "Friends",
      defaults: %{"in_app" => true, "email" => false, "push" => true},
      configurable: ~w(email push),
      types: [],
      admin: false
    },
    %{
      key: "chat",
      label: "Chat messages",
      defaults: %{"in_app" => true, "email" => false, "push" => true},
      configurable: ~w(push),
      types: [],
      admin: false
    },
    # On the site: a quest finishes while the user is playing, and an email
    # an hour later tells them nothing they did not see.
    %{
      key: "quests",
      label: "Quests",
      defaults: %{"in_app" => true, "email" => false, "push" => false},
      configurable: ~w(push),
      types: [],
      admin: false
    },
    # What the site's team tells every player at once
    # (`Gamend.Notifications.announce_to_all/1`): news, so its email waits to
    # be turned on, and the phone is the player's to turn off.
    %{
      key: "announcements",
      label: "News",
      defaults: %{"in_app" => true, "email" => false, "push" => true},
      configurable: ~w(email push),
      types: ~w(announcement),
      admin: false
    }
  ]

  @core_keys Enum.map(@core_groups, & &1.key)

  @doc "The channels, in the order the settings page shows them."
  @spec channels() :: [String.t()]
  def channels, do: @channels

  @doc """
  Every group, core's first then the host's: `%{key, label, defaults,
  configurable, types, admin}`, `configurable` a list of channels, plus
  `email_every`, `email_now`, `shown_to` and `includes` on those that have
  them. A core group a host's `includes` names is left out.
  """
  @spec groups() :: [map()]
  def groups do
    {changes, own} =
      :gamend_core
      |> Application.get_env(:notification_groups, [])
      |> Enum.map(&atom_keys/1)
      |> Enum.split_with(&(to_string(&1[:key]) in @core_keys))

    host = Enum.map(own, &normalize_group/1)
    core_groups = Enum.map(@core_groups, &change_defaults(&1, changes))

    {included, core} =
      Enum.split_with(core_groups, fn core -> Enum.any?(host, &(core.key in &1.includes)) end)

    core ++ Enum.map(host, &take_types(&1, included))
  end

  @doc """
  The groups whose rows `user` sees: every one but the admins' (`admin:
  true`) for anyone else, and a `shown_to` group only for those it names.
  """
  @spec groups_for(User.t() | nil) :: [map()]
  def groups_for(user),
    do: Enum.filter(groups(), &(can_receive_group?(user, &1) and shown_to?(user, &1)))

  defp atom_keys(group), do: Map.new(group, fn {k, v} -> {to_atom_key(k), v} end)

  # A host entry naming a core group: its defaults over core's.
  defp change_defaults(core, changes) do
    case Enum.find(changes, &(to_string(&1[:key]) == core.key)) do
      nil ->
        core

      change ->
        defaults = Map.new(change[:defaults] || %{}, fn {k, v} -> {to_string(k), v == true} end)
        %{core | defaults: Map.merge(core.defaults, defaults)}
    end
  end

  # An included core group's types are the host group's too.
  defp take_types(%{includes: []} = group, _included), do: group

  defp take_types(group, included) do
    types = for core <- included, core.key in group.includes, type <- core.types, do: type
    %{group | types: Enum.uniq(group.types ++ types)}
  end

  defp shown_to?(user, %{shown_to: {module, function}}),
    do: match?(%User{}, user) and apply(module, function, [user]) == true

  defp shown_to?(_user, _group), do: true

  # An admins' group (`admin: true`) is an admin's only.
  defp can_receive_group?(user, %{admin: true}), do: match?(%User{is_admin: true}, user)
  defp can_receive_group?(_user, _group), do: true

  @doc "One group, or nil. A core key a host's group `includes` answers that group."
  @spec group(String.t()) :: map() | nil
  def group(key),
    do: Enum.find(groups(), &(&1.key == key or key in Map.get(&1, :includes, [])))

  @doc """
  The group a notification TYPE (`Gamend.Notifications.Types`) belongs to, so
  a friend request or a chat message follows the user's choices for its row.
  nil for a type in no group (a moderator's notice), which is always sent.
  """
  @spec group_for_type(term()) :: String.t() | nil
  def group_for_type("chat_" <> kind)
      when kind in [ChatType.friend(), ChatType.group(), ChatType.lobby(), ChatType.party()],
      do: PreferenceGroup.chat()

  def group_for_type("friend_" <> _), do: PreferenceGroup.social()
  def group_for_type("group_" <> _), do: PreferenceGroup.social()
  def group_for_type("party_" <> _), do: PreferenceGroup.social()
  def group_for_type(NotificationType.lobby_kicked()), do: PreferenceGroup.social()
  def group_for_type(NotificationType.quest_completed()), do: PreferenceGroup.quests()

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
      admin: group[:admin] == true,
      email_every: email_every(group[:email_every]),
      email_now: Enum.map(group[:email_now] || [], &to_string/1),
      shown_to: shown_to(group[:shown_to]),
      includes: Enum.map(group[:includes] || [], &to_string/1)
    }
  end

  defp to_atom_key(key) when is_atom(key), do: key
  defp to_atom_key(@key_field), do: :key
  defp to_atom_key(@label), do: :label
  defp to_atom_key("defaults"), do: :defaults
  defp to_atom_key("configurable"), do: :configurable
  defp to_atom_key("types"), do: :types
  defp to_atom_key(@admin), do: :admin
  defp to_atom_key("email_every"), do: :email_every
  defp to_atom_key("email_now"), do: :email_now
  defp to_atom_key("shown_to"), do: :shown_to
  defp to_atom_key("includes"), do: :includes
  defp to_atom_key(other), do: other

  defp email_every(every) when every in @digest_every, do: every

  defp email_every(every) when every in [@day, @week, @month],
    do: String.to_existing_atom(every)

  defp email_every(_every), do: nil

  defp shown_to({module, function}) when is_atom(module) and is_atom(function),
    do: {module, function}

  defp shown_to(_none), do: nil

  @doc """
  Whether a notice of `type` in `group` waits for the group's digest
  (`Gamend.Notifications.Digest`): its group has `email_every`, and the type is
  not in its `email_now`.
  """
  @spec digest?(String.t(), String.t() | nil) :: boolean()
  def digest?(group_key, type) do
    case group(group_key) do
      %{email_every: nil} ->
        false

      %{email_every: _every} = group ->
        type not in Map.get(group, :email_now, [])

      _no_digest ->
        false
    end
  end

  @doc "The days between a group's digests: 0 for a group with none, or none any more."
  @spec email_every_days(String.t()) :: non_neg_integer()
  def email_every_days(group_key) do
    case group(group_key) do
      %{email_every: :day} -> 1
      %{email_every: :week} -> 7
      %{email_every: :month} -> 30
      _none -> 0
    end
  end

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

          channel == NotificationChannel.email() and prefs["off_email"] == true ->
            false

          channel == NotificationChannel.push() and prefs["off_push"] == true ->
            false

          is_boolean(get_in(prefs, ["groups", group.key, channel])) ->
            prefs["groups"][group.key][channel]

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

      %{key: key, configurable: configurable} ->
        if channel in configurable,
          do: update(user, &put_choice(&1, key, channel, on?)),
          else: {:error, :not_configurable}
    end
  end

  @switches [
    PreferenceSwitch.off_all(),
    PreferenceSwitch.off_email(),
    PreferenceSwitch.off_push()
  ]

  @doc """
  Several choices at once, in one write, as a client sends them
  (`PUT /api/v1/me/notification_settings`): `"groups"`, `%{group =>
  %{channel => bool}}` (`put/4` each), and the switches `"off_all"`,
  `"off_email"`, `"off_push"`, each `true` (`turn_off/2`) or `false`
  (`turn_on/2`); a key left out is left as it is. Refused whole, with
  nothing written: `:unknown_group` for a group the user has no row for
  (an admins' one for anyone else), `:not_configurable` for a channel the
  group does not let users change.
  """
  @spec change(User.t(), map()) :: {:ok, User.t()} | {:error, term()}
  def change(%User{} = user, changes) when is_map(changes) do
    switches = Map.take(changes, @switches)

    case choices(user, Map.get(changes, "groups") || %{}) do
      {:ok, []} when switches == %{} -> {:ok, user}
      {:ok, choices} -> change(user, choices, switches)
      error -> error
    end
  end

  defp change(user, choices, switches) do
    update(user, fn prefs ->
      prefs =
        Enum.reduce(choices, prefs, fn {key, channel, on?}, acc ->
          put_choice(acc, key, channel, on?)
        end)

      Enum.reduce(switches, prefs, fn
        {switch, true}, acc -> Map.put(acc, switch, true)
        {switch, false}, acc -> Map.delete(acc, switch)
      end)
    end)
  end

  # Every `{group key, channel, on?}` of a change, each checked as `put/4`
  # checks one.
  defp choices(user, groups) do
    Enum.reduce_while(groups, {:ok, []}, fn {group_key, channels}, {:ok, acc} ->
      case group(group_key) do
        %{admin: true} when user.is_admin != true ->
          {:halt, {:error, :unknown_group}}

        %{key: key, configurable: configurable} ->
          if Enum.all?(Map.keys(channels), &(&1 in configurable)),
            do: {:cont, {:ok, acc ++ Enum.map(channels, fn {c, on?} -> {key, c, on?} end)}},
            else: {:halt, {:error, :not_configurable}}

        nil ->
          {:halt, {:error, :unknown_group}}
      end
    end)
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
