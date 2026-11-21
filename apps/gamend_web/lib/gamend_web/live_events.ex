defmodule GamendWeb.LiveEvents do
  @moduledoc """
  A LiveView event's params, declared beside its handler and checked before
  it runs: the LiveView twin of `GamendWeb.Plugs.RequestContract` (the API)
  and `GamendWeb.ChannelContract` (the channels).

  An event comes from the browser, and the browser is the client's: a
  `phx-value-id` can be edited, a `pushEvent` can send any JSON. A handler
  written for the template's params crashed on the rest, and a crashed
  LiveView writes an `[error]` and remounts. Phoenix itself has no schema for
  an event (its answer is pattern matching, and changesets for forms), so the
  declaration is ours:

      event("delete", id: :uuid)
      event("save", user: :map, note: {:optional, :string})
      event("close")

      def handle_event("delete", %{"id" => id}, socket), do: ...

  The keys and types are `GamendWeb.PayloadContract`'s. A declared event
  whose params do not match is refused before `handle_event/3`: logged at
  info (the client's mistake, never ours), and the socket answered
  unchanged. An event nobody declared runs as written.

  `use GamendWeb, :live_view` and `:live_component` bring it in; a module that
  only holds a LiveView's handlers (a settings tab) uses it itself. It
  records the event names its `handle_event/3` clauses match literally
  (`__live_events__(:handled)`), so `GamendWeb.LiveEventsTest` fails on a
  handled event that is not declared and on a declaration nothing handles.
  """

  require Logger

  alias GamendWeb.PayloadContract

  defmacro __using__(_opts) do
    quote do
      import GamendWeb.LiveEvents, only: [event: 1, event: 2]
      Module.register_attribute(__MODULE__, :live_events, accumulate: true)
      @before_compile GamendWeb.LiveEvents
    end
  end

  @doc "Declares the event `name` and its params' keys and types."
  defmacro event(name, keys \\ []) when is_binary(name) do
    quote do
      @live_events {unquote(name), unquote(keys)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    declared = env.module |> Module.get_attribute(:live_events) |> Enum.reverse()
    duplicate = declared |> Enum.map(&elem(&1, 0)) |> then(&(&1 -- Enum.uniq(&1)))

    if duplicate != [] do
      raise ArgumentError, "#{inspect(env.module)} declares #{inspect(duplicate)} twice"
    end

    # Checked here, once every `@attribute` a declaration names has a value.
    for {name, keys} <- declared, not PayloadContract.valid_type?(keys) do
      raise ArgumentError,
            "#{inspect(env.module)}: event #{inspect(name)} declares #{inspect(keys)}; " <>
              "see GamendWeb.PayloadContract for the types (a free-form value is " <>
              "{:free, reason})"
    end

    handled = handled_events(env.module)
    impl = if callback?(env.module), do: quote(do: @impl(true))

    wrapper =
      if Module.defines?(env.module, {:handle_event, 3}) do
        quote do
          defoverridable handle_event: 3

          unquote(impl)

          def handle_event(event, params, socket) do
            case GamendWeb.LiveEvents.check(__MODULE__, event, params) do
              :ok -> super(event, params, socket)
              :refused -> {:noreply, socket}
            end
          end
        end
      end

    quote do
      @doc false
      def __live_events__(:declared), do: unquote(Macro.escape(Map.new(declared)))
      def __live_events__(:handled), do: unquote(handled)

      unquote(wrapper)
    end
  end

  @doc """
  `:ok` when `module` declares no `event`, or `params` match its declaration;
  `:refused`, logged, when they do not.
  """
  @spec check(module(), term(), term()) :: :ok | :refused
  def check(module, event, params) do
    with %{^event => declaration} <- module.__live_events__(:declared),
         {:error, errors} <- PayloadContract.check(declaration, params) do
      Logger.info(fn ->
        "#{inspect(module)}: refused event #{inspect(event)}: #{inspect(errors, limit: 10)}"
      end)

      :refused
    else
      _ -> :ok
    end
  end

  # The names `handle_event/3`'s clauses match as a literal first argument.
  defp handled_events(module) do
    case Module.get_definition(module, {:handle_event, 3}) do
      {:v1, _kind, _meta, clauses} ->
        clauses
        |> Enum.flat_map(fn {_meta, [name | _], _guards, _body} -> literal(name) end)
        |> Enum.uniq()

      nil ->
        []
    end
  end

  defp literal(name) when is_binary(name), do: [name]
  defp literal({:=, _, [left, right]}), do: literal(left) ++ literal(right)
  defp literal(_), do: []

  defp callback?(module) do
    behaviours = Module.get_attribute(module, :behaviour) || []
    Enum.any?(behaviours, &(&1 in [Phoenix.LiveView, Phoenix.LiveComponent]))
  end
end
