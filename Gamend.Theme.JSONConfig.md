# `Gamend.Theme.JSONConfig`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/theme/json_config.ex#L1)

JSON-backed Theme provider. Reads **one** config file — from the
`GAMEND_CONTENT_THEME_CONFIG` setting or the host-owned default path — and
translates its text through gettext at read time.

Structure (urls, icons, layout) lives once, so a field added to the config
reaches every locale, and only the leaves `Gamend.Theme.Translatable` names
as text vary by locale, through the `theme` gettext domain like every other
string in the UI.

A missing translation falls back to the source string, so a config with no
`.po` at all still renders exactly as written.

The decoded file is cached in `:persistent_term`; translation happens per
read, against the caller's current locale. Call `reload/0` after editing the
file at runtime.

`reload/0` emits the telemetry event `[:gamend, :theme, :reload]` once the
cache is cleared, so work derived from the file can follow it without core
knowing who does it: the web app cuts the responsive image variants a new
config asks for (`GamendWeb.ResponsiveImages`).

# `active_path`

Returns the effective theme config path, preferring GAMEND_CONTENT_THEME_CONFIG when set and
otherwise falling back to the host-owned default path.

# `get_theme`

```elixir
@spec get_theme(String.t() | nil) :: map()
```

The theme, with its text translated into `locale` (or the caller's current
locale when `nil`).

Locale fallback is gettext's, not ours: `es_ES` falls back to `es` and then
to the source string, so this never has to hunt for a file that might exist.

# `raw_theme`

```elixir
@spec raw_theme() :: map()
```

The config exactly as written, untranslated.

For the extractor and for admin diagnostics, which must show what is on
disk rather than what a viewer would see.

# `runtime_path`

Returns the runtime GAMEND_CONTENT_THEME_CONFIG override if present and non-blank,
otherwise nil. This intentionally excludes the host default path so admin
diagnostics can distinguish explicit overrides from host defaults.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
