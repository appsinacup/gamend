defmodule GamendWeb.CoreComponents do
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
  use Gettext, backend: GamendWeb.Gettext

  alias Gamend.Accounts.User
  alias Gamend.Captcha
  alias Gamend.OAuth.Providers
  alias Phoenix.Component
  alias Phoenix.Flash
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  attr :name, :string, required: true

  attr :class, :any,
    default: "max-w-[24ch]",
    doc: "width cap; replaced, not merged, so pass the cap you want (`max-w-full` in a sized box)"

  attr :rest, :global

  @doc """
  A player's display name on one line: cut with an ellipsis where it does not
  fit, whole on hover (`title`). A display name may be 255 characters, so any
  place that prints one bare can be pushed wide by a single player.
  """
  def player_name(assigns) do
    ~H"""
    <span class={["inline-block min-w-0 truncate align-bottom", @class]} title={@name} {@rest}>{@name}</span>
    """
  end

  attr :code, :any, required: true, doc: "ISO alpha-2 country code, or nil for none"
  attr :square, :boolean, default: false, doc: "1:1 box instead of 4:3"
  attr :eager, :boolean, default: false, doc: "visible at load: fetch and decode with the page"

  attr :priority, :boolean,
    default: false,
    doc: "site chrome: ahead of the page's other images. Implies `eager`"

  attr :deferred, :boolean,
    default: false,
    doc: "inside a closed dropdown or sheet: fetch when first painted, not at page load"

  attr :class, :any, default: nil

  @doc """
  A country flag.

  An `<img>` rather than a CSS background: the flag-icons plugin inlined all 54
  as base64 data URIs in the critical stylesheet, which made it 951 KB — 69% of
  it flags, blocking the first paint of every page including the ones showing
  none. As files the browser fetches only what is on screen, in parallel, each
  cached on its own.

  Lazy by default because most of a page's flags sit in a closed dropdown.
  But lazy is the wrong default for a flag the reader sees at load — the
  navbar's locale button, a heading, a picker's selected value: the preload
  scanner skips lazy images, the fetch waits for layout, and the decode is
  async, so even a cached flag pops in a frame or two after the text beside
  it. That is the "flash" on every refresh. `eager` opts those few out: the
  browser fetches them with the HTML and paints them with the first frame.

  `priority` is the narrower one, and it implies `eager`: the navbar's locale
  flag is the same two or three pixels on every page of the site, and on a cold
  cache it queued behind whatever that page happened to be full of. It is for
  chrome, not content — a grid of fifty language cards is eager because it *is*
  the page, and marking all fifty high priority would only mean none of them
  are.

  `deferred` is for the ones doing the queueing. `loading="lazy"` buys nothing
  inside a closed dropdown — an `<img>` fetches as soon as the parser sees its
  `src`, and the lazy heuristic is about distance from the viewport, which a
  subtree the browser is not rendering does not have. So the locale picker's
  ~50 options were downloaded on every page load for a panel nobody opened. A
  CSS background is the opposite: it is fetched when the element is first
  *painted*, so a `deferred` flag costs nothing until the panel opens. Use it
  only where the flag is decorative and hidden — it carries no `alt`.

  Sized in `em` so the caller still controls it with a `text-*` class, exactly
  as the old `.fi`/`.fis` classes did.

  No cache-busting query: a page carries up to 114 of these, and a content hash
  on each costs more in HTML than it saves. The artwork is fixed reference
  data — replace a flag by replacing the file and its year-long cache expires
  on its own, which is the one case where that is an acceptable wait.
  """
  def flag(%{deferred: true} = assigns) do
    assigns = assign(assigns, :url, flag_url(assigns.code))

    ~H"""
    <span
      :if={@url}
      aria-hidden="true"
      style={"background-image:url(#{@url})"}
      class={[
        "inline-block h-[1em] shrink-0 bg-contain bg-center bg-no-repeat",
        if(@square, do: "w-[1em]", else: "w-[1.3333em]"),
        @class
      ]}
    />
    """
  end

  def flag(assigns) do
    ~H"""
    <img
      :if={@code}
      src={flag_src(@code)}
      alt=""
      aria-hidden="true"
      loading={if(@eager or @priority, do: "eager", else: "lazy")}
      decoding={if(@eager or @priority, do: "sync", else: "async")}
      fetchpriority={if(@priority, do: "high")}
      class={[
        "inline-block h-[1em] shrink-0 object-contain",
        if(@square, do: "w-[1em]", else: "w-[1.3333em]"),
        @class
      ]}
    />
    """
  end

  # A CSS `url()` is parsed from the attribute *after* HEEx has unescaped it,
  # so escaping is no defence there: a code carrying a quote could close the
  # url and start a rule of its own. Every real code is an ISO alpha-2 or a
  # dashed subdivision ("sh-ac", "es-ga"), so anything else simply renders
  # nothing rather than a URL built from it.
  defp flag_url(code) when is_binary(code) and byte_size(code) in 2..6 do
    if flag_code?(code), do: flag_src(code)
  end

  defp flag_url(_code), do: nil

  # `[a-z0-9-]+`, byte by byte: a regex here ran for every flag on every
  # page (the language menus draw ~160), about 2.5 times the cost.
  defp flag_code?(<<c, rest::binary>>) when c in ?a..?z or c in ?0..?9 or c == ?-,
    do: flag_code?(rest)

  defp flag_code?(<<>>), do: true
  defp flag_code?(_), do: false

  # The WebP a host wrote beside a flag's SVG where it is the smaller file
  # (the reference host's `mix host.flag_rasters`: a flag with a coat of arms
  # is ~50 KB of SVG and 6 ms to draw, ~1.5 KB and 0.1 ms as a 120x90 WebP),
  # else the SVG. Which codes have one is read from the host's
  # `priv/static/flags` once and kept, like the rest of the static files.
  defp flag_src(code) do
    if MapSet.member?(raster_flags(), code),
      do: "/flags/#{code}.webp",
      else: "/flags/#{code}.svg"
  end

  defp raster_flags do
    case :persistent_term.get({__MODULE__, :raster_flags}, nil) do
      nil ->
        flags = load_raster_flags()
        :persistent_term.put({__MODULE__, :raster_flags}, flags)
        flags

      flags ->
        flags
    end
  end

  defp load_raster_flags do
    GamendWeb.host_app()
    |> Application.app_dir("priv/static/flags")
    |> Path.join("*.webp")
    |> Path.wildcard()
    |> Enum.reject(&Regex.match?(~r/-[0-9a-f]{32}\.webp$/, &1))
    |> MapSet.new(&Path.basename(&1, ".webp"))
  end

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

  attr :tag, :string, default: "div", doc: "`section`, `article`, `li`…"
  attr :compact, :boolean, default: false, doc: "`p-3`, not `p-4`: in a list or a sidebar"
  attr :title, :string, default: nil, doc: "a small heading on top (`eyebrow/1`)"

  attr :class, :any,
    default: nil,
    doc: "layout only (`space-y-3`, `flex`), never a colour or padding"

  attr :rest, :global, include: ~w(open action method)
  slot :inner_block, required: true

  @doc """
  A panel: something set on the page, the page's colour behind a `base-300`
  border. The one box every card, form and summary sits in, so a page does
  not grow its own border, radius, padding and shadow.

      <.panel title="Capital">Bucharest</.panel>
      <.panel tag="section" compact class="space-y-3">…</.panel>

  `class` is for layout: a second padding or background would fight the
  panel's own, and which one wins is the stylesheet's order, not the markup's.
  """
  def panel(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={[
        "rounded-box border border-base-300 bg-base-100 shadow-sm",
        if(@compact, do: "p-3", else: "p-4"),
        @class
      ]}
      {@rest}
    >
      <.eyebrow :if={@title}>{@title}</.eyebrow>
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  attr :tag, :string, default: "h1"
  attr :class, :any, default: nil, doc: "layout only (`flex items-center gap-3`), never a size"
  attr :rest, :global
  slot :inner_block, required: true

  @doc """
  A page's title: the one size and weight every page's `<h1>` is drawn in, a
  step smaller on a phone so a heading row with a Back button and a switcher
  still fits one line. `header/1` draws it; a page that builds its own
  heading row uses this rather than restating the classes.
  """
  def page_title(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={["text-3xl font-black text-base-content sm:text-4xl", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  attr :tag, :string, default: "p"
  attr :class, :any, default: nil, doc: "spacing only"
  attr :rest, :global
  slot :inner_block, required: true

  @doc """
  Every heading under a page's title: a section of the page (`tag="h2"`:
  "Level", "Category", "Your tests"), a panel's title, a list's name, a form
  field's label on a dashboard. Small, uppercase, spaced and muted, the one
  way the site says it: a subtitle says less than the title, so a page never
  draws one bigger (`text-xl font-black`) of its own.

      <section class="space-y-2">
        <.eyebrow tag="h2">Category</.eyebrow>
        …
      </section>
  """
  def eyebrow(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={["text-xs font-semibold uppercase tracking-[0.2em] text-muted", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  attr :label, :string, required: true, doc: "the placeholder and the input's accessible name"
  attr :type, :string, default: "search"
  attr :class, :any, default: nil, doc: "on the wrapper: width, flex"
  attr :input_class, :any, default: nil
  attr :close, :any, default: nil, doc: "attributes for an X at the box's end; no X when nil"
  attr :close_label, :string, default: nil
  attr :rest, :global, include: ~w(name value autocomplete role), doc: "on the <input>"

  @doc """
  A search box: the magnifier, the input and, when `close` is given, an X at
  its end. The one search box: the site search palette, a hub's filter and a
  page's own search all draw this, so they cannot drift apart.

      <.search_input label="Search" name="q" value={@q} />
      <.search_input label="Search" close={%{"data-close" => true}} close_label="Close" />

  The icon sits at `start`, not `left` (Arabic reads the other way), and on
  `z-10`: daisyUI's `.input` is positioned, so it painted over an icon before
  it. `autocomplete` is off unless the caller says otherwise. With an X of ours the
  browser's own clear button for `type="search"` is hidden, or a box shows two.
  """
  def search_input(assigns) do
    assigns = update(assigns, :rest, &Map.put_new(&1, :autocomplete, "off"))

    ~H"""
    <div class={["relative", @class]}>
      <.icon
        name="hero-magnifying-glass-solid"
        class="pointer-events-none absolute start-3 top-1/2 z-10 size-4 -translate-y-1/2 opacity-50"
      />
      <input
        type={@type}
        placeholder={@label}
        aria-label={@label}
        class={[
          "input w-full ps-9",
          @close && "pe-10 [&::-webkit-search-cancel-button]:hidden",
          @input_class
        ]}
        {@rest}
      />
      <button
        :if={@close}
        type="button"
        aria-label={@close_label}
        class="btn btn-ghost btn-square btn-sm absolute end-1 top-1/2 -translate-y-1/2"
        {@close}
      >
        <.icon name="hero-x-mark-solid" class="size-4" />
      </button>
    </div>
    """
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
      <p class="text-xs text-muted mt-1" data-local-zone-note></p>
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
  Renders the captcha widget, or nothing when the captcha is disabled.

  Place it inside the form it guards: the widget writes its token into a hidden
  `cf-turnstile-response` input, which arrives in the `phx-submit` params at the
  top level rather than under the form's `as`. Verify it with
  `GamendWeb.UserAuth.verify_captcha/2`.

      <.form for={@form} phx-submit="save">
        <.input field={@form[:email]} type="email" />
        <.captcha id="register_captcha" />
        <.button>Register</.button>
      </.form>

  `id` must be unique on the page — the login page renders two forms, and two
  widgets sharing an id would leave the second one unrendered.
  """
  attr :id, :string, required: true

  def captcha(assigns) do
    assigns = assign(assigns, :site_key, Captcha.enabled?() && Captcha.site_key())

    ~H"""
    <div
      :if={@site_key}
      id={@id}
      phx-hook="Captcha"
      phx-update="ignore"
      data-sitekey={@site_key}
      class="my-2"
    >
    </div>
    """
  end

  @doc """
  Social sign-in buttons for every enabled OAuth provider, preceded by an
  "or" divider. Renders nothing when no provider is enabled, so the auth
  forms need no branching of their own.

      <.oauth_buttons action={:login} />

  The label names the provider ("Log in with Discord"), so a row of buttons
  does not read as the same word five times.
  """
  attr :action, :atom, values: [:login, :register], required: true

  def oauth_buttons(assigns) do
    assigns = assign(assigns, :providers, Providers.enabled())

    ~H"""
    <div :if={@providers != []}>
      <div class="divider">{gettext("or")}</div>

      <%!-- One column until lg: the form is max-w-sm below that, and a named
           label ("Log in with Facebook") does not fit half of it. --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.link
          :for={provider <- @providers}
          href={"/auth/#{provider}"}
          class="btn btn-neutral w-full h-auto min-h-10 py-2 whitespace-normal flex items-center justify-center gap-2"
        >
          <.oauth_icon provider={provider} />
          {oauth_label(@action, oauth_name(provider))}
        </.link>
      </div>
    </div>
    """
  end

  defp oauth_label(:login, name), do: gettext("Log in with %{provider}", provider: name)
  defp oauth_label(:register, name), do: gettext("Register with %{provider}", provider: name)

  # Brand names: never translated.
  defp oauth_name(:discord), do: "Discord"
  defp oauth_name(:google), do: "Google"
  defp oauth_name(:apple), do: "Apple"
  defp oauth_name(:facebook), do: "Facebook"
  defp oauth_name(:github), do: "GitHub"
  defp oauth_name(:steam), do: "Steam"

  attr :provider, :atom, required: true

  defp oauth_icon(%{provider: :discord} = assigns) do
    ~H"""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path d="M20.317 4.492c-1.53-.69-3.17-1.2-4.885-1.49a.075.075 0 0 0-.079.036c-.21.369-.444.85-.608 1.23a18.566 18.566 0 0 0-5.487 0 12.36 12.36 0 0 0-.617-1.23A.077.077 0 0 0 8.562 3c-1.714.29-3.354.8-4.885 1.491a.07.07 0 0 0-.032.027C.533 9.093-.32 13.555.099 17.961a.08.08 0 0 0 .031.055 20.03 20.03 0 0 0 5.993 2.98.078.078 0 0 0 .084-.026 13.83 13.83 0 0 0 1.226-1.963.074.074 0 0 0-.041-.104 13.201 13.201 0 0 1-1.872-.878.075.075 0 0 1-.008-.125c.126-.093.252-.19.372-.287a.075.075 0 0 1 .078-.01c3.927 1.764 8.18 1.764 12.061 0a.075.075 0 0 1 .079.009c.12.098.245.195.372.288a.075.075 0 0 1-.006.125c-.598.344-1.22.635-1.873.877a.075.075 0 0 0-.041.105c.36.687.772 1.341 1.225 1.962a.077.077 0 0 0 .084.028 19.963 19.963 0 0 0 6.002-2.981.076.076 0 0 0 .032-.054c.5-5.094-.838-9.52-3.549-13.442a.06.06 0 0 0-.031-.028zM8.02 15.278c-1.182 0-2.157-1.069-2.157-2.38 0-1.312.956-2.38 2.157-2.38 1.21 0 2.176 1.077 2.157 2.38 0 1.312-.956 2.38-2.157 2.38zm7.975 0c-1.183 0-2.157-1.069-2.157-2.38 0-1.312.955-2.38 2.157-2.38 1.21 0 2.176 1.077 2.157 2.38 0 1.312-.946 2.38-2.157 2.38z" />
    </svg>
    """
  end

  defp oauth_icon(%{provider: :apple} = assigns) do
    ~H"""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
      <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09l.01-.01zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
    </svg>
    """
  end

  defp oauth_icon(%{provider: :google} = assigns) do
    ~H"""
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
        fill="#4285F4"
      />
      <path
        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
        fill="#34A853"
      />
      <path
        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
        fill="#FBBC05"
      />
      <path
        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
        fill="#EA4335"
      />
    </svg>
    """
  end

  defp oauth_icon(%{provider: :facebook} = assigns) do
    ~H"""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
      <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z" />
    </svg>
    """
  end

  defp oauth_icon(%{provider: :github} = assigns) do
    ~H"""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
      <path d="M12 .3a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.4-1.8-1.4-1.8-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 0-.8.4-1.3.7-1.6-2.7-.3-5.5-1.3-5.5-6 0-1.2.5-2.3 1.3-3.1-.2-.4-.6-1.6.1-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0c2.3-1.5 3.3-1.2 3.3-1.2.7 1.6.2 2.8.1 3.2.8.8 1.3 1.9 1.3 3.2 0 4.6-2.8 5.6-5.5 5.9.5.4.9 1.1.9 2.3v3.3c0 .3.1.7.8.6A12 12 0 0 0 12 .3" />
    </svg>
    """
  end

  defp oauth_icon(%{provider: :steam} = assigns) do
    ~H"""
    <svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path d="M11.979 0C5.678 0 .511 4.86.022 11.037l6.432 2.658c.545-.371 1.203-.59 1.912-.59.063 0 .125.004.188.006l2.861-4.142V8.91c0-2.495 2.028-4.524 4.524-4.524 2.494 0 4.524 2.031 4.524 4.527s-2.03 4.525-4.524 4.525h-.105l-4.076 2.911c0 .052.004.105.004.159 0 1.875-1.515 3.396-3.39 3.396-1.635 0-3.016-1.173-3.331-2.727L.436 15.27C1.862 20.307 6.486 24 11.979 24c6.627 0 11.999-5.373 11.999-12S18.605 0 11.979 0zM7.54 18.21l-1.473-.61c.262.543.714.999 1.314 1.25 1.297.539 2.793-.076 3.332-1.375.263-.63.264-1.319.005-1.949s-.75-1.121-1.377-1.383c-.624-.26-1.29-.249-1.878-.03l1.523.63c.956.4 1.409 1.5 1.009 2.455-.397.957-1.497 1.41-2.454 1.012H7.54zm11.415-9.303c0-1.662-1.353-3.015-3.015-3.015-1.665 0-3.015 1.353-3.015 3.015 0 1.665 1.35 3.015 3.015 3.015 1.663 0 3.015-1.35 3.015-3.015zm-5.273-.005c0-1.252 1.013-2.266 2.265-2.266 1.249 0 2.266 1.014 2.266 2.266 0 1.251-1.017 2.265-2.266 2.265-1.253 0-2.265-1.014-2.265-2.265z" />
    </svg>
    """
  end

  @doc """
  Renders a page header: the `<h1>` in the one style every page title uses
  (`text-4xl font-black text-base-content`), an optional subtitle and
  actions.

  The inner block IS the title text — pass words, an icon, a badge; never
  another `<h1>`. A heading start tag inside an open heading is a parse error
  the browser recovers from by closing the outer one first, so the page ended
  up with an empty `<h1>` followed by the real one.

  `class` extends the title (`flex items-center gap-3` for an icon,
  `break-all` for an unbreakable string) — it does not replace the size, so
  every page stays the same size without each caller restating it.
  """
  attr :class, :any, default: nil, doc: "extra classes on the <h1>"

  attr :back, :string,
    default: nil,
    doc: "live path to go up to; renders a Back button on the title's own line"

  attr :back_href, :string,
    default: nil,
    doc: "the same for a plain page (`home_path/0`), followed with a full load"

  attr :back_label, :string, default: nil, doc: ~s(overrides the "Back" wording)
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <%!-- The back button sits ON the title line, not above it as a stray
              text link: one place, one shape, on every page that has a parent. --%>
        <div :if={@back || @back_href} class="flex flex-wrap items-center gap-3">
          <.back_link navigate={@back} href={@back_href} label={@back_label} />
          <.page_title class={@class}>{render_slot(@inner_block)}</.page_title>
        </div>
        <.page_title :if={!(@back || @back_href)} class={@class}>
          {render_slot(@inner_block)}
        </.page_title>
        <p :if={@subtitle != []} class="mt-1 text-sm text-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  attr :href, :string, default: nil, doc: "a plain page"
  attr :navigate, :string, default: nil, doc: "a live route"
  attr :label, :string, default: nil, doc: ~s(overrides the "Back" wording)
  attr :class, :any, default: "btn btn-ghost btn-sm max-sm:btn-circle sm:btn-surface"

  @doc """
  The Back button: one step up the page's own trail, which the browser's
  Back is not (it goes wherever the reader came from). Every page under
  home has one at the start of its title row, the page one step under home
  pointing at `home_path/0`.

  The word from `sm` up; a phone gets the arrow alone, which is the whole
  meaning, and the room goes to the heading. `sr-only`, not `hidden`, so it
  stays the link's name. The arrow is mirrored in a right-to-left locale
  rather than swapped for another icon.

  Pass `navigate` for a live route and `href` for a plain page; a LiveView
  that sends `navigate` at a dead route breaks on the way out.
  """
  def back_link(assigns) do
    ~H"""
    <.link navigate={@navigate} href={@href} class={@class} title={@label || gettext("Back")}>
      <.icon name="hero-arrow-left-solid" class="size-4 rtl:-scale-x-100" />
      <span class="sr-only sm:not-sr-only">{@label || gettext("Back")}</span>
    </.link>
    """
  end

  @doc """
  The home page in the reader's locale (`/de`, `/` in the default one):
  where Back goes on a page one step under it. A plain page, so pass it to
  `back_link/1` as `href`.
  """
  @spec home_path() :: String.t()
  def home_path,
    do: GamendWeb.HostLayouts.localized_href("/", GamendWeb.HostLayouts.current_locale())

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
  your compiled app.css by the shared plugin in `apps/gamend_web/assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ms-1 size-3 motion-safe:animate-spin" />
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
        <%!-- `h2`: a list of these sits straight under the page's `h1`
              (leaderboards, quests, groups), and an `h3` there skips a
              level (axe `heading-order`). The look is the classes'. --%>
        <h2 class="card-title text-lg">
          <.entity_icon
            icon_url={@icon_url}
            icon={@icon}
            type={@type}
            class="w-6 h-6 shrink-0 text-muted"
          />
          {@title}
        </h2>
        <div :if={@badges != []} class="flex flex-col items-end gap-1 shrink-0">
          {render_slot(@badges)}
        </div>
      </div>

      <p :if={@description not in [nil, ""]} class="text-sm text-muted line-clamp-2">
        {@description}
      </p>

      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  An entity's icon: the uploaded `icon_url` when set, otherwise the typed
  default for its entity type (`GamendWeb.Icons.default/1`) — so every
  group, tournament, leaderboard, quest and notification has *some* icon
  without storing one.

  Pass `icon` (any `GamendWeb.Icons` atom — the full heroicons catalog)
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
    case GamendWeb.Icons.from_path(url) do
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
    icon = assigns.icon || GamendWeb.Icons.default(assigns.type)

    # Inline SVG, not a `hero-*` class: Tailwind only generates those classes
    # for names it finds literally in source, and this one is chosen at runtime.
    # The class is interpolated into raw markup, so it has to be flattened to a
    # string first — a list would render as one run-on token.
    svg =
      GamendWeb.Icons.svg(icon)
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

  @doc """
  The "there is nothing here" box: nothing yet, nothing matched, or nothing
  without an account. A dashed border, so it reads as a gap rather than as
  content, with an optional icon, a heading, a line of prose and the way on.

  For a page or a list that legitimately has no content — no changelog file,
  no results, an empty list — not for an error. Both halves of the copy are
  attributes, and both should be translated: the `text` on the changelog page
  was an English literal on every host for exactly as long as it was written
  inline. `compact` is a small note inside something else, left-aligned.

  ## Example

      <.empty_state
        icon="hero-document-text"
        title={gettext("No results.")}
        text={gettext("Add a changelog file at CHANGELOG.md to display it here.")}
      />

      <.empty_state title={gettext("Log in to keep your tests")}>
        <:actions><.link navigate={~p"/users/log_in"} class="btn btn-primary btn-sm">Log in</.link></:actions>
      </.empty_state>
  """
  attr :icon, :string, default: nil
  attr :title, :string, required: true
  attr :text, :string, default: nil
  attr :compact, :boolean, default: false
  attr :class, :any, default: nil, doc: "spacing only"
  attr :rest, :global
  slot :actions, doc: "what to do about it: a button or two"

  def empty_state(assigns) do
    ~H"""
    <div
      class={[
        "rounded-box border border-dashed border-base-300",
        if(@compact, do: "p-3", else: "p-6 text-center"),
        @class
      ]}
      {@rest}
    >
      <.icon :if={@icon} name={@icon} class="mx-auto mb-3 size-12 text-muted" />
      <p class={if @compact, do: "text-sm font-semibold", else: "font-bold"}>{@title}</p>
      <p :if={@text} class="mt-1 text-sm text-muted">{@text}</p>
      <div :if={@actions != []} class={["mt-3 flex flex-wrap gap-2", !@compact && "justify-center"]}>
        {render_slot(@actions)}
      </div>
    </div>
    """
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
    Gettext.dgettext(GamendWeb.Gettext, "errors", msg, opts)
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

  # A bare date (blog posts, release dates) has no instant to localize, and
  # shifting it into the reader's zone would move it across midnight boundaries
  # it never crossed. It used to skip the localizer for that reason, which left
  # it in English for every reader. `calendar-date` translates it with the zone
  # pinned to UTC, so it changes language without changing day.
  def timestamp(%{at: %Date{} = at} = assigns) do
    assigns = assign(assigns, :iso, Date.to_iso8601(at))

    ~H"""
    <time datetime={@iso} data-local-time="calendar-date" class={@class}>
      {Calendar.strftime(@at, "%b %-d, %Y")}
    </time>
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
  # `%-d`, not `%d`: "Sep 8", as `dateStyle: "medium"` writes it, not "Sep 08".
  defp utc_text(at, "date"), do: Calendar.strftime(at, "%b %-d, %Y")
  defp utc_text(at, "time"), do: Calendar.strftime(at, "%H:%M UTC")
  defp utc_text(at, "full"), do: Calendar.strftime(at, "%Y-%m-%d %H:%M:%S UTC")
  defp utc_text(at, _datetime), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  # ---------------------------------------------------------------------------
  # Pagination
  # ---------------------------------------------------------------------------

  @doc """
  Renders a pagination bar with Prev/Next buttons, page info, and optional page-size selector.

  Renders **nothing** when the list fits on one page: two dead buttons and a
  "1 / 1" counter are noise on every short list in the app. The size selector
  survives a one-page list when a smaller size would actually split it —
  otherwise raising the size until everything fits would hide the only control
  that undoes it.

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

  attr :value, :map,
    default: %{},
    doc: "extra phx-value-* pairs sent with every event, e.g. which section the list belongs to"

  attr :class, :string, default: nil

  def pagination(assigns) do
    assigns =
      assigns
      |> assign(:multi_page?, assigns.total_pages > 1)
      |> assign(:show_page_size?, show_page_size?(assigns))
      |> assign(
        :value_attrs,
        Map.new(assigns.value, fn {key, val} -> {"phx-value-#{key}", val} end)
      )

    ~H"""
    <div
      :if={@multi_page? || @show_page_size?}
      class={["flex flex-wrap items-center gap-2", @class]}
    >
      <button
        :if={@multi_page?}
        phx-click={@on_prev}
        class="btn btn-xs"
        disabled={@page <= 1}
        {@value_attrs}
      >
        {gettext("Prev")}
      </button>
      <div :if={@multi_page?} class="text-xs text-muted">
        <%= if @total_count do %>
          {@page} / {@total_pages} ({@total_count})
        <% else %>
          {@page} / {@total_pages}
        <% end %>
      </div>
      <button
        :if={@multi_page?}
        phx-click={@on_next}
        class="btn btn-xs"
        disabled={@page >= @total_pages}
        {@value_attrs}
      >
        {gettext("Next")}
      </button>
      <form
        :if={@show_page_size?}
        id={"#{@on_page_size}-form"}
        phx-change={@on_page_size}
        phx-no-unused-field
        class="inline"
      >
        <input :for={{key, val} <- @value} type="hidden" name={key} value={val} />
        <select
          name="size"
          class="select select-xs select-bordered w-18 ms-2"
        >
          <option :for={size <- @page_sizes} value={size} selected={@page_size == size}>
            {size}
          </option>
        </select>
      </form>
    </div>
    """
  end

  defp show_page_size?(%{on_page_size: on_page_size, page_size: page_size})
       when is_nil(on_page_size) or is_nil(page_size),
       do: false

  defp show_page_size?(%{total_pages: total_pages}) when total_pages > 1, do: true

  defp show_page_size?(%{page_size: page_size, page_sizes: page_sizes, total_count: total_count}) do
    smallest = if page_sizes == [], do: page_size, else: Enum.min(page_sizes)

    # One page at the current size: only worth offering when a smaller size
    # would split the list. Without a count, fall back to "a smaller size exists".
    if is_nil(total_count), do: page_size > smallest, else: total_count > smallest
  end

  @doc """
  Display label for a user in admin tables: username, then display name, then the
  raw id as a last resort. Accepts a loaded `%User{}`; `nil` or a not-loaded
  association renders "-". Surface the full id separately (e.g. a `title`
  attribute on the cell) so it stays available without cluttering the table.
  """
  def user_display(%Gamend.Accounts.User{} = user) do
    cond do
      is_binary(user.username) and user.username != "" -> user.username
      is_binary(user.display_name) and user.display_name != "" -> user.display_name
      true -> user.id
    end
  end

  def user_display(_), do: "-"

  @doc """
  The game's own line under a player's name — a rank, a title, a guild — read
  from a metadata path the host configures:

      config :gamend_web, :user_title_meta_path, ["player", "rank"]

  Core knows nothing about what a rank IS; it only knows where the host keeps
  it. Renders nothing when the path is unset, the user has no metadata, or the
  value is blank, so a fresh account shows a bare name rather than an empty
  badge. Takes a `%User{}`, a metadata map, or `nil`.

  One component so every place that names a player — leaderboards, tournament
  rosters, party lists, profile cards — says the same thing about them, and a
  host that changes where the title lives changes one config key.
  """
  attr :user, :any, required: true
  attr :class, :string, default: "text-xs text-muted"

  def user_title(assigns) do
    assigns = assign(assigns, :title, user_title_text(assigns.user))

    ~H"""
    <span :if={@title} class={@class}>{@title}</span>
    """
  end

  @doc "The title text `user_title/1` renders, or nil. Exposed for plain-text callers."
  def user_title_text(user) do
    with [_ | _] = path <- Application.get_env(:gamend_web, :user_title_meta_path),
         %{} = metadata <- user_metadata(user),
         value when is_binary(value) and value != "" <- get_in(metadata, path) do
      value
    else
      _ -> nil
    end
  end

  defp user_metadata(%Gamend.Accounts.User{metadata: %{} = metadata}), do: metadata
  defp user_metadata(%{metadata: %{} = metadata}), do: metadata
  defp user_metadata(%{"metadata" => %{} = metadata}), do: metadata
  defp user_metadata(%{} = maybe_metadata), do: maybe_metadata
  defp user_metadata(_), do: nil

  @doc """
  A user's avatar as a round image when they have one we host
  (`User.public_avatar_url/1`), falling back to the generic person icon. A
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
    assigns = assign(assigns, :avatar_url, User.public_avatar_url(assigns.user))

    ~H"""
    <%!-- no-referrer: a storage CDN on another origin has no need to learn
          which page showed the avatar. --%>
    <img
      :if={@avatar_url}
      src={@avatar_url}
      alt=""
      crossorigin="anonymous"
      referrerpolicy="no-referrer"
      data-avatar-fallback
      class={["rounded-full object-cover bg-base-300", @class]}
    />
    <.icon :if={@avatar_url} name="hero-user-circle-solid" class={"hidden " <> @class} />
    <.icon :if={!@avatar_url} name="hero-user-circle-solid" class={@class} />
    """
  end
end
