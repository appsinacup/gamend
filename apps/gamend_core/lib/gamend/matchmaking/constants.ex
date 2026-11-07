defmodule Gamend.Matchmaking.Constants do
  @moduledoc """
  Constants for the matchmaking system.
  """

  @status_queued "queued"
  @status_matched "matched"
  @status_cancelled "cancelled"

  @event_found "match_found"
  @event_queued "ticket_queued"
  @event_cancelled "ticket_cancelled"

  @doc "Status for a ticket that is waiting for a match."
  def status_queued, do: @status_queued

  @doc "Status for a ticket that has been matched to a lobby."
  def status_matched, do: @status_matched

  @doc "Status for a ticket that has been cancelled."
  def status_cancelled, do: @status_cancelled

  @doc "Event broadcast when a match is found."
  def event_found, do: @event_found

  @doc "Event broadcast when a ticket goes in the queue: joined, or put back after a failed accept."
  def event_queued, do: @event_queued

  @doc "Event broadcast when a ticket leaves the queue without a match."
  def event_cancelled, do: @event_cancelled
end
