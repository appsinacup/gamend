defmodule Gamend.Analytics.Catalog do
  @moduledoc """
  What the analytics a game reports MEAN: which events and counters there
  are, what each is called, which group it belongs to, which of its fields
  are dimensions (a closed set to filter and break down by) and which are
  numbers (to average). The admin Analytics pages read it to group, label
  and offer filters; nothing is stored by it.

  A host declares its own with a module implementing this behaviour:

      config :gamend_core, :analytics_catalog, MyGame.Analytics

      @impl Gamend.Analytics.Catalog
      def groups, do: [%{id: "games", label: "Word games", prefixes: ["web.game."]}]

      @impl Gamend.Analytics.Catalog
      def events do
        [
          %{
            name: "web.game.finished",
            group: "games",
            label: "Round finished",
            dims: [game: "Game", lang: "Language"],
            measures: [score: "Score", total: "Questions"],
            rates: [{"score", "total", "Score"}]
          }
        ]
      end

  Core adds its own group (Payments, `payments.`). A name nobody declared
  still shows: in the group whose prefix it starts with, else in a group of
  its own made of its first two segments (`web.game.started` →
  `web.game`), labelled with the name itself. With no host catalogue that
  is every name, which is the page as it was before catalogues.

  An event `kind` is `:event` (reported with `Gamend.Analytics.track/3`:
  counted, and kept as a row for an account) or `:counter` (counted only,
  `Gamend.Analytics.count/3`: a visitor's page, a 404, a webhook).

  `tabs/0` (optional) adds the host's own pages to the Analytics tab bar:
  `[%{id: "traffic", label: "Traffic", path: "/admin/analytics/traffic"}]`.
  A host page draws the same bar with
  `GamendWeb.AdminLive.AnalyticsComponents.analytics_header/1`.
  """

  @type group :: %{
          id: String.t(),
          label: String.t(),
          description: String.t() | nil,
          prefixes: [String.t()]
        }

  @type event :: %{
          name: String.t(),
          group: String.t(),
          label: String.t(),
          description: String.t() | nil,
          kind: :event | :counter,
          dims: [{String.t(), String.t()}],
          measures: [{String.t(), String.t()}],
          rates: [{String.t(), String.t(), String.t()}],
          declared: boolean()
        }

  @type tab :: %{id: String.t(), label: String.t(), path: String.t()}

  @callback groups() :: [map()]
  @callback events() :: [map()]
  @callback tabs() :: [map()]
  @optional_callbacks tabs: 0

  @core_groups [
    %{
      id: "payments",
      label: "Payments",
      description: "Checkouts, purchases, subscriptions, refunds and webhooks (Gamend.Payments).",
      prefixes: ["payments."]
    }
  ]

  @doc "The host's catalogue module, or nil."
  @spec host() :: module() | nil
  def host, do: Application.get_env(:gamend_core, :analytics_catalog)

  @doc """
  Every declared group, in order: the host's, then core's. A host group with
  a core group's id replaces it.
  """
  @spec groups() :: [group()]
  def groups do
    host = host_call(:groups, [])
    ids = MapSet.new(host, &to_string(&1.id))

    (host ++ Enum.reject(@core_groups, &MapSet.member?(ids, &1.id)))
    |> Enum.map(&normalize_group/1)
  end

  @doc "Every declared event and counter, normalized, in declaration order."
  @spec events() :: [event()]
  def events, do: Enum.map(host_call(:events, []), &normalize_event/1)

  @doc "The host's extra tabs."
  @spec tabs() :: [tab()]
  def tabs do
    :tabs
    |> host_call([])
    |> Enum.map(fn tab ->
      %{id: to_string(tab.id), label: to_string(tab.label), path: to_string(tab.path)}
    end)
  end

  @doc "One name's entry: the declared one, else one derived from the name."
  @spec event(String.t()) :: event()
  def event(name) when is_binary(name) do
    Enum.find(events(), &(&1.name == name)) || derived(name, groups())
  end

  @doc """
  `names` (event names or counter keys seen in the data) together with every
  declared one, as `[{group, [event]}]`: the declared groups in order with
  their events, then the derived groups, alphabetically. A group with no
  event is left out. `kind:` (`:event` / `:counter`) keeps one kind of the
  declared entries; a name seen is always kept.
  """
  @spec grouped([String.t()], keyword()) :: [{group(), [event()]}]
  def grouped(names, opts \\ []) do
    groups = groups()
    declared = events()
    kind = Keyword.get(opts, :kind)
    seen = MapSet.new(names)

    entries =
      Enum.filter(declared, &(is_nil(kind) or &1.kind == kind or MapSet.member?(seen, &1.name))) ++
        (names
         |> Enum.uniq()
         |> Enum.reject(fn name -> Enum.any?(declared, &(&1.name == name)) end)
         |> Enum.sort()
         |> Enum.map(&derived(&1, groups)))

    by_group = Enum.group_by(entries, & &1.group)

    declared_groups =
      for group <- groups, events = Map.get(by_group, group.id), do: {group, events}

    derived_groups =
      by_group
      |> Map.drop(Enum.map(groups, & &1.id))
      |> Enum.sort_by(fn {id, _} -> id end)
      |> Enum.map(fn {id, events} -> {derived_group(id), events} end)

    declared_groups ++ derived_groups
  end

  @doc "A group by id, declared or derived."
  @spec group(String.t()) :: group()
  def group(id) when is_binary(id),
    do: Enum.find(groups(), &(&1.id == id)) || derived_group(id)

  # ── derivation ──────────────────────────────────────────────────────────

  defp derived(name, groups) do
    %{
      name: name,
      group: group_for(name, groups),
      label: name,
      description: nil,
      kind: :event,
      dims: [],
      measures: [],
      rates: [],
      declared: false
    }
  end

  # The declared group with the longest prefix the name starts with, else
  # the name's first two segments.
  defp group_for(name, groups) do
    groups
    |> Enum.flat_map(fn g -> Enum.map(g.prefixes, &{&1, g.id}) end)
    |> Enum.filter(fn {prefix, _} -> String.starts_with?(name, prefix) end)
    |> Enum.max_by(fn {prefix, _} -> byte_size(prefix) end, fn -> nil end)
    |> case do
      {_prefix, id} -> id
      nil -> name |> String.split(".") |> Enum.take(2) |> Enum.join(".")
    end
  end

  defp derived_group(id),
    do: %{id: id, label: id, description: nil, prefixes: [id <> "."]}

  # ── normalization ───────────────────────────────────────────────────────

  defp normalize_group(group) do
    group = Map.new(group)

    %{
      id: to_string(group.id),
      label: to_string(group.label),
      description: Map.get(group, :description),
      prefixes: group |> Map.get(:prefixes, []) |> Enum.map(&to_string/1)
    }
  end

  defp normalize_event(event) do
    event = Map.new(event)

    %{
      name: to_string(event.name),
      group: to_string(event.group),
      label: to_string(Map.get(event, :label, event.name)),
      description: Map.get(event, :description),
      kind: Map.get(event, :kind, :event),
      dims: pairs(Map.get(event, :dims, [])),
      measures: pairs(Map.get(event, :measures, [])),
      rates:
        event
        |> Map.get(:rates, [])
        |> Enum.map(fn {num, den, label} ->
          {to_string(num), to_string(den), to_string(label)}
        end),
      declared: true
    }
  end

  defp pairs(list) do
    Enum.map(list, fn
      {key, label} -> {to_string(key), to_string(label)}
      key -> {to_string(key), to_string(key)}
    end)
  end

  defp host_call(fun, default) do
    case host() do
      nil ->
        default

      module ->
        if Code.ensure_loaded?(module) and function_exported?(module, fun, 0),
          do: apply(module, fun, []),
          else: default
    end
  end
end
