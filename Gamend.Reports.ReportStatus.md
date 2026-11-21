# `Gamend.Reports.ReportStatus`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/reports/report_status.ex#L1)

A report's status before anyone answers it. The other statuses come from the kind.

# `t`

```elixir
@type t() :: String.t()
```

# `all`

```elixir
@spec all() :: [t()]
```

Every value.

# `duplicate`
*macro* 

# `fixed`
*macro* 

# `open`
*macro* 

# `taken`
*macro* 

Never stored: what a filing answers when the report's kind took it
elsewhere (`c:Gamend.Reports.Kind.take/1`), so no row exists.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
