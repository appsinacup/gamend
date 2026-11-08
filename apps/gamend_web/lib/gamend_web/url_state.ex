defmodule GamendWeb.UrlState do
  @moduledoc """
  Keeps a LiveView's view state in its URL, so a refresh, a dropped socket or a
  link opens the page as the reader left it. A page names the assigns that are
  its state, and nothing else changes:

      use GamendWeb.UrlState,
        reload: :reload,
        keys: [:page, :page_size, :search, status: [in: ~w(open closed)]]

  After every `handle_event/3` the keys are written to the URL (`push_patch`,
  `replace: true`, so Back leaves the page rather than undoing a filter), each
  under its name with hyphens (`:page_size` is `?page-size=`), left out while it
  holds its value from `mount/3`. When the URL says otherwise (a refresh, a
  link), they are read back after `mount/3` and `reload` runs once, a private
  function from socket to socket; without `:reload`, the page's own
  `handle_params/3` loads, and runs after the keys are read. Other query
  parameters stay as they are. So `mount/3` gives each key its default and an
  event only assigns, as pages have always done.

  A key's value is read by the type of its default: an integer (`:page` and any
  `*_page` never below 1, `*_page_size` through `Gamend.Limits`), a boolean, a
  string, nil for a string that may be absent, a list or `MapSet` of strings
  (`?filter=a,b`). A URL is anyone's to write: what cannot be read counts as
  absent. Options, for a key that needs them:

    * `in:` the closed set of values allowed, atoms too
    * `param:` the parameter's name, where a link already uses another
    * `type: :nilable` a string default where `""` means nil
    * `keys:` the keys of an assign holding a map of filters, each its own
      parameter, read by the type of its default
    * `min:` the floor of an integer
    * `type: :integer_set` a `MapSet` of integers
    * `keep: true` a link to this page that does not name it leaves it as it is,
      and it is written back, for what stays while the reader moves around the
      page (a mode, a tree left open)

  `drop:` names parameters a link brings and the page takes once (`?user_id=`
  filling a form): the next write leaves them out, so the URL says what the page
  shows.

  Not for what a person is in the middle of: a form being typed, an edit dialog,
  rows ticked.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Phoenix.LiveView

  require GamendWeb.UrlParam, as: UrlParam

  @private :gamend_url_state

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @url_state %{
        keys: GamendWeb.UrlState.normalize(Keyword.fetch!(opts, :keys)),
        drop: Keyword.get(opts, :drop, [])
      }
      @url_state_reload Keyword.get(opts, :reload)
      @before_compile GamendWeb.UrlState

      on_mount {GamendWeb.UrlState, __MODULE__}
    end
  end

  defmacro __before_compile__(env) do
    reload = Module.get_attribute(env.module, :url_state_reload)

    reloaded =
      if reload do
        quote(do: unquote(reload)(socket))
      else
        quote(do: socket)
      end

    wrapper =
      if Module.defines?(env.module, {:handle_event, 3}) do
        quote do
          defoverridable handle_event: 3

          @impl true
          def handle_event(event, params, socket) do
            GamendWeb.UrlState.after_event(super(event, params, socket))
          end
        end
      end

    # A page that reads nothing itself still has to answer its own patch.
    params =
      unless Module.defines?(env.module, {:handle_params, 3}) do
        quote do
          @impl true
          def handle_params(_params, _uri, socket), do: {:noreply, socket}
        end
      end

    quote do
      @doc false
      def __url_state__, do: @url_state

      @doc false
      def __url_state_reload__(socket), do: unquote(reloaded)

      unquote(wrapper)
      unquote(params)
    end
  end

  @doc false
  def normalize(keys) do
    Enum.map(keys, fn
      {key, opts} when is_atom(key) and is_list(opts) -> {key, Map.new(opts)}
      key when is_atom(key) -> {key, %{}}
    end)
  end

  @doc false
  def on_mount(module, _params, _session, socket) do
    {:cont,
     LiveView.attach_hook(socket, @private, :handle_params, fn params, uri, socket ->
       {:cont, read(socket, module, params, uri)}
     end)}
  end

  @doc false
  def after_event({:noreply, socket}), do: {:noreply, write(socket)}
  def after_event({:reply, reply, socket}), do: {:reply, reply, write(socket)}

  @doc """
  Writes the keys to the URL now. Events do it by themselves; this is for state
  a `handle_info/2` changed.
  """
  @spec write(LiveView.Socket.t()) :: LiveView.Socket.t()
  def write(%{redirected: nil} = socket) do
    case socket.private[@private] do
      nil ->
        socket

      state ->
        query = Map.merge(state.other, encode(state.keys, socket.assigns, state.defaults))

        if query == state.query do
          socket
        else
          LiveView.push_patch(socket, to: url(state.path, query), replace: true)
        end
    end
  end

  # A socket already redirecting has left the page; its URL is not ours to patch.
  def write(socket), do: socket

  # The first read is after `mount/3`, so what the keys hold then is their
  # default. A reload runs only when the URL says something else: an event's own
  # patch reads back what the page already has.
  defp read(socket, module, params, uri) do
    %{keys: keys, drop: drop} = module.__url_state__()

    state =
      socket.private[@private] ||
        %{keys: keys, defaults: Map.new(keys, fn {key, _opts} -> {key, socket.assigns[key]} end)}

    decoded = decode(keys, params, kept(keys, state.defaults, socket))

    %URI{path: path, query: raw} = URI.parse(uri)
    query = URI.decode_query(raw || "")
    other = query |> Map.drop(Enum.flat_map(keys, &params_of/1)) |> Map.drop(drop)

    socket =
      LiveView.put_private(
        socket,
        @private,
        Map.merge(state, %{path: path, other: other, query: query})
      )

    if same?(keys, decoded, socket.assigns) do
      socket
    else
      socket |> assign(merged(keys, decoded, socket.assigns)) |> module.__url_state_reload__()
    end
    |> write_kept(keys, params)
  end

  # A key kept while its link did not name it: the URL says it again.
  defp write_kept(socket, keys, params) do
    missing? =
      Enum.any?(keys, fn {key, opts} ->
        opts[:keep] == true and not is_map_key(params, param(key, opts)) and
          socket.assigns[key] != socket.private[@private].defaults[key]
      end)

    if missing?, do: write(socket), else: socket
  end

  # What an absent parameter reads as: the default, or for a kept key, what the
  # page has.
  defp kept(keys, defaults, socket) do
    Enum.reduce(keys, defaults, fn
      {key, %{keep: true}}, acc when is_map_key(socket.assigns, key) ->
        Map.put(acc, key, socket.assigns[key])

      _key, acc ->
        acc
    end)
  end

  defp url(path, query) when query == %{}, do: path
  defp url(path, query), do: path <> "?" <> URI.encode_query(query)

  defp params_of({_key, %{keys: names}}), do: Enum.map(names, &name_param/1)
  defp params_of({key, opts}), do: [param(key, opts)]

  defp param(key, opts), do: Map.get(opts, :param) || name_param(key)

  defp name_param(name), do: name |> to_string() |> String.replace("_", "-")

  # A map of filters: its absent and empty values are one thing.
  defp same?(keys, decoded, assigns) do
    Enum.all?(keys, fn
      {key, %{keys: names}} ->
        filled(decoded[key]) == filled(Map.take(assigns[key] || %{}, names))

      {key, _opts} ->
        assigns[key] == decoded[key]
    end)
  end

  defp filled(map), do: Map.reject(map, fn {_key, value} -> value in [nil, ""] end)

  defp merged(keys, decoded, assigns) do
    Enum.map(keys, fn
      {key, %{keys: names}} ->
        {key, (assigns[key] || %{}) |> Map.drop(names) |> Map.merge(decoded[key])}

      {key, _opts} ->
        {key, decoded[key]}
    end)
  end

  defp decode(keys, params, defaults) do
    Map.new(keys, fn
      {key, %{keys: names} = opts} ->
        default = defaults[key] || %{}

        {key,
         Enum.reduce(names, %{}, fn name, map ->
           case params[name_param(name)] do
             raw when is_binary(raw) ->
               Map.put(
                 map,
                 name,
                 cast(type(%{}, default[name] || ""), raw, name, default[name], opts)
               )

             _absent when is_map_key(default, name) ->
               Map.put(map, name, default[name])

             _absent ->
               map
           end
         end)}

      {key, opts} ->
        default = defaults[key]

        value =
          case params[param(key, opts)] do
            raw when is_binary(raw) -> cast(type(opts, default), raw, key, default, opts)
            _absent -> default
          end

        {key, allowed(value, default, opts)}
    end)
  end

  defp type(%{type: type}, _default), do: type
  defp type(_opts, default) when is_integer(default), do: :integer
  defp type(_opts, default) when is_boolean(default), do: :boolean
  defp type(_opts, nil), do: :nilable
  defp type(_opts, default) when is_atom(default), do: :atom
  defp type(_opts, default) when is_list(default), do: :list
  defp type(_opts, %MapSet{}), do: :set
  defp type(_opts, _default), do: :string

  defp cast(:string, raw, _key, _default, _opts), do: raw
  defp cast(:nilable, "", _key, _default, _opts), do: nil
  defp cast(:nilable, raw, _key, _default, _opts), do: raw
  defp cast(:boolean, "true", _key, _default, _opts), do: true
  defp cast(:boolean, "false", _key, _default, _opts), do: false
  defp cast(:boolean, _raw, _key, default, _opts), do: default
  defp cast(:list, raw, _key, _default, _opts), do: String.split(raw, ",", trim: true)
  defp cast(:set, raw, _key, _default, _opts), do: MapSet.new(String.split(raw, ",", trim: true))

  defp cast(:integer_set, raw, _key, _default, _opts) do
    raw
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn part ->
      case Integer.parse(part) do
        {number, ""} -> [number]
        _bad -> []
      end
    end)
    |> MapSet.new()
  end

  # A URL names no new atom: one of its `in:` set, else one that exists.
  defp cast(:atom, raw, _key, default, %{in: set}) do
    Enum.find(set, default, &(to_string(&1) == raw))
  end

  defp cast(:atom, "", _key, _default, _opts), do: nil

  defp cast(:atom, raw, _key, default, _opts) do
    String.to_existing_atom(raw)
  rescue
    ArgumentError -> default
  end

  defp cast(:integer, raw, key, default, opts) do
    name = to_string(key)

    if String.ends_with?(name, "page_size") do
      raw |> Gamend.Limits.clamp_page_size(default) |> max(Map.get(opts, :min, 1))
    else
      case Integer.parse(raw) do
        {number, ""} -> at_least(number, floor_of(name, opts))
        _bad -> default
      end
    end
  end

  defp floor_of(name, opts) do
    if name == UrlParam.page() or String.ends_with?(name, "_page"),
      do: Map.get(opts, :min, 1),
      else: Map.get(opts, :min)
  end

  defp at_least(number, nil), do: number
  defp at_least(number, floor), do: max(number, floor)

  defp allowed(value, default, %{in: set}), do: if(value in set, do: value, else: default)
  defp allowed(value, _default, _opts), do: value

  defp encode(keys, assigns, defaults) do
    Enum.reduce(keys, %{}, fn
      {key, %{keys: names}}, query ->
        value = assigns[key] || %{}
        default = defaults[key] || %{}

        Enum.reduce(names, query, fn name, query ->
          now = Map.get(value, name)

          if blank(now) == blank(Map.get(default, name)),
            do: query,
            else: Map.put(query, name_param(name), text(now))
        end)

      {key, opts}, query ->
        now = assigns[key]

        if now == defaults[key],
          do: query,
          else: Map.put(query, param(key, opts), text(now))
    end)
  end

  defp blank(nil), do: ""
  defp blank(value), do: value

  defp text(%MapSet{} = set), do: set |> MapSet.to_list() |> text()
  defp text(list) when is_list(list), do: Enum.join(list, ",")
  defp text(value), do: to_string(value)
end
