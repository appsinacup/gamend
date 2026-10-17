# Gamend SDK

SDK for Gamend hooks development. This package provides type specs, documentation,
and IDE autocomplete for Gamend modules without requiring the full server.

## Installation

Add `gamend_sdk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gamend_sdk, "~> 1.1", runtime: false, optional: true}
  ]
end
```

## Usage

This SDK provides stub modules that match the Gamend API:

### Core Modules

- `Gamend.Accounts` - User account management (registration, login, profile updates, metadata)
- `Gamend.Lobbies` - Lobby management (create, join, leave, kick, host transfer)
- `Gamend.Groups` - Group management (create, join, leave, invite, promote/demote, join requests)
- `Gamend.Parties` - Ephemeral party management (create, invite, lobby integration)
- `Gamend.Leaderboards` - Leaderboard operations (submit scores, rankings, seasonal resets)
- `Gamend.Friends` - Friend relationships and blocking (send/accept/decline requests, block/unblock)
- `Gamend.Notifications` - In-app notification delivery (friend requests, group invites, system alerts)
- `Gamend.KV` - Generic key/value storage (server-side persistent storage for game data)
- `Gamend.Schedule` - Dynamic cron-like job scheduling for hooks

### Behaviour & Types

- `Gamend.Hooks` - Hook behaviour for custom game logic (lifecycle callbacks, RPC functions)
- `Gamend.Types` - Shared types used across Gamend contexts

### Implementing Hooks

Create your hooks module using `use Gamend.Hooks` to get default implementations
for all callbacks, then override only the ones you need:

```elixir
defmodule MyGame.Hooks do
  use Gamend.Hooks

  @impl true
  def after_user_register(user) do
    # Give new users starting coins
    Gamend.Accounts.update_user(user, %{
      metadata: Map.put(user.metadata || %{}, "coins", 100)
    })
  end

  @impl true
  def before_group_create(user, attrs) do
    # Check if user has enough coins to create a group
    coins = get_in(user.metadata, ["coins"]) || 0
    if coins >= 50, do: {:ok, attrs}, else: {:error, :not_enough_coins}
  end

  @impl true
  def before_lobby_join(user, lobby, opts) do
    # Check level requirements
    {:ok, {user, lobby, opts}}
  end

  # Custom RPC - callable from game clients
  def give_coins(amount, _opts) do
    caller = Gamend.Hooks.caller_user()
    coins = get_in(caller.metadata, ["coins"]) || 0
    Gamend.Accounts.update_user(caller, %{
      metadata: Map.put(caller.metadata, "coins", coins + amount)
    })
  end
end
```

### Module APIs

The SDK modules provide the same API as the real Gamend:

```elixir
# Get user by ID (returns nil if not found)
user = Gamend.Accounts.get_user(user_id)

# Update user metadata
{:ok, user} = Gamend.Accounts.update_user(user, %{metadata: %{level: 5}})

# Submit leaderboard score
{:ok, record} = Gamend.Leaderboards.submit_score(leaderboard_id, user_id, 1000)

# Get lobby members
members = Gamend.Lobbies.get_lobby_members(lobby)
```

## Note

This SDK only provides type specifications and documentation for IDE support.
The actual implementations run on the Gamend - these stubs will raise
`RuntimeError` if called directly.
