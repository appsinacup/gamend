defmodule GameServerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: GameServerWeb.Gettext

  alias Phoenix.Component
  alias Phoenix.Flash
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("Close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local utc-datetime-local email file month number
               password search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # A datetime the server stores in UTC but a human enters in their own clock.
  # The named field the form casts always carries UTC; the visible input is a
  # nameless local-time mirror the LocalDatetimeInput hook keeps in sync both
  # ways. Conversion happens in the browser against the *entered* date, so DST
  # is right for a value months out, which a fixed offset sent from the client
  # would get wrong. LiveView needs JS to run at all, so there is no non-JS
  # path to degrade to here.
  def input(%{type: "utc-datetime-local"} = assigns) do
    ~H"""
    <div class="fieldset mb-2" phx-hook="LocalDatetimeInput" id={"#{@id}-local-wrap"}>
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input type="hidden" name={@name} id={@id} value={utc_input_value(@value)} />
        <input
          type="datetime-local"
          data-local-mirror-for={@id}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <p class="text-xs text-base-content/50 mt-1" data-local-zone-note></p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Strict ISO8601 with the offset, because `Date` in the browser parses that
  # everywhere; `DateTime`'s own to_string uses a space and Safari rejects it.
  defp utc_input_value(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp utc_input_value(value) when is_binary(value), do: value
  defp utc_input_value(_value), do: ""

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra">
        <thead>
          <tr>
            <th :for={col <- @col}>{col[:label]}</th>
            <th :if={@action != []}>
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={@row_click && "hover:cursor-pointer"}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="w-0 font-semibold">
              <div class="flex gap-4">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the shared plugin in `apps/game_server_web/assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  The grid card every entity list shares — leaderboards, tournaments, groups,
  quests. One recipe (`bg-base-200`, icon in the title, badges stacked
  top-right, muted two-line description) so the grids read as one family
  instead of four dialects.

      <.entity_card
        navigate={~p"/leaderboards/\#{group.slug}"}
        title={group.title}
        icon_url={group.icon_url}
        type={:leaderboard}
        description={group.description}
      >
        <:badges>
          <span class="badge badge-success">{gettext("Active")}</span>
        </:badges>
      </.entity_card>

  With `navigate` the card is a `<.link>`; without it a `<div>`, and any
  `phx-click`/`title` in `rest` lands on it. `class` appends to the wrapper —
  state borders (`border-success`), `cursor-pointer`, and the like.
  """
  attr :title, :string, required: true
  attr :icon_url, :string, default: nil
  attr :icon, :atom, default: nil

  attr :type, :atom,
    required: true,
    values: [:group, :tournament, :leaderboard, :quest, :notification]

  attr :description, :string, default: nil
  attr :navigate, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :badges
  slot :inner_block

  def entity_card(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link navigate={@navigate} class={[card_classes(), "cursor-pointer", @class]} {@rest}>
      {render_slot_card_body(assigns)}
    </.link>
    """
  end

  def entity_card(assigns) do
    ~H"""
    <div class={[card_classes(), @class]} {@rest}>
      {render_slot_card_body(assigns)}
    </div>
    """
  end

  defp card_classes, do: "card bg-base-200 hover:bg-base-300 transition-colors"

  defp render_slot_card_body(assigns) do
    ~H"""
    <div class="card-body">
      <div class="flex items-start justify-between">
        <h3 class="card-title text-lg">
          <.entity_icon
            icon_url={@icon_url}
            icon={@icon}
            type={@type}
            class="w-6 h-6 shrink-0 text-base-content/60"
          />
          {@title}
        </h3>
        <div :if={@badges != []} class="flex flex-col items-end gap-1 shrink-0">
          {render_slot(@badges)}
        </div>
      </div>

      <p :if={@description not in [nil, ""]} class="text-sm text-base-content/70 line-clamp-2">
        {@description}
      </p>

      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  An entity's icon: the uploaded `icon_url` when set, otherwise the typed
  default for its entity type (`GameServerWeb.Icons.default/1`) — so every
  group, tournament, leaderboard, quest and notification has *some* icon
  without storing one.

  Pass `icon` (any `GameServerWeb.Icons` atom — the full heroicons catalog)
  to override the type default.

  ## Examples

      <.entity_icon icon_url={group.icon_url} type={:group} />
      <.entity_icon icon_url={nil} type={:quest} icon={:fire} />
  """
  attr :icon_url, :string, default: nil
  attr :icon, :atom, default: nil

  attr :type, :atom,
    required: true,
    values: [:group, :tournament, :leaderboard, :quest, :notification]

  # `:any` so callers can pass the usual Phoenix class list; both branches
  # below normalise it the same way.
  attr :class, :any, default: "w-6 h-6"

  def entity_icon(%{icon_url: url} = assigns) when is_binary(url) and url != "" do
    case GameServerWeb.Icons.from_path(url) do
      # One of ours: inline it rather than fetching it back over HTTP, so its
      # `currentColor` follows the theme. In an <img> it would resolve to black
      # and disappear against the dark theme.
      {:ok, icon} -> assigns |> assign(:icon, icon) |> inline_icon()
      :error -> uploaded_icon(assigns)
    end
  end

  def entity_icon(assigns), do: inline_icon(assigns)

  defp uploaded_icon(assigns) do
    ~H"""
    <img src={@icon_url} alt="" loading="lazy" decoding="async" class={[@class, "object-contain"]} />
    """
  end

  defp inline_icon(assigns) do
    icon = assigns.icon || GameServerWeb.Icons.default(assigns.type)

    # Inline SVG, not a `hero-*` class: Tailwind only generates those classes
    # for names it finds literally in source, and this one is chosen at runtime.
    # The class is interpolated into raw markup, so it has to be flattened to a
    # string first — a list would render as one run-on token.
    svg =
      GameServerWeb.Icons.svg(icon)
      |> String.replace("<svg ", ~s|<svg class="#{class_string(assigns.class)}" |, global: false)

    assigns = assign(assigns, :svg, svg)

    ~H"""
    {Phoenix.HTML.raw(@svg)}
    """
  end

  defp class_string(class) do
    class
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.join(" ")
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # Error messages in our forms and APIs are generated dynamically,
    # so we translate them by calling Gettext with our backend.
    # Translations are available in the errors.po file ("errors" domain).
    # We always use dgettext (no plural forms) to keep translations simple.
    Gettext.dgettext(GameServerWeb.Gettext, "errors", msg, opts)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders a stored-UTC timestamp for a human reader.

  The server has no timezone database and no idea where the reader is, so it
  emits the instant in UTC and marks it; `local_time.js` rewrites the text in
  the viewer's own zone and locale once it runs. Without JS the UTC text stands,
  which is why it is labelled rather than left to look local.

  `format` is `"datetime"` (default), `"date"`, `"time"` or `"full"`.

      <.timestamp at={@user.inserted_at} />
      <.timestamp at={@message.inserted_at} format="time" class="text-xs" />
  """
  attr :at, :any, required: true, doc: "a DateTime, or nil to render the dash"
  attr :format, :string, default: "datetime", values: ~w(datetime date time full)
  attr :class, :string, default: nil
  attr :empty, :string, default: "-", doc: "text shown when `at` is nil"

  # Everything this app stores is UTC, so a naive value from a plugin schema is
  # a UTC instant that merely lost its zone on the way here.
  def timestamp(%{at: %NaiveDateTime{} = at} = assigns) do
    assigns |> Map.put(:at, DateTime.from_naive!(at, "Etc/UTC")) |> timestamp()
  end

  def timestamp(%{at: nil} = assigns) do
    ~H"{@empty}"
  end

  # A bare date (blog posts, release dates) has no instant to localize, so it
  # is rendered as-is with no `data-local-time` — shifting it into the
  # reader's zone would move it across midnight boundaries it never crossed.
  def timestamp(%{at: %Date{} = at} = assigns) do
    assigns = assign(assigns, :iso, Date.to_iso8601(at))

    ~H"""
    <time datetime={@iso} class={@class}>{Calendar.strftime(@at, "%b %d, %Y")}</time>
    """
  end

  def timestamp(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@at)} data-local-time={@format} class={@class}>
      {utc_text(@at, @format)}
    </time>
    """
  end

  # Matches what `dateStyle: "medium"` produces in English, so the page does not
  # visibly reflow when the localizer runs. No UTC marker on a date alone: it is
  # an hour shown in the wrong zone that misleads, and the localizer corrects
  # the date across a midnight boundary anyway.
  defp utc_text(at, "date"), do: Calendar.strftime(at, "%b %d, %Y")
  defp utc_text(at, "time"), do: Calendar.strftime(at, "%H:%M UTC")
  defp utc_text(at, "full"), do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S UTC")
  defp utc_text(at, _datetime), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

  @doc """
  Renders a pagination bar with Prev/Next buttons, page info, and optional page-size selector.

  ## Attributes

    * `page` — current page number (required)
    * `total_pages` — total number of pages (required)
    * `total_count` — total number of items (optional, shown in info text)
    * `page_size` — current page size (optional, enables size selector when combined with `on_page_size`)
    * `on_prev` — event name for previous page (required)
    * `on_next` — event name for next page (required)
    * `on_page_size` — event name for page size change (optional, enables size selector)
    * `page_sizes` — list of page size options (default: [25, 50, 100, 200])
    * `class` — additional CSS classes for the container

  ## Usage

      <.pagination
        page={@page}
        total_pages={@total_pages}
        total_count={@count}
        page_size={@page_size}
        on_prev="prev_page"
        on_next="next_page"
        on_page_size="page_size"
      />
  """
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :total_count, :integer, default: nil
  attr :page_size, :integer, default: nil
  attr :on_prev, :string, required: true
  attr :on_next, :string, required: true
  attr :on_page_size, :string, default: nil
  attr :page_sizes, :list, default: [25, 50, 100, 200]
  attr :class, :string, default: nil

  def pagination(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-center gap-2", @class]}>
      <button phx-click={@on_prev} class="btn btn-xs" disabled={@page <= 1}>
        {gettext("Prev")}
      </button>
      <div class="text-xs text-base-content/70">
        <%= if @total_count do %>
          {@page} / {@total_pages} ({@total_count})
        <% else %>
          {@page} / {@total_pages}
        <% end %>
      </div>
      <button
        phx-click={@on_next}
        class="btn btn-xs"
        disabled={@page >= @total_pages || @total_pages == 0}
      >
        {gettext("Next")}
      </button>
      <%= if @on_page_size && @page_size do %>
        <form id={"#{@on_page_size}-form"} phx-change={@on_page_size} class="inline">
          <select
            name="size"
            class="select select-xs select-bordered w-18 ml-2"
          >
            <option :for={size <- @page_sizes} value={size} selected={@page_size == size}>
              {size}
            </option>
          </select>
        </form>
      <% end %>
    </div>
    """
  end

  @doc """
  Display label for a user in admin tables: username, then display name, then the
  raw id as a last resort. Accepts a loaded `%User{}`; `nil` or a not-loaded
  association renders "-". Surface the full id separately (e.g. a `title`
  attribute on the cell) so it stays available without cluttering the table.
  """
  def user_display(%GameServer.Accounts.User{} = user) do
    cond do
      is_binary(user.username) and user.username != "" -> user.username
      is_binary(user.display_name) and user.display_name != "" -> user.display_name
      true -> user.id
    end
  end

  def user_display(_), do: "-"

  @doc """
  A user's avatar as a round image when they have one (`profile_url`), falling
  back to the generic person icon. Pass `class` for sizing, e.g. `"w-5 h-5"`.
  If the image URL fails to load (provider not ready yet, expired CDN link,
  rate-limited avatar CDN), `assets/js/avatar_fallback.js` hides the broken
  image and reveals the same icon. That lives in a real script rather than an
  `onerror` attribute because the CSP here has no `script-src 'unsafe-inline'`,
  so an inline handler is refused and the fallback would never fire.

  `crossorigin="anonymous"` is load-bearing, not decoration: `/play` and
  `/game/*` are served cross-origin isolated for Godot's `SharedArrayBuffer`
  (see `GameServerWeb.Plugs.GameHeaders`), and under
  `Cross-Origin-Embedder-Policy: require-corp` a cross-origin subresource is
  blocked unless it either sends `Cross-Origin-Resource-Policy` or is fetched in
  CORS mode. OAuth avatar CDNs (Google, Discord, Steam, Gravatar) send no CORP
  header but do send `Access-Control-Allow-Origin: *`, so asking for CORS mode
  is what makes them load on those pages. Same-origin and object-storage avatars
  are unaffected — buckets already need CORS for the presigned upload flow.
  """
  attr :user, :any, default: nil
  attr :class, :string, default: "w-6 h-6"

  def user_avatar(assigns) do
    assigns = assign(assigns, :avatar_url, avatar_url(assigns.user))

    ~H"""
    <img
      :if={@avatar_url}
      src={@avatar_url}
      alt=""
      crossorigin="anonymous"
      data-avatar-fallback
      class={["rounded-full object-cover bg-base-300", @class]}
    />
    <.icon :if={@avatar_url} name="hero-user-circle-solid" class={"hidden " <> @class} />
    <.icon :if={!@avatar_url} name="hero-user-circle-solid" class={@class} />
    """
  end

  defp avatar_url(%{profile_url: url}) when is_binary(url) and url != "", do: url
  defp avatar_url(_), do: nil
end
