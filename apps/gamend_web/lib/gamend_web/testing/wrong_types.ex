defmodule GamendWeb.Testing.WrongTypes do
  @moduledoc """
  Tests that send every way into the server the wrong types, and fail on a
  crash: the same three in the engine and in every host.

  A client controls every value it sends. A field typed a string can arrive
  as a list, an object, a number or `null`; an id in a path can be any text;
  a `phx-value-*` can be edited. Each way in is checked before its handler
  (`GamendWeb.Plugs.RequestContract`, `GamendWeb.ChannelContract`,
  `GamendWeb.LiveEvents`), so these are the proof that the checks hold and
  that a value of the right type that names nothing (an id since deleted, a
  number too big) is answered, not crashed on.

      defmodule MyAppWeb.WrongTypesTest do
        use MyAppWeb.ConnCase, async: false
        require GamendWeb.Testing.WrongTypes, as: WrongTypes

        WrongTypes.api_tests()
        WrongTypes.live_tests()
      end

      defmodule MyAppWeb.ChannelWrongTypesTest do
        use MyAppWeb.ChannelCase, async: false
        require GamendWeb.Testing.WrongTypes, as: WrongTypes

        WrongTypes.channel_tests()
      end

  Each macro reads what to send at compile time, so a new route, command or
  event is covered the day it is added:

    * `api_tests/1` — a test per `/api` route of the router
      (`GamendWeb.ContractLint.router/0`, or `router:`), as a fresh admin.
      Each key of its operation, and every `"key" =>` its controller's source
      names, gets each wrong value; each path segment odd text; the whole
      body an array, a string and broken JSON. A 4xx or a deliberate 503
      with an error code passes; a 5xx or a raise fails.
    * `channel_tests/1` — a test per command in `GamendWeb.RealtimeCommands`,
      on a fresh player's channel. Each must reply, and the channel stay up.
    * `live_tests/1` — a test per live route, mounted as an admin of its
      own (a path's parameters are `1`, or `params:`'s), each
      declared event sent wrong and odd params. The page must stay up; an
      event that navigates is followed by a fresh mount. `extra_events:`
      adds a page's events declared elsewhere (`%{Page => [Tab, ...]}`, a
      settings page's tabs). A page that attaches them only on one of its
      paths names it: `%{Page => {"/games/spanish", [Strip]}}`, as does one
      that does not mount at `1` (`{"/games/spanish/pairs", []}`). A page
      that does not mount fails, so none passes with its events unsent;
      `skip:` leaves pages out, each with why (`%{Page => "needs a build"}`).
      A path may be `{module, function, args}`, called as the test runs (a
      row it makes), and `{path, extra, as: :visitor}` mounts with no
      session (a page an account is sent away from); core's own such pages
      are set up already (`core_pages/0`). `params:` gives a route's
      parameters real values (`%{"lang" => "spanish"}`), each else `1`.

  The caller's module provides the case (`ConnCase` with `@endpoint` and the
  SQL sandbox; `ChannelCase` for the channel tests). The players are made
  through `Gamend.Accounts`, so no fixtures are needed.
  """

  alias Gamend.Accounts
  require Gamend.HttpHeader, as: HttpHeader
  alias GamendWeb.Auth.Guardian
  alias OpenApiSpex.{Operation, Parameter, PathItem, Reference, RequestBody, Schema}

  @wrong_values [["a", "b"], %{"a" => "b"}, 1, nil, "nope"]
  @path_values ["abc", "-1", "99999999999999999999999999", "00000000-0000-0000-0000-000000000000"]
  @whole_bodies ["[1, 2]", "\"text\"", "{"]
  @odd_strings [
    "",
    "nope",
    "-1",
    "99999999999999999999999999",
    "00000000-0000-0000-0000-000000000000"
  ]
  @verbs [:get, :post, :put, :patch, :delete]

  # ── The macros ─────────────────────────────────────────────────────────────

  @doc "A test per `/api` route, sent the wrong types as an admin."
  defmacro api_tests(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      alias GamendWeb.Testing.WrongTypes

      @moduletag :capture_log
      @moduletag timeout: 600_000

      for route <- WrongTypes.api_routes(opts[:router]) do
        @wrong_types_route route
        test "#{route.verb |> to_string() |> String.upcase()} #{route.path} survives wrong types" do
          conn = WrongTypes.api_conn()
          dispatch = fn conn, verb, path, data -> dispatch(conn, @endpoint, verb, path, data) end
          crashes = WrongTypes.api_crashes(conn, @wrong_types_route, dispatch)

          assert crashes == [],
                 "#{length(crashes)} request(s) crashed:\n\n" <>
                   Enum.map_join(crashes, "\n\n", &WrongTypes.describe/1)
        end
      end
    end
  end

  @doc "A test per channel command, sent the wrong types on a player's channel."
  defmacro channel_tests(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      alias GamendWeb.Testing.WrongTypes
      # Called by name: a case that imports `Phoenix.ConnTest` as well has
      # two `connect/2`.
      require Phoenix.ChannelTest

      @moduletag :capture_log
      @wrong_types_socket opts[:socket] || GamendWeb.UserSocket

      for command <- GamendWeb.RealtimeCommands.all() do
        @wrong_types_command command
        test "#{command.topic} #{command.event} survives wrong types" do
          topics = WrongTypes.channel_topics()

          {:ok, socket} =
            Phoenix.ChannelTest.connect(@wrong_types_socket, %{"token" => topics.token})

          topic = Map.fetch!(topics, @wrong_types_command.topic)
          {:ok, _reply, channel} = Phoenix.ChannelTest.subscribe_and_join(socket, topic, %{})

          for payload <- WrongTypes.command_payloads(@wrong_types_command) do
            WrongTypes.reset_rate_limits()
            ref = Phoenix.ChannelTest.push(channel, @wrong_types_command.event, payload)

            assert_receive %Phoenix.Socket.Reply{ref: ^ref},
                           10_000,
                           "#{@wrong_types_command.event} #{inspect(payload, limit: 8)} got no reply"

            assert Process.alive?(channel.channel_pid),
                   "#{@wrong_types_command.event} #{inspect(payload, limit: 8)} took the channel down"
          end
        end
      end
    end
  end

  @doc "A test per live route, each declared event sent wrong and odd params as an admin."
  defmacro live_tests(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      alias GamendWeb.Testing.WrongTypes

      import Phoenix.LiveViewTest

      @moduletag :capture_log
      @moduletag timeout: 600_000

      for {module, path, events, as} <-
            WrongTypes.live_routes(
              opts[:router],
              Map.merge(WrongTypes.core_pages(), opts[:extra_events] || %{}),
              opts[:params] || %{}
            ),
          not Map.has_key?(opts[:skip] || %{}, module) do
        @wrong_types_live {module, path, events, as}
        test "#{inspect(module)} #{WrongTypes.path_name(path)} survives wrong types" do
          Process.flag(:trap_exit, true)
          {_module, path, events, as} = @wrong_types_live
          player = WrongTypes.player(as)
          mount = fn conn, path -> live(conn, path) end
          crashes = WrongTypes.live_crashes(path, events, mount, &render_hook/3, player)

          assert crashes == [],
                 "#{length(crashes)} event(s) crashed #{WrongTypes.path_name(path)}:\n\n" <>
                   Enum.join(crashes, "\n\n")
        end
      end
    end
  end

  # ── Players ────────────────────────────────────────────────────────────────

  @doc "A new confirmed admin."
  @spec admin() :: Accounts.User.t()
  def admin do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "wrong-types#{System.unique_integer([:positive])}@example.com"
      })

    user = user |> Accounts.User.confirm_changeset() |> Gamend.Repo.update!()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})
    admin
  end

  @doc "A conn that calls the API as a new admin."
  @spec api_conn() :: Plug.Conn.t()
  def api_conn do
    {:ok, token, _claims} = Guardian.encode_and_sign(admin())

    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
    |> Plug.Conn.put_req_header(HttpHeader.accept(), "application/json")
  end

  @doc "A conn signed in to the site as `user` (a new admin by default)."
  @spec live_conn(Accounts.User.t()) :: Plug.Conn.t()
  def live_conn(user \\ admin()) do
    token = Accounts.generate_user_session_token(user)

    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  A live test's player: a new admin, or nil, a visitor with no session (a
  page an account is sent away from: log in, register).
  """
  @spec player(:admin | :visitor) :: Accounts.User.t() | nil
  def player(:admin), do: admin()
  def player(:visitor), do: nil

  # A new session for each mount, the player's; a visitor's has none.
  defp player_conn(nil),
    do: Phoenix.ConnTest.build_conn() |> Phoenix.ConnTest.init_test_session(%{})

  defp player_conn(user), do: live_conn(user)

  @doc "Clears the rate limiter, which would refuse a test's next request."
  @spec reset_rate_limits() :: :ok
  def reset_rate_limits do
    case :ets.whereis(GamendWeb.RateLimit.ETS) do
      :undefined -> :ok
      _tid -> :ets.delete_all_objects(GamendWeb.RateLimit.ETS)
    end

    :ok
  end

  # ── API ────────────────────────────────────────────────────────────────────

  @doc false
  def api_routes(router) do
    case router || GamendWeb.ContractLint.router() do
      nil ->
        []

      router ->
        router
        |> Phoenix.Router.routes()
        |> Enum.filter(&(String.starts_with?(&1.path, "/api/") and &1.verb in @verbs))
        |> Enum.uniq_by(&{&1.verb, &1.path})
    end
  end

  @doc false
  def api_crashes(conn, route, dispatch) do
    keys = api_keys(route)
    base_path = fill_path(route.path, fn _ -> "1" end)
    base = Map.new(keys, &{&1, "1"})

    path_requests =
      for segment <- path_segments(route.path), value <- @path_values do
        {fill_path(route.path, &if(&1 == segment, do: value, else: "1")), {:params, base}}
      end

    key_requests =
      for key <- keys,
          value <- @wrong_values,
          do: {base_path, {:params, Map.put(base, key, value)}}

    body_requests =
      if route.verb in [:post, :put, :patch],
        do: for(body <- @whole_bodies, do: {base_path, {:raw, body}}),
        else: []

    [{base_path, {:params, %{}}} | path_requests ++ key_requests ++ body_requests]
    |> Enum.flat_map(fn {path, payload} ->
      case send_request(conn, route.verb, path, payload, dispatch) do
        :ok -> []
        {:crash, reason} -> [%{verb: route.verb, path: path, payload: payload, reason: reason}]
      end
    end)
    # One crash of each kind is enough to read: forty copies hide the second.
    |> Enum.uniq_by(&crash_kind(&1.reason))
  end

  defp send_request(conn, verb, path, payload, dispatch) do
    reset_rate_limits()

    {conn, data} =
      case payload do
        {:raw, body} ->
          {Plug.Conn.put_req_header(conn, HttpHeader.content_type(), "application/json"), body}

        {:params, params} when verb in [:get, :delete] ->
          {conn, params}

        {:params, params} ->
          {Plug.Conn.put_req_header(conn, HttpHeader.content_type(), "application/json"),
           Jason.encode!(params)}
      end

    result =
      try do
        dispatch.(conn, verb, path, data)
      rescue
        e -> {:raised, e, __STACKTRACE__}
      catch
        kind, reason -> {:caught, kind, reason}
      end

    case result do
      %Plug.Conn{status: status} when is_integer(status) and status < 500 ->
        :ok

      # A service down on purpose (no sweeper, no storage) answers its code.
      %Plug.Conn{status: 503, resp_body: body} ->
        if match?({:ok, %{"error" => _}}, Jason.decode(body)),
          do: :ok,
          else: {:crash, {:status, 503, String.slice(body, 0, 300)}}

      %Plug.Conn{status: status, resp_body: body} ->
        {:crash, {:status, status, String.slice(to_string(body), 0, 300)}}

      {:raised, e, stack} ->
        if Plug.Exception.status(e) < 500, do: :ok, else: {:crash, {:raise, e, stack}}

      {:caught, kind, reason} ->
        {:crash, {:caught, kind, reason}}
    end
  end

  defp crash_kind({:status, status, _body}), do: {:status, status}
  defp crash_kind({:raise, %{__struct__: mod}, [{m, f, a, _} | _]}), do: {mod, m, f, arity(a)}
  defp crash_kind(other), do: other

  defp arity(a) when is_list(a), do: length(a)
  defp arity(a), do: a

  @doc false
  def describe(%{verb: verb, path: path, payload: payload, reason: reason}) do
    sent =
      case payload do
        {:raw, body} -> "body " <> body
        {:params, params} -> inspect(params, limit: 20)
      end

    "#{verb |> to_string() |> String.upcase()} #{path} #{sent}\n  " <> reason_text(reason)
  end

  defp reason_text({:status, status, body}), do: "answered #{status}: #{body}"

  defp reason_text({:raise, e, stack}) do
    Exception.format_banner(:error, e, stack)
    |> String.slice(0, 600)
    |> Kernel.<>("\n  " <> Exception.format_stacktrace(Enum.take(stack, 4)))
  end

  defp reason_text({:caught, kind, reason}), do: "#{kind}: #{inspect(reason, limit: 20)}"

  # The keys its operation names, and every `"key" =>` its controller's source
  # does: an action can read a key the document leaves out.
  defp api_keys(route) do
    path_keys = route.path |> path_segments() |> Enum.map(&String.trim(&1, ":"))

    (spec_keys(route) ++ source_keys(route.plug))
    |> Enum.uniq()
    |> Kernel.--(path_keys)
    |> Enum.sort()
  end

  defp spec_keys(%{path: path, verb: verb}) do
    spec = spec()

    with %PathItem{} = item <-
           Map.get(spec.paths || %{}, Regex.replace(~r/:(\w+)/, path, "{\\1}")),
         %Operation{} = op <- Map.get(item, verb) do
      params =
        for %Parameter{in: place, name: name} <- op.parameters || [],
            place in [:query, :path],
            do: to_string(name)

      params ++ body_keys(op.requestBody, spec)
    else
      _ -> []
    end
  end

  defp body_keys(%RequestBody{content: content}, spec) when is_map(content),
    do: content |> Map.values() |> Enum.flat_map(&schema_keys(&1.schema, spec))

  defp body_keys(_body, _spec), do: []

  defp schema_keys(%Schema{properties: props}, _spec) when is_map(props),
    do: Enum.map(Map.keys(props), &to_string/1)

  defp schema_keys(%Reference{"$ref": "#/components/schemas/" <> name}, spec) do
    case spec.components.schemas do
      %{^name => schema} -> schema_keys(schema, spec)
      _ -> []
    end
  end

  defp schema_keys(_schema, _spec), do: []

  defp source_keys(controller) do
    with source when is_list(source) <- controller.module_info(:compile)[:source],
         {:ok, text} <- File.read(List.to_string(source)) do
      ~r/"([a-z][a-z0-9_]*)"\s*=>/ |> Regex.scan(text, capture: :all_but_first) |> List.flatten()
    else
      _ -> []
    end
  end

  # Built once a test process: the document is the whole API's.
  defp spec do
    with nil <- Process.get({__MODULE__, :spec}) do
      Process.put({__MODULE__, :spec}, GamendWeb.ApiSpec.spec())
      Process.get({__MODULE__, :spec})
    end
  end

  defp path_segments(path),
    do:
      path
      |> String.split("/")
      |> Enum.filter(&(String.starts_with?(&1, ":") or String.starts_with?(&1, "*")))

  defp fill_path(path, value_for) do
    path
    |> String.split("/")
    |> Enum.map_join("/", fn segment ->
      if String.starts_with?(segment, ":") or String.starts_with?(segment, "*"),
        do: value_for.(segment),
        else: segment
    end)
  end

  # ── Channels ───────────────────────────────────────────────────────────────

  @doc false
  # A new player's token and a topic of each kind they may join: their own
  # user channel, a lobby they host and its signaling room.
  def channel_topics do
    user = admin()
    {:ok, lobby} = Gamend.Lobbies.create_lobby(%{"title" => "Wrong types", "host_id" => user.id})

    {:ok, lobby} =
      Gamend.Signaling.configure(lobby, enabled: true, topology: :mesh, reconnect_timeout: 0)

    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    %{
      :token => token,
      "user:*" => "user:#{user.id}",
      "lobby:*" => "lobby:#{lobby.id}",
      "signaling:*" => "signaling:#{lobby.id}"
    }
  end

  @doc false
  def command_payloads(%{types: types}) do
    keys = Map.keys(types)
    base = Map.new(keys, &{&1, "1"})

    wrong =
      for key <- keys,
          value <- [["a", "b"], %{"a" => "b"}, 1, true],
          do: Map.put(base, key, value)

    odd =
      for {key, type} <- types,
          text_type?(type),
          value <- ["", "nope", "-1", "99999999999999999999999999", String.duplicate("x", 5_000)],
          do: Map.put(base, key, value)

    [[1, 2], "words", 12, nil, %{}, base] ++ wrong ++ odd
  end

  # ── LiveView ───────────────────────────────────────────────────────────────

  @doc false
  def live_routes(router, extra_events, params \\ %{}) do
    case router || GamendWeb.ContractLint.router() do
      nil ->
        []

      router ->
        for route <- Phoenix.Router.routes(router),
            route.plug == Phoenix.LiveView.Plug and route.verb == :get,
            module = elem(route.metadata.phoenix_live_view, 0),
            {path, extra, opts} = extra_for(Map.get(extra_events, module, [])),
            events = events(module, extra),
            events != %{},
            uniq: true,
            do:
              {module, path || fill_live_path(route.path, params), events,
               Keyword.get(opts, :as, :admin)}
    end
    |> Enum.uniq_by(&elem(&1, 0))
  end

  # Each `:name` the host's `params:` gives a value, else `1`.
  defp fill_live_path(path, params) do
    Regex.replace(~r/[:*]([a-z_]+)/, path, fn _whole, name -> Map.get(params, name, "1") end)
  end

  @doc """
  Core's pages that mount only on a row or as a visitor, set up for every
  host's `live_tests/1` (a host's `extra_events:` wins).
  """
  @spec core_pages() :: map()
  def core_pages do
    %{
      GamendWeb.AdminLive.QuestCodes => {{__MODULE__, :quest_codes_path, []}, []},
      GamendWeb.UserLive.Confirmation => {{__MODULE__, :magic_link_path, []}, [], as: :visitor},
      GamendWeb.UserLive.Registration => {"/users/register", [], as: :visitor}
    }
  end

  @doc "A quest's codes page, on a quest made for it."
  @spec quest_codes_path(Accounts.User.t() | nil) :: String.t()
  def quest_codes_path(_player) do
    {:ok, quest} =
      Gamend.Quests.create_quest(%{
        key: "wrong_types_#{System.unique_integer([:positive])}",
        title: "Codes",
        code_only: true
      })

    "/admin/quests/#{quest.key}/codes"
  end

  @doc "A magic link's page, for a new account."
  @spec magic_link_path(Accounts.User.t() | nil) :: String.t()
  def magic_link_path(_visitor) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "wrong-types-link#{System.unique_integer([:positive])}@example.com"
      })

    me = self()

    Accounts.deliver_login_instructions(user, fn token ->
      send(me, {:wrong_types_token, token})
      "/users/log_in/#{token}"
    end)

    receive do
      {:wrong_types_token, token} -> "/users/log_in/#{token}"
    end
  end

  defp extra_for({path, modules}), do: extra_for({path, modules, []})

  defp extra_for({path, modules, opts}) when is_list(modules) and is_list(opts),
    do: {path, modules, opts}

  defp extra_for(modules) when is_list(modules), do: {nil, modules, []}

  @doc """
  A page's path: as written, or `{module, function, args}` called with the
  test's player first when it runs (a path that names a row the test makes,
  the player's own where the page is its owner's).
  """
  @spec path(String.t() | {module(), atom(), list()}, Accounts.User.t() | nil) :: String.t()
  def path({module, fun, args}, player), do: apply(module, fun, [player | args])
  def path(path, _player) when is_binary(path), do: path

  @doc false
  def path_name({module, fun, _args}), do: "#{inspect(module)}.#{fun}()"
  def path_name(path) when is_binary(path), do: path

  defp events(module, extra) do
    for source <- [module | extra],
        Code.ensure_loaded?(source) and function_exported?(source, :__live_events__, 1),
        reduce: %{} do
      acc -> Map.merge(source.__live_events__(:declared), acc)
    end
  end

  @doc false
  def live_crashes(spec, events, mount, render_hook, player) do
    path = path(spec, player)

    mount = fn
      # An event can delete the page's row: then a new one, its path again.
      :anew, _path -> mount.(player_conn(player), path(spec, player))
      # Or delete or sign out the player: then a new admin.
      :again, path -> mount.(live_conn(), path)
      :player, path -> mount.(player_conn(player), path)
    end

    case live_mount(mount, path) do
      {:ok, view} ->
        {_view, crashes} =
          Enum.reduce(events, {view, []}, fn {event, declaration}, acc ->
            Enum.reduce(
              event_payloads(declaration),
              acc,
              &send_event(mount, render_hook, path, event, &1, &2)
            )
          end)

        Enum.reverse(crashes)

      {:skip, why} ->
        [
          "#{path} did not mount (#{why}), so none of its events was sent: name a path " <>
            "it mounts at (`extra_events: %{Page => {path, []}}`), or say why it is left " <>
            "out (`skip: %{Page => \"why\"}`)"
        ]
    end
  end

  defp live_mount(mount, path, who \\ :player) do
    case mount.(who, path) do
      {:ok, view, _html} -> {:ok, view}
      other -> {:skip, inspect(other, limit: 4)}
    end
  rescue
    error -> {:skip, Exception.message(error)}
  catch
    :exit, reason -> {:skip, inspect(reason, limit: 4)}
  end

  defp send_event(_mount, _render_hook, _path, _event, _params, {:gone, crashes}),
    do: {:gone, crashes}

  defp send_event(mount, render_hook, path, event, params, {view, crashes}) do
    result =
      try do
        render_hook.(view, event, params)
      catch
        :exit, reason -> {:crashed, reason}
      end

    case result do
      {:crashed, reason} ->
        crash =
          "#{event} #{inspect(params, limit: 10)}\n  #{reason |> Exception.format_exit() |> String.slice(0, 700)}"

        {remount(mount, path, view), [crash | crashes]}

      {:error, _navigated} ->
        {remount(mount, path, view), crashes}

      _html ->
        {view, crashes}
    end
  end

  # The page again; none (an event deleted all it needs) sends the rest
  # nowhere, rather than to the page that is gone.
  defp remount(mount, path, _old) do
    with {:skip, _why} <- live_mount(mount, path),
         {:skip, _why} <- live_mount(mount, path, :anew),
         {:skip, _why} <- live_mount(mount, path, :again) do
      :gone
    else
      {:ok, view} -> view
    end
  end

  @doc false
  def event_payloads(declaration) do
    keys = for {key, spec} <- declaration, do: {to_string(key), bare(spec)}
    base = Map.new(keys, fn {key, type} -> {key, plain(type)} end)

    wrong =
      for {key, _type} <- keys,
          value <- [["a", "b"], %{"a" => "b"}, 1, nil],
          do: Map.put(base, key, value)

    odd =
      for {key, type} <- keys,
          text_type?(type),
          value <- @odd_strings,
          do: Map.put(base, key, value)

    # An id the page drew may come as a number: odd ones of those too.
    numbers =
      for {key, type} <- keys,
          bare(type) == :id,
          value <- [0, -1, 99_999_999_999_999_999_999],
          do: Map.put(base, key, value)

    left_out = for {key, {:optional, _}} <- declaration, do: Map.delete(base, to_string(key))

    [%{}, base] ++ wrong ++ odd ++ numbers ++ left_out
  end

  defp bare({:optional, type}), do: bare(type)
  defp bare({:or_blank, type}), do: bare(type)
  defp bare(type), do: type

  # A value of the declared type, so each wrong one is the only thing wrong.
  defp plain(:string), do: "1"
  defp plain(:uuid), do: "00000000-0000-0000-0000-000000000000"
  defp plain(:id), do: "1"
  defp plain(:integer), do: "1"
  defp plain(:boolean), do: "true"
  defp plain({:in, [value | _]}), do: value
  defp plain({:list, type}), do: [plain(bare(type))]
  defp plain({:map_of, type}), do: %{"a" => plain(bare(type))}
  defp plain({:schema, _module}), do: %{}
  defp plain({:free, _reason}), do: "1"

  defp plain(keys) when is_list(keys),
    do: Map.new(keys, fn {k, t} -> {to_string(k), plain(bare(t))} end)

  defp text_type?(type),
    do: bare(type) in [:string, :id, :integer, :uuid] or match?({:free, _}, bare(type))
end
