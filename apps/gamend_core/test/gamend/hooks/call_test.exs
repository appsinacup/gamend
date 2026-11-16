defmodule Gamend.Hooks.CallTest do
  use ExUnit.Case, async: false

  setup do
    orig = Application.get_env(:gamend_core, :hooks_module)
    on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, orig) end)
    :ok
  end

  test "call invokes exported function and exported_functions lists it" do
    n = System.unique_integer([:positive])
    mod = Module.concat([Gamend, TestHooks, String.to_atom("CallTest_#{n}")])

    # Create a simple module with a couple of public functions
    Module.create(
      mod,
      quote do
        def hello(a), do: {:hello, a}
        def add(a, b), do: a + b
      end,
      __ENV__
    )

    Application.put_env(:gamend_core, :hooks_module, mod)

    assert {:ok, {:hello, "x"}} = Gamend.Hooks.call(:hello, ["x"])
    assert {:ok, 3} = Gamend.Hooks.call(:add, [1, 2])

    funcs = Gamend.Hooks.exported_functions()
    names = Enum.map(funcs, & &1.name)
    assert "hello" in names
    assert "add" in names
  end

  test "private defp functions are hidden and not callable via public call/3" do
    n = System.unique_integer([:positive])
    mod = Module.concat([Gamend, TestHooks, String.to_atom("HiddenTest_#{n}")])

    Module.create(
      mod,
      quote do
        defp hidden, do: :secret
        def visible, do: :ok
      end,
      __ENV__
    )

    Application.put_env(:gamend_core, :hooks_module, mod)

    funcs = Gamend.Hooks.exported_functions()
    names = Enum.map(funcs, & &1.name)

    assert "visible" in names
    refute "hidden" in names

    # defp functions are not exported and call/3 should report not_implemented
    assert {:error, :not_implemented} = Gamend.Hooks.call(:hidden, [])
  end

  test "docs, signatures and example args come from the module's beam" do
    mod =
      Module.concat([
        Gamend,
        TestHooks,
        String.to_atom("DocsTest_#{System.unique_integer([:positive])}")
      ])

    # `mix test` compiles without docs; a plugin is compiled with them.
    docs = Code.get_compiler_option(:docs)
    Code.put_compiler_option(:docs, true)

    {:module, ^mod, beam, _} =
      try do
        Module.create(
          mod,
          quote do
            @moduledoc false
            @doc "Does something.\n\nReturns: a special return value"
            def foo(count), do: {:ok, count}

            @doc "No-arg function"
            def no_args, do: :ok
          end,
          __ENV__
        )
      after
        Code.put_compiler_option(:docs, docs)
      end

    # Docs are read from a beam on the code path, as a plugin's ebin is: a
    # module that only exists in memory has none.
    dir = Path.join(System.tmp_dir!(), "gs-hooks-docs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "#{mod}.beam"), beam)
    :code.purge(mod)
    :code.delete(mod)
    Code.prepend_path(dir)

    on_exit(fn ->
      Code.delete_path(dir)
      File.rm_rf!(dir)
    end)

    {:module, ^mod} = Code.ensure_loaded(mod)

    Application.put_env(:gamend_core, :hooks_module, mod)
    funcs = Gamend.Hooks.exported_functions()

    assert %{signatures: [foo]} = Enum.find(funcs, &(&1.name == "foo"))
    assert foo.doc =~ "Returns: a special return value"
    assert foo.signature == "foo(count)"
    assert foo.example_args == "[0]"

    assert %{signatures: [no_args]} = Enum.find(funcs, &(&1.name == "no_args"))
    assert no_args.signature == "no_args()"
    assert no_args.example_args == "[]"
  end

  test "call returns :not_implemented for missing function" do
    m = System.unique_integer([:positive])
    mod = Module.concat([Gamend, TestHooks, String.to_atom("CallTestMissing_#{m}")])

    Module.create(
      mod,
      quote do
        def ok, do: :ok
      end,
      __ENV__
    )

    Application.put_env(:gamend_core, :hooks_module, mod)

    assert {:error, :not_implemented} = Gamend.Hooks.call(:does_not_exist, [])
  end

  test "call returns a structured error on bad arg types (function clause)" do
    m = System.unique_integer([:positive])
    mod = Module.concat([Gamend, TestHooks, String.to_atom("CallTestType_#{m}")])

    Module.create(
      mod,
      quote do
        def hello(name) when is_binary(name), do: "hi: #{name}"
      end,
      __ENV__
    )

    Application.put_env(:gamend_core, :hooks_module, mod)

    assert {:error, {:function_clause, _msg}} = Gamend.Hooks.call(:hello, [1])
  end

  test "a hook that raises answers exception and logs the stack trace" do
    m = System.unique_integer([:positive])
    mod = Module.concat([Gamend, TestHooks, String.to_atom("CallTestRaise_#{m}")])

    Module.create(
      mod,
      quote do
        def boom(_arg), do: raise("boom")

        # The clause that refuses is deeper in the plugin, not the hook's own:
        # a bug, not the caller's arguments.
        def deep(arg), do: inner(arg)
        def inner(n) when is_integer(n), do: n
      end,
      __ENV__
    )

    Application.put_env(:gamend_core, :hooks_module, mod)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:exception, "boom"}} = Gamend.Hooks.call(:boom, [1])
        assert {:error, {:exception, _msg}} = Gamend.Hooks.call(:deep, ["x"])
      end)

    assert log =~ "#{inspect(mod)}.boom/1 raised"
    assert log =~ "(RuntimeError) boom"
    assert log =~ "#{inspect(mod)}.deep/1 raised"
    assert log =~ "FunctionClauseError"
  end

  test "call exposes caller context available via Gamend.Hooks.caller/0 and caller_id/0" do
    mod =
      Module.concat([
        Gamend,
        TestHooks,
        String.to_atom("CallerTest_#{System.unique_integer([:positive])}")
      ])

    Module.create(
      mod,
      quote do
        def who_called, do: Gamend.Hooks.caller()
        def who_called_id, do: Gamend.Hooks.caller_id()
      end,
      __ENV__
    )

    Application.put_env(:gamend_core, :hooks_module, mod)

    caller = %{id: 999, email: "caller@example.com"}

    assert {:ok, ^caller} = Gamend.Hooks.call(:who_called, [], caller: caller)
    assert {:ok, 999} = Gamend.Hooks.call(:who_called_id, [], caller: caller)
  end

  test "caller_user/0 resolves user struct when caller is id or struct" do
    # Use a plain struct here (no DB dependency) to test struct-path resolution
    user = %Gamend.Accounts.User{id: 123_456, email: "caller@example.com"}

    mod =
      Module.concat([
        Gamend,
        TestHooks,
        String.to_atom("CallerUserTest_#{System.unique_integer([:positive])}")
      ])

    Module.create(
      mod,
      quote do
        def who_called_user, do: Gamend.Hooks.caller_user()
      end,
      __ENV__
    )

    Application.put_env(:gamend_core, :hooks_module, mod)

    # call with full struct (we avoid DB-dependent id resolution in tests)
    assert {:ok, %Gamend.Accounts.User{id: id2}} =
             Gamend.Hooks.call(:who_called_user, [], caller: user)

    assert id2 == user.id
  end

  test "exported_functions lists a module from another BEAM language" do
    # A Gleam or Erlang plugin has no `__info__/1`; listing it used to crash
    # `GET /api/v1/hooks` with an UndefinedFunctionError.
    names = :math |> Gamend.Hooks.exported_functions() |> Enum.map(& &1.name)

    assert "sqrt" in names
    refute "module_info" in names
  end

  test "exported_functions returns empty for default module and handles multiple arities" do
    # ensure default module is used
    Application.put_env(:gamend_core, :hooks_module, Gamend.Hooks.Default)

    assert Gamend.Hooks.exported_functions() == []

    # create module with multiple arities and a function lacking docs or source
    mod =
      Module.concat([
        Gamend,
        TestHooks,
        String.to_atom("MultiArity_#{System.unique_integer([:positive])}")
      ])

    Module.create(
      mod,
      quote do
        def foo(a), do: a
        def foo(a, b), do: a + b
        def no_doc, do: :ok
      end,
      __ENV__
    )

    Application.put_env(:gamend_core, :hooks_module, mod)

    funcs = Gamend.Hooks.exported_functions()
    foo = Enum.find(funcs, &(&1.name == "foo"))

    assert foo != nil
    assert Enum.sort(foo.arities) == [1, 2]

    no_doc = Enum.find(funcs, &(&1.name == "no_doc"))
    assert no_doc != nil
    # signature may be nil when neither docs nor source are available
    assert Enum.any?(no_doc.signatures, fn s -> s.signature == nil end)
  end
end
