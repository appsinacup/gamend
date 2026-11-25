# `Gamend.Analytics.Catalog`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/catalog.ex#L1)

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

Core adds its own groups (Payments, `payments.`; Accounts, `accounts.`). A name nobody declared
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

`overview/0` (optional) tells the Overview what this game's numbers mean
(`overview/0` below has the keys and the defaults):

    @impl Gamend.Analytics.Catalog
    def overview do
      %{
        retention_since: ~D[2026-10-14],
        activation: %{label: "Finished a round", events: ["web.game.finished"]},
        funnel: [
          %{label: "Search visits", source: {:counter, "web.visit.ref:google"}},
          %{label: "Accounts made", source: :new_accounts},
          %{label: "Paid", source: :payers}
        ],
        trial_keys: ["pro_trial"],
        bands: %{d1: {0.08, 0.2}}
      }
    end

# `groups`

```elixir
@callback groups() :: [map()]
```

# `band`

```elixir
@type band() :: {float(), float()}
```

A rate's bands: low under the first, fair up to the second, good from it.

# `event`

```elixir
@type event() :: %{
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
```

# `funnel_source`

```elixir
@type funnel_source() ::
  {:counter, String.t() | [String.t()]}
  | :new_accounts
  | :registered
  | {:entitlement, String.t() | [String.t()]}
  | {:entitlement_paid, String.t() | [String.t()]}
  | :payers
```

A funnel step's count: a counter's (or several counters') total over the
window, the accounts made in it, those of them registered now, the people
given an entitlement key in it, those of them who paid after it
(`:entitlement_paid`, the step after an `:entitlement` one, so its share
is a trial's conversion), or the payers in it (whatever came before).

# `group`

```elixir
@type group() :: %{
  id: String.t(),
  label: String.t(),
  description: String.t() | nil,
  prefixes: [String.t()]
}
```

# `overview`

```elixir
@type overview() :: %{
  retention_since: Date.t() | nil,
  activation: %{label: String.t(), events: [String.t()]} | nil,
  funnel: [%{label: String.t(), source: funnel_source()}],
  trial_keys: [String.t()],
  traits: [%{field: String.t(), label: String.t()}],
  bands: %{required(atom()) =&gt; band()},
  time: map()
}
```

# `tab`

```elixir
@type tab() :: %{id: String.t(), label: String.t(), path: String.t()}
```

# `events`

```elixir
@callback events() :: [map()]
```

# `overview`
*optional* 

```elixir
@callback overview() :: map()
```

# `tabs`
*optional* 

```elixir
@callback tabs() :: [map()]
```

# `event`

```elixir
@spec event(String.t()) :: event()
```

One name's entry: the declared one, else one derived from the name.

# `events`

```elixir
@spec events() :: [event()]
```

Every declared event and counter, normalized, in declaration order.

# `group`

```elixir
@spec group(String.t()) :: group()
```

A group by id, declared or derived.

# `grouped`

```elixir
@spec grouped([String.t()], keyword()) :: [{group(), [event()]}]
```

`names` (event names or counter keys seen in the data) together with every
declared one, as `[{group, [event]}]`: the declared groups in order with
their events, then the derived groups, alphabetically. A group with no
event is left out. `kind:` (`:event` / `:counter`) keeps one kind of the
declared entries; a name seen is always kept.

# `groups`

```elixir
@spec groups() :: [group()]
```

Every declared group, in order: the host's, then core's. A host group with
a core group's id replaces it.

# `host`

```elixir
@spec host() :: module() | nil
```

The host's catalogue module, or nil.

# `overview`

```elixir
@spec overview() :: overview()
```

What the Overview needs to know about this game, the host's
(`c:overview/0`) over the defaults:

  * `retention_since` — the first sign-up day whose activity is counted in
    full (`Gamend.Analytics.record_activity/2`): earlier cohorts read low
    and are left out of D1 / D7 / D30 and the weekly cohorts. nil: every
    cohort counts.
  * `activation` — `%{label, events}`: a new account is activated when it
    reports one of `events` on the day it was made. nil: no card.
  * `funnel` — the steps, in order (`t:funnel_source/0`). Default:
    accounts made, registered, paid.
  * `trial_keys` — the entitlement keys that are a free trial. Default none.
  * `traits` — `[%{field, label}]`: the event fields the Overview, Time and
    Features tabs filter accounts by (`Gamend.Analytics.Segment.with_trait/2`:
    "Device: phone"), in the order they are listed. Default none.
  * `bands` — per rate (`:stickiness`, `:d1`, `:d7`, `:d30`), `{fair, good}`;
    the host's replace core's one by one.
  * `time` — how the Time tab reads the rows (`Gamend.Analytics.TimeSpent`):
    `idle_seconds` (300: a longer gap between two moments is time away),
    `spans` (`[{first, last}]` event names: the time from the first to the
    last counts, up to `span_seconds`, 7,200), `results` (the area a
    play's moments are filed under, its kind the detail; `"plays"`),
    `dim` (`{field, [event names]}`: those events' area is that field's
    value), `areas` (`%{raw => area}`: a group or field value filed under
    another area) and `labels` (`%{area => label}`; else the group's).

# `tabs`

```elixir
@spec tabs() :: [tab()]
```

The host's extra tabs.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
