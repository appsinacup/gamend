defmodule GamendWeb.AdminLive.PluginsTest do
  # Points the plugins directory at a temporary one and reloads, which is global.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Hooks.PluginManager
  alias Gamend.Repo
  alias Gamend.SettingsHelpers

  @plugin "admin_test_plugin"

  setup %{conn: conn} do
    admin =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update!()

    install_plugin()
    %{conn: log_in_user(conn, admin)}
  end

  defp install_plugin do
    tmp = Path.join(System.tmp_dir!(), "gs-admin-plugin-#{System.unique_integer([:positive])}")
    plugin_root = Path.join(tmp, "modules/plugins")
    ebin_dir = Path.join([plugin_root, @plugin, "ebin"])
    File.mkdir_p!(ebin_dir)

    hook_mod = Module.concat([Gamend, AdminPluginsTestHook])

    src = """
    defmodule #{inspect(hook_mod)} do
      def after_startup, do: [%{hook: "custom_hello"}]
      def before_stop, do: :ok

      def on_custom_hook("custom_hello", _args), do: "hello"
      def on_custom_hook(_hook, _args), do: {:error, :not_implemented}

      @doc "Say hi with two names"
      def hello2(name, name2), do: "Hello2, \#{name} \#{name2}!"

      @doc "Say hi to a user"
      def hello(name), do: "Hello, \#{name}!"
    end
    """

    [{^hook_mod, beam}] = Code.compile_string(src)
    File.write!(Path.join(ebin_dir, Atom.to_string(hook_mod) <> ".beam"), beam)

    app_term =
      {:application, String.to_atom(@plugin),
       [
         {:description, ~c"admin test plugin"},
         {:vsn, ~c"0.1.0"},
         {:modules, [hook_mod]},
         {:registered, []},
         {:applications, [:kernel, :stdlib]},
         {:env, [hooks_module: to_charlist(Atom.to_string(hook_mod))]}
       ]}

    File.write!(
      Path.join(ebin_dir, "#{@plugin}.app"),
      :io_lib.format(~c"~p.~n", [app_term]) |> IO.iodata_to_binary()
    )

    previous = SettingsHelpers.get(:gamend_core, Gamend.ContentSettings, :plugins_dir)
    SettingsHelpers.put(:gamend_core, Gamend.ContentSettings, :plugins_dir, plugin_root)
    _ = PluginManager.reload()

    on_exit(fn ->
      if previous,
        do: SettingsHelpers.put(:gamend_core, Gamend.ContentSettings, :plugins_dir, previous),
        else: SettingsHelpers.delete(:gamend_core, Gamend.ContentSettings, :plugins_dir)

      _ = PluginManager.reload()
      File.rm_rf!(tmp)
    end)
  end

  defp call_form(view), do: element(view, "#plugins-call-form")

  defp select_function(view, function) do
    view
    |> call_form()
    |> render_change(%{
      "_target" => ["call", "function"],
      "call" => %{"plugin" => @plugin, "function" => function}
    })
  end

  defp args_value(view) do
    view
    |> element("#call_args")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
  end

  test "lists the plugin and its status", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    assert has_element?(view, "#plugin-#{@plugin}", "OK")
    assert has_element?(view, "#plugin-#{@plugin} button[phx-value-plugin='#{@plugin}']")
    assert has_element?(view, "#plugins-reload-btn")
  end

  test "choosing a function selects it and fills in the shape of its arguments", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    select_function(view, "hello2")

    assert has_element?(view, "#call_function option[selected][value='hello2']")
    assert has_element?(view, "#plugins-functions button[aria-current='true']", "hello2/2")
    assert args_value(view) == "[null,null]"
  end

  test "clicking a function in the list selects it too", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    view |> element("button[phx-value-function='hello']") |> render_click()

    assert has_element?(view, "#call_function option[selected][value='hello']")
    assert args_value(view) == "[null]"
  end

  test "calls the function and shows what it answered", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    view
    |> call_form()
    |> render_submit(%{
      "call" => %{
        "plugin" => @plugin,
        "function" => "hello2",
        "args" => ~s(["Ada", "Grace"]),
        "format" => "json"
      }
    })

    assert has_element?(view, "#plugins-call-result", "Hello2, Ada Grace!")
  end

  test "arguments that are not JSON are refused, not called with none", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    view
    |> call_form()
    |> render_submit(%{
      "call" => %{
        "plugin" => @plugin,
        "function" => "hello",
        "args" => "[oops",
        "format" => "json"
      }
    })

    assert has_element?(view, "#plugins-call-result", "not valid JSON")
  end

  test "typing arguments keeps them, and a reload does too", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    view
    |> call_form()
    |> render_change(%{
      "_target" => ["call", "args"],
      "call" => %{"plugin" => @plugin, "function" => "hello", "args" => ~s(["Ada"])}
    })

    assert args_value(view) == ~s(["Ada"])

    view |> element("#plugins-reload-btn") |> render_click()

    assert has_element?(view, "#plugins-reload-result")
    assert args_value(view) == ~s(["Ada"])
  end

  test "a URL naming a function that does not exist opens the first one", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins?plugin=nope&fn=nope")

    assert has_element?(view, "#call_plugin option[selected][value='#{@plugin}']")
  end

  test "a URL can open a function", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins?plugin=#{@plugin}&fn=hello2")

    assert has_element?(view, "#call_function option[selected][value='hello2']")
  end

  test "shows the schema coverage", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plugins")

    assert has_element?(view, "#plugins-coverage", "kv data")
    assert has_element?(view, "#plugins-coverage", "typed hooks")
  end
end
