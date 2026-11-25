# `Gamend.Reports.ReportSource`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/reports/report_source.ex#L1)

Where a report was filed from: core's report page (`web`), the API
(`api`), or the host's own code (`host`), for a kind no form of core's
files (`c:Gamend.Reports.Kind.sources/0`): an in-game survey, a form on a
page of the host's.

# `t`

```elixir
@type t() :: String.t()
```

# `all`

```elixir
@spec all() :: [t()]
```

Every value.

# `api`
*macro* 

# `host`
*macro* 

# `web`
*macro* 

---

*Consult [api-reference.md](api-reference.md) for complete listing*
