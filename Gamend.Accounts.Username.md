# `Gamend.Accounts.Username`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/username.ex#L1)

The username handle's rules, in one place for the changeset and the
generator.

A handle is Unicode: letters and digits of any script, each letter carrying
at most three combining marks, joined by non-consecutive `.` `_` `-` and
starting and ending on a letter or digit. It is stored NFKC-normalized and
lowercased, so the fullwidth `ｄｒａｇｏｓ`, the ligature `ﬁ` and the
precomposed/decomposed forms of `ș` each land on one spelling and the
unique index sees them as the same name.

Two rules exist only to stop impersonation, which a Unicode handle opens:

  * **One script per handle.** `pаypal` with a Cyrillic `а` renders as
    `paypal`. Mixing is refused, except Han with kana (Japanese) and Han
    with Hangul (Korean), where one name legitimately spans scripts. Digits
    and separators belong to no script.
  * **At most three combining marks per letter**, which stops stacked-mark
    "zalgo" text while allowing Vietnamese (`ệ` is two).

Format-control characters (zero-width joiners, direction overrides) are not
letters, so they are refused by the format alone.

# `format`

```elixir
@spec format() :: Regex.t()
```

The format regex (letters, digits, marks, separators).

# `normalize`

```elixir
@spec normalize(String.t()) :: String.t()
```

The spelling a handle is stored and looked up under.

# `single_script?`

```elixir
@spec single_script?(String.t()) :: boolean()
```

Whether a NORMALIZED handle keeps to one script (see moduledoc).

# `valid?`

```elixir
@spec valid?(String.t()) :: boolean()
```

Format, length and script rules together, for a normalized handle.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
