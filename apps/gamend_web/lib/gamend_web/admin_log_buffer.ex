defmodule GamendWeb.AdminLogBuffer do
  @moduledoc """
  In-memory ring buffer of recent log entries for the admin dashboard.

  Entries are written directly into a public ETS `ordered_set` from the
  calling (logger handler) process, so logging never serializes through this
  GenServer — under a log storm writers stay concurrent and reads stay cheap.
  The GenServer only owns the table and trims it periodically.
  """

  use GenServer

  require GamendWeb.AdminLogSource, as: AdminLogSource
  require GamendWeb.FilterValue, as: FilterValue

  @name __MODULE__
  @table __MODULE__
  @topic "admin_logs"
  @max_entries 5000
  # Trim in batches instead of per insert; the buffer may briefly exceed
  # @max_entries by up to this amount.
  @trim_every 500

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  def topic, do: @topic

  @doc """
  Appends a log entry. Called from the logger handler in the logging
  process — writes straight to ETS, no GenServer round-trip.
  """
  def put(entry) when is_map(entry) do
    if :ets.whereis(@table) != :undefined do
      entry = normalize_entry(entry)
      seq = :ets.update_counter(@table, :seq, 1, {:seq, 0})
      :ets.insert(@table, {seq, entry})

      if rem(seq, @trim_every) == 0 do
        GenServer.cast(@name, :trim)
      end

      Phoenix.PubSub.broadcast(Gamend.PubSub, @topic, {:admin_log, entry})
    end

    :ok
  end

  @doc """
  Returns buffered entries, newest first, with optional filters.

  Beyond `:module`, `:level` and `:query`:

  - `:source` — `"server"`, `"client"` or `"all"`. Client log uploads are
    re-emitted through `Logger` (see `Gamend.ClientLogs`), so without this the
    server's own tail is buried under every connected player's entries.
  - `:session` — one client session id, the key that joins a client's lines to
    the server lines logged while handling its requests.
  - `:user` — a user id, matched against either a client entry's owner or a
    server entry's logged user.
  """
  def list(opts \\ []) do
    entries()
    |> apply_filters(opts)
    |> Enum.take(Keyword.get(opts, :limit, @max_entries))
  end

  defp apply_filters(entries, opts) do
    entries
    |> maybe_filter_source(Keyword.get(opts, :source))
    |> maybe_filter_module(Keyword.get(opts, :module))
    |> maybe_filter_level(Keyword.get(opts, :level))
    |> maybe_filter_meta(:client_session, Keyword.get(opts, :session))
    |> maybe_filter_user(Keyword.get(opts, :user))
    |> maybe_filter_query(Keyword.get(opts, :query))
  end

  @doc "How many buffered entries came from game clients rather than the server."
  def count_by_source do
    Enum.reduce(entries(), %{server: 0, client: 0}, fn entry, acc ->
      key = if client_entry?(entry), do: :client, else: :server
      Map.update!(acc, key, &(&1 + 1))
    end)
  end

  @doc "Recent entries for one client session, oldest first — the session timeline."
  def session_entries(session_id, limit \\ 500) when is_binary(session_id) do
    [session: session_id, limit: limit] |> list() |> Enum.reverse()
  end

  @doc """
  A map of level => count.

  With no options, every buffered entry — "what is in the buffer".

  With `opts`, the same filters `list/1` takes, **except** `:level`, which is
  ignored: the answer is then "how many would I see at each level if I picked
  it", which is what a level chip beside a live filter has to say. Counting the
  whole buffer there is what let the admin page offer `error(7)` and then list
  one — the other six were client entries, and the source filter defaults to
  server-only.
  """
  def count_by_level(opts \\ []) do
    entries()
    |> apply_filters(Keyword.delete(opts, :level))
    |> Enum.group_by(& &1.level)
    |> Map.new(fn {level, entries} -> {level, length(entries)} end)
  end

  @doc "Returns the count of error/critical/alert/emergency entries in the last `seconds` seconds."
  def count_recent_errors(seconds \\ 3600) do
    cutoff = DateTime.add(DateTime.utc_now(), -seconds, :second)
    error_levels = [:error, :critical, :alert, :emergency]

    Enum.count(entries(), fn entry ->
      entry.level in error_levels and DateTime.compare(entry.timestamp, cutoff) == :gt
    end)
  end

  @impl true
  def init(_) do
    _ =
      :ets.new(@table, [
        :ordered_set,
        :public,
        :named_table,
        write_concurrency: true,
        read_concurrency: true
      ])

    # Installed before the handlers so no filtered noise reaches the buffer.
    _ = GamendWeb.LogFilters.install()
    _ = GamendWeb.AdminLogHandler.install()
    _ = GamendWeb.FileLogHandler.install()
    {:ok, %{}}
  end

  @impl true
  def handle_cast(:trim, state) do
    case :ets.lookup(@table, :seq) do
      [{:seq, seq}] when seq > @max_entries ->
        # Delete all numeric keys at or below the cutoff (`:seq` is an atom
        # key and sorts after integers in an ordered_set, so it is untouched).
        cutoff = seq - @max_entries

        :ets.select_delete(@table, [
          {{:"$1", :_}, [{:is_integer, :"$1"}, {:"=<", :"$1", cutoff}], [true]}
        ])

      _ ->
        :ok
    end

    {:noreply, state}
  end

  # Newest first: descending key order, skipping the :seq counter row.
  defp entries do
    @table
    |> :ets.select_reverse([{{:"$1", :"$2"}, [{:is_integer, :"$1"}], [:"$2"]}])
  rescue
    ArgumentError -> []
  end

  defp client_entry?(entry), do: Map.get(entry[:meta] || %{}, :source) == :client

  defp maybe_filter_source(entries, source) when source in [nil, "", FilterValue.everything()],
    do: entries

  defp maybe_filter_source(entries, AdminLogSource.client()),
    do: Enum.filter(entries, &client_entry?/1)

  defp maybe_filter_source(entries, AdminLogSource.server()),
    do: Enum.reject(entries, &client_entry?/1)

  defp maybe_filter_source(entries, _), do: entries

  defp maybe_filter_meta(entries, _key, value) when value in [nil, ""], do: entries

  defp maybe_filter_meta(entries, key, value) when is_binary(value) do
    Enum.filter(entries, fn entry ->
      to_string(Map.get(entry[:meta] || %{}, key, "")) == value
    end)
  end

  # A user id reaches a log line by two different routes: as the owner of a
  # client session, or as whatever the server put in its own metadata. Matching
  # only one of them would silently answer half the question.
  defp maybe_filter_user(entries, value) when value in [nil, ""], do: entries

  defp maybe_filter_user(entries, value) when is_binary(value) do
    Enum.filter(entries, fn entry ->
      meta = entry[:meta] || %{}

      Enum.any?([:client_user_id, :user_id], fn key ->
        to_string(Map.get(meta, key, "")) == value
      end)
    end)
  end

  defp maybe_filter_module(entries, nil), do: entries
  defp maybe_filter_module(entries, ""), do: entries

  defp maybe_filter_module(entries, module_filter) when is_binary(module_filter) do
    filter = String.trim(module_filter)

    if filter == "" do
      entries
    else
      Enum.filter(entries, fn entry ->
        mod = entry.module

        mod_str =
          case mod do
            nil -> ""
            atom when is_atom(atom) -> Atom.to_string(atom)
            other -> to_string(other)
          end

        String.contains?(mod_str, filter)
      end)
    end
  end

  defp maybe_filter_level(entries, nil), do: entries
  defp maybe_filter_level(entries, ""), do: entries
  defp maybe_filter_level(entries, FilterValue.everything()), do: entries

  defp maybe_filter_level(entries, level) when is_binary(level) do
    atom_level = String.to_existing_atom(level)
    Enum.filter(entries, fn entry -> entry.level == atom_level end)
  rescue
    _ -> entries
  end

  defp maybe_filter_query(entries, nil), do: entries
  defp maybe_filter_query(entries, ""), do: entries

  defp maybe_filter_query(entries, query) when is_binary(query) do
    case String.trim(query) do
      "" ->
        entries

      trimmed ->
        needle = String.downcase(trimmed)

        Enum.filter(entries, fn entry ->
          entry.message
          |> to_string()
          |> String.downcase()
          |> String.contains?(needle)
        end)
    end
  end

  defp normalize_entry(entry) do
    module =
      cond do
        is_atom(entry[:module]) -> entry[:module]
        is_tuple(entry[:mfa]) and tuple_size(entry[:mfa]) == 3 -> elem(entry[:mfa], 0)
        true -> nil
      end

    entry
    |> Map.put_new(:timestamp, DateTime.utc_now())
    |> Map.put(:module, module)
  end
end
