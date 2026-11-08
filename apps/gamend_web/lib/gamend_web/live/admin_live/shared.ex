defmodule GamendWeb.AdminLive.Shared do
  @moduledoc """
  Small pieces more than one admin LiveView needs.

  Each of these existed as an identical private function in two or three
  console pages. They are here rather than in `GamendWeb.CoreComponents`
  because none of them is part of the player-facing surface: a mute duration
  list and a country flag are admin furniture.
  """

  use Gettext, backend: GamendWeb.Gettext

  require GamendWeb.FilterValue, as: FilterValue

  @durations %{
    "10m" => 600,
    "1h" => 3_600,
    "24h" => 86_400,
    "7d" => 604_800,
    "30d" => 2_592_000
  }

  @doc """
  The mute/ban durations the console offers, as `{value, label}` pairs.

  Shared by the chat-mutes, chat-reports and rate-limiting (IP ban) pages,
  which offered their own lists and would have drifted the first time one of
  them gained an option. `expires_at/1` reads a value back.
  """
  @spec duration_options() :: [{String.t(), String.t()}]
  def duration_options do
    [
      {"10m", gettext("10 minutes")},
      {"1h", gettext("1 hour")},
      {"24h", gettext("24 hours")},
      {"7d", gettext("7 days")},
      {"30d", gettext("30 days")},
      {"permanent", gettext("Permanent")}
    ]
  end

  @doc """
  The `expires_at` a `duration_options/0` value sets, from now: nil for
  `"permanent"` (and anything the list does not offer).
  """
  @spec expires_at(String.t() | nil) :: DateTime.t() | nil
  def expires_at(duration) do
    case Map.fetch(@durations, duration) do
      {:ok, seconds} -> DateTime.add(DateTime.utc_now(:second), seconds, :second)
      :error -> nil
    end
  end

  @doc "A changeset's errors as one line, `field message; field message`."
  @spec error_summary(Ecto.Changeset.t()) :: String.t()
  def error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  @doc """
  Applies an admin list's filter form and returns the list to its first page.

  `fields` maps each assign to the form param it reads, as `assign: "param"`
  (defaulting to `""`) or `assign: {"param", default}`. Values are trimmed, so a
  pasted id with a trailing space still matches.

      Shared.put_filters(socket, params, status_filter: {"status", "all"}, user_filter: "user_id")

  Four console pages wrote this out by hand, field by field.
  """
  @spec put_filters(Phoenix.LiveView.Socket.t(), map(), keyword()) :: Phoenix.LiveView.Socket.t()
  def put_filters(socket, params, fields) do
    fields
    |> Enum.reduce(socket, fn
      {assign_key, {param, default}}, acc ->
        Phoenix.Component.assign(acc, assign_key, read_filter(params, param, default))

      {assign_key, param}, acc ->
        Phoenix.Component.assign(acc, assign_key, read_filter(params, param, ""))
    end)
    |> Phoenix.Component.assign(:page, 1)
  end

  @doc """
  The options a filtered, paginated console list hands its context: each
  `option: assign` pair read from `assigns`, where `"all"` and `""` mean no
  filter, followed by the current page and page size -- the other half of
  `put_filters/3`.

      Shared.list_opts(socket.assigns, status: :status_filter, user_id: :user_filter)
  """
  @spec list_opts(map(), keyword(atom())) :: keyword()
  def list_opts(assigns, fields) do
    filters =
      Enum.map(fields, fn {option, assign_key} ->
        {option,
         if(assigns[assign_key] == FilterValue.everything(),
           do: nil,
           else: Gamend.Parse.blank_to_nil(assigns[assign_key])
         )}
      end)

    filters ++ [page: assigns.page, page_size: assigns.page_size]
  end

  defp read_filter(params, param, default) do
    case Map.get(params, param) do
      value when is_binary(value) -> String.trim(value)
      _ -> default
    end
  end

  @doc """
  An ISO-3166 alpha-2 code as its flag emoji, or a globe when it is not one.

  The regional-indicator block sits at a fixed offset from `A`, so the two
  letters map straight onto it.
  """
  @spec country_flag(term()) :: String.t()
  def country_flag(<<a, b>> = code)
      when (a in ?A..?Z or a in ?a..?z) and (b in ?A..?Z or b in ?a..?z) do
    code
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.map(fn char -> char - ?A + 0x1F1E6 end)
    |> List.to_string()
  end

  def country_flag(_code), do: "🌐"

  @doc """
  Runs `fun` with `record`, or flashes that it is gone when it is `nil`.

  A console row can name a record another admin, its player or a sweep deleted
  after the page drew it. A `get_*!` there crashed the page into a remount;
  this says what happened and leaves the page as it was.

      def handle_event("edit_group", %{"id" => id}, socket) do
        Shared.with_record(socket, Groups.get_group(id), fn group -> ... end)
      end
  """
  @spec with_record(Phoenix.LiveView.Socket.t(), struct() | nil, (struct() -> result)) ::
          result | {:noreply, Phoenix.LiveView.Socket.t()}
        when result: term()
  def with_record(socket, nil, _fun),
    do: {:noreply, Phoenix.LiveView.put_flash(socket, :error, gone_message())}

  def with_record(_socket, record, fun), do: fun.(record)

  @doc "The flash for a record deleted since the page listed it."
  @spec gone_message() :: String.t()
  def gone_message, do: gettext("It no longer exists. It was deleted after this page loaded.")
end
