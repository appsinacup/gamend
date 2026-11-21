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
      event("save", user: [name: :string, note: {:optional, :string}])
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

  An event a hook takes (`attach_hook(socket, name, :handle_event, fun)`)
  never reaches `handle_event/3`, so the module that holds the hook names
  its function and attaches it through `hook/2`, which checks first:

      use GamendWeb.LiveEvents, hook: :on_event

      event("strip_buy", kind: :string)

      def attach(socket),
        do: attach_hook(socket, :strip, :handle_event, LiveEvents.hook(__MODULE__, &on_event/3))

      defp on_event("strip_buy", %{"kind" => kind}, socket), do: ...
      defp on_event(_event, _params, socket), do: {:cont, socket}

  A refused event is the hook's own, so it halts there. The names the hook's
  clauses match literally count as handled. A hook that takes more than the
  event, its params and the socket is named with its arity
  (`hook: {:on_event, 4}`) and attached as a capture of three
  (`&on_event(&1, &2, &3, changed)`).

  A `handle_event/3` clause that hands a list of events to another function
  (`def handle_event(event, params, socket) when event in @acting, do:
  run(event, params, socket)`) names it, so its clauses count as handled too:

      @live_event_handlers [run: 3]
  """

  require Logger

  alias GamendWeb.PayloadContract

  defmacro __using__(opts) do
    quote do
      import GamendWeb.LiveEvents, only: [event: 1, event: 2]
      Module.register_attribute(__MODULE__, :live_events, accumulate: true)
      @live_events_hook unquote(opts[:hook])
      Module.register_attribute(__MODULE__, :live_event_handlers, [])
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

    hook =
      case Module.get_attribute(env.module, :live_events_hook) do
        nil -> nil
        {name, arity} -> {name, arity}
        name -> {name, 3}
      end

    if hook && not Module.defines?(env.module, hook) do
      {name, arity} = hook
      raise ArgumentError, "#{inspect(env.module)} names hook #{name}/#{arity} and defines none"
    end

    handlers = Module.get_attribute(env.module, :live_event_handlers) || []

    for {name, arity} = handler <- handlers, not Module.defines?(env.module, handler) do
      raise ArgumentError,
            "#{inspect(env.module)} names event handler #{name}/#{arity} and defines none"
    end

    handled =
      [{:handle_event, 3} | List.wrap(hook)]
      |> Enum.concat(handlers)
      |> Enum.flat_map(&handled_events(env.module, &1))
      |> Enum.uniq()

    impl = if callback?(env.module), do: quote(do: @impl(true))

    wrapper =
      if Module.defines?(env.module, {:handle_event, 3}, :def) do
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

  @doc """
  `fun`, a `:handle_event` hook of `module`, behind `module`'s declarations:
  an event it declares whose params do not match halts, unchanged.
  """
  @spec hook(module(), (String.t(), term(), term() -> term())) ::
          (String.t(), term(), term() -> term())
  def hook(module, fun) when is_atom(module) and is_function(fun, 3) do
    fn event, params, socket ->
      case check(module, event, params) do
        :ok -> fun.(event, params, socket)
        :refused -> {:halt, socket}
      end
    end
  end

  # The names a function's clauses match as a literal first argument.
  defp handled_events(module, fun_arity) do
    case Module.get_definition(module, fun_arity) do
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
