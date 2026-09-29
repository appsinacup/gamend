defmodule Gamend.GDScriptTest do
  use ExUnit.Case, async: true

  alias Gamend.GDScript
  alias Gamend.GDScript.CompileError

  # Compile a script and load it, so assertions are about behaviour rather than
  # about the text we happened to emit. Text assertions live in "output" below;
  # everything else runs the thing.
  defp load!(source) do
    module = "GDTest#{System.unique_integer([:positive])}"
    elixir = GDScript.compile_string(source, module, file: "test.gd")
    [{mod, _binary}] = compile_without_warnings!(elixir)
    mod
  end

  # Generated code that warns is a codegen bug -- an emitted-but-unused helper,
  # a clause that cannot match. Elixir finds those for free, but only if
  # nothing swallows them, so every test in this file asserts on a silent
  # compile. (`Code.put_compiler_option(:warnings_as_errors, true)` does not
  # reach `Code.compile_string/2`; capturing stderr does.)
  defp compile_without_warnings!(source) do
    {modules, output} =
      ExUnit.CaptureIO.with_io(:stderr, fn -> Code.compile_string(source, "test.gd") end)

    if output != "" do
      flunk("generated code compiled with warnings:\n\n#{output}\n#{source}")
    end

    modules
  end

  defp compile!(source), do: GDScript.compile_string(source, "T", file: "test.gd")

  describe "semantics that differ from Elixir" do
    test "two ints divide to an int" do
      mod = load!("func f(a, b):\n\treturn a / b\n")

      assert mod.f(7, 2) == 3
      assert mod.f(7.0, 2) == 3.5
    end

    test "`+` concatenates strings and arrays" do
      mod = load!("func s(a, b):\n\treturn a + b\n")

      assert mod.s("ab", "cd") == "abcd"
      assert mod.s([1], [2]) == [1, 2]
      assert mod.s(1, 2) == 3
    end

    test "0, empty string and empty array are falsy" do
      mod =
        load!(
          "func f(value):\n\tvar out = \"falsy\"\n\tif value:\n\t\tout = \"truthy\"\n\treturn out\n"
        )

      for falsy <- [0, 0.0, "", [], %{}, nil, false] do
        assert mod.f(falsy) == "falsy", "expected #{inspect(falsy)} to be falsy"
      end

      for truthy <- [1, -1, 0.5, "x", [nil], %{a: 1}, true] do
        assert mod.f(truthy) == "truthy", "expected #{inspect(truthy)} to be truthy"
      end
    end

    test "`%` is rem on integers" do
      mod = load!("func f(a, b):\n\treturn a % b\n")
      assert mod.f(7, 3) == 1
    end
  end

  describe "mutation lifting" do
    test "an if branch rebinds a variable declared outside it" do
      mod =
        load!(
          "func f(score):\n\tvar bonus = 0\n\tif score > 10:\n\t\tbonus = 50\n\treturn bonus\n"
        )

      assert mod.f(20) == 50
      assert mod.f(1) == 0
    end

    test "several variables across an elif chain" do
      mod =
        load!("""
        func f(score):
        \tvar tier = "bronze"
        \tvar bonus = 0
        \tif score >= 90:
        \t\ttier = "gold"
        \t\tbonus = 100
        \telif score >= 50:
        \t\ttier = "silver"
        \t\tbonus = 25
        \telse:
        \t\tbonus = -1
        \treturn [tier, bonus]
        """)

      assert mod.f(95) == ["gold", 100]
      assert mod.f(60) == ["silver", 25]
      assert mod.f(10) == ["bronze", -1]
    end

    test "nested ifs with overlapping assigned sets" do
      mod =
        load!("""
        func f(a, b):
        \tvar x = 1
        \tvar y = 2
        \tif a > 0:
        \t\tx = 10
        \t\tif b > 0:
        \t\t\ty = 20
        \t\t\tx = 30
        \treturn [x, y]
        """)

      assert mod.f(1, 1) == [30, 20]
      assert mod.f(1, -1) == [10, 2]
      assert mod.f(-1, 1) == [1, 2]
    end

    test "a var declared inside a branch is block-scoped, not lifted" do
      # `temp` exists only in the branch. Were it lifted, the generated module
      # would bind a name nothing outside declares.
      elixir =
        compile!("""
        func f(a):
        \tvar out = 0
        \tif a > 0:
        \t\tvar temp = 5
        \t\tout = temp
        \treturn out
        """)

      refute elixir =~ "{out, temp}"
      refute elixir =~ "{temp, out}"
    end

    test "compound assignment inside a branch" do
      mod =
        load!("""
        func f(n):
        \tvar total = 100
        \tif n > 0:
        \t\ttotal += n
        \t\ttotal *= 2
        \treturn total
        """)

      assert mod.f(5) == 210
      assert mod.f(0) == 100
    end
  end

  describe "loops" do
    test "for accumulates across iterations" do
      mod =
        load!("""
        func f(xs):
        \tvar total = 0
        \tfor x in xs:
        \t\ttotal += x
        \treturn total
        """)

      assert mod.f([1, 2, 3]) == 6
      assert mod.f([]) == 0
    end

    test "for over range()" do
      mod =
        load!("""
        func f(n):
        \tvar total = 0
        \tfor i in range(n):
        \t\ttotal += i
        \treturn total
        """)

      assert mod.f(4) == 6
      assert mod.f(0) == 0
    end

    test "a for that assigns nothing becomes a plain walk" do
      elixir = compile!("func f(xs):\n\tfor x in xs:\n\t\tprint(x)\n")

      assert elixir =~ "Enum.each("
      refute elixir =~ "Enum.reduce"
    end

    test "the loop variable is not lifted out" do
      mod =
        load!("""
        func f(xs):
        \tvar last = 0
        \tfor x in xs:
        \t\tlast = x
        \treturn last
        """)

      assert mod.f([1, 2, 3]) == 3
    end

    test "break leaves the loop with the values so far" do
      mod =
        load!("""
        func f(xs):
        \tvar total = 0
        \tfor x in xs:
        \t\tif x < 0:
        \t\t\tbreak
        \t\ttotal += x
        \treturn total
        """)

      assert mod.f([1, 2, -1, 100]) == 3
      assert mod.f([1, 2, 3]) == 6
    end

    test "continue skips the rest of the iteration" do
      mod =
        load!("""
        func f(xs):
        \tvar total = 0
        \tfor x in xs:
        \t\tif x < 0:
        \t\t\tcontinue
        \t\ttotal += x
        \treturn total
        """)

      assert mod.f([1, -5, 2, -7, 3]) == 6
    end

    test "while loops over an accumulator" do
      mod =
        load!("""
        func f(hp, dmg):
        \tvar turns = 0
        \twhile hp > 0:
        \t\thp -= dmg
        \t\tturns += 1
        \treturn turns
        """)

      assert mod.f(10, 3) == 4
      assert mod.f(0, 3) == 0
    end

    test "break inside while" do
      mod =
        load!("""
        func f(limit):
        \tvar n = 0
        \twhile true:
        \t\tn += 1
        \t\tif n >= limit:
        \t\t\tbreak
        \treturn n
        """)

      assert mod.f(5) == 5
    end

    test "nested loops with overlapping assigned sets" do
      mod =
        load!("""
        func f(rows, cols):
        \tvar cells = 0
        \tvar rows_seen = 0
        \tfor r in rows:
        \t\trows_seen += 1
        \t\tfor c in cols:
        \t\t\tcells += 1
        \treturn [rows_seen, cells]
        """)

      assert mod.f([1, 2], [1, 2, 3]) == [2, 6]
    end

    test "a break in an inner loop does not exit the outer one" do
      mod =
        load!("""
        func f(rows, cols):
        \tvar cells = 0
        \tfor r in rows:
        \t\tfor c in cols:
        \t\t\tif c > 1:
        \t\t\t\tbreak
        \t\t\tcells += 1
        \treturn cells
        """)

      # Inner loop stops at the first c > 1 on every outer pass.
      assert mod.f([1, 2, 3], [1, 2, 3]) == 3
    end

    test "return inside a loop leaves the function, not just the loop" do
      mod =
        load!("""
        func f(xs, target):
        \tfor x in xs:
        \t\tif x == target:
        \t\t\treturn "found"
        \treturn "missing"
        """)

      assert mod.f([1, 2, 3], 2) == "found"
      assert mod.f([1, 2, 3], 9) == "missing"
    end

    test "a loop calling a context function" do
      elixir =
        compile!(
          "func f(users):\n\tfor u in users:\n\t\tEconomy.grant(u.id, \"gold\", 5, opts({\"reason\": \"bulk\"}))\n"
        )

      assert elixir =~ "Enum.each("
      assert elixir =~ "Gamend.Economy.grant(gd_get(u, :id), \"gold\", 5, reason: \"bulk\")"
    end
  end

  describe "return" do
    test "a tail return needs no try/catch" do
      refute compile!("func f(a):\n\treturn a\n") =~ "try do"
    end

    test "an early return inside a branch throws and is caught" do
      mod = load!("func f(a):\n\tif a == 0:\n\t\treturn \"zero\"\n\treturn \"nonzero\"\n")

      assert mod.f(0) == "zero"
      assert mod.f(1) == "nonzero"
    end

    test "a bare return yields nil" do
      mod = load!("func f(a):\n\tif a:\n\t\treturn\n\treturn \"kept\"\n")

      assert mod.f(true) == nil
      assert mod.f(false) == "kept"
    end
  end

  describe "calls and access" do
    test "a context call becomes a Gamend module call" do
      assert compile!("func f(user):\n\tEconomy.grant(user.id, \"gold\", 10)\n") =~
               "Gamend.Economy.grant("
    end

    test "field access reads structs, atom maps and string maps alike" do
      mod = load!("func f(record):\n\treturn record.name\n")

      assert mod.f(%{name: "atom"}) == "atom"
      assert mod.f(%{"name" => "string"}) == "string"
      assert mod.f("not a map") == nil
    end

    test "indexing works on arrays and dictionaries" do
      mod = load!("func f(container, key):\n\treturn container[key]\n")

      assert mod.f(["a", "b"], 1) == "b"
      assert mod.f(%{"k" => "v"}, "k") == "v"
    end

    test "a local func can be called by name" do
      mod =
        load!("func double(n):\n\treturn n * 2\n\nfunc quad(n):\n\treturn double(double(n))\n")

      assert mod.quad(3) == 12
    end

    test "default arguments" do
      mod = load!("func f(a, b = 10):\n\treturn a + b\n")

      assert mod.f(1) == 11
      assert mod.f(1, 2) == 3
    end

    test "dictionary literals become string-keyed maps" do
      mod = load!("func f(name):\n\treturn {\"title\": name, \"read\": false}\n")
      assert mod.f("hi") == %{"title" => "hi", "read" => false}
    end
  end

  describe "opts() keyword lists" do
    test "becomes a keyword list" do
      elixir =
        compile!(
          "func f(id):\n\tEconomy.grant(id, \"gold\", 10, opts({\"reason\": \"welcome\"}))\n"
        )

      assert elixir =~ "Gamend.Economy.grant(id, \"gold\", 10, reason: \"welcome\")"
    end

    test "several options keep their order" do
      mod =
        load!("func f(a):\n\treturn opts({\"reason\": \"x\", \"idempotency_key\": a})\n")

      assert mod.f("k") == [reason: "x", idempotency_key: "k"]
      assert Keyword.get(mod.f("k"), :reason) == "x"
    end

    test "a trailing Dictionary is still a map, not options" do
      # The distinguishing case: this argument is a payload, and inferring
      # options from position would silently corrupt it.
      elixir =
        compile!(
          "func f(a):\n\tNotifications.admin_create_notification(a, a, {\"title\": \"hi\"})\n"
        )

      assert elixir =~ "%{\"title\" => \"hi\"}"
      refute elixir =~ "title:"
    end

    test "keys must be plain lowercase names" do
      assert_raise CompileError, ~r/plain lowercase names/, fn ->
        compile!("func f():\n\treturn opts({\"Not Valid\": 1})\n")
      end
    end

    test "keys must be literals" do
      assert_raise CompileError, ~r/string literals/, fn ->
        compile!("func f(k):\n\treturn opts({k: 1})\n")
      end
    end

    test "takes exactly one Dictionary" do
      assert_raise CompileError, ~r/exactly one Dictionary/, fn ->
        compile!("func f():\n\treturn opts(1, 2)\n")
      end
    end

    test "a builtin cannot be shadowed by a local func" do
      assert_raise CompileError, ~r/built-in and cannot be redefined/, fn ->
        compile!("func opts(a):\n\treturn a\n")
      end
    end
  end

  describe "the API table" do
    alias Gamend.GDScript.API

    test "comes from @sdk_modules, not a hand-kept list" do
      # The point of generating it: a context added to gen.sdk is callable from
      # a script with no change here.
      assert "Economy" in API.contexts()
      assert "Tournaments" in API.contexts()
      assert API.arities("Economy", "grant") == [3, 4]
    end

    test "includes contexts whose stub is hand-written" do
      # `Gamend.Cache` and `Gamend.Hooks` are outside @sdk_modules but are still
      # callable from an Elixir plugin, so a script must reach them too.
      assert "Cache" in API.contexts()
      assert API.arities("Hooks", "caller_user") == [0]
    end

    test "a default argument makes both arities callable" do
      assert compile!("func f(u):\n\tEconomy.grant(u, \"gold\", 1)\n") =~ "Gamend.Economy.grant("

      assert compile!("func f(u):\n\tEconomy.grant(u, \"gold\", 1, opts({\"reason\": \"x\"}))\n") =~
               "reason: \"x\""
    end

    test "a wrong argument count is a compile error" do
      error =
        assert_raise CompileError, fn ->
          compile!("func f(u):\n\tEconomy.grant(u, \"gold\")\n")
        end

      assert Exception.message(error) =~ "takes 3 or 4 argument(s), called with 2"
    end

    test "an unknown function on a known context names the near miss" do
      error =
        assert_raise CompileError, fn ->
          compile!("func f(u):\n\tEconomy.grnt(u, \"gold\", 1)\n")
        end

      assert Exception.message(error) =~ "has no function `grnt`"
      assert Exception.message(error) =~ "did you mean `grant`?"
    end

    test "a misspelled context names the near miss and lists the rest" do
      error = assert_raise CompileError, fn -> compile!("func f():\n\tEconomny.grant(1)\n") end

      assert Exception.message(error) =~ "did you mean `Economy`?"
      assert Exception.message(error) =~ "available: Accounts,"
    end
  end

  describe "lambdas, spawn and await" do
    test "a single-line lambda" do
      mod = load!("func f(n):\n\tvar double = func(x): return x * 2\n\treturn double.call(n)\n")
      assert mod.f(5) == 10
    end

    test "a multi-line lambda" do
      mod =
        load!("""
        func f(n):
        \tvar scale = func(x):
        \t\tvar total = x * 10
        \t\treturn total
        \treturn scale.call(n)
        """)

      assert mod.f(3) == 30
    end

    test "a lambda captures the enclosing scope by value" do
      mod =
        load!("""
        func f(base):
        \tvar add = func(x): return x + base
        \tbase = 100
        \treturn [add.call(1), base]
        """)

      # GDScript lambdas capture by value, so reassigning `base` afterwards
      # does not change what the lambda closed over.
      assert mod.f(10) == [11, 100]
    end

    test "an early return inside a lambda returns from the lambda" do
      mod =
        load!("""
        func f(n):
        \tvar classify = func(x):
        \t\tif x < 0:
        \t\t\treturn "negative"
        \t\treturn "positive"
        \treturn classify.call(n)
        """)

      assert mod.f(-1) == "negative"
      assert mod.f(1) == "positive"
    end

    test "spawn runs a lambda concurrently and await collects it" do
      mod =
        load!("""
        func f(a, b):
        \tvar left = spawn(func(): return a * 2)
        \tvar right = spawn(func(): return b * 3)
        \treturn [await left, await right]
        """)

      assert mod.f(2, 3) == [4, 9]
    end

    test "spawn requires a lambda" do
      assert_raise CompileError, ~r/exactly one lambda/, fn ->
        compile!("func f():\n\treturn spawn(1)\n")
      end
    end

    test "an unknown method is refused with a suggestion" do
      assert_raise CompileError, ~r/unknown method `.bnd\(\)`/, fn ->
        compile!("func f(cb):\n\treturn cb.bnd(1)\n")
      end
    end

    test "an unknown PascalCase name is still an unknown context" do
      assert_raise CompileError, ~r/unknown context/, fn ->
        compile!("func f():\n\treturn Wallet.call(1)\n")
      end
    end

    test "a multi-line lambda inside brackets is refused with advice" do
      assert_raise CompileError, ~r/cannot be written inside brackets/, fn ->
        compile!("func f():\n\treturn spawn(func():\n\t\tvar n = 1\n\t\treturn n\n\t)\n")
      end
    end

    test "a lambda parameter cannot have a default" do
      assert_raise CompileError, ~r/cannot have a default/, fn ->
        compile!("func f():\n\tvar g = func(x = 1): return x\n\treturn g.call()\n")
      end
    end

    test "spawn cannot be redefined" do
      assert_raise CompileError, ~r/built-in and cannot be redefined/, fn ->
        compile!("func spawn(a):\n\treturn a\n")
      end
    end
  end

  describe "single-line bodies" do
    test "if on one line" do
      mod = load!("func f(a):\n\tif a: return \"yes\"\n\treturn \"no\"\n")

      assert mod.f(true) == "yes"
      assert mod.f(0) == "no"
    end

    test "if/else on one line each" do
      mod = load!("func f(a):\n\tvar out = 0\n\tif a: out = 1\n\telse: out = 2\n\treturn out\n")

      assert mod.f(true) == 1
      assert mod.f(false) == 2
    end

    test "a one-line loop body" do
      mod = load!("func f(xs):\n\tvar n = 0\n\tfor x in xs: n += x\n\treturn n\n")
      assert mod.f([1, 2, 3]) == 6
    end
  end

  describe "match" do
    test "literal, multi-pattern, bind and fallthrough" do
      mod =
        load!("""
        func rank(score):
        \tvar label = "unranked"
        \tmatch score:
        \t\t0:
        \t\t\tlabel = "zero"
        \t\t1, 2, 3:
        \t\t\tlabel = "low"
        \t\t"vip":
        \t\t\tlabel = "special"
        \t\tvar other:
        \t\t\tlabel = "other:" + str(other)
        \treturn label
        """)

      assert mod.rank(0) == "zero"
      assert mod.rank(2) == "low"
      assert mod.rank(3) == "low"
      assert mod.rank("vip") == "special"
      assert mod.rank(99) == "other:99"
    end

    test "a match with no catch-all does nothing when nothing matches" do
      # GDScript falls through silently; Elixir's `case` would raise, so a
      # fallback clause is appended.
      mod = load!("func f(x):\n\tvar hit = false\n\tmatch x:\n\t\t1: hit = true\n\treturn hit\n")

      assert mod.f(1) == true
      assert mod.f(9) == false
    end

    test "a `_` case is the catch-all" do
      mod =
        load!(
          "func f(x):\n\tvar out = 0\n\tmatch x:\n\t\t1: out = 10\n\t\t_: out = -1\n\treturn out\n"
        )

      assert mod.f(1) == 10
      assert mod.f(5) == -1
    end

    test "negative literals" do
      mod =
        load!(
          "func f(x):\n\tvar out = \"\"\n\tmatch x:\n\t\t-1: out = \"neg\"\n\t\t_: out = \"other\"\n\treturn out\n"
        )

      assert mod.f(-1) == "neg"
      assert mod.f(1) == "other"
    end

    test "match inside a loop can break" do
      mod =
        load!("""
        func f(xs):
        \tvar total = 0
        \tfor x in xs:
        \t\tmatch x:
        \t\t\t0: break
        \t\t\t_: total += x
        \treturn total
        """)

      assert mod.f([1, 2, 0, 100]) == 3
    end

    test "array patterns, open and closed" do
      mod =
        load!("""
        func f(v):
        \tmatch v:
        \t\t[]:
        \t\t\treturn "empty"
        \t\t[var only]:
        \t\t\treturn "one:" + str(only)
        \t\t[1, var second, ..]:
        \t\t\treturn "starts with 1 then " + str(second)
        \t\t_:
        \t\t\treturn "other"
        """)

      assert mod.f([]) == "empty"
      assert mod.f([7]) == "one:7"
      assert mod.f([1, 2, 3]) == "starts with 1 then 2"
      assert mod.f([9, 9]) == "other"
    end

    test "dictionary patterns, closed by default and open with `..`" do
      mod =
        load!("""
        func f(v):
        \tmatch v:
        \t\t{"kind": "gold", "amount": var amount}:
        \t\t\treturn amount
        \t\t{"kind": "item", ..}:
        \t\t\treturn "item"
        \t\t_:
        \t\t\treturn "unknown"
        """)

      assert mod.f(%{"kind" => "gold", "amount" => 5}) == 5
      # Closed: an extra key means the first pattern no longer matches.
      assert mod.f(%{"kind" => "gold", "amount" => 5, "extra" => 1}) == "unknown"
      assert mod.f(%{"kind" => "item", "code" => "sword"}) == "item"
    end

    test "a destructuring pattern cannot be one of several alternatives" do
      assert_raise CompileError, ~r/cannot be one of several alternatives/, fn ->
        compile!("func f(x):\n\tmatch x:\n\t\t1, [2]: pass\n")
      end
    end

    test "a catch-all cannot be combined with other patterns" do
      assert_raise CompileError, ~r/cannot be combined/, fn ->
        compile!("func f(x):\n\tmatch x:\n\t\t1, _: pass\n")
      end
    end
  end

  describe "value types" do
    test "construction and component access" do
      mod = load!("func f(a, b):\n\tvar p = Vector2(a, b)\n\treturn [p, p.x, p.y]\n")
      assert mod.f(4, 6) == [%{x: 4, y: 6}, 4, 6]
    end

    test "Vector3 and Color, with Color's alpha defaulting" do
      mod = load!("func f():\n\treturn [Vector3(1, 2, 3), Color(1, 0, 0), Color(1, 0, 0, 0.5)]\n")

      assert mod.f() == [
               %{x: 1, y: 2, z: 3},
               %{r: 1, g: 0, b: 0, a: 1.0},
               %{r: 1, g: 0, b: 0, a: 0.5}
             ]
    end

    test "component-wise arithmetic and scaling" do
      mod =
        load!("""
        func f(a, b):
        \tvar p = Vector2(a, b)
        \tvar q = Vector2(1, 1)
        \treturn [p + q, p - q, p * 3, 2 * q]
        """)

      assert mod.f(4, 6) == [%{x: 5, y: 7}, %{x: 3, y: 5}, %{x: 12, y: 18}, %{x: 2, y: 2}]
    end

    test "scalar arithmetic is unaffected" do
      mod = load!("func f(a, b):\n\treturn [a - b, a * b, a + b, a / b]\n")
      assert mod.f(8, 2) == [6, 16, 10, 4]
    end

    test "a Dictionary is not a value type" do
      # String keys, so the helpers leave it alone rather than merging it.
      mod = load!("func f(d):\n\treturn d\n")
      assert mod.f(%{"x" => 1}) == %{"x" => 1}

      assert_raise ArithmeticError, fn ->
        load!("func f(a, b):\n\treturn a + b\n").f(%{"x" => 1}, %{"x" => 2})
      end
    end

    test "a wrong argument count is a compile error" do
      assert_raise CompileError, ~r/`Vector2` takes 2 argument\(s\), called with 3/, fn ->
        compile!("func f():\n\treturn Vector2(1, 2, 3)\n")
      end
    end

    test "a value type cannot be redefined" do
      assert_raise CompileError, ~r/built-in and cannot be redefined/, fn ->
        compile!("func Vector2(a, b):\n\treturn a\n")
      end
    end
  end

  describe "reference semantics" do
    # Arrays and Dictionaries are reference types in GDScript. These are the
    # cases that a value-semantics compiler gets silently wrong.
    test "a callee mutates its caller's Array" do
      mod =
        load!("""
        func add_reward(rewards):
        \trewards[0] = "gold"

        func f():
        \tvar rewards = ["none"]
        \tadd_reward(rewards)
        \treturn rewards
        """)

      assert mod.f() == ["gold"]
    end

    test "two names alias one collection" do
      mod = load!("func f():\n\tvar a = [\"x\"]\n\tvar b = a\n\tb[0] = \"changed\"\n\treturn a\n")
      assert mod.f() == ["changed"]
    end

    test "mutating through the container it is held in" do
      mod =
        load!("""
        func f():
        \tvar d = {"items": ["a"]}
        \tvar items = d["items"]
        \titems[0] = "sword"
        \treturn d
        """)

      assert mod.f() == %{"items" => ["sword"]}
    end

    test "`+` makes a new Array, so the copy is independent" do
      mod =
        load!("""
        func f():
        \tvar xs = [1]
        \tvar ys = xs
        \tvar zs = ys + [2]
        \tzs[0] = 7
        \txs[0] = 9
        \treturn [xs, ys, zs]
        """)

      assert mod.f() == [[9], [9], [7, 2]]
    end

    test "collections compare by contents, not identity" do
      mod = load!("func f():\n\tvar a = [1, 2]\n\tvar b = [1, 2]\n\tb[0] = 1\n\treturn a == b\n")
      assert mod.f() == true
    end

    test "element assignment on arrays, dictionaries and nested paths" do
      mod =
        load!("""
        func f():
        \tvar xs = [1, 2, 3]
        \tvar d = {"n": 1, "a": {"b": 1}}
        \txs[1] = 99
        \td["n"] += 5
        \td["a"]["b"] = 2
        \treturn [xs, d]
        """)

      assert mod.f() == [[1, 99, 3], %{"n" => 6, "a" => %{"b" => 2}}]
    end

    test "a loop can build a dictionary" do
      mod =
        load!(
          "func f(xs):\n\tvar counts = {}\n\tfor x in xs:\n\t\tcounts[x] = 1\n\treturn counts\n"
        )

      assert mod.f(["a", "b"]) == %{"a" => 1, "b" => 1}
    end

    test "what leaves the script is a plain term, not a reference" do
      mod =
        load!(
          "func f():\n\tvar d = {\"a\": [1, {\"b\": 2}]}\n\td[\"a\"] = [1, {\"b\": 3}]\n\treturn d\n"
        )

      assert mod.f() == %{"a" => [1, %{"b" => 3}]}
    end

    test "struct payloads and value types cross the boundary untouched" do
      mod =
        load!("""
        func f(user):
        \tvar seen = {}
        \tseen["who"] = user.username
        \tseen["at"] = Vector2(1, 2)
        \treturn seen
        """)

      assert mod.f(%{username: "bob"}) == %{"who" => "bob", "at" => %{x: 1, y: 2}}
    end

    test "a spawned lambda sees a snapshot, not the live heap" do
      # Documented divergence: the task has its own process dictionary.
      mod =
        load!("""
        func f():
        \tvar d = {"n": 1}
        \tvar t = spawn(func(): return d["n"])
        \td["n"] = 2
        \treturn [await t, d["n"]]
        """)

      assert mod.f() == [1, 2]
    end

    test "a script that never mutates compiles with no heap at all" do
      # The whole point of the module-level switch: existing scripts are
      # byte-identical, and pay nothing.
      elixir =
        compile!("func f(user):\n\tvar b = 100\n\tif user.metadata: b += 50\n\treturn b\n")

      for marker <- ["gd_new", "gd_load", "gd_box", "gd_deref", "gd_fn_"] do
        refute elixir =~ marker
      end
    end

    test "one mutation turns the heap on for the whole module" do
      elixir = compile!("func f():\n\tvar d = {}\n\td[\"k\"] = 1\n\treturn d\n")

      assert elixir =~ "gd_new("
      assert elixir =~ "gd_store("
      assert elixir =~ "defp gd_fn_f"
      assert elixir =~ "do: gd_deref(gd_fn_f())"
    end
  end

  describe "methods" do
    test "Array" do
      mod =
        load!("""
        func f(xs):
        \treturn [xs.size(), xs.is_empty(), xs.has(2), xs.find(2), xs.front(), xs.back()]
        """)

      assert mod.f([1, 2, 3]) == [3, false, true, 1, 1, 3]
      assert mod.f([]) == [0, true, false, -1, nil, nil]
    end

    test "Dictionary" do
      mod =
        load!("func f(d):\n\treturn [d.size(), d.has(\"a\"), d.keys(), d.values()]\n")

      assert mod.f(%{"a" => 1}) == [1, true, ["a"], [1]]
    end

    test "String" do
      mod =
        load!("""
        func f(s):
        \treturn [s.length(), s.to_upper(), s.begins_with("he"), s.contains("ll"),
        \t\ts.replace("l", "L"), s.split("l"), s.strip_edges()]
        """)

      assert mod.f("hello") == [
               5,
               "HELLO",
               true,
               true,
               "heLLo",
               ["he", "", "o"],
               "hello"
             ]
    end

    test "to_int and to_float never raise" do
      mod = load!("func f(s):\n\treturn [s.to_int(), s.to_float()]\n")

      assert mod.f("42") == [42, 42.0]
      assert mod.f("nope") == [0, 0.0]
    end

    test "join is called on the separator, as in Godot 4" do
      mod = load!("func f(xs):\n\treturn \", \".join(xs)\n")
      assert mod.f(["a", "b"]) == "a, b"
    end

    test "mutating methods change the collection every name sees" do
      mod =
        load!("""
        func add(xs):
        \txs.append("gold")

        func f():
        \tvar rewards = []
        \tvar alias = rewards
        \tadd(rewards)
        \talias.append("gems")
        \treturn rewards
        """)

      assert mod.f() == ["gold", "gems"]
    end

    test "erase on an Array removes a value, on a Dictionary a key" do
      mod =
        load!("""
        func f():
        \tvar xs = [1, 2, 3]
        \tvar d = {"a": 1, "b": 2}
        \txs.erase(2)
        \td.erase("a")
        \treturn [xs, d]
        """)

      assert mod.f() == [[1, 3], %{"b" => 2}]
    end

    test "sort, reverse, insert, remove_at, clear and merge" do
      mod =
        load!("""
        func f():
        \tvar xs = [3, 1, 2]
        \txs.sort()
        \txs.insert(0, 0)
        \txs.remove_at(3)
        \txs.reverse()
        \tvar d = {"a": 1}
        \td.merge({"b": 2})
        \tvar gone = [1, 2]
        \tgone.clear()
        \treturn [xs, d, gone]
        """)

      assert mod.f() == [[2, 1, 0], %{"a" => 1, "b" => 2}, []]
    end

    test "a collection-returning method hands back something mutable" do
      mod =
        load!("""
        func f(d):
        \tvar ks = d.keys()
        \tks.append("extra")
        \treturn ks
        """)

      assert mod.f(%{"a" => 1}) == ["a", "extra"]
    end

    test "duplicate makes an independent copy" do
      mod =
        load!("""
        func f():
        \tvar a = [1]
        \tvar b = a.duplicate()
        \tb.append(2)
        \treturn [a, b]
        """)

      assert mod.f() == [[1], [1, 2]]
    end

    test "a non-mutating method leaves reference mode off" do
      elixir = compile!("func f(xs):\n\treturn xs.size()\n")

      refute elixir =~ "gd_new"
      assert elixir =~ "gd_size("
    end

    test "a mutating method turns reference mode on" do
      elixir = compile!("func f(xs):\n\txs.append(1)\n")

      assert elixir =~ "gd_mutate("
      assert elixir =~ "gd_append("
    end

    test "wrong arity is a compile error" do
      assert_raise CompileError, ~r/`.size\(\)` takes 0 argument\(s\), called with 1/, fn ->
        compile!("func f(xs):\n\treturn xs.size(1)\n")
      end
    end
  end

  describe "constants and enums" do
    test "a top-level const folds into the code that uses it" do
      elixir = compile!("const MAX = 4\n\nfunc f(n):\n\treturn n > MAX\n")

      assert elixir =~ "n > 4"
      refute elixir =~ "MAX"
    end

    test "named and unnamed enums, with explicit values" do
      mod =
        load!("""
        enum Tier { BRONZE, SILVER = 10, GOLD }
        enum { RED, GREEN, BLUE }

        func f():
        \treturn [Tier.BRONZE, Tier.SILVER, Tier.GOLD, RED, GREEN, BLUE]
        """)

      assert mod.f() == [0, 10, 11, 0, 1, 2]
    end

    test "a variable cannot shadow a constant" do
      assert_raise CompileError, ~r/`MAX` is a constant/, fn ->
        compile!("const MAX = 4\n\nfunc f():\n\tvar MAX = 9\n\treturn MAX\n")
      end
    end

    test "a const must be a scalar" do
      assert_raise CompileError, ~r/must be a number, string, boolean or null/, fn ->
        compile!("const XS = [1, 2]\n\nfunc f():\n\treturn XS\n")
      end
    end
  end

  describe "expressions and builtins" do
    test "ternary" do
      mod = load!("func f(n):\n\treturn \"big\" if n > 3 else \"small\"\n")

      assert mod.f(9) == "big"
      assert mod.f(1) == "small"
    end

    test "a ternary inside a container or an argument list" do
      # A bare `if ..., do: ..., else: ...` is ambiguous to Elixir's parser
      # inside a list, so the emission is parenthesised.
      mod =
        load!("""
        func f(n):
        \tvar xs = ["a" if n > 0 else "b", 2]
        \treturn [xs, str("yes" if n > 0 else "no")]
        """)

      assert mod.f(1) == [["a", 2], "yes"]
      assert mod.f(-1) == [["b", 2], "no"]
    end

    test "`is` and `as`" do
      mod = load!("func f(v):\n\treturn [v is int, v is String, v as int, v as String]\n")

      assert mod.f(7) == [true, false, 7, "7"]
      assert mod.f("42") == [false, true, 42, "42"]
    end

    test "`%` formats a string and stays modulo on numbers" do
      mod = load!("func f(a, b):\n\treturn [\"%s has %d\" % [a, b], b % 3]\n")
      assert mod.f("bob", 7) == ["bob has 7", 1]
    end

    test "str() prints collections and null the way Godot does" do
      mod = load!("func f(v):\n\treturn str(v)\n")

      assert mod.f([1, 2]) == "[1, 2]"
      assert mod.f(nil) == "<null>"
      assert mod.f(%{"a" => 1}) == "{a: 1}"
    end

    test "numeric builtins" do
      mod =
        load!(
          "func f(x):\n\treturn [abs(x), floor(2.7), ceil(2.1), round(2.4), min(1, 2), max(1, 2)]\n"
        )

      assert mod.f(-3) == [3, 2.0, 3.0, 2.0, 1, 2]
    end

    test "typeof" do
      mod = load!("func f(v):\n\treturn typeof(v)\n")

      assert mod.f(1) == "int"
      assert mod.f("s") == "String"
      assert mod.f([1]) == "Array"
      assert mod.f(nil) == "null"
    end

    test "assert raises with its message" do
      mod = load!("func f(x):\n\tassert(x, \"x is required\")\n\treturn x\n")

      assert mod.f(1) == 1
      assert_raise RuntimeError, "x is required", fn -> mod.f(nil) end
    end

    test "static func is an ordinary function" do
      mod = load!("static func f(a):\n\treturn a * 2\n")
      assert mod.f(3) == 6
    end

    test "typed parameters and return types parse and are dropped" do
      mod =
        load!(
          "func f(items: Array[int], count: int = 2) -> Array:\n\treturn items.slice(0, count)\n"
        )

      assert mod.f([1, 2, 3]) == [1, 2]
      assert mod.f([1, 2, 3], 1) == [1]
    end
  end

  describe "signals" do
    # `Gamend.Signals` lives in the server, so these assert on the emitted call
    # shape; the round trip is exercised against a running node.
    test "emit carries its arguments and is scoped to the plugin" do
      elixir =
        compile!("signal level_up(uid, level)\n\nfunc f(u):\n\tlevel_up.emit(u, 5)\n")

      assert elixir =~ ~s|Gamend.Signals.emit("T", "level_up", [u, 5])|
    end

    test "a signal with no arguments emits null" do
      elixir = compile!("signal ready\n\nfunc f():\n\tready.emit()\n")
      assert elixir =~ ~s|Gamend.Signals.emit("T", "ready", nil)|
    end

    test "await subscribes at function entry, not at the await" do
      # Subscribing where the await sits would drop anything emitted in between.
      elixir = compile!("signal done\n\nfunc f():\n\tvar x = 1\n\treturn await done\n")

      [subscribe, assignment] =
        String.split(elixir, "\n") |> Enum.filter(&(&1 =~ "subscribe" or &1 =~ "x = 1"))

      assert subscribe =~ "Gamend.Signals.subscribe"
      assert assignment =~ "x = 1"
    end

    test "a timeout reads as null" do
      elixir = compile!("signal done\n\nfunc f():\n\treturn await done\n")

      assert elixir =~ "Gamend.Signals.await"
      assert elixir =~ "_timeout -> nil"
    end

    test "await on a task is still a task await" do
      elixir = compile!("func f():\n\tvar t = spawn(func(): return 1)\n\treturn await t\n")

      assert elixir =~ "Task.await("
      refute elixir =~ "Gamend.Signals"
    end

    test "emitting an undeclared signal is a compile error" do
      assert_raise CompileError, ~r/is not a declared signal/, fn ->
        compile!("func f():\n\tnope.emit(1)\n")
      end
    end
  end

  describe "@GlobalScope, JSON and Time" do
    test "arithmetic and rounding" do
      mod =
        load!("""
        func f(x):
        \treturn [clamp(x, 0, 10), sign(-3), sqrt(16.0), pow(2.0, 3.0), posmod(-1, 4),
        \t\tsnapped(7.3, 0.5), nearest_po2(17), wrapi(12, 0, 10), absi(-2.7)]
        """)

      assert mod.f(42) == [10, -1, 4.0, 8.0, 3, 7.5, 32, 2, 2]
    end

    test "min and max take any number of arguments, as in Godot" do
      mod = load!("func f():\n\treturn [min(3, 1, 2), max(3, 1, 2), min(2, 5)]\n")
      assert mod.f() == [1, 3, 2]
    end

    test "interpolation" do
      mod =
        load!("""
        func f():
        \treturn [lerp(0.0, 10.0, 0.5), inverse_lerp(0.0, 10.0, 2.5),
        \t\tremap(5.0, 0.0, 10.0, 0.0, 100.0), move_toward(0.0, 10.0, 3.0),
        \t\tmove_toward(0.0, 2.0, 5.0), pingpong(3.0, 2.0)]
        """)

      assert mod.f() == [5.0, 0.25, 50.0, 3.0, 2.0, 1.0]
    end

    test "approximate comparison" do
      mod =
        load!(
          "func f():\n\treturn [is_equal_approx(0.1 + 0.2, 0.3), is_zero_approx(0.0000001), is_nan(0.0)]\n"
        )

      assert mod.f() == [true, true, false]
    end

    test "trigonometry and angle conversion" do
      mod =
        load!(
          "func f():\n\treturn [round(rad_to_deg(deg_to_rad(90.0))), round(cos(0.0)), round(sin(0.0))]\n"
        )

      assert mod.f() == [90.0, 1.0, 0.0]
    end

    test "randomness is seedable and stays in range" do
      mod =
        load!("""
        func f():
        \tseed(42)
        \tvar rolls = []
        \tfor i in range(50):
        \t\trolls.append(randi_range(1, 6))
        \treturn rolls
        """)

      rolls = mod.f()
      assert length(rolls) == 50
      assert Enum.all?(rolls, &(&1 >= 1 and &1 <= 6))
    end

    test "JSON round-trips, and answers null on bad input" do
      mod =
        load!("""
        func f(d):
        \tvar text = JSON.stringify(d)
        \treturn [text, JSON.parse_string(text), JSON.parse_string("nope{")]
        """)

      assert mod.f(%{"a" => 1}) == [~s|{"a":1}|, %{"a" => 1}, nil]
    end

    test "Time" do
      mod =
        load!("""
        func f():
        \tvar parts = Time.get_datetime_dict_from_unix_time(0)
        \treturn [Time.get_unix_time_from_system() > 1700000000, parts["year"], parts["month"],
        \t\tTime.get_datetime_string_from_unix_time(0),
        \t\tTime.get_unix_time_from_datetime_string("1970-01-01T00:00:00Z")]
        """)

      assert mod.f() == [true, 1970, 1, "1970-01-01T00:00:00Z", 0]
    end

    test "an unknown static method names the class" do
      assert_raise CompileError, ~r/`JSON` has no `stringifyy`/, fn ->
        compile!("func f(d):\n\treturn JSON.stringifyy(d)\n")
      end
    end

    test "a builtin called with the wrong number of arguments fails on its line" do
      error =
        assert_raise CompileError, fn ->
          compile!("func f():\n\tvar a = 1\n\treturn clamp(a, 2)\n")
        end

      assert Exception.message(error) =~ "`clamp` takes 3 argument(s), called with 2"
      assert Exception.message(error) =~ "test.gd:3"
    end

    test "the print family and str() are variadic, as in Godot" do
      mod = load!("func f():\n\treturn [str(\"a\", 1, [2]), str(3)]\n")
      assert mod.f() == ["a1[2]", "3"]

      assert ExUnit.CaptureIO.capture_io(fn ->
               load!("func f():\n\tprint(\"score: \", 7)\n\tprints(1, 2)\n").f()
             end) == "score: 7\n1 2\n"
    end
  end

  describe "range()" do
    test "returns an Array, not something that merely iterates" do
      mod =
        load!("""
        func f():
        \tvar xs = range(3)
        \treturn [xs, xs.size(), xs[1], xs.map(func(i): return i * 2), str(range(2))]
        """)

      assert mod.f() == [[0, 1, 2], 3, 1, [0, 2, 4], "[0, 1]"]
    end

    test "takes a step, counting up or down" do
      mod =
        load!("""
        func f():
        \treturn [range(0, 10, 2), range(10, 0, -2), range(5, 0), range(0, 5, 0)]
        """)

      assert mod.f() == [[0, 2, 4, 6, 8], [10, 8, 6, 4, 2], [], []]
    end

    test "a fourth argument is a compile error" do
      assert_raise CompileError, ~r/`range` takes 1, 2 or 3 argument\(s\), called with 4/, fn ->
        compile!("func f():\n\treturn range(1, 2, 3, 4)\n")
      end
    end
  end

  describe "the builtin table" do
    test "every declared arity still matches the helper it names" do
      %{builtins: builtins, helpers: helpers} = Gamend.GDScript.Codegen.__tables__()

      drifted =
        for {name, {"gd_" <> _ = target, arity}} <- builtins,
            source = Map.fetch!(helpers, String.to_atom(target)),
            actual = helper_arities(source, target),
            arity not in actual,
            do: {name, target, declared: arity, actual: actual}

      assert drifted == []
    end

    test "a variadic builtin names a helper that takes the list" do
      %{variadic: variadic, helpers: helpers} = Gamend.GDScript.Codegen.__tables__()

      drifted =
        for {name, target} <- variadic,
            source = Map.fetch!(helpers, String.to_atom(target)),
            1 not in helper_arities(source, target),
            do: {name, target}

      assert drifted == []
    end

    defp helper_arities(source, target) do
      ~r/defp #{Regex.escape(target)}\(([^)]*)\)/
      |> Regex.scan(source)
      |> Enum.map(fn [_, params] ->
        case String.trim(params) do
          "" -> 0
          params -> length(String.split(params, ","))
        end
      end)
      |> then(fn
        [] -> [0]
        arities -> arities
      end)
    end
  end

  describe "vector methods" do
    test "Vector2" do
      mod =
        load!("""
        func f():
        \tvar a = Vector2(3.0, 4.0)
        \treturn [a.length(), a.length_squared(), a.distance_to(Vector2(0.0, 0.0)),
        \t\ta.normalized(), a.dot(Vector2(1.0, 0.0)), a.is_normalized(),
        \t\ta.limit_length(1.0), Vector2(1.0, 0.0).angle()]
        """)

      assert mod.f() == [5.0, 25.0, 5.0, %{x: 0.6, y: 0.8}, 3.0, false, %{x: 0.6, y: 0.8}, 0.0]
    end

    test "Vector3, including a cross product that is a vector" do
      mod =
        load!("""
        func f():
        \tvar v = Vector3(1.0, 2.0, 2.0)
        \treturn [v.length(), v.cross(Vector3(1.0, 0.0, 0.0)),
        \t\tv.lerp(Vector3(3.0, 2.0, 2.0), 0.5)]
        """)

      assert mod.f() == [3.0, %{x: 0.0, y: 2.0, z: -2.0}, %{x: 2.0, y: 2.0, z: 2.0}]
    end

    test "Vector2's cross product is a scalar" do
      mod = load!("func f():\n\treturn Vector2(1.0, 0.0).cross(Vector2(0.0, 1.0))\n")
      assert mod.f() == 1.0
    end

    test "length() still counts characters on a String" do
      # One name, two classes -- dispatched on the receiver like `erase`.
      mod = load!("func f(s):\n\treturn s.length()\n")
      assert mod.f("hello") == 5
    end

    test "component-wise rounding and sign" do
      mod =
        load!(
          "func f():\n\tvar v = Vector2(-1.7, 2.3)\n\treturn [v.abs(), v.floor(), v.sign()]\n"
        )

      assert mod.f() == [%{x: 1.7, y: 2.3}, %{x: -2.0, y: 2.0}, %{x: -1.0, y: 1.0}]
    end
  end

  describe "cross-script calls" do
    # `class_name` is how Godot makes a script reachable from every other one,
    # so it is how a plugin's scripts reach each other here.
    defp compile_scripts!(sources) do
      dir = Path.join(System.tmp_dir!(), "gd#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      paths =
        Enum.map(sources, fn {name, source} ->
          path = Path.join(dir, "#{name}.gd")
          File.write!(path, source)
          path
        end)

      Gamend.GDScript.compile_all(paths)
    end

    defp load_scripts!(sources) do
      sources
      |> compile_scripts!()
      |> Enum.flat_map(fn {_module, source} -> compile_without_warnings!(source) end)
      |> Map.new(fn {module, _binary} -> {module |> Module.split() |> List.last(), module} end)
    end

    test "one script calls another by its class_name" do
      mods =
        load_scripts!([
          {"helpers", "class_name Helpers\n\nfunc double(n):\n\treturn n * 2\n"},
          {"main", "class_name Main\n\nfunc run(n):\n\treturn Helpers.double(n) + 1\n"}
        ])

      assert mods["Main"].run(5) == 11
    end

    test "a reference survives the call, so a callee mutates the caller's Array" do
      # The whole reason cross-script calls go to the private body rather than
      # the boxed wrapper.
      mods =
        load_scripts!([
          {"a_mutator", "class_name Mutator\n\nfunc add(xs, value):\n\txs.append(value)\n"},
          {"b_main",
           "class_name Main\n\nfunc run():\n\tvar xs = []\n\tMutator.add(xs, \"gold\")\n\treturn xs\n"}
        ])

      # The module name comes from the file, so `b_main.gd` is `BMain`; the
      # `class_name` is only how *other scripts* address it.
      assert mods["BMain"].run() == ["gold"]
    end

    test "one script mutating puts the whole plugin in reference mode" do
      [{_a, first}, {_b, second}] =
        compile_scripts!([
          {"a_pure", "class_name Pure\n\nfunc add(a, b):\n\treturn a + b\n"},
          {"b_impure", "class_name Impure\n\nfunc touch(d):\n\td[\"k\"] = 1\n"}
        ])

      # A reference handed from one script to another has to stay a reference,
      # so the mode cannot differ between files.
      assert first =~ "gd_fn_add"
      assert second =~ "gd_fn_touch"
    end

    test "a wrong name across files is a compile error with a suggestion" do
      error =
        assert_raise CompileError, fn ->
          compile_scripts!([
            {"helpers", "class_name Helpers\n\nfunc double(n):\n\treturn n * 2\n"},
            {"main", "class_name Main\n\nfunc run(n):\n\treturn Helpers.doubel(n)\n"}
          ])
        end

      assert Exception.message(error) =~ "`Helpers` has no `doubel`"
      assert Exception.message(error) =~ "did you mean `double`?"
    end

    test "a wrong argument count across files is a compile error" do
      error =
        assert_raise CompileError, fn ->
          compile_scripts!([
            {"helpers", "class_name Helpers\n\nfunc double(n):\n\treturn n * 2\n"},
            {"main", "class_name Main\n\nfunc run():\n\treturn Helpers.double(1, 2)\n"}
          ])
        end

      assert Exception.message(error) =~ "taking 2 argument(s)"
    end

    test "a script without class_name is not reachable" do
      assert_raise CompileError, ~r/unknown context `Hidden`/, fn ->
        compile_scripts!([
          {"hidden", "func helper():\n\treturn 1\n"},
          {"main", "class_name Main\n\nfunc run():\n\treturn Hidden.helper()\n"}
        ])
      end
    end

    test "a gamend context still wins over a script of the same shape" do
      [{_module, source}] =
        compile_scripts!([
          {"main", "class_name Main\n\nfunc run(u):\n\treturn Economy.balance(u, \"gold\")\n"}
        ])

      assert source =~ "Gamend.Economy.balance("
    end
  end

  describe "methods against the Godot reference" do
    # The first pass of this table was curated from memory and got arities,
    # defaults and two semantics wrong. These pin the cases the docs corrected.
    test "the higher-order Array methods" do
      mod =
        load!("""
        func f(xs):
        \tvar doubled = xs.map(func(x): return x * 2)
        \tvar big = xs.filter(func(x): return x > 1)
        \treturn [doubled, big, xs.reduce(func(acc, x): return acc + x, 0),
        \t\txs.any(func(x): return x > 2), xs.all(func(x): return x > 0)]
        """)

      assert mod.f([1, 2, 3]) == [[2, 4, 6], [2, 3], 6, true, true]
    end

    test "reduce passes (accumulator, element), not Elixir's order" do
      mod =
        load!(
          "func f(xs):\n\treturn xs.reduce(func(acc, x): return acc + \"-\" + x, \"start\")\n"
        )

      assert mod.f(["a", "b"]) == "start-a-b"
    end

    test "sort_custom and find_custom" do
      mod =
        load!("""
        func f(xs):
        \txs.sort_custom(func(a, b): return a > b)
        \treturn [xs, xs.find_custom(func(x): return x < 3)]
        """)

      assert mod.f([1, 3, 2]) == [[3, 2, 1], 1]
    end

    test "merge keeps the existing entry unless overwrite is true" do
      # Godot's `overwrite` defaults to false; Elixir's Map.merge/2 is the
      # opposite, which is how the first version silently overwrote.
      mod =
        load!("""
        func f():
        \tvar keep = {"a": 1}
        \tvar over = {"a": 1}
        \tkeep.merge({"a": 99, "b": 2})
        \tover.merge({"a": 99}, true)
        \treturn [keep, over]
        """)

      assert mod.f() == [%{"a" => 1, "b" => 2}, %{"a" => 99}]
    end

    test "optional arguments are filled in from the documented defaults" do
      mod =
        load!("""
        func f(xs, s):
        \treturn [xs.slice(1), xs.slice(0, 2), s.substr(1), s.substr(1, 1),
        \t\ts.split("-"), s.lpad(5), s.strip_edges()]
        """)

      assert mod.f([1, 2, 3], "a-b") == [[2, 3], [1, 2], "-b", "-", ["a", "b"], "  a-b", "a-b"]
    end

    test "erase means three different things, as in Godot" do
      mod =
        load!("""
        func f(s):
        \tvar xs = [1, 2, 3]
        \tvar d = {"a": 1, "b": 2}
        \txs.erase(2)
        \td.erase("a")
        \treturn [xs, d, s.erase(1), s.erase(0, 2)]
        """)

      assert mod.f("abc") == [[1, 3], %{"b" => 2}, "ac", "c"]
    end

    test "reverse mutates an Array but returns a new String" do
      mod =
        load!("""
        func f(s):
        \tvar xs = [1, 2, 3]
        \txs.reverse()
        \treturn [xs, s.reverse()]
        """)

      assert mod.f("abc") == [[3, 2, 1], "cba"]
    end

    test "the pop family returns the element and removes it" do
      mod =
        load!("""
        func f():
        \tvar xs = [1, 2, 3]
        \tvar last = xs.pop_back()
        \tvar first = xs.pop_front()
        \treturn [last, first, xs]
        """)

      assert mod.f() == [3, 1, [2]]
    end

    test "Dictionary.get takes a default" do
      mod = load!("func f(d):\n\treturn [d.get(\"a\"), d.get(\"missing\", 9)]\n")
      assert mod.f(%{"a" => 1}) == [1, 9]
    end

    test "the string case converters" do
      mod =
        load!("""
        func f(s):
        \treturn [s.to_snake_case(), s.to_kebab_case(), s.to_pascal_case(),
        \t\ts.to_camel_case(), s.capitalize()]
        """)

      assert mod.f("helloWorld") == [
               "hello_world",
               "hello-world",
               "HelloWorld",
               "helloWorld",
               "Hello World"
             ]
    end

    test "string search, padding and trimming" do
      mod =
        load!("""
        func f(s):
        \treturn [s.find("b"), s.rfind("b"), s.count("b"), s.trim_prefix("a"),
        \t\ts.trim_suffix("c"), s.repeat(2), s.left(2), s.right(2)]
        """)

      assert mod.f("abc") == [1, 1, 1, "bc", "ab", "abcabc", "ab", "bc"]
    end

    test "hashes and uri encoding" do
      mod = load!("func f(s):\n\treturn [s.md5_text(), s.uri_encode()]\n")
      [md5, encoded] = mod.f("a b")

      assert String.length(md5) == 32
      assert encoded == "a%20b"
    end

    test "a wrong argument count names the accepted range" do
      assert_raise CompileError, ~r/`.slice\(\)` takes 1 to 3 argument\(s\), called with 5/, fn ->
        compile!("func f(xs):\n\treturn xs.slice(0, 1, 1, false, 9)\n")
      end
    end

    test "a deep copy is refused where it is written, not at run time" do
      assert_raise CompileError, ~r/a deep `duplicate` is not supported/, fn ->
        compile!("func f(xs):\n\treturn xs.duplicate(true)\n")
      end

      assert_raise CompileError, ~r/a deep `slice` is not supported/, fn ->
        compile!("func f(xs):\n\treturn xs.slice(0, 1, 1, true)\n")
      end
    end
  end

  describe "classes" do
    test "fields, a constructor and a method" do
      mod =
        load!("""
        class Reward:
        \tvar kind = "gold"
        \tvar amount = 0

        \tfunc _init(k, a):
        \t\tkind = k
        \t\tamount = a

        \tfunc describe():
        \t\treturn "%s x%d" % [kind, amount]

        func f():
        \tvar r = Reward.new("gems", 3)
        \treturn [r.describe(), r.kind, r.amount]
        """)

      assert mod.f() == ["gems x3", "gems", 3]
    end

    test "field defaults apply when there is no _init" do
      mod = load!("class R:\n\tvar k = 7\n\nfunc f():\n\treturn R.new().k\n")
      assert mod.f() == 7
    end

    test "a method mutates the instance every name sees" do
      mod =
        load!("""
        class Counter:
        \tvar n = 0

        \tfunc bump(by):
        \t\tn += by

        func f():
        \tvar c = Counter.new()
        \tvar alias = c
        \tc.bump(2)
        \talias.bump(3)
        \treturn c.n
        """)

      assert mod.f() == 5
    end

    test "extends inherits fields, _init and methods" do
      mod =
        load!("""
        class Reward:
        \tvar kind = "gold"
        \tvar amount = 0

        \tfunc _init(k, a):
        \t\tkind = k
        \t\tamount = a

        \tfunc describe():
        \t\treturn "%s x%d" % [kind, amount]

        class Bonus extends Reward:
        \tfunc describe():
        \t\treturn "bonus: " + kind

        func f():
        \tvar r = Reward.new("gems", 3)
        \tvar b = Bonus.new("gold", 1)
        \treturn [r.describe(), b.describe(), b.amount]
        """)

      # Bonus overrides describe but inherits _init and both fields.
      assert mod.f() == ["gems x3", "bonus: gold", 1]
    end

    test "a parameter shadows a field of the same name" do
      mod =
        load!("""
        class R:
        \tvar k = "field"

        \tfunc show(k):
        \t\treturn k

        \tfunc mine():
        \t\treturn k

        func f():
        \tvar r = R.new()
        \treturn [r.show("param"), r.mine()]
        """)

      assert mod.f() == ["param", "field"]
    end

    test "an instance is a Dictionary, so it crosses the boundary as data" do
      mod = load!("class R:\n\tvar k = 1\n\nfunc f():\n\treturn R.new()\n")
      assert mod.f() == %{"__class__" => "R", "k" => 1}
    end

    test "class_name is accepted at the top level and dropped" do
      elixir = compile!("class_name Thing\n\nfunc f():\n\treturn 1\n")

      assert elixir =~ "def f"
      refute elixir =~ "Thing"
    end

    test "extending something undeclared is a compile error" do
      assert_raise CompileError, ~r/extends `Missing`, which is not declared/, fn ->
        compile!("class A extends Missing:\n\tvar k = 1\n\nfunc f():\n\treturn 1\n")
      end
    end

    test "a class cannot inherit from itself" do
      assert_raise CompileError, ~r/inherits from itself/, fn ->
        compile!("class A extends A:\n\tvar k = 1\n\nfunc f():\n\treturn 1\n")
      end
    end

    test "new checks its argument count" do
      assert_raise CompileError, ~r/`R.new` takes 2 argument\(s\), called with 1/, fn ->
        compile!("class R:\n\tfunc _init(a, b):\n\t\tpass\n\nfunc f():\n\treturn R.new(1)\n")
      end
    end

    test "an unknown method on an instance raises at run time with the class named" do
      mod =
        load!("""
        class A:
        \tfunc known():
        \t\treturn 1

        class B:
        \tfunc other():
        \t\treturn 2

        func f(v):
        \treturn v.known()
        """)

      assert mod.f(%{"__class__" => "A"}) == 1
      assert_raise ArgumentError, ~r|no method B.known/0|, fn -> mod.f(%{"__class__" => "B"}) end
    end
  end

  describe "callv" do
    test "emits a bounded dispatch, not a bare apply" do
      elixir = compile!("func f(uid, which):\n\treturn Economy.callv(which, [uid, \"gold\"])\n")

      assert elixir =~ "gd_callv(Gamend.Economy, @gd_api_economy, which,"
      assert elixir =~ ~s|{"grant", 3}|
      assert elixir =~ ~s|{"grant", 4}|
      # The whitelist is a literal in the module, so nothing outside it is reachable.
      refute elixir =~ "apply(Gamend.Economy"
    end

    test "the table only covers the contexts actually dispatched into" do
      elixir = compile!("func f(w):\n\treturn Economy.callv(w, [])\n")

      assert elixir =~ "@gd_api_economy"
      refute elixir =~ "@gd_api_lobbies"
    end

    test "a name outside the table raises rather than reaching the function" do
      defmodule DispatchTarget do
        def known(a), do: {:ok, a}
        def forbidden, do: :should_never_run
      end

      # The emitted helper, exercised directly against a stand-in module.
      allowed = [{"known", 1}]

      dispatch = fn name, args ->
        arity = length(args)

        if {name, arity} in allowed,
          do: apply(DispatchTarget, String.to_existing_atom(name), args),
          else: raise(ArgumentError, "no #{name}/#{arity}")
      end

      assert dispatch.("known", [1]) == {:ok, 1}
      assert_raise ArgumentError, ~r|no forbidden/0|, fn -> dispatch.("forbidden", []) end
      assert_raise ArgumentError, ~r|no known/2|, fn -> dispatch.("known", [1, 2]) end
    end

    test "an unknown context is still a compile error" do
      assert_raise CompileError, ~r/unknown context `Wallet`/, fn ->
        compile!("func f(w):\n\treturn Wallet.callv(w, [])\n")
      end
    end

    test "callv wants a name and an array" do
      assert_raise CompileError, ~r/takes a name and an array/, fn ->
        compile!("func f(w):\n\treturn Economy.callv(w)\n")
      end
    end
  end

  describe "gaps worth pinning" do
    test "d.get and d.set" do
      mod = load!("func f(d):\n\td.set(\"k\", 1)\n\treturn [d.get(\"k\"), d.get(\"missing\")]\n")
      assert mod.f(%{}) == [1, nil]
    end

    test "d.set mutates through a reference, like d[k] = v" do
      mod =
        load!("""
        func fill(d):
        \td.set("from_callee", true)

        func f():
        \tvar d = {}
        \tfill(d)
        \treturn d
        """)

      assert mod.f() == %{"from_callee" => true}
    end

    test "%% is a literal percent, and %x is hex" do
      mod = load!("func f(n):\n\treturn [\"100%%\" % [], \"%x\" % [n]]\n")
      assert mod.f(255) == ["100%", "ff"]
    end

    test "a format with too few arguments leaves the placeholder" do
      mod = load!("func f():\n\treturn \"%s and %s\" % [\"one\"]\n")
      assert mod.f() == "one and %s"
    end

    test "a bare value on the right of % is treated as one argument" do
      mod = load!("func f(n):\n\treturn \"n=%d\" % n\n")
      assert mod.f(7) == "n=7"
    end

    test "str() sees through references in reference mode" do
      mod =
        load!("""
        func f():
        \tvar d = {"xs": [1, 2]}
        \td["extra"] = true
        \treturn str(d["xs"])
        """)

      assert mod.f() == "[1, 2]"
    end

    test "enum members work as match patterns" do
      mod =
        load!("""
        enum Tier { BRONZE, SILVER }

        func f(t):
        \tmatch t:
        \t\tTier.BRONZE:
        \t\t\treturn "bronze"
        \t\tTier.SILVER:
        \t\t\treturn "silver"
        \t\t_:
        \t\t\treturn "other"
        """)

      assert mod.f(0) == "bronze"
      assert mod.f(1) == "silver"
      assert mod.f(9) == "other"
    end

    test "methods chain" do
      mod = load!("func f(s):\n\treturn s.strip_edges().to_upper().split(\",\").size()\n")
      assert mod.f("  a,b,c  ") == 3
    end

    test "a method on the result of a context call" do
      elixir = compile!("func f():\n\treturn KV.get(\"k\").size()\n")
      assert elixir =~ "gd_size(Gamend.KV.get("
    end

    test "an unknown builtin is still an unknown function" do
      assert_raise CompileError, ~r/unknown function `flor`/, fn ->
        compile!("func f(x):\n\treturn flor(x)\n")
      end
    end

    test "nested lambdas capture correctly" do
      mod =
        load!("""
        func f(base):
        \tvar outer = func(a):
        \t\tvar inner = func(b): return b + base
        \t\treturn inner.call(a)
        \treturn outer.call(1)
        """)

      assert mod.f(10) == 11
    end

    test "a loop over a dictionary iterates its keys, as in Godot" do
      mod =
        load!(
          "func f(d):\n\tvar out = []\n\tfor k in d.keys():\n\t\tout = out + [k]\n\treturn out\n"
        )

      assert mod.f(%{"a" => 1, "b" => 2}) == ["a", "b"]
    end

    test "an empty function body still compiles" do
      mod = load!("func f():\n\tpass\n")
      assert mod.f() == nil
    end

    test "a script with only declarations compiles" do
      elixir = compile!("const A = 1\nenum { X }\nsignal s\n")
      assert elixir =~ "defmodule T do"
    end
  end

  describe "rejects rather than approximates" do
    # The subset is enforced by refusing. Each case below would otherwise be a
    # silent mistranslation, which is the failure mode worth engineering away.
    for {label, source, fragment} <- [
          {"a bare statement as a match pattern", "func f(a):\n\tmatch a:\n\t\tpass\n",
           "in a match pattern"},
          {"class_name inside a func", "func f():\n\tclass_name Foo\n",
           "belongs at the top level"},
          {"break outside a loop", "func f():\n\tbreak\n", "only valid inside"},
          {"continue outside a loop", "func f():\n\tcontinue\n", "only valid inside"},
          {"reserved gd_ prefix", "func f():\n\tvar gd_x = 1\n\treturn gd_x\n", "are reserved"},
          {"reserved gd_ func", "func gd_add(a, b):\n\treturn a\n", "are reserved"},
          {"unknown context", "func f():\n\tWallet.grant(1)\n", "unknown context"},
          {"unknown function", "func f():\n\tnope(1)\n", "unknown function"},
          {"assign before declare", "func f():\n\tx = 1\n", "before it is declared"},
          {"field assignment", "func f(u):\n\tu.gold = 1\n", "only a variable or an element"},
          {"top-level var", "var x = 1\n", "no meaning server-side"},
          {"top-level expression", "print(1)\n", "only `func`, `const`, `enum`"}
        ] do
      test "rejects #{label}" do
        assert_raise CompileError, ~r/#{unquote(fragment)}/, fn -> compile!(unquote(source)) end
      end
    end

    test "an error names the file and line" do
      error =
        assert_raise CompileError, fn ->
          compile!("func f():\n\tvar a = 1\n\tWallet.grant(a)\n")
        end

      assert Exception.message(error) =~ "test.gd:3:"
    end

    test "a misaligned block is rejected" do
      assert_raise CompileError, ~r/unindent does not match/, fn ->
        compile!("func f(a):\n\tif a:\n\t\tvar x = 1\n\tvar y = 2\n  var z = 3\n")
      end
    end
  end

  describe "output" do
    test "generated source is formatted, so it parses" do
      elixir = compile!("func f(a):\n\treturn a\n")

      assert elixir == elixir |> Code.format_string!() |> IO.iodata_to_binary() |> Kernel.<>("\n")
    end

    test "the header names the source file" do
      assert compile!("func f():\n\tpass\n") =~ "# Generated from test.gd"
    end

    test "only the helpers a script actually uses are emitted" do
      elixir = compile!("func f(a, b):\n\treturn a * b\n")

      refute elixir =~ "gd_add"
      refute elixir =~ "gd_truthy"
      refute elixir =~ "gd_get"
    end

    test "a comment-only body still compiles" do
      mod = load!("func f():\n\t# nothing yet\n\tpass\n")
      assert mod.f() == nil
    end

    test "calls may wrap across lines" do
      mod = load!("func f(a):\n\treturn [\n\t\ta,\n\t\ta,\n\t]\n")
      assert mod.f(1) == [1, 1]
    end

    test "a wrapped call is followed by the next statement, not merged with it" do
      # The closing bracket line has to end the statement. Without that the
      # next line runs on and the parse fails -- and the case above hid it,
      # because a block ending there is terminated by the dedent anyway.
      mod =
        load!("""
        func f(a):
        \tvar total = len([
        \t\ta,
        \t\ta,
        \t])
        \tvar doubled = total * 2
        \treturn doubled
        """)

      assert mod.f(1) == 4
    end
  end

  describe "module naming" do
    test "derives a module from the file name" do
      assert GDScript.default_module("scripts/shop_hooks.gd") == "Gamend.Modules.ShopHooks"
    end

    test "places a module's source where mix compile expects it" do
      assert GDScript.source_path("Gamend.Modules.ShopHooks") == "gamend/modules/shop_hooks.ex"
    end
  end

  describe "compile_all/2 with :root" do
    # The server builds a plugin in-process without changing its working
    # directory: the files come from `root`, the header names the path as given.
    test "reads under root and names the relative path" do
      root = Path.join(System.tmp_dir!(), "gdroot#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "scripts"))
      on_exit(fn -> File.rm_rf!(root) end)
      File.write!(Path.join(root, "scripts/shop.gd"), "func price():\n\treturn 3\n")

      assert [{"Gamend.Modules.Shop", source}] =
               GDScript.compile_all(["scripts/shop.gd"], root: root)

      assert source =~ "# Generated from scripts/shop.gd by `mix gamend.gdscript.compile`"
      refute source =~ root
    end
  end
end
