# `Gamend.MatchSeating`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/match_seating.ex#L1)

What a game decides for a formed match: where its players sit, and whether
they are asked first. `matchmaking_seat_match/1` answers with one:

    def matchmaking_seat_match(tickets) do
      case room_with_a_free_seat(tickets) do
        nil -> MatchSeating.new_lobby(max_users: 10, accept_timeout_ms: 15_000)
        lobby_id -> MatchSeating.in_lobby(lobby_id)
      end
    end

Every answer is built by a function here, so a misspelt name fails where it
is written: a function the compiler does not know, or an option that raises.
Core does the rest: it seats the players, checks seats and blocks, and puts
the tickets back in the queue when it cannot.

Pure, and the SDK carries a copy of it (`mix gen.sdk`).

# `lobby_attrs`

```elixir
@type lobby_attrs() :: %{optional(atom()) =&gt; term()}
```

A lobby's settings, as `new_lobby/1` takes them.

# `t`

```elixir
@type t() :: %Gamend.MatchSeating{
  accept_timeout_ms: pos_integer() | nil,
  lobby: lobby_attrs() | nil,
  lobby_id: String.t() | nil
}
```

# `default`

```elixir
@spec default(keyword()) :: t()
```

Core's seat: the lobby a host's ticket fills, else a new hidden, locked,
hostless lobby sized to the match. Answer this to change only whether the
players are asked.

`:accept_timeout_ms`: the time everyone holding a ticket has to accept.
Left out, they are seated at once.

# `dump`

```elixir
@spec dump(t()) :: map()
```

JSON for the wait while players accept: where the match will sit. The accept
may resolve on another node, or after a restart.

# `in_lobby`

```elixir
@spec in_lobby(String.t(), keyword()) :: t()
```

An existing lobby: `lobby_id`, past its hidden and locked flags. Takes
`:accept_timeout_ms`. Only the players holding the match's tickets are asked,
so whoever is already seated there is not interrupted.

# `load`

```elixir
@spec load(map() | nil) :: t()
```

The seating `dump/1` wrote. Nothing stored is `default/1`.

# `lobby_attrs`

```elixir
@spec lobby_attrs(t(), %{max_players: pos_integer(), match_params: map()}) :: map()
```

The attrs core creates a new lobby with, for a match whose oldest ticket is
`ticket`. Always locked at birth, so a stranger cannot take a seat while
the match is being seated; `unlock?/1` says whether to open it after.

# `new_lobby`

```elixir
@spec new_lobby(keyword()) :: t()
```

A new lobby for the match. Takes `:title`, `:max_users`, `:host_id`,
`:hostless`, `:is_hidden`, `:is_locked`, `:metadata`, `:slowdown` and
`:accept_timeout_ms`.

What is left out is core's: hidden, locked, sized to the match, hostless
unless a `:host_id` is named. A host who holds a ticket is not seated twice.

# `unlock?`

```elixir
@spec unlock?(t()) :: boolean()
```

Whether the new lobby is opened once the match is seated.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
