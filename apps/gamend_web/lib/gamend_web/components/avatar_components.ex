defmodule GamendWeb.AvatarComponents do
  @moduledoc """
  A person's picture and a group's, the card every list draws a player with,
  and the owner picker that shows both. Out of `GamendWeb.CoreComponents`, so
  an edit here recompiles only the templates that draw them; imported through
  `html_helpers`.
  """
  use Phoenix.Component
  use Gettext, backend: GamendWeb.Gettext

  import GamendWeb.CoreComponents,
    only: [
      entity_icon: 1,
      icon: 1,
      player_name: 1,
      user_badge: 1,
      user_title_class: 2,
      user_title_text: 1
    ]

  alias Gamend.Accounts.User
  alias Phoenix.LiveView.JS

  @doc """
  A user's avatar as a round image when they have one we host
  (`User.public_avatar_url/1`), or the icon they picked in its place, drawn
  on a round tile, falling back to the generic person icon. A
  provider's URL is never drawn: it would send the viewer's IP to that provider,
  so an avatar not yet mirrored shows the icon. Pass `class` for sizing, e.g.
  `"w-5 h-5"`. If the image fails to load (an object gone from storage),
  `assets/js/avatar_fallback.js` hides the broken image and reveals the same
  icon. That lives in a real script rather than an `onerror` attribute because
  the CSP here has no `script-src 'unsafe-inline'`, so an inline handler is
  refused and the fallback would never fire.

  `crossorigin="anonymous"` is load-bearing, not decoration: `/play` and
  `/game/*` are served cross-origin isolated for Godot's `SharedArrayBuffer`
  (see `GamendWeb.Plugs.GameHeaders`), and under
  `Cross-Origin-Embedder-Policy: require-corp` a cross-origin subresource is
  blocked unless it either sends `Cross-Origin-Resource-Policy` or is fetched in
  CORS mode. A bucket or CDN on another origin (`storage.public_url`) is that
  case; it already sends CORS for the presigned upload flow. Same-origin
  avatars are unaffected.
  """
  attr :user, :any, default: nil
  attr :class, :string, default: "w-6 h-6"

  def user_avatar(assigns) do
    url = User.public_avatar_url(assigns.user)

    assigns =
      assign(assigns,
        avatar_url: url,
        avatar_icon?: match?({:ok, _}, GamendWeb.Icons.from_path(url || "")),
        tile_style: icon_tile_style(url)
      )

    ~H"""
    <%!-- One of the site's icons as the avatar (`Gamend.Icons`): drawn
          over `currentColor`, so it follows the theme, on a round tile the size of a
          picture, tinted with its colour when it has one. Everyone has one
          (`User.public_avatar_url/1`): the person icon is only for no user. --%>
    <span
      :if={@avatar_icon?}
      style={@tile_style}
      class={[
        "inline-flex shrink-0 items-center justify-center rounded-full bg-base-300 text-muted",
        @class
      ]}
    >
      <.entity_icon icon_url={@avatar_url} type={:user} class="w-3/5 h-3/5" />
    </span>
    <%!-- no-referrer: a storage CDN on another origin has no need to learn
          which page showed the avatar. --%>
    <img
      :if={@avatar_url && !@avatar_icon?}
      src={@avatar_url}
      alt=""
      crossorigin="anonymous"
      referrerpolicy="no-referrer"
      data-avatar-fallback
      data-icon-backdrop
      class={["rounded-full object-cover bg-base-300", @class]}
    />
    <.icon
      :if={@avatar_url && !@avatar_icon?}
      name="hero-user-circle-solid"
      class={"hidden " <> @class}
    />
    <.icon :if={!@avatar_url} name="hero-user-circle-solid" class={@class} />
    """
  end

  attr :user, :any, default: nil
  attr :class, :string, default: "w-6 h-6"

  @doc """
  A player's avatar as other players see it: `user_avatar/1` with whatever the
  host draws with it. A function component, given `user`, the avatar's `class`
  (its size, for anything that must match it) and the avatar as its
  `inner_block`, free to wrap, frame or draw over it:

      config :gamend_web, :player_avatar, {MyHost.UI, :player_avatar}

  Unset, the avatar alone. Core knows nothing of what is drawn: a rank's
  emblem, a level ring, a seasonal hat, an online dot. `player_card/1` uses it,
  so do the navbar, the friends and groups lists and chat; a table for admins
  keeps `user_avatar/1`.
  """
  def player_avatar(assigns) do
    ~H"""
    <.host_player_avatar user={@user} class={@class}>
      <.user_avatar user={@user} class={@class} />
    </.host_player_avatar>
    """
  end

  attr :user, :any, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp host_player_avatar(assigns) do
    case Application.get_env(:gamend_web, :player_avatar) do
      {module, function} when is_atom(module) and is_atom(function) ->
        apply(module, function, [assigns])

      _ ->
        ~H"{render_slot(@inner_block)}"
    end
  end

  # A coloured icon's round tile (`user_avatar/1`, `group_avatar/1`): its
  # colour over the page's base, so it reads in both themes. Nil, the plain
  # tile, for an icon in no colour.
  defp icon_tile_style(url) do
    if css = Gamend.Icons.color_css(Gamend.Icons.color(url)),
      do: "background-color: color-mix(in oklab, #{css} 20%, var(--color-base-100))"
  end

  attr :icon_url, :string, default: nil, doc: "the group's `icon_url`"
  attr :class, :any, default: "size-6"

  @doc """
  A group's icon as `user_avatar/1` draws a person's, on a tile the size of a
  picture: an uploaded image filling it, or one of the site's icons,
  tinted with its colour. Square-cornered where a person's is round, so a
  group and a person beside it (`owner_picker/1`) read as two kinds.
  """
  def group_avatar(assigns) do
    assigns =
      assign(assigns,
        icon?:
          assigns.icon_url in [nil, ""] or GamendWeb.Icons.from_path(assigns.icon_url) != :error,
        tile_style: icon_tile_style(assigns.icon_url)
      )

    ~H"""
    <span
      style={@tile_style}
      class={[
        "inline-flex shrink-0 items-center justify-center overflow-hidden rounded-field bg-base-300 text-muted",
        @class
      ]}
    >
      <.entity_icon
        icon_url={@icon_url}
        type={:group}
        class={if @icon?, do: "w-3/5 h-3/5", else: "size-full object-cover"}
      />
    </span>
    """
  end

  attr :id, :string, required: true

  attr :field, Phoenix.HTML.FormField,
    default: nil,
    doc: "the owning group's id field (`server[group_id]`); else `name` and `value`"

  attr :name, :string, default: nil
  attr :value, :any, default: nil
  attr :user, :any, required: true, doc: "the reader, the owner when no group is picked"

  attr :groups, :list,
    required: true,
    doc: "the groups that may own it: `%{id, title, icon_url}` (a `%Group{}`), or `{title, id}`"

  attr :label, :any,
    default: nil,
    doc: "the field's label, Owner when not given; `false` for none seen (a panel titled Owner)"

  attr :disabled, :boolean, default: false

  slot :inner_block, doc: "beside the picker: the page's New group, its Members"

  @doc """
  Who owns a thing: the reader, or one of their groups, each drawn as a card,
  a person's (`player_card/1`) or a group's (`group_avatar/1`) — not a bare
  select, which can hold no icon. A button showing the owner opens the list;
  a pick is a radio of the field's, so the form's `phx-change` hears it, and
  closes the list. The reader's is the empty value: no group.

      <.owner_picker id="server-owner" field={@form[:group_id]} user={@user} groups={@groups}>
        <NewGroupComponent.open_button target="#new-group" />
      </.owner_picker>
  """
  def owner_picker(assigns) do
    {name, value} =
      case assigns.field do
        %Phoenix.HTML.FormField{name: name, value: value} -> {name, value}
        nil -> {assigns.name, assigns.value}
      end

    groups = Enum.map(assigns.groups, &owner_group/1)
    value = if value in [nil, ""], do: "", else: to_string(value)

    assigns =
      assign(assigns,
        input_name: name,
        options: [{"", nil} | Enum.map(groups, &{&1.id, &1})],
        selected: Enum.find(groups, &(&1.id == value)),
        value: value,
        menu: "#{assigns.id}-menu",
        legend_class: if(assigns.label == false, do: "sr-only", else: "label mb-1"),
        label: assigns.label || gettext("Owner")
      )

    ~H"""
    <fieldset id={@id} class="fieldset">
      <legend class={@legend_class}>{@label}</legend>
      <div class="flex flex-wrap items-center gap-2">
        <div
          class="relative w-full sm:w-auto sm:min-w-72"
          phx-click-away={JS.hide(to: "##{@menu}")}
          phx-window-keydown={JS.hide(to: "##{@menu}")}
          phx-key="Escape"
        >
          <button
            type="button"
            id={"#{@id}-button"}
            disabled={@disabled}
            aria-haspopup="true"
            aria-controls={@menu}
            phx-click={JS.toggle(to: "##{@menu}")}
            class="btn btn-surface h-auto min-h-11 w-full justify-between gap-3 py-1.5 font-normal"
          >
            <.owner_option user={@user} group={@selected} />
            <.icon name="hero-chevron-up-down-solid" class="size-4 shrink-0 text-muted" />
          </button>
          <div
            id={@menu}
            role="radiogroup"
            aria-label={@label}
            class="absolute start-0 top-full z-30 mt-1 hidden max-h-80 w-full overflow-y-auto rounded-box border border-base-300 bg-base-100 p-1 shadow-lg"
          >
            <label
              :for={{id, group} <- @options}
              :key={id}
              phx-click={JS.hide(to: "##{@menu}")}
              class="flex cursor-pointer items-center gap-2 rounded-field px-2 py-1.5 hover:bg-base-200 has-checked:bg-base-200 has-focus-visible:outline-2 has-focus-visible:outline-primary"
            >
              <input
                type="radio"
                name={@input_name}
                value={id}
                checked={@value == id}
                disabled={@disabled}
                class="sr-only"
              />
              <.owner_option user={@user} group={group} />
              <.icon :if={@value == id} name="hero-check-solid" class="ms-auto size-4 text-primary" />
            </label>
          </div>
        </div>
        {render_slot(@inner_block)}
      </div>
    </fieldset>
    """
  end

  defp owner_group({title, id}), do: %{id: to_string(id), title: title, icon_url: nil}

  defp owner_group(%{id: id, title: title} = group),
    do: %{id: to_string(id), title: title, icon_url: Map.get(group, :icon_url)}

  attr :user, :any, required: true
  attr :group, :any, required: true

  # One owner as a card: the reader's (their avatar, their name, You), or a
  # group's (its icon, its name, Group).
  defp owner_option(%{group: nil} = assigns) do
    assigns = assign(assigns, :name, GamendWeb.LiveHelpers.public_user_name(assigns.user))

    ~H"""
    <.player_card user={@user} name={@name} subtitle={gettext("You")} size="sm" />
    """
  end

  defp owner_option(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2">
      <.group_avatar icon_url={@group.icon_url} class="size-6" />
      <span class="flex min-w-0 flex-col text-start leading-tight">
        <span class="truncate" title={@group.title}>{@group.title}</span>
        <span class="truncate text-xs text-muted">{gettext("Group")}</span>
      </span>
    </div>
    """
  end

  attr :name, :string, required: true, doc: "the name shown, cut where it does not fit"

  attr :user, :any,
    default: nil,
    doc:
      "the `%User{}` behind it (its avatar, its title), or nil: a row with no account (a label)"

  attr :avatar, :any,
    default: nil,
    doc:
      "a row with no account: markup of the caller's where the avatar stands, in the avatar's box (a leaderboard's `row_avatar/2`); nil for the person icon"

  attr :subtitle, :any,
    default: :title,
    doc: "the line under the name: `:title` (default) is `user_title_text/1`, nil or \"\" none"

  attr :subtitle_class, :any,
    default: "text-muted",
    doc:
      "the line's tone: `text-muted`, or nil to take the surrounding colour (on a filled button)"

  attr :you, :boolean,
    default: false,
    doc: "the reader's own: the name bold, a You badge after it"

  attr :size, :string, default: "md", values: ~w(sm md), doc: "the avatar: `sm` 1.5rem, `md` 2rem"
  attr :class, :any, default: nil, doc: "layout only (a width cap, `flex-1`)"
  attr :rest, :global

  slot :inner_block, doc: "after the card's text: a tag of the caller's"

  @doc """
  A player as every list and header draws one: the avatar (the person icon
  for a row with no account behind it, so every row's name starts in the
  same place), the name on one line, cut with an ellipsis where it does not
  fit and whole on hover (`player_name/1`), the host's badge after it
  (`user_badge/1`), and one line under it, the
  host's title for the user (`user_title_text/1`) unless the caller names
  the line itself (a run's language, a made-up runner's mark). The reader's
  own card is bold and says You.

  One component for leaderboards, rosters, the account menu and a host's
  own lists, so a player looks the same wherever they are named.
  """
  def player_card(assigns) do
    line = card_line(assigns.subtitle, assigns.user)

    assigns =
      assign(assigns,
        line: line,
        # Nil asks for the surrounding colour (a filled button): no host look.
        line_class:
          if(assigns.subtitle == :title and assigns.subtitle_class,
            do: user_title_class(assigns.user, line)
          ),
        avatar_class: if(assigns.size == "sm", do: "size-6 shrink-0", else: "size-8 shrink-0")
      )

    ~H"""
    <div class={["flex min-w-0 items-center gap-2", @class]} {@rest}>
      <%!-- A row with no account may bring its own mark (`avatar`), in the
            avatar's box: its font size is the box's, so a 1em mark fills it. --%>
      <span
        :if={@avatar && !@user}
        class={[
          "grid place-items-center overflow-hidden",
          @avatar_class,
          if(@size == "sm", do: "text-2xl", else: "text-[2rem]")
        ]}
      >
        {@avatar}
      </span>
      <.player_avatar :if={!(@avatar && !@user)} user={@user} class={@avatar_class} />
      <span class="flex min-w-0 flex-col text-start leading-tight">
        <span class="flex min-w-0 items-center gap-1">
          <.player_name name={@name} class={["max-w-full", @you && "font-bold"]} />
          <.user_badge user={@user} />
        </span>
        <span
          :if={@line}
          class={["truncate text-xs font-normal", @subtitle_class, @line_class]}
          title={@line}
        >
          {@line}
        </span>
      </span>
      <span :if={@you} class="badge badge-primary badge-sm shrink-0">{gettext("You")}</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp card_line(:title, user), do: user_title_text(user)
  defp card_line(line, _user) when is_binary(line) and line != "", do: line
  defp card_line(_line, _user), do: nil
end
