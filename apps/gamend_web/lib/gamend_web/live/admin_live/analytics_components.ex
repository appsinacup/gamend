defmodule GamendWeb.AdminLive.AnalyticsComponents do
  @moduledoc """
  What every Analytics tab shares: the heading with its tab bar (core's tabs
  and the host's, `Gamend.Analytics.Catalog.tabs/0`), the switches that set a
  URL parameter, the stat tiles and the number formats. A host tab draws
  `analytics_header/1` too, so it reads as one of them:

      <.analytics_header tab="traffic">
        <:controls>…</:controls>
      </.analytics_header>

  Every control is a link that patches the URL: a view is its address, so
  it can be reloaded, bookmarked and sent.
  """
  use Phoenix.Component
  use GamendWeb, :verified_routes

  import GamendWeb.CoreComponents, only: [back_link: 1, page_title: 1, eyebrow: 1, panel: 1]

  alias Gamend.Analytics.Catalog

  @core_tabs [
    %{id: "overview", label: "Overview", path: "/admin/analytics"},
    %{id: "features", label: "Features", path: "/admin/analytics/features"},
    %{id: "explore", label: "Explore", path: "/admin/analytics/explore"},
    %{id: "people", label: "People", path: "/admin/analytics/people"},
    %{id: "counters", label: "Counters", path: "/admin/analytics/counters"},
    %{id: "economy", label: "Economy", path: "/admin/analytics/economy"}
  ]

  @doc "Every tab, core's then the host's."
  @spec tabs() :: [map()]
  def tabs, do: @core_tabs ++ Catalog.tabs()

  attr :tab, :string, required: true, doc: "the id of the tab this page is"
  attr :note, :string, default: nil, doc: "a line under the tabs: what this tab counts"
  slot :controls, doc: "the tab's switches, on the right of the title row"

  @doc "The title row (Back, Analytics, the tab's controls), the tab bar and a note."
  def analytics_header(assigns) do
    assigns = assign(assigns, :tabs, tabs())

    ~H"""
    <header class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <.back_link navigate={~p"/admin"} />
          <.page_title>Analytics</.page_title>
        </div>
        <div :if={@controls != []} class="flex flex-wrap items-center gap-2">
          {render_slot(@controls)}
        </div>
      </div>
      <nav class="tabs tabs-border overflow-x-auto" aria-label="Analytics">
        <.link
          :for={tab <- @tabs}
          navigate={tab.path}
          class={["tab whitespace-nowrap", tab.id == @tab && "tab-active"]}
          aria-current={tab.id == @tab && "page"}
        >
          {tab.label}
        </.link>
      </nav>
      <p :if={@note} class="text-sm text-muted">{@note}</p>
    </header>
    """
  end

  attr :options, :list, required: true, doc: "`[{value, label}]`"
  attr :selected, :any, required: true
  attr :to, :any, required: true, doc: "`fn value -> path end`"
  attr :label, :string, default: nil, doc: "the switch's accessible name"

  @doc "A row of buttons, one per value, each a patch to the page with that value."
  def switch(assigns) do
    ~H"""
    <div class="join" role="group" aria-label={@label}>
      <.link
        :for={{value, label} <- @options}
        patch={@to.(value)}
        class={["btn btn-sm join-item", value == @selected && "btn-active"]}
        aria-current={value == @selected && "true"}
      >
        {label}
      </.link>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :desc, :string, default: nil
  attr :id, :string, default: nil

  @doc "One headline number."
  def stat(assigns) do
    ~H"""
    <.panel compact id={@id}>
      <.eyebrow tag="div">{@title}</.eyebrow>
      <div class="text-2xl font-bold">{@value}</div>
      <div :if={@desc} class="text-xs text-muted">{@desc}</div>
    </.panel>
    """
  end

  @doc "A rate in 0..1 as a percent, `nil` as a dash."
  @spec pct(number() | nil) :: String.t()
  def pct(rate), do: GamendWeb.Charts.format(rate, :percent)

  @doc "A count with thousands separators, `nil` as a dash."
  @spec num(number() | nil) :: String.t()
  def num(n), do: GamendWeb.Charts.format(n, :count)

  @doc """
  `path` with `params` as its query, leaving out empty values and those equal
  to their default in `defaults` (`%{"days" => "30"}`), so the plain page
  has the plain address.
  """
  @spec link_to(String.t(), map(), map()) :: String.t()
  def link_to(path, params, defaults \\ %{}) do
    query =
      params
      |> Enum.flat_map(fn
        {_key, nil} -> []
        {_key, ""} -> []
        {key, %{} = map} -> Enum.map(map, fn {k, v} -> {"#{key}[#{k}]", to_string(v)} end)
        {key, value} -> [{to_string(key), to_string(value)}]
      end)
      |> Enum.reject(fn {key, value} -> Map.get(defaults, key) == value end)
      |> Enum.sort()

    if query == [], do: path, else: path <> "?" <> URI.encode_query(query)
  end

  @doc "An integer parameter, kept only when it is one of `allowed`."
  @spec int_param(map(), String.t(), [integer()], integer()) :: integer()
  def int_param(params, key, allowed, default) do
    case Integer.parse(to_string(params[key] || "")) do
      {n, ""} -> if n in allowed, do: n, else: default
      _ -> default
    end
  end

  @doc "A short id: the first 8 characters."
  @spec short_id(String.t() | nil) :: String.t()
  def short_id(nil), do: "—"
  def short_id(id), do: String.slice(id, 0, 8)
end
