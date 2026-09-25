defmodule Gamend.Broadcast do
  @moduledoc """
  PubSub broadcasts that must never take the caller down with them.

  Some state is applied locally first and only *mirrored* to other nodes — an
  IP ban, a chat mute, a moderation notice. For those, a failed broadcast must
  not undo the local effect: the ban still has to block this node's traffic
  even when PubSub is unavailable, which happens in early boot and in bare
  ExUnit cases.

  The subtle part, and why this is one function rather than three copies:
  `Phoenix.PubSub.broadcast/3` *exits* rather than raising when the PubSub
  server is not registered, so a `rescue` alone does not catch it. The chat
  moderation cache, its user notices and the IP-ban plug each carried their own
  `rescue`/`catch :exit` pair to get this right.
  """

  require Logger

  @doc """
  Broadcasts `message` on `topic` through `Gamend.PubSub`, always returning `:ok`.

  A raise is logged as a warning naming `label`, when one is given; an exit
  (no PubSub server) is silent, since that is the expected state during boot.
  """
  @spec best_effort(String.t(), term(), String.t() | nil) :: :ok
  def best_effort(topic, message, label \\ nil) do
    Gamend.AfterCommit.defer(fn -> send_best_effort(topic, message, label) end)
  end

  @doc """
  Broadcasts `message` on `topic` through `Gamend.PubSub` once the enclosing
  transaction commits (`Gamend.AfterCommit`), or now outside one.

  Subscribers then never see a write before it is visible, nor one a rollback
  erases, and the broadcast never runs while a transaction holds the database.
  Every broadcast in core goes through here; the cache's own invalidation
  messages are the exception (`Gamend.Cache`).
  """
  @spec publish(String.t(), term()) :: :ok
  def publish(topic, message) do
    Gamend.AfterCommit.defer(fn -> Phoenix.PubSub.broadcast(Gamend.PubSub, topic, message) end)
  end

  defp send_best_effort(topic, message, label) do
    Phoenix.PubSub.broadcast(Gamend.PubSub, topic, message)
    :ok
  rescue
    e ->
      if label, do: Logger.warning("#{label} broadcast failed: " <> Exception.message(e))
      :ok
  catch
    :exit, _reason -> :ok
  end
end
