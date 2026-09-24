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

The rules against impersonation, which a Unicode handle opens, follow
published standards rather than a list of our own:

  * **Scripts mix as UTS #39 "Highly Restrictive" allows** (Unicode Security
    Mechanisms, section 5.2): one script, or Latin with Chinese, Japanese or
    Korean (Latin + Han + Hiragana + Katakana; Latin + Han + Bopomofo;
    Latin + Han + Hangul). `王wang` and `yamada太郎` pass; `pаypal` with a
    Cyrillic `а` renders as `paypal` and is refused, as is Latin with
    Cyrillic or Greek, or Hangul with kana. Digits and separators belong to
    no script. Chromium applies the same profile to domain names.
  * **Chromium's lookalike patterns.** Mixing Latin with CJK lets `丨` pass
    for `l`, `一` for `-`, `〇` for `o`. `@lookalike` ports the patterns
    Chromium's IDN spoof checker (`idn_spoof_checker.cc`) refuses and a
    handle can hold, character lists and all: those ideographs and Bopomofo
    letters only next to Chinese or Japanese (`一刀` passes, `tom一号` does
    not), `ー` only after kana, look-alike `へ`/`ヘ` inside the other kana,
    and combining marks only where they belong.
  * **No lone Hangul jamo** (`ㅇ`, `ㅣ`). UTS #39 marks the standalone jamo
    Obsolete for identifiers; syllables (`이`) are unaffected.
  * **Combining marks** (UTS #39 section 5.4): decomposed, never the same
    mark twice in a row nor more than four in a row; the stored form also
    caps three per letter. That stops stacked-mark "zalgo" text while
    allowing Vietnamese (`ệ` is two).

Format-control characters (zero-width joiners, direction overrides) are not
letters, so they are refused by the format alone.

# `check_scripts`

```elixir
@spec check_scripts(String.t()) :: :ok | {:error, String.t()}
```

The script, lookalike, jamo and mark rules (see moduledoc) for a
NORMALIZED handle: `:ok`, or `{:error, message}` for the changeset.

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
