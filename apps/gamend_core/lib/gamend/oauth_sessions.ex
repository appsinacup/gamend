defmodule Gamend.OAuthSessions do
  @moduledoc """
  Helpers for creating and retrieving short-lived OAuth sessions.
  """

  use Nebulex.Caching, cache: Gamend.Cache
  alias Gamend.OAuthSession
  alias Gamend.Repo

  require Gamend.OAuth.SessionStatus, as: SessionStatus

  @oauth_sessions_cache_ttl_ms 30_000

  defp invalidate_oauth_session_cache(session_id) when is_binary(session_id) do
    _ = Gamend.Cache.invalidate({:oauth_sessions, :session, session_id})
    :ok
  end

  @spec create_session(String.t(), map()) ::
          {:ok, OAuthSession.t()} | {:error, Ecto.Changeset.t()}
  def create_session(session_id, attrs \\ %{}) do
    attrs = Map.merge(%{session_id: session_id}, attrs)

    %OAuthSession{}
    |> OAuthSession.changeset(attrs)
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :session_id)
    |> case do
      {:ok, _session} = ok ->
        _ = invalidate_oauth_session_cache(session_id)
        ok

      other ->
        other
    end
  end

  @spec get_session(String.t()) :: OAuthSession.t() | nil
  def get_session(session_id) do
    get_session_cached(session_id)
  end

  @decorate cacheable(
              key: {:oauth_sessions, :session, session_id},
              match: &(&1 != nil),
              opts: [ttl: @oauth_sessions_cache_ttl_ms]
            )
  defp get_session_cached(session_id) when is_binary(session_id) do
    Repo.get_by(OAuthSession, session_id: session_id)
  end

  @doc """
  How long a session may sit in `pending` before a callback stops being accepted.

  An OAuth round trip is seconds; the only thing a long window buys is time for
  someone to hand a started flow's URL to another person and have that person's
  consent land in the starter's session.
  """
  @spec pending_ttl_seconds() :: pos_integer()
  def pending_ttl_seconds, do: 600

  @doc """
  A session that may still accept a callback: it exists, is `pending`, was
  started for `provider`, and is inside `pending_ttl_seconds/0`.

  Returns `nil` otherwise, so a stale, replayed or provider-mismatched state is
  indistinguishable from one that was never issued.
  """
  @spec get_pending_session(String.t(), String.t() | nil) :: OAuthSession.t() | nil
  def get_pending_session(session_id, provider \\ nil) when is_binary(session_id) do
    with %OAuthSession{status: SessionStatus.pending()} = session <- get_session(session_id),
         true <- is_nil(provider) or session.provider in [nil, provider],
         true <- fresh?(session) do
      session
    else
      _ -> nil
    end
  end

  defp fresh?(%OAuthSession{inserted_at: %DateTime{} = at}) do
    DateTime.diff(DateTime.utc_now(), at, :second) <= pending_ttl_seconds()
  end

  defp fresh?(_session), do: false

  @spec update_session(String.t(), map()) ::
          {:ok, OAuthSession.t()} | {:error, Ecto.Changeset.t()} | :not_found
  def update_session(session_id, attrs) do
    case get_session(session_id) do
      nil ->
        :not_found

      session ->
        session
        |> OAuthSession.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _session} = ok ->
            _ = invalidate_oauth_session_cache(session_id)
            ok

          other ->
            other
        end
    end
  end
end
