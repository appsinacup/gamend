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

Against impersonation, which a Unicode handle opens, it applies two clauses
of UTS #39 (Unicode Security Mechanisms), the standard browsers apply to
international domain names:

  * **Section 5.2, "Highly Restrictive" script mixing.** One script, or
    Latin with Chinese, Japanese or Korean (Latin + Han + Hiragana +
    Katakana; Latin + Han + Bopomofo; Latin + Han + Hangul). `王wang` and
    `yamada太郎` pass. `pаypal` with a Cyrillic `а` renders as `paypal` and
    is refused, as is any mix of Latin, Cyrillic and Greek, which share
    dozens of identical letters. Digits and separators belong to no script.
  * **Section 5.4, combining marks.** Decomposed, never the same mark twice
    in a row nor more than four in a row (`café` with the accent typed
    twice renders as `café`); the stored form also caps three per letter.
    That stops stacked-mark "zalgo" text while allowing Vietnamese (`ệ` is
    two).

Nothing else: a CJK letter that resembles a Latin one (`丨` for `l`, `ㅇ`
for `o`) is no more confusable than `1` and `0`, which any ASCII handle
holds. Format-control characters (zero-width joiners, direction overrides)
are not letters, so the format refuses them.

`GAMEND_LIMITS_USERNAME_ASCII_ONLY=true` keeps handles to `a-z`, `0-9` and
the separators, the GitHub and Discord model, after the same normalization
(`ＷＡＮＧ` is still `wang`); the generator then transliterates or picks a
word.

# `check_scripts`

```elixir
@spec check_scripts(String.t()) :: :ok | {:error, String.t()}
```

The ASCII-only, script and mark rules (see moduledoc) for a NORMALIZED
handle: `:ok`, or `{:error, message}` for the changeset.

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

# `valid?`

```elixir
@spec valid?(String.t()) :: boolean()
```

Format, length and script rules together, for a normalized handle.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
