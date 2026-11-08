# Example hook plugin

This is a minimal OTP hook plugin example.

## Build

From the repo root:

- `cd modules/plugins_examples/example_hook`
- `mix deps.get`
- `mix compile`

This compiles the plugin into `_build/dev/lib/example_hook/ebin/` (and generates the `.app` file with `hooks_module`).

## Package (plugin bundle)

The server loads plugins from a directory containing an `ebin/` folder.
To create a bundle directory you can drop into `modules/plugins/`:

- `mix plugin.bundle`

This also copies transitive runtime dependencies, including:

- compiled dependency BEAMs into `deps/<dep>/ebin`
- plugin/runtime `priv/` directories into `priv` and `deps/<dep>/priv`

The `priv/` copy is important for dependencies that ship NIFs or other runtime assets.

## Run locally

- Set `GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples` (or copy the built bundle into `modules/plugins/example_hook`)
- Open the Admin Config page and click **Reload plugins**
- Call a function via the “Hooks - Test RPC” form using:
  - `plugin`: `example_hook`
  - `fn`: `hello` (or `set_current_user_meta`)

## Ranked matchmaking

A complete rated queue, every step in `lib/gamend/modules/example_hook.ex`:

| Step | Where |
|---|---|
| Startup | `ensure_rating_leaderboard/0`: a `set` leaderboard is the rating table |
| Join | `before_matchmaking_join/2`: checks the mode, stamps a skill band from the stored rating |
| Pair | `matchmaking_form_matches/2`: closest ratings, within `Gamend.Rating.band/2` |
| Seat | `matchmaking_seat_match/1`: a `Gamend.MatchSeating` answer, a lobby of its own and 15 s to accept |
| Result | `after_lobby_state_changed/3`: on `ended`, `Gamend.Rating.settle/3` from the lobby's winner |

To try it, queue two online players with `{"match_params": {"mode": "ranked"}}` at `POST /api/v1/matchmaking/tickets` and answer `POST /api/v1/me/ready_check` for each. Server code then says who won and ends the lobby:

```elixir
{:ok, lobby} = Gamend.Lobbies.merge_metadata(lobby, %{"winner" => user_id})
{:ok, _lobby} = Gamend.Lobbies.transition_state(lobby, "ended")
```

Both ratings appear on the `example_ranked_rating` leaderboard. After changing the plugin, run `mix plugin.bundle` again: the server loads the bundle, not `_build`.
