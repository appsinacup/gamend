defmodule Gamend.Signals do
  @moduledoc """
  Server-side signals: a plugin emits a named event, another part of the plugin
  waits for it.

  This is the server's answer to Godot's `signal` / `emit` / `await`. Nothing
  on the server emits engine signals, so a hook that wants to wait for
  something needs a source of its own:

      Gamend.Signals.subscribe("my_game", "level_up")
      Gamend.Signals.emit("my_game", "level_up", [user_id, 5])
      {:ok, [user_id, level]} = Gamend.Signals.await("my_game", "level_up")

  Signals are scoped to one plugin, so two plugins may use the same name
  without colliding, and they ride `Phoenix.PubSub`, so an emit reaches every
  node in a cluster.

  `subscribe/2` before `await/3`, not inside it: a signal emitted between the
  two would otherwise be missed. The GDScript front end does this
  automatically, subscribing at function entry for every signal the function
  awaits.
  """

  @default_timeout 30_000

  @typedoc "Whatever the emitter passed, unchanged."
  @type payload :: term()

  @doc "Topic a signal rides on. Public so a plugin can subscribe by hand."
  @spec topic(String.t(), String.t()) :: String.t()
  def topic(plugin, name) when is_binary(plugin) and is_binary(name),
    do: "gdsignal:" <> plugin <> ":" <> name

  @doc """
  Subscribes the calling process to `name`.

  Idempotent, and scoped to the process that calls it -- when a hook's Task
  ends, the subscription goes with it.
  """
  @spec subscribe(String.t(), String.t()) :: :ok
  def subscribe(plugin, name) do
    Phoenix.PubSub.subscribe(Gamend.PubSub, topic(plugin, name))
  end

  @doc """
  Emits `name` with `payload` to every subscriber, on every node.

  Returns `:ok` whether or not anyone was listening -- a signal with no
  listener is dropped, as in Godot.
  """
  @spec emit(String.t(), String.t(), payload()) :: :ok
  def emit(plugin, name, payload \\ nil) do
    Gamend.Broadcast.publish(
      topic(plugin, name),
      {:gd_signal, plugin, name, payload}
    )
  end

  @doc """
  Waits for the next `name`, returning `{:ok, payload}` or `{:error, :timeout}`.

  Only sees signals emitted after `subscribe/2` ran in this process.
  """
  @spec await(String.t(), String.t(), timeout()) :: {:ok, payload()} | {:error, :timeout}
  def await(plugin, name, timeout \\ @default_timeout) do
    receive do
      {:gd_signal, ^plugin, ^name, payload} -> {:ok, payload}
    after
      timeout -> {:error, :timeout}
    end
  end
end
