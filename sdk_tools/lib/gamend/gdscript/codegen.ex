defmodule Gamend.GDScript.Codegen do
  @moduledoc """
  AST into Elixir source text.

  Two things make this more than a pretty-printer.

  **Mutation.** Elixir allows rebinding, but a rebinding inside a block does
  not escape it. So for every `if`, codegen computes the set of already-declared
  variables assigned in any branch and threads them out as a tuple:

      var bonus = 0          bonus = 0
      if score > 100:   =>   bonus = if gd_truthy(score > 100), do: 50, else: bonus
          bonus = 50

  A `var` declared *inside* a branch is block-scoped in GDScript too, so it is
  deliberately not lifted.

  **Semantics that differ.** `+` concatenates strings in GDScript, `/` is
  integer division between two ints, and `0`/`""`/`[]` are falsy. Elixir agrees
  with none of those, so those operators emit small private helpers rather than
  the native operator. They are emitted into the module itself only when used,
  so the output stays dependency-free and readable.
  """

  alias Gamend.GDScript.API
  alias Gamend.GDScript.CompileError
  require Gamend.GDScript.Word, as: Word

  @new "new"
  @duplicate "duplicate"
  @continue Word.continue()
  @break Word.break()
  @nofile Word.nofile()

  # `@GlobalScope` functions, as `{helper, arity}`. Engine-only ones
  # (`instance_from_id`, the `rid_*` family, `bytes_to_var`) are left out;
  # everything here has a meaning without an engine. The arity is checked
  # against the call so that `clamp(a, b)` fails on its own line rather than
  # as an undefined function inside the generated Elixir.
  @builtins %{
    # conversion and inspection
    "len" => {"gd_size", 1},
    "range" => {"gd_range", 3},
    "assert" => {"gd_assert", 2},
    "int" => {"gd_to_int", 1},
    "float" => {"gd_to_float", 1},
    "typeof" => {"gd_typeof", 1},
    "hash" => {"gd_hash", 1},
    # arithmetic
    "abs" => {"abs", 1},
    "absf" => {"gd_absf", 1},
    "absi" => {"gd_absi", 1},
    "sqrt" => {"gd_sqrt", 1},
    "cbrt" => {"gd_cbrt", 1},
    "pow" => {"gd_pow", 2},
    "log" => {"gd_log", 1},
    "exp" => {"gd_exp", 1},
    "fmod" => {"gd_fmod", 2},
    "fposmod" => {"gd_fposmod", 2},
    "posmod" => {"gd_posmod", 2},
    "sign" => {"gd_sign", 1},
    "signf" => {"gd_signf", 1},
    "signi" => {"gd_signi", 1},
    "floor" => {"gd_floor", 1},
    "floorf" => {"gd_floorf", 1},
    "floori" => {"gd_floori", 1},
    "ceil" => {"gd_ceil", 1},
    "ceilf" => {"gd_ceilf", 1},
    "ceili" => {"gd_ceili", 1},
    "round" => {"gd_round", 1},
    "roundf" => {"gd_roundf", 1},
    "roundi" => {"gd_roundi", 1},
    "snapped" => {"gd_snapped", 2},
    "snappedf" => {"gd_snapped", 2},
    "snappedi" => {"gd_snappedi", 2},
    "nearest_po2" => {"gd_nearest_po2", 1},
    "wrapi" => {"gd_wrapi", 3},
    "wrapf" => {"gd_wrapf", 3},
    # trigonometry
    "sin" => {"gd_sin", 1},
    "cos" => {"gd_cos", 1},
    "tan" => {"gd_tan", 1},
    "asin" => {"gd_asin", 1},
    "acos" => {"gd_acos", 1},
    "atan" => {"gd_atan", 1},
    "atan2" => {"gd_atan2", 2},
    "sinh" => {"gd_sinh", 1},
    "cosh" => {"gd_cosh", 1},
    "tanh" => {"gd_tanh", 1},
    "deg_to_rad" => {"gd_deg_to_rad", 1},
    "rad_to_deg" => {"gd_rad_to_deg", 1},
    # interpolation
    "lerp" => {"gd_lerp", 3},
    "lerpf" => {"gd_lerp", 3},
    "lerp_angle" => {"gd_lerp_angle", 3},
    "inverse_lerp" => {"gd_inverse_lerp", 3},
    "remap" => {"gd_remap", 5},
    "move_toward" => {"gd_move_toward", 3},
    "ease" => {"gd_ease", 2},
    "pingpong" => {"gd_pingpong", 2},
    # comparison
    "clamp" => {"gd_clamp", 3},
    "clampf" => {"gd_clamp", 3},
    "clampi" => {"gd_clampi", 3},
    "is_equal_approx" => {"gd_is_equal_approx", 2},
    "is_zero_approx" => {"gd_is_zero_approx", 1},
    "is_finite" => {"gd_is_finite", 1},
    "is_inf" => {"gd_is_inf", 1},
    "is_nan" => {"gd_is_nan", 1},
    "is_same" => {"gd_is_same", 2},
    # randomness
    "randi" => {"gd_randi", 0},
    "randf" => {"gd_randf", 0},
    "randi_range" => {"gd_randi_range", 2},
    "randf_range" => {"gd_randf_range", 2},
    "randfn" => {"gd_randfn", 2},
    "randomize" => {"gd_randomize", 0},
    "seed" => {"gd_seed", 1}
  }

  # Builtins that take any number of arguments in Godot. They are compiled as a
  # list rather than mapped onto a fixed arity -- `min`/`max` then share their
  # helper with `Array.min()` and `Array.max()`, and the `print` family joins
  # its arguments the way Godot does: nothing between them, a space for
  # `prints`, a tab for `printt`.
  @variadic %{
    "min" => "gd_min",
    "max" => "gd_max",
    "str" => "gd_str_all",
    "print" => "gd_print",
    "printraw" => "gd_printraw",
    "prints" => "gd_prints",
    "printt" => "gd_printt",
    "printerr" => "gd_printerr",
    "print_verbose" => "gd_print_verbose",
    "push_error" => "gd_push_error",
    "push_warning" => "gd_push_warning"
  }

  # Classes with static methods that mean something without an engine. Checked
  # before the gamend contexts, so `JSON` is not mistaken for one.
  # `{helper, required arity, defaults}`
  @static_classes %{
    "JSON" => %{
      "stringify" => {:gd_json_stringify, 1, []},
      "parse_string" => {:gd_json_parse, 1, []}
    },
    "Time" => %{
      "get_unix_time_from_system" => {:gd_unix_time, 0, []},
      "get_ticks_msec" => {:gd_ticks_msec, 0, []},
      "get_ticks_usec" => {:gd_ticks_usec, 0, []},
      "get_datetime_dict_from_unix_time" => {:gd_datetime_dict, 1, []},
      "get_datetime_string_from_unix_time" => {:gd_datetime_string, 1, []},
      "get_unix_time_from_datetime_string" => {:gd_unix_from_string, 1, []}
    }
  }

  # Many contexts take a trailing keyword list -- `reason:`, `idempotency_key:`.
  # GDScript has no atoms and no tuples, so it cannot spell one, and it cannot
  # be inferred either: `Notifications.admin_create_notification(a, b, {...})`
  # ends in a Dictionary that is a *payload map*, not options. Converting every
  # trailing Dictionary would silently corrupt that call. So the conversion is
  # explicit and local:
  #
  #     Economy.grant(user.id, "gold", 100, opts({"reason": "welcome"}))
  #       ->  Gamend.Economy.grant(user.id, "gold", 100, reason: "welcome")
  @opts_builtin "opts"

  # Recognised in call position and compiled specially rather than mapped to a
  # function, so they cannot be redefined.
  @special_forms [@opts_builtin, "spawn"]

  # Value types, constructed like functions and represented as plain maps with
  # atom keys -- so `v.x` reads a component and storing one in the KV store
  # yields the obvious `{"x": .., "y": ..}` JSON. Arithmetic on them goes
  # through the operator helpers below. There is no `v["x"]`, matching Godot,
  # where a Vector2 indexes by component name only through `.x`.
  @value_types %{
    "Vector2" => {[:x, :y], []},
    "Vector3" => {[:x, :y, :z], []},
    "Color" => {[:r, :g, :b, :a], [a: "1.0"]}
  }

  # Derived, so a new value type cannot forget to widen the run-time check.
  # Methods on Arrays, Dictionaries and Strings.
  # `{helper, argument count, mutates the receiver?, returns a collection?}`
  # The receiver's type is not known at compile time, so each helper dispatches
  # at run time -- one `cond` on the value it was handed.
  # Methods on Array, Dictionary and String, taken from the Godot class
  # reference rather than from memory -- the first pass was curated by guess and
  # got arities, defaults and two semantics wrong.
  #
  # `{helper, required arity, defaults for the optional tail, kind, collection?}`
  # where kind is `:value` (returns something), `:mutate` (writes the receiver
  # in place, or returns a new value when the receiver is a String) or `:take`
  # (writes *and* returns, like `pop_back`).
  #
  # Codegen fills the optional tail in from `defaults`, so every helper has one
  # fixed arity and no Elixir default arguments -- an unused default is a
  # warning in the generated module.
  @methods %{
    # ── Array ──
    "all" => {:gd_all, 1, [], :value, false},
    "any" => {:gd_any, 1, [], :value, false},
    "append" => {:gd_append, 1, [], :mutate, false},
    "append_array" => {:gd_append_array, 1, [], :mutate, false},
    "back" => {:gd_back, 0, [], :value, false},
    "count" => {:gd_count, 1, ["0", "0"], :value, false},
    "fill" => {:gd_fill, 1, [], :mutate, false},
    "filter" => {:gd_filter, 1, [], :value, true},
    "find_custom" => {:gd_find_custom, 1, ["0"], :value, false},
    "front" => {:gd_front, 0, [], :value, false},
    "map" => {:gd_map, 1, [], :value, true},
    "max" => {:gd_max_of, 0, [], :value, false},
    "min" => {:gd_min_of, 0, [], :value, false},
    "pick_random" => {:gd_pick_random, 0, [], :value, false},
    "pop_at" => {:gd_pop_at, 1, [], :take, false},
    "pop_back" => {:gd_pop_back, 0, [], :take, false},
    "pop_front" => {:gd_pop_front, 0, [], :take, false},
    "push_back" => {:gd_append, 1, [], :mutate, false},
    "push_front" => {:gd_push_front, 1, [], :mutate, false},
    "reduce" => {:gd_reduce, 1, ["nil"], :value, false},
    "remove_at" => {:gd_remove_at, 1, [], :mutate, false},
    "resize" => {:gd_resize, 1, [], :mutate, false},
    "rfind_custom" => {:gd_rfind_custom, 1, ["-1"], :value, false},
    "shuffle" => {:gd_shuffle, 0, [], :mutate, false},
    "sort" => {:gd_sort, 0, [], :mutate, false},
    "sort_custom" => {:gd_sort_custom, 1, [], :mutate, false},

    # ── Dictionary ──
    "find_key" => {:gd_find_key, 1, [], :value, false},
    "get_or_add" => {:gd_get_or_add, 1, ["nil"], :take, false},
    "has_all" => {:gd_has_all, 1, [], :value, false},
    "keys" => {:gd_keys, 0, [], :value, true},
    "merge" => {:gd_merge, 1, ["false"], :mutate, false},
    "merged" => {:gd_merged, 1, ["false"], :value, true},
    "values" => {:gd_values, 0, [], :value, true},

    # ── String ──
    "begins_with" => {:gd_begins_with, 1, [], :value, false},
    "capitalize" => {:gd_capitalize, 0, [], :value, false},
    "contains" => {:gd_has, 1, [], :value, false},
    "containsn" => {:gd_containsn, 1, [], :value, false},
    "dedent" => {:gd_dedent, 0, [], :value, false},
    "ends_with" => {:gd_ends_with, 1, [], :value, false},
    "indent" => {:gd_indent, 1, [], :value, false},
    "is_valid_float" => {:gd_is_valid_float, 0, [], :value, false},
    "is_valid_int" => {:gd_is_valid_int, 0, [], :value, false},
    "join" => {:gd_join, 1, [], :value, false},
    "left" => {:gd_left, 1, [], :value, false},
    "length" => {:gd_size, 0, [], :value, false},
    "lpad" => {:gd_lpad, 1, ["\" \""], :value, false},
    "lstrip" => {:gd_lstrip, 1, [], :value, false},
    "md5_text" => {:gd_md5_text, 0, [], :value, false},
    "pad_zeros" => {:gd_pad_zeros, 1, [], :value, false},
    "repeat" => {:gd_repeat, 1, [], :value, false},
    "replace" => {:gd_replace, 2, [], :value, false},
    "replacen" => {:gd_replacen, 2, [], :value, false},
    "right" => {:gd_right, 1, [], :value, false},
    "rpad" => {:gd_rpad, 1, ["\" \""], :value, false},
    "rsplit" => {:gd_rsplit, 1, ["true", "0"], :value, true},
    "rstrip" => {:gd_rstrip, 1, [], :value, false},
    "sha256_text" => {:gd_sha256_text, 0, [], :value, false},
    "similarity" => {:gd_similarity, 1, [], :value, false},
    "split" => {:gd_split, 1, ["true", "0"], :value, true},
    "strip_edges" => {:gd_strip_edges, 0, ["true", "true"], :value, false},
    "substr" => {:gd_substr, 1, ["-1"], :value, false},
    "to_camel_case" => {:gd_to_camel_case, 0, [], :value, false},
    "to_float" => {:gd_to_float, 0, [], :value, false},
    "to_int" => {:gd_to_int, 0, [], :value, false},
    "to_kebab_case" => {:gd_to_kebab_case, 0, [], :value, false},
    "to_lower" => {:gd_to_lower, 0, [], :value, false},
    "to_pascal_case" => {:gd_to_pascal_case, 0, [], :value, false},
    "to_snake_case" => {:gd_to_snake_case, 0, [], :value, false},
    "to_upper" => {:gd_to_upper, 0, [], :value, false},
    "trim_prefix" => {:gd_trim_prefix, 1, [], :value, false},
    "trim_suffix" => {:gd_trim_suffix, 1, [], :value, false},
    "uri_decode" => {:gd_uri_decode, 0, [], :value, false},
    "uri_encode" => {:gd_uri_encode, 0, [], :value, false},

    # ── Vector2 / Vector3 / Color ──
    "length_squared" => {:gd_vec_length_sq, 0, [], :value, false},
    "distance_to" => {:gd_distance_to, 1, [], :value, false},
    "distance_squared_to" => {:gd_distance_sq_to, 1, [], :value, false},
    "normalized" => {:gd_normalized, 0, [], :value, false},
    "is_normalized" => {:gd_is_normalized, 0, [], :value, false},
    "limit_length" => {:gd_limit_length, 0, ["1.0"], :value, false},
    "dot" => {:gd_dot, 1, [], :value, false},
    "cross" => {:gd_cross, 1, [], :value, false},
    "angle" => {:gd_angle, 0, [], :value, false},
    "angle_to" => {:gd_angle_to, 1, [], :value, false},
    "angle_to_point" => {:gd_angle_to_point, 1, [], :value, false},
    "direction_to" => {:gd_direction_to, 1, [], :value, false},
    "rotated" => {:gd_rotated, 1, [], :value, false},
    "orthogonal" => {:gd_orthogonal, 0, [], :value, false},
    "lerp" => {:gd_lerp, 2, [], :value, false},
    "clamp" => {:gd_vec_clamp, 2, [], :value, false},
    "snapped" => {:gd_snapped, 1, [], :value, false},
    "move_toward" => {:gd_vec_move_toward, 2, [], :value, false},
    "abs" => {:gd_vec_abs, 0, [], :value, false},
    "sign" => {:gd_vec_sign, 0, [], :value, false},
    "floor" => {:gd_vec_floor, 0, [], :value, false},
    "ceil" => {:gd_vec_ceil, 0, [], :value, false},
    "round" => {:gd_vec_round, 0, [], :value, false},
    "is_equal_approx" => {:gd_vec_equal_approx, 1, [], :value, false},
    "is_zero_approx" => {:gd_vec_zero_approx, 0, [], :value, false},

    # ── Shared across types, dispatching on the receiver ──
    "clear" => {:gd_clear, 0, [], :mutate, false},
    "duplicate" => {:gd_duplicate, 0, [], :value, true},
    "erase" => {:gd_erase, 1, ["1"], :mutate, false},
    "find" => {:gd_find, 1, ["0"], :value, false},
    "get" => {:gd_index, 1, ["nil"], :value, false},
    "has" => {:gd_has, 1, [], :value, false},
    "insert" => {:gd_insert, 2, [], :mutate, false},
    "is_empty" => {:gd_is_empty, 0, [], :value, false},
    "reverse" => {:gd_reverse, 0, [], :mutate, false},
    "rfind" => {:gd_rfind, 1, ["-1"], :value, false},
    "set" => {:gd_set, 2, [], :mutate, false},
    "size" => {:gd_size, 0, [], :value, false},
    "slice" => {:gd_slice, 1, ["2_147_483_647", "1"], :value, true}
  }

  @methods_loading_args ~w(merge merged join has_all append_array)

  @type_names ~w(int float String bool Array Dictionary Vector2 Vector3 Color)

  @value_type_keys @value_types
                   |> Enum.flat_map(fn {_type, {fields, _defaults}} -> fields end)
                   |> Enum.uniq()
                   |> Enum.sort()

  @doc "Generate Elixir source for `module` from parsed statements."
  @spec generate([tuple()], module :: String.t(), keyword()) :: String.t()
  def generate(statements, module, opts \\ []) do
    file = Keyword.get(opts, :file, @nofile)
    functions = Enum.filter(statements, &match?({:func, _, _, _, _}, &1))
    reject_reserved_names(functions, %{file: file})

    constants = collect_constants(statements, %{file: file})
    signals = for {:signal, name, _line} <- statements, do: name
    classes = collect_classes(statements, %{file: file})
    functions = fold_constants(functions, constants, %{file: file})

    # An instance is a mutable Dictionary, so a script that declares a class
    # always needs the heap.
    # Reference mode is plugin-wide when the caller says so: a reference handed
    # from one script to another has to stay a reference, and mixing modes
    # across files would break that.
    mutates? =
      classes != %{} or Enum.any?(functions, fn {:func, _n, _p, body, _l} -> mutates?(body) end)

    ref_mode? = Keyword.get(opts, :ref_mode?, mutates?)

    # Value mode cannot express writing through an alias -- `xs.append(v)` in a
    # loop would rebind a copy and throw it away. `compile_all` never asks for
    # this (one mutating script puts the whole plugin in reference mode), so
    # anything that does is a caller mistake, and a silent wrong answer is the
    # one outcome this compiler does not produce.
    if mutates? and not ref_mode? do
      raise CompileError,
        file: file,
        line: 1,
        message: "this script mutates a collection in place, so it cannot compile in value mode"
    end

    # Bare calls resolve against the funcs this file declares. Anything else is
    # a typo, and saying so here beats an UndefinedFunctionError at runtime.
    state = %{
      file: file,
      locals:
        MapSet.new(functions, fn {:func, name, params, _body, _line} ->
          {name, length(params)}
        end),
      # The enclosing loop's accumulator expression, so `break` and `continue`
      # can throw the current values out of the iteration. A `nil` accumulator
      # is legal (a loop that assigns nothing), hence the separate flag.
      loop_acc: nil,
      in_loop?: false,
      # Names the *enclosing* block's tail value will read. A branch or loop
      # body ends in the lifted tuple, so those names are read even though no
      # statement mentions them -- without this, `result_binder/3` would drop a
      # nested lift's binding and the tuple would carry the stale outer value.
      tail_reads: MapSet.new(),
      # Expressions are generated with only `state`, but a lambda body contains
      # statements and so needs the enclosing scope. `gen_statements/4` keeps
      # this current as it folds.
      scope: MapSet.new(),
      # Reference semantics are opt-in per module: a script that never mutates a
      # collection in place compiles exactly as it did before, with no refs and
      # no boundary walk. One `d[k] = v` anywhere in the file turns it on for
      # the whole file -- mixing the two modes would break local calls, which
      # pass refs straight through.
      ref_mode?: ref_mode?,
      signals: signals,
      module: module,
      classes: classes,
      # Set while generating a class method: the fields `self` exposes, and the
      # class they belong to.
      fields: MapSet.new(),
      class: nil,
      constructed: MapSet.new(constructed_classes(functions ++ class_bodies(classes))),
      # Other scripts in the same plugin, by the `class_name` they declared.
      scripts: Keyword.get(opts, :scripts, %{}),
      # Functions whose public wrapper has to cross the boundary. Reference mode
      # is plugin-wide, but most functions never touch a reference -- boxing
      # every payload for all of them was the bulk of the cost.
      needs_refs: needs_refs(functions)
    }

    reject_non_functions(statements, state)

    body =
      functions
      |> Enum.map(&gen_function(&1, state))
      |> Enum.join("\n\n")

    # Class bodies are not in `functions`, but they emit code too -- the scan has
    # to see them or their helpers come out undefined. The dispatcher reads the
    # instance's tag, so it needs `gd_index` even when no method reads a field.
    dispatcher = if invokes_method?(functions, classes), do: [{:gd_index_marker, 0}], else: []

    classes_code = gen_classes(state)
    dispatcher_code = if invokes_method?(functions, classes), do: gen_dispatcher(state), else: ""

    helpers =
      (functions ++ dispatcher ++ class_code(classes))
      |> required_helpers(ref_mode?, body <> classes_code <> dispatcher_code)
      |> Enum.map(&helper_source/1)

    """
    # Generated from #{file} by `mix gamend.gdscript.compile`. Do not edit.
    #
    # This is ordinary Elixir: it compiles to the same BEAM bytecode a
    # hand-written plugin does, and stack traces point here.
    defmodule #{module} do
      @moduledoc "Generated from `#{file}`."

    #{api_attributes(functions)}

    #{body}
    #{classes_code}
    #{dispatcher_code}
    #{Enum.join(helpers, "\n")}
    end
    """
    |> format()
  end

  defp reject_reserved_names(functions, state) do
    Enum.each(functions, fn {:func, name, params, _body, line} ->
      if name in @special_forms or Map.has_key?(@builtins, name) or
           Map.has_key?(@variadic, name) or Map.has_key?(@value_types, name) do
        raise CompileError,
          file: state.file,
          line: line,
          message: "`#{name}` is a built-in and cannot be redefined"
      end

      assert_available!(name, line, state)
      Enum.each(params, fn {param, _default} -> assert_available!(param, line, state) end)
    end)
  end

  # Codegen emits helpers (`gd_add`, `gd_truthy`, ...) and internal binders into
  # the same module, so the prefix has to be off limits -- otherwise a script
  # could shadow one and change what its own arithmetic means.
  defp assert_available!(name, line, state) do
    if String.starts_with?(name, "gd_") do
      raise CompileError,
        file: state.file,
        line: line,
        message: "names starting with `gd_` are reserved for the compiler"
    end
  end

  defp reject_non_functions(statements, state) do
    Enum.each(statements, fn
      {:func, _name, _params, _body, _line} ->
        :ok

      {:enum, _name, _members, _line} ->
        :ok

      {:const, _name, _expr, _line} ->
        :ok

      {:signal, _name, _line} ->
        :ok

      {:class, _name, _parent, _body, _line} ->
        :ok

      {:class_name, _name, _line} ->
        :ok

      statement ->
        raise CompileError,
          file: state.file,
          line: elem(statement, tuple_size(statement) - 1),
          message: "only `func`, `const`, `enum` and `signal` are supported at the top level"
    end)
  end

  # A constant must fold to a literal: it is substituted where it is used, so
  # there is no storage and no run-time lookup.
  defp collect_constants(statements, state) do
    Enum.reduce(statements, %{}, fn
      {:const, name, expr, line}, acc ->
        Map.put(acc, name, constant_value!(name, expr, line, state))

      {:enum, enum_name, members, _line}, acc ->
        Enum.reduce(members, acc, fn {member, value}, acc ->
          key = if enum_name, do: "#{enum_name}.#{member}", else: member
          Map.put(acc, key, {:int, value, 0})
        end)

      _statement, acc ->
        acc
    end)
  end

  defp constant_value!(_name, {kind, _, _} = literal, _line, _state)
       when kind in [:int, :float, :string, :bool],
       do: literal

  defp constant_value!(_name, {:null, _} = literal, _line, _state), do: literal

  defp constant_value!(name, {:unop, :-, {kind, value, l}, _}, _line, _state)
       when kind in [:int, :float] do
    _ = name
    {kind, -value, l}
  end

  defp constant_value!(name, _expr, line, state) do
    raise CompileError,
      file: state.file,
      line: line,
      message:
        "a top-level `const` must be a number, string, boolean or null (`#{name}`); " <>
          "return a collection from a `func` instead"
  end

  @doc """
  Does anything here mutate a collection in place? That is what needs the heap,
  and `Gamend.GDScript.compile_all/2` asks across every script in a plugin.
  """
  @spec mutates?(term()) :: boolean()
  def mutates?(node) when is_list(node), do: Enum.any?(node, &mutates?/1)
  def mutates?({:assign, {:index, _, _, _}, _op, _expr, _}), do: true

  def mutates?({:call, {:member, object, method, _}, args, _}) do
    case Map.fetch(@methods, method) do
      {:ok, {_helper, _required, _defaults, kind, _collection?}} when kind in [:mutate, :take] ->
        true

      _ ->
        mutates?([object | args])
    end
  end

  def mutates?({:call, callee, args, _}), do: mutates?([callee | args])
  def mutates?({:expr, expr, _}), do: mutates?(expr)
  def mutates?({:var, _name, expr, _}), do: mutates?(expr)
  def mutates?({:assign, _target, _op, expr, _}), do: mutates?(expr)
  def mutates?({:return, expr, _}), do: expr != nil and mutates?(expr)
  def mutates?({:binop, _op, left, right, _}), do: mutates?([left, right])
  def mutates?({:array, elements, _}), do: mutates?(elements)

  def mutates?({:if, clauses, else_body, _}) do
    Enum.any?(clauses, fn {_c, body} -> mutates?(body) end) or
      (else_body != nil and mutates?(else_body))
  end

  def mutates?({:match, _subject, cases, _}),
    do: Enum.any?(cases, fn {_patterns, body} -> mutates?(body) end)

  def mutates?({:for, _var, _collection, body, _}), do: mutates?(body)
  def mutates?({:while, _condition, body, _}), do: mutates?(body)
  def mutates?({:lambda, _params, body, _}), do: mutates?(body)
  def mutates?(_node), do: false

  # `const` and `enum` members are substituted into the tree before codegen, so
  # they cost nothing at run time and everything downstream -- including the
  # helper scan -- sees a plain literal.
  defp fold_constants(node, constants, _state) when map_size(constants) == 0, do: node
  defp fold_constants(node, constants, state), do: fold(node, constants, state)

  defp fold(node, constants, state) when is_list(node),
    do: Enum.map(node, &fold(&1, constants, state))

  defp fold({:ident, name, _line} = node, constants, _state), do: Map.get(constants, name, node)

  defp fold({:member, {:ident, enum, _}, member, _} = node, constants, state) do
    case Map.fetch(constants, "#{enum}.#{member}") do
      {:ok, literal} -> literal
      :error -> fold_children(node, constants, state)
    end
  end

  # An assignment target names a binding, never a constant to substitute -- only
  # the expression parts of it are folded.
  defp fold({:assign, {:index, object, key, l}, op, expr, line}, constants, state) do
    {:assign, {:index, fold(object, constants, state), fold(key, constants, state), l}, op,
     fold(expr, constants, state), line}
  end

  defp fold({:assign, target, op, expr, line}, constants, state),
    do: {:assign, target, op, fold(expr, constants, state), line}

  defp fold({:var, name, expr, line}, constants, state) do
    reject_shadow!(name, constants, line, state)
    {:var, name, fold(expr, constants, state), line}
  end

  defp fold({:for, var, collection, body, line}, constants, state) do
    reject_shadow!(var, constants, line, state)
    {:for, var, fold(collection, constants, state), fold(body, constants, state), line}
  end

  defp fold({:func, name, params, body, line}, constants, state) do
    Enum.each(params, fn {param, _default} -> reject_shadow!(param, constants, line, state) end)
    params = Enum.map(params, fn {param, default} -> {param, fold(default, constants, state)} end)
    {:func, name, params, fold(body, constants, state), line}
  end

  defp fold(node, constants, state) when is_tuple(node), do: fold_children(node, constants, state)
  defp fold(node, _constants, _state), do: node

  defp fold_children(node, constants, state) do
    node |> Tuple.to_list() |> Enum.map(&fold(&1, constants, state)) |> List.to_tuple()
  end

  defp reject_shadow!(name, constants, line, state) do
    if Map.has_key?(constants, name) do
      raise CompileError,
        file: state.file,
        line: line,
        message: "`#{name}` is a constant and cannot be used as a variable name"
    end
  end

  # ── Classes ──────────────────────────────────────────────────────────────

  # An inner class becomes a set of private functions plus a tagged Dictionary
  # for its instances. There is no object system to inherit from here, so
  # dispatch is one generated `case` over `{class, method, arity}` -- resolved
  # through the `extends` chain at compile time, so a call costs one lookup.
  defp collect_classes(statements, state) do
    Enum.reduce(statements, %{}, fn
      {:class, name, parent, body, line}, acc ->
        Map.put(acc, name, %{
          name: name,
          parent: parent,
          line: line,
          fields: class_fields(body),
          methods: Map.new(class_methods(body), fn {:func, m, p, b, l} -> {m, {p, b, l}} end)
        })

      _statement, acc ->
        acc
    end)
    |> tap(&assert_class_parents!(&1, state))
  end

  # Everything a class contributes to the helper scan: field defaults, method
  # bodies, and the `gd_index` / `gd_put` the constructor and dispatcher use.
  defp class_code(classes) when classes == %{}, do: []

  defp class_code(classes) do
    mutating = if class_assigns_field?(classes), do: [{:gd_store_marker, 0}], else: []
    reading = if class_reads_field?(classes), do: [{:gd_index_marker, 0}], else: []

    mutating ++
      reading ++
      Enum.flat_map(classes, fn {_name, class} ->
        Enum.map(class.fields, fn {_field, default} -> default end) ++
          Enum.flat_map(class.methods, fn {_m, {_params, body, _line}} -> body end)
      end)
  end

  # Is any class method actually called? The dispatcher and its `gd_index` are
  # only reachable through one, and an emitted-but-unused helper warns.
  defp invokes_method?(_statements, classes) when classes == %{}, do: false

  defp invokes_method?(statements, classes) do
    names =
      classes
      |> Enum.flat_map(fn {_name, class} -> Map.keys(class.methods) end)
      |> MapSet.new()

    calls_any_method?(statements ++ class_bodies(classes), names)
  end

  defp class_bodies(classes),
    do:
      Enum.flat_map(classes, fn {_n, c} ->
        Enum.flat_map(c.methods, fn {_m, {_p, body, _l}} -> body end)
      end)

  defp calls_any_method?(node, names) when is_list(node),
    do: Enum.any?(node, &calls_any_method?(&1, names))

  defp calls_any_method?({:call, {:member, object, method, _}, args, _}, names) do
    (MapSet.member?(names, method) and not Map.has_key?(@methods, method) and
       not context_object?(object)) or calls_any_method?([object | args], names)
  end

  defp calls_any_method?(node, names) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.any?(&calls_any_method?(&1, names))

  defp calls_any_method?(_node, _names), do: false

  # Does any method read one of its class's fields? Field reads are the only
  # thing in a class body that emits `gd_index`.
  defp class_reads_field?(classes) do
    Enum.any?(classes, fn {name, class} ->
      fields = classes |> all_fields(name) |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      Enum.any?(class.methods, fn {_method, {params, body, _line}} ->
        taken = MapSet.new(params, fn {param, _default} -> param end)
        reads_any?(body, MapSet.difference(fields, taken))
      end)
    end)
  end

  defp reads_any?(node, fields) when is_list(node), do: Enum.any?(node, &reads_any?(&1, fields))
  defp reads_any?({:ident, name, _}, fields), do: MapSet.member?(fields, name)

  defp reads_any?(node, fields) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.any?(&reads_any?(&1, fields))

  defp reads_any?(_node, _fields), do: false

  # Does any method write one of its class's fields? That is what needs the
  # store pair; a class that only constructs and reads does not.
  defp class_assigns_field?(classes) do
    Enum.any?(classes, fn {name, class} ->
      fields = classes |> all_fields(name) |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      Enum.any?(class.methods, fn {_method, {_params, body, _line}} ->
        assigns_any?(body, fields)
      end)
    end)
  end

  defp assigns_any?(node, fields) when is_list(node),
    do: Enum.any?(node, &assigns_any?(&1, fields))

  defp assigns_any?({:assign, {:ident, name, _}, _op, _expr, _}, fields),
    do: MapSet.member?(fields, name)

  defp assigns_any?(node, fields) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.any?(&assigns_any?(&1, fields))

  defp assigns_any?(_node, _fields), do: false

  defp class_fields(body), do: for({:var, name, default, _line} <- body, do: {name, default})
  defp class_methods(body), do: for({:func, _n, _p, _b, _l} = f <- body, do: f)

  defp assert_class_parents!(classes, state) do
    Enum.each(classes, fn {name, class} ->
      cond do
        class.parent == nil ->
          :ok

        not Map.has_key?(classes, class.parent) ->
          raise CompileError,
            file: state.file,
            line: class.line,
            message: "`#{name}` extends `#{class.parent}`, which is not declared in this file"

        cyclic_parent?(classes, class.parent, [name]) ->
          raise CompileError,
            file: state.file,
            line: class.line,
            message: "`#{name}` inherits from itself"

        true ->
          :ok
      end
    end)
  end

  defp cyclic_parent?(_classes, parent, seen), do: parent in seen

  # Own fields first, then the parent chain -- a redeclared field wins.
  defp all_fields(classes, name) do
    case Map.fetch(classes, name) do
      {:ok, class} -> all_fields(classes, class.parent) ++ class.fields
      :error -> []
    end
  end

  # Own methods win over inherited ones.
  defp resolve_method(classes, name, method) do
    case Map.fetch(classes, name) do
      {:ok, class} ->
        case Map.fetch(class.methods, method) do
          {:ok, {params, _body, _line}} -> {name, length(params)}
          :error -> resolve_method(classes, class.parent, method)
        end

      :error ->
        nil
    end
  end

  defp gen_classes(state) do
    state.classes
    |> Enum.sort_by(fn {name, _class} -> name end)
    |> Enum.map_join("\n\n", fn {name, class} -> gen_class(name, class, state) end)
  end

  defp gen_class(name, class, state) do
    fields = all_fields(state.classes, name)
    field_state = %{state | fields: MapSet.new(fields, &elem(&1, 0)), class: name}

    # Only emit a constructor for a class something actually instantiates.
    constructor =
      if constructed?(state.constructed, name), do: gen_constructor(name, fields, state), else: ""

    methods =
      class.methods
      |> Enum.sort_by(fn {method, _} -> method end)
      |> Enum.map_join("\n\n", fn {method, {params, body, _line}} ->
        gen_class_method(name, method, params, body, field_state)
      end)

    Enum.join(Enum.reject([constructor, methods], &(&1 == "")), "\n\n")
  end

  defp gen_constructor(name, fields, state) do
    defaults =
      Enum.map_join([{"__class__", {:string, name, 0}} | fields], ", ", fn {field, default} ->
        value = if default == nil, do: "nil", else: gen_expression(default, state)
        ~s("#{field}" => #{value})
      end)

    # `_init` may come from a parent, so it is resolved through the chain rather
    # than read off this class.
    {params, owner} = init_params(state.classes, name)
    signature = if params == [], do: "", else: "(" <> Enum.join(params, ", ") <> ")"

    call =
      if owner,
        do: "\n    #{class_fun(owner, "_init")}(gd_self#{args_suffix(params)})",
        else: ""

    """
      defp #{class_fun(name, @new)}#{signature} do
        gd_self = gd_new(%{#{defaults}})#{call}
        gd_self
      end\
    """
  end

  defp init_params(classes, name) do
    case resolve_method(classes, name, "_init") do
      nil ->
        {[], nil}

      {owner, _arity} ->
        {params, _body, _line} = get_in(classes, [owner, :methods, "_init"])
        {Enum.map(params, fn {param, _default} -> param end), owner}
    end
  end

  defp args_suffix([]), do: ""
  defp args_suffix(params), do: ", " <> Enum.join(params, ", ")

  defp gen_class_method(class, method, params, body, state) do
    names = Enum.map(params, fn {name, _default} -> name end)
    scope = MapSet.new(names)
    {lines, _scope} = gen_statements(body, scope, %{state | scope: scope}, true)
    inner = if non_tail_return?(body), do: wrap_return_catch(lines), else: Enum.join(lines, "\n")

    # A method that never touches a field never mentions `gd_self`, and an
    # unused parameter is a warning.
    visible = MapSet.difference(state.fields, scope)

    self_name =
      if reads_any?(body, visible) or assigns_any?(body, visible), do: "gd_self", else: "_gd_self"

    """
      defp #{class_fun(class, method)}(#{self_name}#{args_suffix(names)}) do
    #{indent(inner, 4)}
      end\
    """
  end

  defp class_fun(class, method), do: "gd_cls_#{class}_#{method}"

  defp constructed?(constructed, name), do: MapSet.member?(constructed, name)

  defp constructed_classes(node) when is_list(node),
    do: Enum.flat_map(node, &constructed_classes/1)

  defp constructed_classes({:call, {:member, {:ident, class, _}, @new, _}, args, _}),
    do: [class | Enum.flat_map(args, &constructed_classes/1)]

  defp constructed_classes(node) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.flat_map(&constructed_classes/1)

  defp constructed_classes(_node), do: []

  defp field?(state, name),
    do:
      state.class != nil and MapSet.member?(state.fields, name) and
        not MapSet.member?(state.scope, name)

  # One dispatcher for every class in the file, so a method call on an instance
  # is a single `case` over the tag it carries.
  defp gen_dispatcher(state) do
    branches =
      for {class, _} <- Enum.sort_by(state.classes, &elem(&1, 0)),
          method <- state.classes |> reachable_methods(class) |> Enum.sort() |> Enum.uniq(),
          {owner, arity} = resolve_method(state.classes, class, method) do
        args =
          case arity do
            0 -> ""
            n -> Enum.map_join(0..(n - 1), "", &", Enum.at(gd_args, #{&1})")
          end

        "      {\"#{class}\", \"#{method}\", #{arity}} -> " <>
          "#{class_fun(owner, method)}(gd_instance#{args})"
      end

    """
      defp gd_invoke(gd_instance, gd_method, gd_args) do
        case {gd_index(gd_load(gd_instance), "__class__", nil), gd_method, length(gd_args)} do
    #{Enum.join(branches, "\n")}

          {gd_class, gd_name, gd_arity} ->
            raise ArgumentError,
                  "no method \#{gd_class}.\#{gd_name}/\#{gd_arity}"
        end
      end\
    """
  end

  defp reachable_methods(classes, name) do
    case Map.fetch(classes, name) do
      {:ok, class} -> Map.keys(class.methods) ++ reachable_methods(classes, class.parent)
      :error -> []
    end
  end

  # ── Functions ────────────────────────────────────────────────────────────

  defp gen_function({:func, name, params, body, _line}, state) do
    scope = MapSet.new(params, fn {param_name, _default} -> param_name end)
    names = Enum.map(params, fn {param_name, _default} -> param_name end)
    {lines, _scope} = gen_statements(body, scope, state, true)

    # Subscribing where the `await` sits would miss anything emitted between
    # entry and there, so every signal this function waits for is subscribed up
    # front.
    lines = signal_subscriptions(body, state) ++ lines
    inner = if non_tail_return?(body), do: wrap_return_catch(lines), else: Enum.join(lines, "\n")

    if state.ref_mode? do
      # The public function is a boundary: values arrive from gamend as plain
      # terms and have to be boxed into the heap, and whatever comes back has to
      # be unboxed before it leaves. The body is private so local calls skip the
      # boundary entirely and pass references straight through.
      #
      # A function that can never reach a reference skips both -- which is most
      # of them, since one mutating function puts the whole plugin in reference
      # mode but does not make its neighbours touch the heap.
      entry =
        if MapSet.member?(state.needs_refs, name) do
          "gd_deref(#{body_name(name)}(#{Enum.map_join(names, ", ", &"gd_box(#{&1})")}))"
        else
          "#{body_name(name)}#{arg_list(names)}"
        end

      """
        #{def_head(name, params, state)},
          do: #{entry}

        #{if state.scripts == %{}, do: "defp", else: "def"} #{body_name(name)}#{arg_list(names)} do
      #{indent(inner, 4)}
        end\
      """
    else
      """
        #{def_head(name, params, state)} do
      #{indent(inner, 4)}
        end\
      """
    end
  end

  # The plugin's module name scopes a signal, so two plugins may use the same
  # name without hearing each other.
  defp signal_scope(state), do: state.module

  defp api_attribute(context), do: "@gd_api_" <> String.downcase(context)

  # One attribute per context a script dispatches into dynamically, holding the
  # exact `{name, arity}` pairs that context exposes.
  defp api_attributes(statements) do
    statements
    |> dynamic_contexts()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map_join("\n", fn context ->
      pairs =
        for name <- API.functions(context),
            arity <- API.arities(context, name),
            do: ~s({"#{name}", #{arity}})

      "  #{api_attribute(context)} [#{Enum.join(pairs, ", ")}]"
    end)
  end

  defp dynamic_contexts(node) when is_list(node), do: Enum.flat_map(node, &dynamic_contexts/1)

  defp dynamic_contexts({:call, {:member, {:ident, context, _}, "callv", _}, _args, _}),
    do: [context]

  defp dynamic_contexts(node) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.flat_map(&dynamic_contexts/1)

  defp dynamic_contexts(_node), do: []

  defp signal_subscriptions(body, state) do
    body
    |> awaited_signals(state)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&"Gamend.Signals.subscribe(\"#{signal_scope(state)}\", \"#{&1}\")")
  end

  defp awaited_signals(node, state) when is_list(node),
    do: Enum.flat_map(node, &awaited_signals(&1, state))

  defp awaited_signals({:await, {:ident, name, _}, _}, state),
    do: if(name in state.signals, do: [name], else: [])

  defp awaited_signals(node, state) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.flat_map(&awaited_signals(&1, state))

  defp awaited_signals(_node, _state), do: []

  # Which functions can reach a reference at all? A reference only ever comes
  # from an in-place mutation, a collection literal, a context call (whose
  # result is boxed) or an `await` -- so a function that reaches none of those,
  # directly or through the functions it calls, needs no boundary.
  #
  # A cross-script call is treated as reaching one: the callee may mutate, and
  # handing it a plain collection would silently transform a copy instead.
  defp needs_refs(functions) do
    direct =
      Map.new(functions, fn {:func, name, _params, body, _line} ->
        {name, {touches_refs?(body), called_locally(body)}}
      end)

    close_refs(direct, MapSet.new(for {name, {true, _}} <- direct, do: name))
  end

  defp close_refs(direct, needs) do
    added =
      for {name, {_direct?, callees}} <- direct,
          not MapSet.member?(needs, name),
          Enum.any?(callees, &MapSet.member?(needs, &1)),
          into: MapSet.new(),
          do: name

    if MapSet.size(added) == 0, do: needs, else: close_refs(direct, MapSet.union(needs, added))
  end

  defp touches_refs?(node) when is_list(node), do: Enum.any?(node, &touches_refs?/1)
  defp touches_refs?({:array, _elements, _}), do: true
  defp touches_refs?({:dict, _pairs, _}), do: true
  defp touches_refs?({:await, _expr, _}), do: true

  defp touches_refs?({:assign, {:index, _, _, _}, _op, _expr, _}), do: true

  defp touches_refs?({:call, {:member, object, method, _}, _args, _} = node) do
    # A context call is boxed on the way in and a cross-script call may mutate;
    # a mutating method writes the heap; a collection-returning one builds a
    # fresh reference that still has to be unwrapped on the way out.
    cond do
      context_object?(object) -> true
      method_touches_refs?(method) -> true
      true -> touches_children?(node)
    end
  end

  defp touches_refs?(node) when is_tuple(node), do: touches_children?(node)
  defp touches_refs?(_node), do: false

  defp touches_children?(node),
    do: node |> Tuple.to_list() |> Enum.any?(&touches_refs?/1)

  defp method_touches_refs?(method) do
    case Map.fetch(@methods, method) do
      {:ok, {_helper, _required, _defaults, kind, collection?}} ->
        kind in [:mutate, :take] or collection?

      :error ->
        false
    end
  end

  defp called_locally(node) when is_list(node), do: Enum.flat_map(node, &called_locally/1)

  defp called_locally({:call, {:ident, name, _}, args, _}),
    do: [name | Enum.flat_map(args, &called_locally/1)]

  defp called_locally(node) when is_tuple(node),
    do: node |> Tuple.to_list() |> Enum.flat_map(&called_locally/1)

  defp called_locally(_node), do: []

  defp def_head(name, [], _state), do: "  def #{name}"

  defp def_head(name, params, state),
    do: "  def #{name}(#{Enum.map_join(params, ", ", &gen_param(&1, state))})"

  defp arg_list([]), do: ""
  defp arg_list(names), do: "(" <> Enum.join(names, ", ") <> ")"

  # Prefixed so it cannot collide with a helper or with a user name, since `gd_`
  # is reserved for the compiler.
  defp body_name(name), do: "gd_fn_#{name}"

  defp wrap_return_catch(lines) do
    """
    try do
    #{indent(lines, 2)}
    catch
      {:gd_return, value} -> value
    end\
    """
  end

  defp gen_param({name, nil}, _state), do: name
  defp gen_param({name, default}, state), do: "#{name} \\\\ #{gen_expression(default, state)}"

  # Only a `return` as the very last top-level statement can be expressed as a
  # value. Anything nested needs throw/catch -- and the check is deliberately
  # conservative: it wraps more often than strictly necessary, never less.
  defp non_tail_return?(body) do
    {last, rest} = List.pop_at(body, -1)

    Enum.any?(rest, &contains_return?/1) or
      case last do
        {:return, _, _} -> false
        other -> other != nil and contains_return?(other)
      end
  end

  defp contains_return?({:return, _, _}), do: true

  defp contains_return?({:if, clauses, else_body, _}) do
    Enum.any?(clauses, fn {_cond, body} -> Enum.any?(body, &contains_return?/1) end) or
      (else_body != nil and Enum.any?(else_body, &contains_return?/1))
  end

  defp contains_return?({:match, _subject, cases, _}),
    do: Enum.any?(cases, fn {_patterns, body} -> Enum.any?(body, &contains_return?/1) end)

  defp contains_return?({:for, _var, _collection, body, _}),
    do: Enum.any?(body, &contains_return?/1)

  defp contains_return?({:while, _condition, body, _}),
    do: Enum.any?(body, &contains_return?/1)

  defp contains_return?(_), do: false

  # ── Statements ───────────────────────────────────────────────────────────

  # `tail_ok?` is false inside an `if` branch: a `return` there is not the
  # function's value, it is an early exit, and must throw. Only the outermost
  # body can hand back a value directly. Recomputing tail-ness per block --
  # rather than threading it from the function -- is exactly the bug that makes
  # `return` inside a branch silently fall through.
  defp gen_statements(statements, scope, state, tail_ok?) do
    last_index = length(statements) - 1

    {lines, scope} =
      statements
      |> Enum.with_index()
      |> Enum.reduce({[], scope}, fn {statement, index}, {acc, scope} ->
        tail? = tail_ok? and index == last_index
        rest = Enum.drop(statements, index + 1)
        state = %{state | scope: scope}

        if dead_store?(statement, rest) do
          {:var, name, _, _} = statement
          {[gen_dead_store(statement, state) | acc], MapSet.put(scope, name)}
        else
          {line, scope} = gen_statement(statement, scope, state, tail?, rest)
          {[line | acc], scope}
        end
      end)

    lines = lines |> Enum.reverse() |> Enum.reject(&(&1 == ""))

    # `do end` is not valid Elixir, so a body that generated nothing (a lone
    # `pass`, or an empty function) still has to yield a value.
    {if(lines == [], do: ["nil"], else: lines), scope}
  end

  defp gen_statement({:var, name, expr, line}, scope, state, _tail?, _rest) do
    assert_available!(name, line, state)
    {"#{name} = #{gen_expression(expr, state)}", MapSet.put(scope, name)}
  end

  defp gen_statement({:for, var, _collection, _body, line} = node, scope, state, _tail?, rest) do
    assert_available!(var, line, state)
    {gen_for(node, scope, state, rest), scope}
  end

  defp gen_statement({:while, _condition, _body, _line} = node, scope, state, _tail?, rest) do
    {gen_while(node, scope, state, rest), scope}
  end

  defp gen_statement({:break, line}, scope, state, _tail?, _rest) do
    assert_in_loop!(@break, line, state)
    {"throw({:gd_break, #{state.loop_acc || "nil"}})", scope}
  end

  defp gen_statement({:continue, line}, scope, state, _tail?, _rest) do
    assert_in_loop!(@continue, line, state)
    {"throw({:gd_continue, #{state.loop_acc || "nil"}})", scope}
  end

  defp gen_statement({:assign, {:ident, name, line}, op, expr, _}, scope, state, _tail?, _rest)
       when is_binary(name) do
    state = %{state | scope: scope}

    if field?(state, name) do
      value =
        case op do
          "=" -> gen_expression(expr, state)
          _ -> gen_binop(compound_op(op), {:ident, name, line}, expr, state)
        end

      {"gd_store(gd_self, fn gd_c -> gd_put(gd_c, \"#{name}\", #{value}) end)", scope}
    else
      gen_local_assign(name, op, expr, line, scope, state)
    end
  end

  defp gen_statement({:return, nil, _line}, scope, _state, true, _rest), do: {"nil", scope}

  defp gen_statement({:return, expr, _line}, scope, state, true, _rest),
    do: {gen_expression(expr, state), scope}

  defp gen_statement({:return, nil, _line}, scope, _state, false, _rest),
    do: {"throw({:gd_return, nil})", scope}

  defp gen_statement({:return, expr, _line}, scope, state, false, _rest),
    do: {"throw({:gd_return, #{gen_expression(expr, state)}})", scope}

  defp gen_statement({:expr, expr, _line}, scope, state, _tail?, _rest),
    do: {gen_expression(expr, state), scope}

  defp gen_statement({:pass, _line}, scope, _state, _tail?, _rest), do: {"", scope}

  defp gen_statement({:class_name, _name, line}, _scope, state, _tail?, _rest) do
    raise CompileError,
      file: state.file,
      line: line,
      message: "`class_name` belongs at the top level"
  end

  # `d[k] = v` mutates through the reference, so it reaches every other name
  # bound to the same collection -- which is the whole point of the heap.
  defp gen_statement({:assign, {:index, object, key, line}, op, expr, _}, scope, state, _t, _r) do
    value =
      case op do
        "=" -> gen_expression(expr, state)
        _ -> gen_binop(compound_op(op), {:index, object, key, line}, expr, state)
      end

    container = gen_expression(object, state)

    {"gd_store(#{container}, fn gd_c -> gd_put(gd_c, #{gen_expression(key, state)}, #{value}) end)",
     scope}
  end

  defp gen_statement({:match, subject, cases, _line} = node, scope, state, _tail?, rest) do
    assigned = assigned_in_match(node, scope)
    {gen_match(subject, cases, assigned, scope, state, rest), scope}
  end

  defp gen_statement({:if, clauses, else_body, _line} = node, scope, state, _tail?, rest) do
    assigned = assigned_in_if(node, scope)
    {gen_if(clauses, else_body, assigned, scope, state, rest), scope}
  end

  # ── match ────────────────────────────────────────────────────────────────

  # An Elixir `case`, with the same mutation lift as `if`. One difference has to
  # be corrected for: a GDScript `match` that matches nothing simply does
  # nothing, while `case` raises -- so a catch-all is appended when the script
  # has not written one.
  defp gen_match(subject, cases, assigned, scope, state, rest) do
    clauses =
      Enum.map(cases, fn {patterns, body} ->
        body_scope = Enum.reduce(bound_names(patterns), scope, &MapSet.put(&2, &1))

        gen_match_head(patterns, state) <>
          " ->\n" <> indent(branch_lines(body, assigned, body_scope, state), 2)
      end)

    clauses =
      if Enum.any?(cases, fn {patterns, _body} -> catch_all?(patterns) end),
        do: clauses,
        else: clauses ++ ["_ ->\n" <> indent(tail_value(assigned), 2)]

    binder(result_binder(assigned, rest, state)) <>
      "case #{deref(state, subject, gen_expression(subject, state))} do\n" <>
      indent(Enum.join(clauses, "\n"), 2) <> "\nend"
  end

  defp gen_match_head([{:wildcard, _}], _state), do: "_"
  defp gen_match_head([{:bind, name, _}], _state), do: name
  defp gen_match_head([{:literal, expr, line}], state), do: literal_pattern!(expr, line, state)

  defp gen_match_head([{:array_pattern, _, _, _} = pattern], state),
    do: gen_pattern(pattern, state)

  defp gen_match_head([{:dict_pattern, _, _, _} = pattern], state),
    do: gen_pattern(pattern, state)

  defp gen_match_head(patterns, state) do
    # Several patterns share one body. `case` has no `1, 2 ->` form, so the
    # alternatives become a guard over a bound subject.
    if Enum.any?(patterns, &catch_all?([&1])) do
      raise CompileError,
        file: state.file,
        line: pattern_line(hd(patterns)),
        message: "`_` and `var name` cannot be combined with other patterns"
    end

    unless Enum.all?(patterns, &match?({:literal, _, _}, &1)) do
      raise CompileError,
        file: state.file,
        line: pattern_line(hd(patterns)),
        message: "a destructuring pattern cannot be one of several alternatives"
    end

    values =
      Enum.map_join(patterns, ", ", fn {:literal, expr, _} -> gen_expression(expr, state) end)

    "gd_match when gd_match in [#{values}]"
  end

  # A pattern has to be a value, and constant folding has already run -- so
  # anything still naming something is a name the script never declared.
  defp literal_pattern!({kind, _, _} = expr, _line, state)
       when kind in [:int, :float, :string, :bool],
       do: gen_expression(expr, state)

  defp literal_pattern!({:null, _} = expr, _line, state), do: gen_expression(expr, state)

  defp literal_pattern!(expr, line, state) do
    name =
      case expr do
        {:ident, ident, _} -> ident
        {:member, {:ident, enum, _}, member, _} -> "#{enum}.#{member}"
        _other -> "that"
      end

    raise CompileError,
      file: state.file,
      line: line,
      message:
        "`#{name}` is not a constant, so it cannot be a match pattern -- " <>
          "use a literal, or `var #{if name =~ ".", do: "value", else: name}` to bind"
  end

  # A destructuring pattern becomes an Elixir pattern directly -- the subject is
  # dereferenced before the `case`, so patterns always see plain values.
  defp gen_pattern({:wildcard, _}, _state), do: "_"
  defp gen_pattern({:bind, name, _}, _state), do: name
  defp gen_pattern({:literal, expr, line}, state), do: literal_pattern!(expr, line, state)

  defp gen_pattern({:array_pattern, elements, open?, _}, state) do
    inner = Enum.map_join(elements, ", ", &gen_pattern(&1, state))
    if open?, do: "[" <> inner <> " | _]", else: "[" <> inner <> "]"
  end

  defp gen_pattern({:dict_pattern, pairs, open?, _}, state) do
    inner =
      Enum.map_join(pairs, ", ", fn {key, value} ->
        "#{gen_pattern(key, state)} => #{gen_pattern(value, state)}"
      end)

    map = "%{" <> inner <> "}"

    # An Elixir map pattern matches a subset, so a closed dictionary pattern
    # needs a size guard to mean what Godot means.
    if open?, do: map, else: "#{map} = gd_match when map_size(gd_match) == #{length(pairs)}"
  end

  defp catch_all?(patterns) do
    Enum.any?(patterns, fn
      {:wildcard, _} -> true
      {:bind, _, _} -> true
      _ -> false
    end)
  end

  defp bound_names(patterns), do: Enum.flat_map(patterns, &pattern_binds/1)

  defp pattern_binds({:bind, name, _}), do: [name]

  defp pattern_binds({:array_pattern, elements, _open?, _}),
    do: Enum.flat_map(elements, &pattern_binds/1)

  defp pattern_binds({:dict_pattern, pairs, _open?, _}),
    do: Enum.flat_map(pairs, fn {key, value} -> pattern_binds(key) ++ pattern_binds(value) end)

  defp pattern_binds(_pattern), do: []

  defp pattern_line(pattern), do: pattern |> Tuple.to_list() |> List.last()

  defp assigned_in_match({:match, _subject, cases, _line}, scope) do
    cases
    |> Enum.flat_map(fn {patterns, body} ->
      # A `var name` pattern declares a clause-local, so assignments to it are
      # not lifted -- the same rule as a `var` inside an `if` branch.
      inner = Enum.reduce(bound_names(patterns), scope, &MapSet.delete(&2, &1))
      assigned_in_body(body, inner)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ── Loops ────────────────────────────────────────────────────────────────

  # A loop is a fold: the variables it assigns become the accumulator, exactly
  # as with `if`, except the tuple is threaded through every iteration instead
  # of every branch. The loop variable is a fresh binding, so assignments to it
  # are loop-local and never lifted.
  defp gen_for({:for, var, collection, body, _line} = node, scope, state, rest) do
    assigned = assigned_in_loop(node, scope)
    acc = tuple_of(assigned)
    body_scope = MapSet.put(scope, var)
    jumps? = contains_jump?(body)
    # GDScript allows an unused loop variable; Elixir warns about one.
    var = if reads?(body, var), do: var, else: "_" <> var

    cond do
      # Nothing assigned and no early exit: a plain side-effecting walk.
      acc == nil and not jumps? ->
        """
        Enum.each(#{load(state, collection, gen_expression(collection, state))}, fn #{var} ->
        #{indent(plain_body(body, body_scope, loop_state(state, acc, assigned)), 2)}
        end)\
        """

      jumps? ->
        binder(result_binder(assigned, rest, state)) <>
          """
          Enum.reduce_while(#{load(state, collection, gen_expression(collection, state))}, #{acc || "nil"}, fn #{var}, #{body_pattern(assigned, body, acc)} ->
          #{indent(loop_body(body, assigned, acc, body_scope, state, true, false), 2)}
          end)\
          """

      true ->
        binder(result_binder(assigned, rest, state)) <>
          """
          Enum.reduce(#{load(state, collection, gen_expression(collection, state))}, #{acc}, fn #{var}, #{body_pattern(assigned, body, acc)} ->
          #{indent(loop_body(body, assigned, acc, body_scope, state, false, false), 2)}
          end)\
          """
    end
  end

  defp gen_while({:while, condition, body, _line} = node, scope, state, rest) do
    assigned = assigned_in_loop(node, scope)
    acc = tuple_of(assigned)
    inner = loop_body(body, assigned, acc, scope, state, contains_jump?(body), true)

    binder(result_binder(assigned, rest, state)) <>
      """
      gd_while(#{acc || "nil"}, fn #{condition_pattern(assigned, condition, acc)} -> gd_truthy(#{load(state, condition, gen_expression(condition, state))}) end, fn #{body_pattern(assigned, body, acc)} ->
      #{indent(inner, 2)}
      end)\
      """
  end

  defp binder(nil), do: ""
  defp binder(acc), do: "#{acc} =\n  "

  defp loop_state(state, acc, assigned),
    do: %{state | loop_acc: acc, in_loop?: true, tail_reads: MapSet.new(assigned)}

  # One iteration. `break` and `continue` throw the accumulator out rather than
  # restructuring the body, so they work at any nesting depth inside the loop --
  # and a `return` throws past this catch to the function, which is what it
  # should do.
  defp loop_body(body, assigned, acc, scope, state, jumps?, tagged?) do
    lines = plain_body(body, scope, loop_state(state, acc, assigned))
    value = acc || "nil"

    cond do
      jumps? ->
        """
        try do
        #{indent(lines, 2)}
          {:cont, #{value}}
        catch
          {:gd_break, gd_acc} -> {:halt, gd_acc}
          {:gd_continue, gd_acc} -> {:cont, gd_acc}
        end\
        """

      tagged? ->
        lines <> "\n{:cont, " <> value <> "}"

      true ->
        lines <> "\n" <> value
    end
  end

  # An accumulator bound in a `fn` head that the body overwrites before reading
  # is an unused variable, and Elixir warns on it -- with a shadowing note, since
  # the same name exists outside. The dead-store analysis already answers
  # exactly this question, so the head takes `_name` for those.
  defp body_pattern(assigned, body, acc) do
    if acc == nil do
      "nil"
    else
      assigned
      |> Enum.map(fn name ->
        if overwritten_before_read?(name, body), do: "_" <> name, else: name
      end)
      |> tuple_of()
    end
  end

  # The condition only reads some of the accumulator, and the rest would warn.
  defp condition_pattern(assigned, condition, acc) do
    if acc == nil do
      "nil"
    else
      assigned
      |> Enum.map(fn name -> if reads?(condition, name), do: name, else: "_" <> name end)
      |> tuple_of()
    end
  end

  defp plain_body(body, scope, state) do
    {lines, _scope} = gen_statements(body, scope, state, false)
    lines |> Enum.join("\n") |> String.trim_trailing()
  end

  defp assert_in_loop!(keyword, line, state) do
    unless state.in_loop? do
      raise CompileError,
        file: state.file,
        line: line,
        message: "`#{keyword}` is only valid inside a `for` or `while` loop"
    end
  end

  # A jump belongs to the nearest enclosing loop, so this does not descend into
  # a nested `for`/`while` -- that loop catches its own.
  defp contains_jump?(statements) do
    Enum.any?(statements, fn
      {:break, _} ->
        true

      {:continue, _} ->
        true

      {:if, clauses, else_body, _} ->
        Enum.any?(clauses, fn {_condition, body} -> contains_jump?(body) end) or
          (else_body != nil and contains_jump?(else_body))

      {:match, _subject, cases, _} ->
        Enum.any?(cases, fn {_patterns, body} -> contains_jump?(body) end)

      _ ->
        false
    end)
  end

  defp assigned_in_loop({:for, var, _collection, body, _line}, scope) do
    body |> assigned_in_body(MapSet.delete(scope, var)) |> Enum.uniq() |> Enum.sort()
  end

  defp assigned_in_loop({:while, _condition, body, _line}, scope) do
    body |> assigned_in_body(scope) |> Enum.uniq() |> Enum.sort()
  end

  # ── Dead stores ──────────────────────────────────────────────────────────
  # A declaration whose value every later path overwrites before reading is a
  # dead store, and Elixir warns "variable is unused" on it. That matters more
  # than tidiness: warnings on generated code are how a codegen bug announces
  # itself, so routine noise would drown the signal. The initializer is still
  # evaluated, in case it has side effects -- only the binding is dropped.
  defp gen_dead_store({:var, _name, expr, _line}, state) do
    "_ = #{gen_expression(expr, state)}"
  end

  # Only ever answers true when the binding is provably never read: a later
  # unconditional assignment, or an `if` that assigns it in every branch (else
  # included) and reads it in none. Defaulting to false costs a warning at
  # worst; a wrong true would be a compile error, so the bias is deliberate.
  defp dead_store?({:var, name, _expr, _line}, rest), do: overwritten_before_read?(name, rest)
  defp dead_store?(_statement, _rest), do: false

  defp overwritten_before_read?(_name, []), do: false

  defp overwritten_before_read?(name, [statement | rest]) do
    cond do
      reads?(statement, name) -> false
      overwrites?(statement, name) -> true
      true -> overwritten_before_read?(name, rest)
    end
  end

  defp overwrites?({:assign, {:ident, name, _}, "=", _expr, _}, name), do: true

  defp overwrites?({:match, _subject, cases, _}, name) do
    # Only definite when some clause always matches and every clause assigns.
    Enum.any?(cases, fn {patterns, _body} -> catch_all?(patterns) end) and
      Enum.all?(cases, fn {_patterns, body} -> Enum.any?(body, &overwrites?(&1, name)) end)
  end

  defp overwrites?({:if, clauses, else_body, _}, name) do
    bodies = Enum.map(clauses, fn {_condition, body} -> body end)

    # No `else` means a path that skips every branch, so the outer value
    # survives and is read by the lift.
    else_body != nil and
      Enum.all?(bodies ++ [else_body], fn body ->
        Enum.any?(body, &overwrites?(&1, name))
      end)
  end

  defp overwrites?(_statement, _name), do: false

  defp reads?(node, name) when is_list(node), do: Enum.any?(node, &reads?(&1, name))
  defp reads?({:ident, name, _}, name), do: true
  defp reads?({:var, _, expr, _}, name), do: reads?(expr, name)

  # `x += 1` reads x before writing it; `x = 1` does not -- and `y += 1` reads
  # neither. Testing the operator without testing the target reported every
  # name as read, which silently disabled the analyses built on this.
  defp reads?({:assign, {:ident, target, _}, op, expr, _}, name),
    do: (op != "=" and target == name) or reads?(expr, name)

  # An element assignment reads its container and its key, always.
  defp reads?({:assign, {:index, object, key, _}, _op, expr, _}, name),
    do: reads?([object, key, expr], name)

  defp reads?({:return, expr, _}, name), do: expr != nil and reads?(expr, name)
  defp reads?({:expr, expr, _}, name), do: reads?(expr, name)

  defp reads?({:if, clauses, else_body, _}, name) do
    Enum.any?(clauses, fn {condition, body} ->
      reads?(condition, name) or reads?(body, name)
    end) or (else_body != nil and reads?(else_body, name))
  end

  # A loop that reads the name keeps it live. Being conservative about a loop
  # variable that shadows it only costs a binding we could have dropped.
  defp reads?({:for, _var, collection, body, _}, name),
    do: reads?(collection, name) or reads?(body, name)

  defp reads?({:while, condition, body, _}, name),
    do: reads?(condition, name) or reads?(body, name)

  defp reads?({:match, subject, cases, _}, name) do
    reads?(subject, name) or
      Enum.any?(cases, fn {patterns, body} ->
        name not in bound_names(patterns) and reads?(body, name)
      end)
  end

  defp reads?({:lambda, params, body, _}, name) do
    # A parameter of the same name shadows the outer one inside the body.
    not Enum.any?(params, fn {param, _default} -> param == name end) and reads?(body, name)
  end

  defp reads?({:await, expr, _}, name), do: reads?(expr, name)
  defp reads?({:binop, _, left, right, _}, name), do: reads?([left, right], name)
  defp reads?({:unop, _, operand, _}, name), do: reads?(operand, name)
  defp reads?({:member, object, _, _}, name), do: reads?(object, name)
  defp reads?({:index, object, index, _}, name), do: reads?([object, index], name)
  defp reads?({:call, callee, args, _}, name), do: reads?([callee | args], name)
  defp reads?({:array, elements, _}, name), do: reads?(elements, name)

  defp reads?({:dict, pairs, _}, name),
    do: Enum.any?(pairs, fn {key, value} -> reads?([key, value], name) end)

  defp reads?(_node, _name), do: false

  defp gen_local_assign(name, op, expr, line, scope, state) do
    unless MapSet.member?(scope, name) do
      raise CompileError,
        file: state.file,
        line: line,
        message: "`#{name}` is assigned before it is declared -- use `var #{name} = ...`"
    end

    value =
      case op do
        "=" -> gen_expression(expr, state)
        _ -> gen_binop(compound_op(op), {:ident, name, line}, expr, state)
      end

    {"#{name} = #{value}", scope}
  end

  defp compound_op("+="), do: :+
  defp compound_op("-="), do: :-
  defp compound_op("*="), do: :*
  defp compound_op("/="), do: :/
  defp compound_op("%="), do: :%

  # ── if, and the mutation lift ────────────────────────────────────────────

  defp gen_if(clauses, else_body, assigned, scope, state, rest) do
    expression = gen_if_chain(clauses, else_body, assigned, scope, state)

    case result_binder(assigned, rest, state) do
      nil -> expression
      binder -> "#{binder} = #{expression}"
    end
  end

  # The construct hands back every variable it may have changed, but the code
  # after it may read only some. Binding the rest under their own names is a
  # dead store, which Elixir warns about -- so those take `_name`.
  defp result_binder(assigned, rest, state) do
    assigned
    |> Enum.map(fn name ->
      if reads?(rest, name) or MapSet.member?(state.tail_reads, name),
        do: name,
        else: "_" <> name
    end)
    |> tuple_of()
  end

  # An `elif` chain is a nested `else`. Recursing keeps every `if` paired with
  # its own `end` by construction, rather than counting them at the end.
  defp gen_if_chain([{condition, body} | rest], else_body, assigned, scope, state) do
    tail =
      case rest do
        [] ->
          case else_body do
            nil -> tail_value(assigned)
            body -> branch_lines(body, assigned, scope, state)
          end

        _ ->
          gen_if_chain(rest, else_body, assigned, scope, state)
      end

    """
    if gd_truthy(#{load(state, condition, gen_expression(condition, state))}) do
    #{indent(branch_lines(body, assigned, scope, state), 2)}
    else
    #{indent(tail, 2)}
    end\
    """
  end

  defp branch_lines(body, assigned, scope, state) do
    state = %{state | tail_reads: MapSet.new(assigned)}
    {lines, _scope} = gen_statements(body, scope, state, false)

    # `return`, `break` and `continue` have all thrown by the time control would
    # reach the lifted tuple, so emitting one is dead text.
    lines = if terminates?(List.last(body)), do: lines, else: lines ++ [tail_value(assigned)]

    lines |> Enum.join("\n") |> String.trim_trailing()
  end

  defp terminates?({:return, _, _}), do: true
  defp terminates?({:break, _}), do: true
  defp terminates?({:continue, _}), do: true
  defp terminates?(_statement), do: false

  defp tail_value([]), do: "nil"
  defp tail_value(names), do: tuple_of(names)

  defp tuple_of([]), do: nil
  defp tuple_of([one]), do: one
  defp tuple_of(names), do: "{" <> Enum.join(names, ", ") <> "}"

  # Names assigned in any branch that already exist in the enclosing scope. A
  # `var` inside a branch declares a block-scoped local, so it is excluded --
  # lifting it would leak a binding GDScript does not have.
  defp assigned_in_if({:if, clauses, else_body, _line}, scope) do
    # `List.wrap/1` would splice the else body's statements in as separate
    # bodies -- it is already a list.
    else_bodies = if else_body, do: [else_body], else: []
    bodies = Enum.map(clauses, fn {_cond, body} -> body end) ++ else_bodies

    bodies
    |> Enum.flat_map(&assigned_in_body(&1, scope))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp assigned_in_body(body, scope) do
    {names, _local_scope} =
      Enum.reduce(body, {[], scope}, fn statement, {names, scope} ->
        case statement do
          {:var, name, _, _} ->
            # Declared here, so assignments to it below are local, not lifted.
            {names, MapSet.delete(scope, name)}

          {:assign, {:ident, name, _}, _, _, _} ->
            {if(MapSet.member?(scope, name), do: [name | names], else: names), scope}

          {:if, _, _, _} = nested ->
            {assigned_in_if(nested, scope) ++ names, scope}

          {:match, _, _, _} = nested ->
            {assigned_in_match(nested, scope) ++ names, scope}

          {:for, _, _, _, _} = nested ->
            {assigned_in_loop(nested, scope) ++ names, scope}

          {:while, _, _, _} = nested ->
            {assigned_in_loop(nested, scope) ++ names, scope}

          _ ->
            {names, scope}
        end
      end)

    names
  end

  # In reference mode a collection is a `{:gd_ref, _}`, so anything that *reads*
  # one wraps in `gd_load` and anything that *produces* a fresh one wraps in
  # `gd_rebox`. Outside reference mode both are the identity, which is why a
  # script that never mutates compiles to exactly the same text as before.
  defp load(state, ast, code) do
    if state.ref_mode? and ref_possible?(ast), do: "gd_load(#{code})", else: code
  end

  defp deref(state, ast, code) do
    if state.ref_mode? and ref_possible?(ast), do: "gd_deref(#{code})", else: code
  end

  defp rebox(state, left, right, code) do
    if state.ref_mode? and (ref_possible?(left) or ref_possible?(right)),
      do: "gd_rebox(#{code})",
      else: code
  end

  # Only some expressions can evaluate to a reference. Literals, comparisons,
  # logical operators, non-`+` arithmetic and value-type constructors never can,
  # so wrapping them would be noise in code whose readability is the point.
  defp ref_possible?({kind, _, _}) when kind in [:int, :float, :string, :bool], do: false
  defp ref_possible?({:null, _}), do: false
  defp ref_possible?({:unop, _, _, _}), do: false

  defp ref_possible?({:binop, op, _, _, _})
       when op in [:==, :!=, :<, :>, :<=, :>=, :and, :or, :-, :*, :/, :%],
       do: false

  defp ref_possible?({:call, {:ident, type, _}, _, _}) when is_map_key(@value_types, type),
    do: false

  # Most methods answer with a number, a boolean or a string. Only the ones that
  # hand back a fresh collection are reboxed into a reference.
  defp ref_possible?({:call, {:member, object, method, _}, _args, _}) do
    # A context call's result is boxed, so it can be a reference; a method's
    # cannot unless it built a fresh collection.
    if context_object?(object) do
      true
    else
      case Map.fetch(@methods, method) do
        {:ok, {_helper, _required, _defaults, kind, collection?}} ->
          collection? and kind == :value

        :error ->
          true
      end
    end
  end

  defp ref_possible?(_ast), do: true

  # ── Expressions ──────────────────────────────────────────────────────────

  defp gen_expression({:int, value, _}, _state), do: Integer.to_string(value)
  defp gen_expression({:float, value, _}, _state), do: Float.to_string(value)
  defp gen_expression({:string, value, _}, _state), do: inspect(value)
  defp gen_expression({:bool, value, _}, _state), do: to_string(value)
  defp gen_expression({:null, _}, _state), do: "nil"

  defp gen_expression({:raw, code, _line}, _state), do: code

  defp gen_expression({:ident, name, _}, state) do
    # Inside a class method a bare name is a field unless a parameter or a
    # local shadows it, which is how GDScript's implicit `self` reads.
    if field?(state, name),
      do: "gd_index(gd_load(gd_self), \"#{name}\", nil)",
      else: name
  end

  defp gen_expression({:array, elements, _}, state) do
    list = "[" <> Enum.map_join(elements, ", ", &gen_expression(&1, state)) <> "]"
    if state.ref_mode?, do: "gd_new(#{list})", else: list
  end

  defp gen_expression({:dict, pairs, _}, state) do
    inner =
      Enum.map_join(pairs, ", ", fn {key, value} ->
        "#{gen_expression(key, state)} => #{gen_expression(value, state)}"
      end)

    map = "%{" <> inner <> "}"
    if state.ref_mode?, do: "gd_new(#{map})", else: map
  end

  defp gen_expression({:index, object, index, _}, state),
    do:
      "gd_index(#{load(state, object, gen_expression(object, state))}, " <>
        "#{gen_expression(index, state)}, nil)"

  defp gen_expression({:unop, :not, operand, _}, state),
    do: "!gd_truthy(#{load(state, operand, gen_expression(operand, state))})"

  defp gen_expression({:unop, :-, operand, _}, state), do: "-#{gen_expression(operand, state)}"

  defp gen_expression({:binop, op, left, right, _}, state), do: gen_binop(op, left, right, state)

  # A bare `Foo.bar` that is not called is meaningless server-side; a called one
  # is resolved below. So member access here is always a field read.
  defp gen_expression({:member, _object, _field, _} = node, state),
    do: gen_field_read(node, state)

  defp gen_expression({:lambda, params, body, line}, state) do
    Enum.each(params, fn
      {_name, nil} ->
        :ok

      {name, _default} ->
        raise CompileError,
          file: state.file,
          line: line,
          message: "a lambda parameter cannot have a default value (`#{name}`)"
    end)

    names = Enum.map(params, fn {name, _default} -> name end)
    Enum.each(names, &assert_available!(&1, line, state))

    # GDScript lambdas capture by value, and an Elixir closure rebinding a
    # captured name cannot escape either -- so the enclosing scope comes in and
    # nothing goes back out.
    scope = MapSet.union(state.scope, MapSet.new(names))
    {lines, _scope} = gen_statements(body, scope, state, true)
    inner = if non_tail_return?(body), do: wrap_return_catch(lines), else: Enum.join(lines, "\n")

    "fn #{Enum.join(names, ", ")} ->\n" <> indent(inner, 2) <> "\nend"
  end

  defp gen_expression({:ternary, condition, then_expr, else_expr, _line}, state) do
    # Parenthesised because a bare `if ..., do: ..., else: ...` inside a list or
    # an argument list is ambiguous to the Elixir parser.
    "(if gd_truthy(#{load(state, condition, gen_expression(condition, state))}), " <>
      "do: #{gen_expression(then_expr, state)}, else: #{gen_expression(else_expr, state)})"
  end

  defp gen_expression({:await, {:ident, name, _}, _} = node, state) do
    if name in state.signals do
      # `subscribe` already ran at function entry, so nothing emitted between
      # then and here is missed.
      # A catch-all rather than `{:error, :timeout}`: the SDK stub's inferred
      # return type is narrower than its @spec, so a precise second clause
      # reads as unreachable to the type checker in a plugin build.
      unwrapped =
        "case Gamend.Signals.await(\"#{signal_scope(state)}\", \"#{name}\") do\n" <>
          "  {:ok, gd_payload} -> gd_payload\n  _timeout -> nil\nend"

      if state.ref_mode?, do: "gd_box(#{unwrapped})", else: unwrapped
    else
      gen_task_await(node, state)
    end
  end

  defp gen_expression({:await, _expr, _line} = node, state), do: gen_task_await(node, state)

  # `Foo.bar()` is a context call; `f.call()` invokes a Callable. GDScript
  # spells classes in PascalCase and variables in snake_case, which is what
  # tells them apart -- so an unknown PascalCase name still gets the "unknown
  # context" error rather than being mistaken for a variable.
  # `Economy.callv("grant", [id, "gold", 5])` -- the name is resolved at run
  # time against the same generated table, so a script still cannot reach a
  # function outside it; only the error moves from build time to a raise.
  defp gen_expression({:call, {:member, {:ident, class, line}, @new, _}, args, _}, state)
       when is_binary(class) do
    if Map.has_key?(state.classes, class) do
      {init_args, _owner} = init_params(state.classes, class)
      expected = length(init_args)

      unless length(args) == expected do
        raise CompileError,
          file: state.file,
          line: line,
          message: "`#{class}.new` takes #{expected} argument(s), called with #{length(args)}"
      end

      "#{class_fun(class, @new)}(#{gen_args(args, state)})"
    else
      if context_name?(class) do
        assert_context_call!(class, @new, length(args), line, state)
        call = "Gamend.#{class}.new(#{gen_context_args(args, state)})"
        if state.ref_mode?, do: "gd_box(#{call})", else: call
      else
        gen_callable_call({:ident, class, line}, @new, args, line, state)
      end
    end
  end

  defp gen_expression({:call, {:member, {:ident, context, line}, "callv", _}, args, _}, state) do
    unless context_name?(context) and API.functions(context) != nil do
      raise CompileError,
        file: state.file,
        line: line,
        message: "unknown context `#{context}`" <> suggestion(context, API.contexts())
    end

    case args do
      [name, list] ->
        ("gd_callv(Gamend.#{context}, #{api_attribute(context)}, " <>
           "#{deref(state, name, gen_expression(name, state))}, " <>
           "#{deref(state, list, gen_expression(list, state))})")
        |> then(&if(state.ref_mode?, do: "gd_box(#{&1})", else: &1))

      _ ->
        raise CompileError,
          file: state.file,
          line: line,
          message:
            "`callv` takes a name and an array of arguments, " <>
              "e.g. Economy.callv(\"grant\", [id, \"gold\", 5])"
    end
  end

  defp gen_expression({:call, {:member, object, function, line}, args, _}, state) do
    case object do
      {:ident, name, _} ->
        cond do
          # Another script in this plugin, reached by the `class_name` it
          # declared -- Godot's own mechanism for cross-script access.
          Map.has_key?(state.scripts, name) ->
            gen_script_call(name, function, args, line, state)

          Map.has_key?(@static_classes, name) ->
            gen_static_call(name, function, args, line, state)

          context_name?(name) ->
            assert_context_call!(name, function, length(args), line, state)
            # gamend speaks plain terms, so references are flattened on the way
            # out and whatever comes back is boxed on the way in.
            call = "Gamend.#{name}.#{function}(#{gen_context_args(args, state)})"
            if state.ref_mode?, do: "gd_box(#{call})", else: call

          true ->
            gen_callable_call(object, function, args, line, state)
        end

      _ ->
        gen_callable_call(object, function, args, line, state)
    end
  end

  defp gen_expression({:call, {:ident, type, line}, args, _}, state)
       when is_map_key(@value_types, type) do
    {fields, defaults} = Map.fetch!(@value_types, type)
    required = length(fields) - length(defaults)

    unless length(args) in required..length(fields) do
      raise CompileError,
        file: state.file,
        line: line,
        message:
          "`#{type}` takes #{Enum.join(Enum.uniq([required, length(fields)]), " or ")} " <>
            "argument(s), called with #{length(args)}"
    end

    given = Enum.zip(fields, Enum.map(args, &gen_expression(&1, state)))

    missing =
      for {field, default} <- defaults,
          field not in Enum.map(given, &elem(&1, 0)),
          do: {field, default}

    "%{" <> Enum.map_join(given ++ missing, ", ", fn {k, v} -> "#{k}: #{v}" end) <> "}"
  end

  defp gen_expression({:call, {:ident, name, _line}, args, _}, state)
       when is_map_key(@variadic, name) do
    # `min(a, b, c)` takes any number of arguments in Godot. Like the
    # fixed-arity builtins these want the contents, not a reference.
    inner = Enum.map_join(args, ", ", &deref(state, &1, gen_expression(&1, state)))
    "#{Map.fetch!(@variadic, name)}([#{inner}])"
  end

  defp gen_expression({:call, {:ident, "assert", line}, args, _}, state) do
    case args do
      [condition] ->
        "gd_assert(#{gen_expression(condition, state)}, \"assertion failed\")"

      [condition, message] ->
        "gd_assert(#{gen_expression(condition, state)}, #{gen_expression(message, state)})"

      _ ->
        raise CompileError,
          file: state.file,
          line: line,
          message: "`assert` takes 1 or 2 arguments, called with #{length(args)}"
    end
  end

  defp gen_expression({:call, {:ident, "spawn", line}, args, _}, state) do
    case args do
      [{:lambda, _, _, _} = lambda] ->
        starter = if state.ref_mode?, do: "gd_spawn", else: "Task.async"
        "#{starter}(#{gen_expression(lambda, state)})"

      _ ->
        raise CompileError,
          file: state.file,
          line: line,
          message: "`spawn` takes exactly one lambda, e.g. spawn(func(): return 1)"
    end
  end

  defp gen_expression({:call, {:ident, @opts_builtin, line}, args, _}, state) do
    case args do
      [{:dict, pairs, _}] -> gen_keyword_list(pairs, state)
      _ -> raise_opts_shape(line, state)
    end
  end

  defp gen_expression({:call, {:ident, "range", line}, args, _}, state) do
    # `range` is the one builtin with optional arguments, so they are filled in
    # here rather than by a second clause of the helper.
    filled =
      case Enum.map(args, &deref(state, &1, gen_expression(&1, state))) do
        [count] -> ["0", count, "1"]
        [from, to] -> [from, to, "1"]
        [_from, _to, _step] = all -> all
        _ -> raise_builtin_arity!("range", "1, 2 or 3", length(args), line, state)
      end

    "gd_range(#{Enum.join(filled, ", ")})"
  end

  defp gen_expression({:call, {:ident, name, line}, args, _}, state) do
    case Map.fetch(@builtins, name) do
      {:ok, {target, arity}} ->
        unless length(args) == arity do
          raise_builtin_arity!(name, arity, length(args), line, state)
        end

        # `len` and the arithmetic builtins want the contents, not a reference.
        "#{target}(#{Enum.map_join(args, ", ", &deref(state, &1, gen_expression(&1, state)))})"

      :error ->
        assert_local!(name, length(args), line, state)
        # Local calls go to the private body, so references pass straight
        # through without a trip across the boundary.
        target = if state.ref_mode?, do: body_name(name), else: name
        "#{target}(#{gen_args(args, state)})"
    end
  end

  defp gen_expression({:call, _callee, _args, line}, state) do
    raise CompileError,
      file: state.file,
      line: line,
      message: "only `Context.function(...)` and local functions can be called"
  end

  defp raise_builtin_arity!(name, expected, actual, line, state) do
    raise CompileError,
      file: state.file,
      line: line,
      message: "`#{name}` takes #{expected} argument(s), called with #{actual}"
  end

  defp gen_keyword_list(pairs, state) do
    inner =
      Enum.map_join(pairs, ", ", fn
        {{:string, key, key_line}, value} ->
          # The key becomes an atom in the generated source, so it must be a
          # plain identifier -- nothing here can be used to emit arbitrary
          # Elixir, and the atom set is bounded by the script's own text.
          unless Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*[?!]?$/, key) do
            raise CompileError,
              file: state.file,
              line: key_line,
              message: "`opts` keys must be plain lowercase names, got #{inspect(key)}"
          end

          "#{key}: #{gen_expression(value, state)}"

        {other, _value} ->
          raise CompileError,
            file: state.file,
            line: elem(other, tuple_size(other) - 1),
            message: "`opts` keys must be string literals"
      end)

    "[" <> inner <> "]"
  end

  defp raise_opts_shape(line, state) do
    raise CompileError,
      file: state.file,
      line: line,
      message:
        "`opts` takes exactly one Dictionary literal, " <>
          "e.g. opts({\"reason\": \"welcome\"})"
  end

  # A GDScript `Foo.bar()` is an Elixir `Gamend.Foo.bar()`, resolved against the
  # table `mix gen.sdk` generates from `@sdk_modules`. Nothing here is a
  # hand-kept list, so a new SDK context is callable from a script the moment it
  # is added -- and a typo or a wrong argument count is a compile error rather
  # than an UndefinedFunctionError at run time.
  defp context_name?(name), do: String.first(name) == String.upcase(String.first(name))

  defp context_object?({:ident, name, _}), do: context_name?(name)
  defp context_object?(_other), do: false

  defp gen_callable_call({:ident, name, line}, "emit", args, _line, state) do
    unless name in state.signals do
      raise CompileError,
        file: state.file,
        line: line,
        message: "`#{name}` is not a declared signal -- add `signal #{name}` at the top level"
    end

    payload =
      case args do
        [] ->
          "nil"

        [one] ->
          deref(state, one, gen_expression(one, state))

        many ->
          "[" <>
            Enum.map_join(many, ", ", &deref(state, &1, gen_expression(&1, state))) <> "]"
      end

    "Gamend.Signals.emit(\"#{signal_scope(state)}\", \"#{name}\", #{payload})"
  end

  defp gen_callable_call(object, "call", args, _line, state),
    do: "#{gen_expression(object, state)}.(#{gen_args(args, state)})"

  defp gen_callable_call(object, method, args, line, state) do
    if class_method?(state, method) and not Map.has_key?(@methods, method) do
      "gd_invoke(#{gen_expression(object, state)}, \"#{method}\", [#{gen_args(args, state)}])"
    else
      gen_builtin_method(object, method, args, line, state)
    end
  end

  defp class_method?(state, method),
    do: Enum.any?(state.classes, fn {_name, class} -> Map.has_key?(class.methods, method) end)

  defp gen_builtin_method(object, method, args, line, state) do
    case Map.fetch(@methods, method) do
      {:ok, {helper, required, defaults, kind, collection?}} ->
        reject_deep_copy!(method, args, line, state)
        args = fill_defaults(method, args, required, defaults, line, state)
        gen_method(object, method, helper, args, kind, collection?, state)

      :error ->
        raise CompileError,
          file: state.file,
          line: line,
          message:
            "unknown method `.#{method}()`" <>
              suggestion(method, Map.keys(@methods) ++ ["call"])
    end
  end

  # Godot's methods have optional tails (`slice(begin, end, step, deep)`).
  # Codegen fills them in, so every helper keeps one fixed arity -- an Elixir
  # default argument that only one call site uses is a warning.
  # `duplicate(true)` and `slice(..., deep)` copy nested collections in Godot.
  # Rebuilding every nested reference is a different operation from the shallow
  # one, so the deep form is refused where it is written rather than quietly
  # doing the shallow thing.
  defp reject_deep_copy!(method, args, line, state) when method in [@duplicate, "slice"] do
    deep_at = if method == @duplicate, do: 0, else: 3

    case Enum.at(args, deep_at) do
      nil ->
        :ok

      {:bool, false, _} ->
        :ok

      _deep ->
        raise CompileError,
          file: state.file,
          line: line,
          message:
            "a deep `#{method}` is not supported -- it would have to rebuild every " <>
              "nested Array and Dictionary; copy the parts you need instead"
    end
  end

  defp reject_deep_copy!(_method, _args, _line, _state), do: :ok

  defp fill_defaults(method, args, required, defaults, line, state) do
    given = length(args)
    most = required + length(defaults)

    unless given >= required and given <= most do
      expected =
        if defaults == [],
          do: "#{required}",
          else: "#{required} to #{most}"

      raise CompileError,
        file: state.file,
        line: line,
        message: "`.#{method}()` takes #{expected} argument(s), called with #{given}"
    end

    args ++ Enum.map(Enum.drop(defaults, given - required), &{:raw, &1, line})
  end

  # `gd_mutate` writes through a reference and returns null, but *transforms* a
  # plain value and returns it -- which is exactly the Array/String split:
  # `xs.reverse()` mutates the array, `s.reverse()` hands back a new string.
  defp gen_method(object, method, helper, args, :mutate, _collection?, state) do
    "gd_mutate(#{gen_expression(object, state)}, fn gd_c -> " <>
      "#{helper}(gd_c#{method_args(args, state, method)}) end)"
  end

  # `pop_back` and friends write *and* return, so the helper answers
  # `{new_receiver, result}`.
  defp gen_method(object, method, helper, args, :take, _collection?, state) do
    "gd_take(#{gen_expression(object, state)}, fn gd_c -> " <>
      "#{helper}(gd_c#{method_args(args, state, method)}) end)"
  end

  defp gen_method(object, method, helper, args, :value, collection?, state) do
    call =
      "#{helper}(#{load(state, object, gen_expression(object, state))}" <>
        "#{method_args(args, state, method)})"

    # `keys()`, `split()` and friends hand back a fresh Array, which has to be a
    # reference of its own so it can be aliased and mutated like any other.
    if collection? and state.ref_mode?, do: "gd_rebox(#{call})", else: call
  end

  defp method_args([], _state, _method), do: ""

  defp method_args(args, state, method) when method in @methods_loading_args,
    do: ", " <> Enum.map_join(args, ", ", &load(state, &1, gen_expression(&1, state)))

  defp method_args(args, state, _method), do: ", " <> gen_args(args, state)

  defp assert_context_call!(context, function, arity, line, state) do
    cond do
      API.functions(context) == nil ->
        raise CompileError,
          file: state.file,
          line: line,
          message:
            "unknown context `#{context}`" <>
              suggestion(context, API.contexts()) <>
              "\navailable: " <> Enum.join(API.contexts(), ", ")

      API.arities(context, function) == nil ->
        raise CompileError,
          file: state.file,
          line: line,
          message:
            "`#{context}` has no function `#{function}`" <>
              suggestion(function, API.functions(context))

      arity not in API.arities(context, function) ->
        raise CompileError,
          file: state.file,
          line: line,
          message:
            "`#{context}.#{function}` takes " <>
              Enum.map_join(API.arities(context, function), " or ", &to_string/1) <>
              " argument(s), called with #{arity}"

      true ->
        :ok
    end
  end

  defp suggestion(given, candidates) do
    candidates
    |> Enum.filter(&(String.jaro_distance(String.downcase(&1), String.downcase(given)) > 0.8))
    |> Enum.sort_by(&(-String.jaro_distance(String.downcase(&1), String.downcase(given))))
    |> Enum.take(2)
    |> case do
      [] -> ""
      names -> " -- did you mean " <> Enum.map_join(names, " or ", &"`#{&1}`") <> "?"
    end
  end

  defp assert_local!(name, arity, line, state) do
    arities = for {local, local_arity} <- state.locals, local == name, do: local_arity

    cond do
      arity in arities ->
        :ok

      arities != [] ->
        raise CompileError,
          file: state.file,
          line: line,
          message:
            "`#{name}` takes #{Enum.join(Enum.sort(arities), " or ")} argument(s), " <>
              "called with #{arity}"

      true ->
        raise CompileError,
          file: state.file,
          line: line,
          message: "unknown function `#{name}`"
    end
  end

  defp gen_task_await({:await, expr, _line}, state) do
    awaited = "Task.await(#{gen_expression(expr, state)}, 30_000)"
    # The task has its own heap, so it hands back plain terms; box them into
    # this process's heap on arrival.
    if state.ref_mode?, do: "gd_box(#{awaited})", else: awaited
  end

  defp gen_static_call(class, function, args, line, state) do
    methods = Map.fetch!(@static_classes, class)

    case Map.fetch(methods, function) do
      {:ok, {helper, required, defaults}} ->
        args = fill_defaults("#{class}.#{function}", args, required, defaults, line, state)
        "#{helper}(#{gen_context_args(args, state)})"

      :error ->
        raise CompileError,
          file: state.file,
          line: line,
          message: "`#{class}` has no `#{function}`" <> suggestion(function, Map.keys(methods))
    end
  end

  defp gen_script_call(script, function, args, line, state) do
    entry = Map.fetch!(state.scripts, script)
    arity = length(args)

    unless MapSet.member?(entry.functions, {function, arity}) do
      names = entry.functions |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

      raise CompileError,
        file: state.file,
        line: line,
        message:
          "`#{script}` has no `#{function}` taking #{arity} argument(s)" <>
            suggestion(function, names)
    end

    # Straight to the private body: references stay references, and the
    # boundary is only crossed where gamend calls in.
    target = if state.ref_mode?, do: body_name(function), else: function
    "#{entry.module}.#{target}(#{gen_args(args, state)})"
  end

  defp gen_field_read({:member, object, field, _}, state),
    do: "gd_get(#{load(state, object, gen_expression(object, state))}, :#{field})"

  defp gen_args(args, state), do: Enum.map_join(args, ", ", &gen_expression(&1, state))

  defp gen_context_args(args, state),
    do: Enum.map_join(args, ", ", &deref(state, &1, gen_expression(&1, state)))

  # `+` concatenates strings, `/` is integer division between ints, `%` is
  # `rem` -- none of which Elixir's operators do, so those three go through a
  # helper. The rest map straight across.
  # `+` on Arrays makes a *new* Array in GDScript, so the result is reboxed --
  # otherwise it could not be aliased or mutated afterwards.
  defp gen_binop(:+, left, right, state),
    do:
      rebox(
        state,
        left,
        right,
        "gd_add(#{load(state, left, gen_expression(left, state))}, " <>
          "#{load(state, right, gen_expression(right, state))})"
      )

  # Godot compares Arrays and Dictionaries by contents; two refs never match.
  defp gen_binop(op, left, right, state) when op in [:==, :!=] do
    "(#{deref(state, left, gen_expression(left, state))} #{op} " <>
      "#{deref(state, right, gen_expression(right, state))})"
  end

  defp gen_binop(:/, left, right, state),
    do:
      "gd_div(#{load(state, left, gen_expression(left, state))}, " <>
        "#{load(state, right, gen_expression(right, state))})"

  # `"%s" % [a, b]` formats, so the right-hand side has to be plain all the way
  # down -- a shallow load would leave nested references in the argument list.
  defp gen_binop(:%, left, right, state),
    do:
      "gd_mod(#{load(state, left, gen_expression(left, state))}, " <>
        "#{deref(state, right, gen_expression(right, state))})"

  defp gen_binop(:-, left, right, state),
    do:
      "gd_sub(#{load(state, left, gen_expression(left, state))}, " <>
        "#{load(state, right, gen_expression(right, state))})"

  defp gen_binop(:*, left, right, state),
    do:
      "gd_mul(#{load(state, left, gen_expression(left, state))}, " <>
        "#{load(state, right, gen_expression(right, state))})"

  defp gen_binop(op, left, {:ident, type, line}, state) when op in [:is, :as] do
    unless type in @type_names do
      raise CompileError,
        file: state.file,
        line: line,
        message: "unknown type `#{type}`" <> suggestion(type, @type_names)
    end

    helper = if op == :is, do: "gd_is", else: "gd_as"
    "#{helper}(#{load(state, left, gen_expression(left, state))}, :#{String.downcase(type)})"
  end

  defp gen_binop(op, _left, right, state) when op in [:is, :as] do
    raise CompileError,
      file: state.file,
      line: elem(right, tuple_size(right) - 1),
      message: "`#{op}` expects a type name on the right, e.g. `value #{op} int`"
  end

  defp gen_binop(op, left, right, state) when op in [:and, :or] do
    elixir_op = if op == :and, do: "and", else: "or"

    "(gd_truthy(#{gen_expression(left, state)}) #{elixir_op} " <>
      "gd_truthy(#{gen_expression(right, state)}))"
  end

  defp gen_binop(op, left, right, state),
    do: "(#{gen_expression(left, state)} #{op} #{gen_expression(right, state)})"

  # ── Emitted helpers ──────────────────────────────────────────────────────

  # Emitted into the generated module itself rather than pulled from a runtime
  # library, so a compiled script has no dependency at all.
  # Every helper is deliberately ONE clause with an internal `cond`.
  # Multi-clause guards look nicer, but Elixir's type checker narrows from the
  # call sites in the generated module and then warns "this clause is never
  # used" -- turning perfectly correct output into warnings, and into hard
  # errors under `--warnings-as-errors`. A single clause cannot be narrowed.
  @helper_sources %{
    gd_truthy: ~S'''
      # GDScript truthiness: 0, 0.0, "", [] and {} are falsy, unlike Elixir.
      defp gd_truthy(value) do
        cond do
          value == nil or value == false -> false
          is_number(value) -> value != 0
          is_binary(value) -> value != ""
          is_list(value) -> value != []
          is_map(value) -> map_size(value) > 0
          true -> true
        end
      end
    ''',
    gd_add: ~S'''
      # `+` concatenates in GDScript when both sides are strings or arrays, and
      # adds value types component-wise.
      defp gd_add(left, right) do
        cond do
          is_binary(left) and is_binary(right) -> left <> right
          is_list(left) and is_list(right) -> left ++ right
          gd_vec?(left) and gd_vec?(right) -> Map.merge(left, right, fn _key, a, b -> a + b end)
          true -> left + right
        end
      end
    ''',
    gd_div: ~S'''
      # Two ints divide to an int in GDScript; Elixir's `/` always floats.
      defp gd_div(left, right) do
        if is_integer(left) and is_integer(right),
          do: div(left, right),
          else: left / right
      end
    ''',
    gd_mod: ~S'''
      defp gd_mod(left, right) do
        cond do
          is_binary(left) -> gd_format(left, right)
          is_integer(left) and is_integer(right) -> rem(left, right)
          true -> :math.fmod(left, right)
        end
      end
    ''',
    gd_new: ~S'''
      # Arrays and Dictionaries are mutable and compared by identity in GDScript,
      # so they live in the hook process's own dictionary and a script holds
      # references to them. Every hook and RPC already runs in its own Task, so
      # the heap is scoped to one call and dies with it -- there is nothing to
      # free, and no other hook can see it.
      defp gd_new(value) do
        ref = make_ref()
        Process.put(ref, value)
        {:gd_ref, ref}
      end
    ''',
    gd_load: ~S'''
      defp gd_load(value) do
        case value do
          {:gd_ref, ref} -> Process.get(ref)
          other -> other
        end
      end
    ''',
    gd_ref?: ~S'''
      defp gd_ref?(value), do: match?({:gd_ref, _}, value)
    ''',
    gd_deref: ~S'''
      defp gd_deref(value) do
        cond do
          gd_ref?(value) -> value |> gd_load() |> gd_deref()
          is_list(value) -> Enum.map(value, &gd_deref/1)
          is_struct(value) or gd_vec?(value) -> value
          is_map(value) -> Map.new(value, fn {k, v} -> {k, gd_deref(v)} end)
          is_tuple(value) -> value |> Tuple.to_list() |> Enum.map(&gd_deref/1) |> List.to_tuple()
          true -> value
        end
      end
    ''',
    gd_box: ~S'''
      # The boundary in. gamend speaks plain terms; the script speaks
      # references. Structs and value types cross unchanged -- a struct is a
      # payload to read, not a Dictionary to mutate.
      defp gd_box(value) do
        cond do
          gd_ref?(value) -> value
          is_list(value) -> gd_new(Enum.map(value, &gd_box/1))
          is_struct(value) or gd_vec?(value) -> value
          is_map(value) -> gd_new(Map.new(value, fn {k, v} -> {k, gd_box(v)} end))
          is_tuple(value) -> value |> Tuple.to_list() |> Enum.map(&gd_box/1) |> List.to_tuple()
          true -> value
        end
      end
    ''',
    gd_store: ~S'''
      defp gd_store(value, fun) do
        case value do
          {:gd_ref, ref} ->
            Process.put(ref, fun.(Process.get(ref)))
            nil

          _other ->
            raise ArgumentError,
                  "cannot modify this value in place: it is not an Array or Dictionary"
        end
      end
    ''',
    gd_put: ~S'''
      defp gd_put(container, key, value) do
        cond do
          is_list(container) and is_integer(key) -> List.replace_at(container, key, value)
          is_map(container) -> Map.put(container, key, value)
          true -> container
        end
      end
    ''',
    gd_rebox: ~S'''
      # `+` on Arrays produces a new Array, which has to be a reference too.
      defp gd_rebox(value) do
        cond do
          gd_ref?(value) -> value
          is_list(value) -> gd_new(value)
          is_struct(value) or gd_vec?(value) -> value
          is_map(value) -> gd_new(value)
          true -> value
        end
      end
    ''',
    gd_spawn: ~S'''
      # A spawned lambda runs in another process with another heap, so it gets a
      # snapshot of this one and hands plain terms back. Mutations inside it do
      # not travel home -- see the guide.
      defp gd_spawn(fun) do
        snapshot = for {key, value} <- Process.get(), is_reference(key), do: {key, value}

        Task.async(fn ->
          Enum.each(snapshot, fn {key, value} -> Process.put(key, value) end)
          gd_deref(fun.())
        end)
      end
    ''',
    gd_str: ~S'''
      # Godot's `str()`: Arrays and Dictionaries print as themselves, and null
      # prints as `<null>`. `to_string/1` gets both wrong.
      defp gd_str(value) do
        cond do
          is_binary(value) -> value
          is_nil(value) -> "<null>"
          is_list(value) -> "[" <> Enum.map_join(value, ", ", &gd_str/1) <> "]"
          is_struct(value) -> inspect(value)
          is_map(value) -> "{" <> Enum.map_join(value, ", ", &gd_str_pair/1) <> "}"
          is_number(value) or is_atom(value) -> to_string(value)
          true -> inspect(value)
        end
      end

      defp gd_str_pair({key, value}), do: "#{gd_str(key)}: #{gd_str(value)}"
    ''',
    gd_print: ~S'''
      defp gd_print(values) do
        IO.puts(gd_str_join(values, ""))
        nil
      end
    ''',
    gd_str_all: ~S'''
      defp gd_str_all(values), do: gd_str_join(values, "")
    ''',
    gd_str_join: ~S'''
      defp gd_str_join(values, separator), do: Enum.map_join(values, separator, &gd_str/1)
    ''',
    gd_format: ~S'''
      # `"%s scored %d" % [name, score]`.
      defp gd_format(format, args) do
        args = if is_list(args), do: args, else: [args]

        ~r/%[sdfx%]/
        |> Regex.split(format, include_captures: true)
        |> Enum.reduce({[], args}, &gd_format_part/2)
        |> elem(0)
        |> Enum.reverse()
        |> IO.iodata_to_binary()
      end

      defp gd_format_part(part, {acc, rest}) do
        cond do
          part == "%%" -> {["%" | acc], rest}
          String.starts_with?(part, "%") and rest == [] -> {[part | acc], []}
          String.starts_with?(part, "%") -> {[gd_format_one(part, hd(rest)) | acc], tl(rest)}
          true -> {[part | acc], rest}
        end
      end

      defp gd_format_one(spec, value) do
        case spec do
          "%d" -> gd_str(gd_to_int(value))
          "%f" -> gd_str(gd_to_float(value))
          # Godot prints hex lowercase; `Integer.to_string/2` prints it upper.
          "%x" -> value |> gd_to_int() |> Integer.to_string(16) |> String.downcase()
          _string -> gd_str(value)
        end
      end
    ''',
    gd_assert: ~S'''
      defp gd_assert(condition, message) do
        if gd_truthy(condition), do: nil, else: raise(message)
      end
    ''',
    gd_is: ~S'''
      defp gd_is(value, type) do
        case type do
          :int -> is_integer(value)
          :float -> is_float(value)
          :string -> is_binary(value)
          :bool -> is_boolean(value)
          :array -> is_list(value)
          :dictionary -> is_map(value) and not is_struct(value)
          _vector -> gd_vec?(value)
        end
      end
    ''',
    gd_as: ~S'''
      # A cast that does not fit returns null, as in Godot.
      defp gd_as(value, type) do
        cond do
          gd_is(value, type) -> value
          type == :int -> gd_to_int(value)
          type == :float -> gd_to_float(value)
          type == :string -> gd_str(value)
          true -> nil
        end
      end
    ''',
    gd_floor: ~S'''
      defp gd_floor(value), do: if(is_integer(value), do: value, else: Float.floor(value))
    ''',
    gd_ceil: ~S'''
      defp gd_ceil(value), do: if(is_integer(value), do: value, else: Float.ceil(value))
    ''',
    gd_round: ~S'''
      defp gd_round(value), do: if(is_integer(value), do: value, else: Float.round(value))
    ''',
    gd_typeof: ~S'''
      # Godot's Variant.Type names, as strings -- the numeric ids are engine
      # constants that mean nothing here.
      defp gd_typeof(value) do
        cond do
          is_nil(value) -> "null"
          is_boolean(value) -> "bool"
          is_integer(value) -> "int"
          is_float(value) -> "float"
          is_binary(value) -> "String"
          is_list(value) -> "Array"
          gd_vec?(value) -> "Vector"
          is_map(value) -> "Dictionary"
          true -> "Object"
        end
      end
    ''',
    gd_parsed: ~S'''
      # `Integer.parse/1` and `Float.parse/1` answer `{number, rest}` or `:error`.
      defp gd_parsed(result, fallback) do
        case result do
          {number, _rest} -> number
          _error -> fallback
        end
      end
    ''',
    gd_callv: ~S'''
      # Dispatch by name, bounded by the table the compiler generated: a name
      # outside it raises rather than reaching an arbitrary function.
      defp gd_callv(module, allowed, name, args) do
        args = if is_list(args), do: args, else: [args]
        arity = length(args)

        if {name, arity} in allowed do
          apply(module, String.to_existing_atom(name), args)
        else
          raise ArgumentError,
                "#{inspect(module)} has no #{name}/#{arity} available to scripts"
        end
      end
    ''',
    gd_mutate: ~S'''
      # Writes through a reference and answers null; transforms a plain value
      # and answers it. That is the Array/String split in Godot: `xs.reverse()`
      # mutates the array, `s.reverse()` returns a new string.
      defp gd_mutate(target, fun) do
        case target do
          {:gd_ref, ref} ->
            Process.put(ref, fun.(Process.get(ref)))
            nil

          value ->
            fun.(value)
        end
      end
    ''',
    gd_take: ~S'''
      # For methods that write *and* return, like `pop_back`. The helper answers
      # `{new_receiver, result}`.
      defp gd_take(target, fun) do
        case target do
          {:gd_ref, ref} ->
            {updated, result} = fun.(Process.get(ref))
            Process.put(ref, updated)
            result

          value ->
            {_updated, result} = fun.(value)
            result
        end
      end
    ''',
    gd_all: ~S'''
      defp gd_all(list, fun), do: is_list(list) and Enum.all?(list, fun)
    ''',
    gd_any: ~S'''
      defp gd_any(list, fun), do: is_list(list) and Enum.any?(list, fun)
    ''',
    gd_map: ~S'''
      defp gd_map(list, fun), do: if(is_list(list), do: Enum.map(list, fun), else: [])
    ''',
    gd_filter: ~S'''
      defp gd_filter(list, fun), do: if(is_list(list), do: Enum.filter(list, fun), else: [])
    ''',
    gd_reduce: ~S'''
      # Godot's callable takes `(accum, elem)`; Elixir's takes `(elem, accum)`.
      defp gd_reduce(list, fun, accum) do
        if is_list(list), do: Enum.reduce(list, accum, fn e, a -> fun.(a, e) end), else: accum
      end
    ''',
    gd_sort_custom: ~S'''
      defp gd_sort_custom(list, fun), do: if(is_list(list), do: Enum.sort(list, fun), else: list)
    ''',
    gd_find_custom: ~S'''
      defp gd_find_custom(list, fun, from) do
        if is_list(list) do
          case Enum.find_index(Enum.drop(list, from), fun) do
            nil -> -1
            index -> index + from
          end
        else
          -1
        end
      end
    ''',
    gd_rfind_custom: ~S'''
      defp gd_rfind_custom(list, fun, _from) do
        if is_list(list) do
          case list |> Enum.reverse() |> Enum.find_index(fun) do
            nil -> -1
            index -> length(list) - 1 - index
          end
        else
          -1
        end
      end
    ''',
    gd_append_array: ~S'''
      defp gd_append_array(list, other) do
        if is_list(list) and is_list(other), do: list ++ other, else: list
      end
    ''',
    gd_push_front: ~S'''
      defp gd_push_front(list, value), do: if(is_list(list), do: [value | list], else: list)
    ''',
    gd_fill: ~S'''
      defp gd_fill(list, value),
        do: if(is_list(list), do: List.duplicate(value, length(list)), else: list)
    ''',
    gd_resize: ~S'''
      # Godot pads with null and truncates; the return is an error code, which
      # is meaningless here.
      defp gd_resize(list, size) do
        cond do
          not is_list(list) -> list
          size <= length(list) -> Enum.take(list, size)
          true -> list ++ List.duplicate(nil, size - length(list))
        end
      end
    ''',
    gd_shuffle: ~S'''
      defp gd_shuffle(list), do: if(is_list(list), do: Enum.shuffle(list), else: list)
    ''',
    gd_pick_random: ~S'''
      defp gd_pick_random(list) do
        if is_list(list) and list != [], do: Enum.random(list), else: nil
      end
    ''',
    gd_pop_at: ~S'''
      defp gd_pop_at(list, index) do
        if is_list(list),
          do: {List.delete_at(list, index), Enum.at(list, index)},
          else: {list, nil}
      end
    ''',
    gd_pop_back: ~S'''
      defp gd_pop_back(list) do
        if is_list(list) and list != [],
          do: {Enum.drop(list, -1), List.last(list)},
          else: {list, nil}
      end
    ''',
    gd_pop_front: ~S'''
      defp gd_pop_front(list) do
        if is_list(list) and list != [], do: {tl(list), hd(list)}, else: {list, nil}
      end
    ''',
    gd_max_of: ~S'''
      defp gd_max_of(list), do: if(is_list(list) and list != [], do: Enum.max(list), else: nil)
    ''',
    gd_min_of: ~S'''
      defp gd_min_of(list), do: if(is_list(list) and list != [], do: Enum.min(list), else: nil)
    ''',
    gd_count: ~S'''
      # `Array.count(value)` counts occurrences; `String.count(what, from, to)`
      # counts substrings in a range, where `to = 0` means "to the end".
      defp gd_count(container, value, from, to) do
        cond do
          is_list(container) ->
            Enum.count(container, &(&1 == value))

          is_binary(container) ->
            stop = if to == 0, do: String.length(container), else: to
            container |> String.slice(from, max(stop - from, 0)) |> gd_occurrences(value)

          true ->
            0
        end
      end

      defp gd_occurrences(_haystack, ""), do: 0
      defp gd_occurrences(haystack, needle), do: length(String.split(haystack, needle)) - 1
    ''',
    gd_has: ~S'''
      # `Dictionary.has` tests a key, `Array.has` a value, `String.contains` a
      # substring. Nested collections compare by reference, not by contents.
      defp gd_has(container, value) do
        cond do
          is_map(container) -> Map.has_key?(container, value)
          is_binary(container) -> String.contains?(container, value)
          is_list(container) -> Enum.member?(container, value)
          true -> false
        end
      end
    ''',
    gd_has_all: ~S'''
      defp gd_has_all(map, keys) do
        is_map(map) and is_list(keys) and Enum.all?(keys, &Map.has_key?(map, &1))
      end
    ''',
    gd_find_key: ~S'''
      defp gd_find_key(map, value) do
        if is_map(map) do
          case Enum.find(map, fn {_key, entry} -> entry == value end) do
            {key, _entry} -> key
            nil -> nil
          end
        else
          nil
        end
      end
    ''',
    gd_get_or_add: ~S'''
      defp gd_get_or_add(map, key, default) do
        cond do
          not is_map(map) -> {map, default}
          Map.has_key?(map, key) -> {map, Map.fetch!(map, key)}
          true -> {Map.put(map, key, default), default}
        end
      end
    ''',
    gd_merge: ~S'''
      # Godot keeps the existing entry unless `overwrite` is true. Elixir's
      # `Map.merge/2` does the opposite, which is how the first version of this
      # silently overwrote.
      defp gd_merge(map, other, overwrite) do
        cond do
          not (is_map(map) and is_map(other)) -> map
          overwrite -> Map.merge(map, other)
          true -> Map.merge(other, map)
        end
      end
    ''',
    gd_merged: ~S'''
      defp gd_merged(map, other, overwrite), do: gd_merge(map, other, overwrite)
    ''',
    gd_duplicate: ~S'''
      # Shallow, like Godot's default. `deep` would have to copy nested
      # references, which is refused rather than silently ignored.
      defp gd_duplicate(value), do: value
    ''',
    gd_erase: ~S'''
      # A value from an Array, a key from a Dictionary, characters from a
      # String -- three meanings for one name, as in Godot.
      defp gd_erase(container, value, chars) do
        cond do
          is_map(container) ->
            Map.delete(container, value)

          is_list(container) ->
            List.delete(container, value)

          is_binary(container) ->
            String.slice(container, 0, value) <>
              String.slice(container, value + chars, String.length(container))

          true ->
            container
        end
      end
    ''',
    gd_insert: ~S'''
      # Array.insert mutates; String.insert returns a new String. `gd_mutate`
      # tells them apart by whether the receiver is a reference.
      defp gd_insert(container, position, value) do
        cond do
          is_list(container) ->
            List.insert_at(container, position, value)

          is_binary(container) ->
            String.slice(container, 0, position) <>
              value <> String.slice(container, position, String.length(container))

          true ->
            container
        end
      end
    ''',
    gd_set: ~S'''
      defp gd_set(container, key, value), do: gd_put(container, key, value)
    ''',
    gd_find: ~S'''
      # -1 when absent, as in Godot.
      defp gd_find(container, what, from) do
        cond do
          is_list(container) ->
            case container |> Enum.drop(from) |> Enum.find_index(&(&1 == what)) do
              nil -> -1
              index -> index + from
            end

          is_binary(container) ->
            case container |> String.slice(from, String.length(container)) |> :binary.match(what) do
              {index, _length} -> index + from
              :nomatch -> -1
            end

          true ->
            -1
        end
      end
    ''',
    gd_rfind: ~S'''
      defp gd_rfind(container, what, _from) do
        cond do
          is_list(container) ->
            case container |> Enum.reverse() |> Enum.find_index(&(&1 == what)) do
              nil -> -1
              index -> length(container) - 1 - index
            end

          is_binary(container) ->
            case :binary.matches(container, what) do
              [] -> -1
              matches -> matches |> List.last() |> elem(0)
            end

          true ->
            -1
        end
      end
    ''',
    gd_reverse: ~S'''
      defp gd_reverse(value) do
        cond do
          is_list(value) -> Enum.reverse(value)
          is_binary(value) -> String.reverse(value)
          true -> value
        end
      end
    ''',
    gd_slice: ~S'''
      # `end` defaults to INT_MAX, and a negative index counts from the end.
      defp gd_slice(value, from, to, step) do
        length = gd_size(value)
        from = if from < 0, do: max(length + from, 0), else: from
        to = if to < 0, do: max(length + to, 0), else: min(to, length)
        count = max(to - from, 0)

        taken =
          cond do
            is_list(value) -> Enum.slice(value, from, count)
            is_binary(value) -> String.slice(value, from, count)
            true -> []
          end

        if step > 1 and is_list(taken),
          do: taken |> Enum.with_index() |> Enum.filter(&(rem(elem(&1, 1), step) == 0)) |> Enum.map(&elem(&1, 0)),
          else: taken
      end
    ''',
    gd_split: ~S'''
      # An empty delimiter splits into characters, as in Godot.
      defp gd_split(value, delimiter, allow_empty, maxsplit) do
        cond do
          not is_binary(value) -> []
          delimiter == "" -> String.graphemes(value)
          true -> value |> gd_split_parts(delimiter, maxsplit) |> gd_drop_empty(allow_empty)
        end
      end

      defp gd_split_parts(value, delimiter, 0), do: String.split(value, delimiter)

      defp gd_split_parts(value, delimiter, maxsplit),
        do: String.split(value, delimiter, parts: maxsplit + 1)

      defp gd_drop_empty(parts, true), do: parts
      defp gd_drop_empty(parts, _false), do: Enum.reject(parts, &(&1 == ""))
    ''',
    gd_rsplit: ~S'''
      defp gd_rsplit(value, delimiter, allow_empty, maxsplit) do
        if is_binary(value) and maxsplit > 0 do
          value
          |> String.reverse()
          |> String.split(String.reverse(delimiter), parts: maxsplit + 1)
          |> Enum.map(&String.reverse/1)
          |> Enum.reverse()
          |> gd_drop_empty(allow_empty)
        else
          gd_split(value, delimiter, allow_empty, 0)
        end
      end
    ''',
    gd_join: ~S'''
      # `separator.join(parts)`, as in Godot 4.
      defp gd_join(separator, parts),
        do: if(is_list(parts), do: Enum.join(parts, separator), else: "")
    ''',
    gd_left: ~S'''
      # A negative length drops that many from the end.
      defp gd_left(value, length) do
        cond do
          not is_binary(value) -> value
          length < 0 -> String.slice(value, 0, max(String.length(value) + length, 0))
          true -> String.slice(value, 0, length)
        end
      end
    ''',
    gd_right: ~S'''
      defp gd_right(value, length) do
        cond do
          not is_binary(value) -> value
          length < 0 -> String.slice(value, min(-length, String.length(value))..-1//1)
          true -> String.slice(value, max(String.length(value) - length, 0)..-1//1)
        end
      end
    ''',
    gd_lpad: ~S'''
      defp gd_lpad(value, min_length, character),
        do: if(is_binary(value), do: String.pad_leading(value, min_length, character), else: value)
    ''',
    gd_rpad: ~S'''
      defp gd_rpad(value, min_length, character),
        do: if(is_binary(value), do: String.pad_trailing(value, min_length, character), else: value)
    ''',
    gd_lstrip: ~S'''
      defp gd_lstrip(value, chars) do
        if is_binary(value),
          do: String.trim_leading(value, chars),
          else: value
      end
    ''',
    gd_rstrip: ~S'''
      defp gd_rstrip(value, chars) do
        if is_binary(value),
          do: String.trim_trailing(value, chars),
          else: value
      end
    ''',
    gd_strip_edges: ~S'''
      defp gd_strip_edges(value, left, right) do
        cond do
          not is_binary(value) -> value
          left and right -> String.trim(value)
          left -> String.trim_leading(value)
          right -> String.trim_trailing(value)
          true -> value
        end
      end
    ''',
    gd_substr: ~S'''
      # A length of -1 means "to the end".
      defp gd_substr(value, from, length) do
        cond do
          not is_binary(value) -> value
          length < 0 -> String.slice(value, from, String.length(value))
          true -> String.slice(value, from, length)
        end
      end
    ''',
    gd_repeat: ~S'''
      defp gd_repeat(value, count),
        do: if(is_binary(value) and count > 0, do: String.duplicate(value, count), else: "")
    ''',
    gd_replacen: ~S'''
      # Case-insensitive replace.
      defp gd_replacen(value, what, forwhat) do
        if is_binary(value),
          do: String.replace(value, ~r/#{Regex.escape(what)}/i, forwhat),
          else: value
      end
    ''',
    gd_containsn: ~S'''
      defp gd_containsn(value, what) do
        is_binary(value) and String.contains?(String.downcase(value), String.downcase(what))
      end
    ''',
    gd_capitalize: ~S'''
      # Godot's `capitalize` turns any casing into "Title Case Words".
      defp gd_capitalize(value) do
        if is_binary(value) do
          value
          |> gd_words()
          |> Enum.map_join(" ", &String.capitalize/1)
        else
          value
        end
      end

    ''',
    gd_words: ~S'''
      # Splits camelCase, snake_case, kebab-case and spaces into plain words.
      defp gd_words(value) do
        value
        |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1 \\2")
        |> String.split(~r/[\s_\-]+/, trim: true)
      end
    ''',
    gd_to_snake_case: ~S'''
      defp gd_to_snake_case(value),
        do: if(is_binary(value), do: value |> gd_words() |> Enum.map_join("_", &String.downcase/1), else: value)
    ''',
    gd_to_kebab_case: ~S'''
      defp gd_to_kebab_case(value),
        do: if(is_binary(value), do: value |> gd_words() |> Enum.map_join("-", &String.downcase/1), else: value)
    ''',
    gd_to_pascal_case: ~S'''
      defp gd_to_pascal_case(value),
        do: if(is_binary(value), do: value |> gd_words() |> Enum.map_join("", &String.capitalize/1), else: value)
    ''',
    gd_to_camel_case: ~S'''
      defp gd_to_camel_case(value) do
        if is_binary(value) do
          case gd_words(value) do
            [] -> ""
            [first | rest] -> String.downcase(first) <> Enum.map_join(rest, "", &String.capitalize/1)
          end
        else
          value
        end
      end
    ''',
    gd_trim_prefix: ~S'''
      defp gd_trim_prefix(value, prefix),
        do: if(is_binary(value), do: String.replace_prefix(value, prefix, ""), else: value)
    ''',
    gd_trim_suffix: ~S'''
      defp gd_trim_suffix(value, suffix),
        do: if(is_binary(value), do: String.replace_suffix(value, suffix, ""), else: value)
    ''',
    gd_indent: ~S'''
      defp gd_indent(value, prefix) do
        if is_binary(value),
          do: value |> String.split("\n") |> Enum.map_join("\n", &(prefix <> &1)),
          else: value
      end
    ''',
    gd_dedent: ~S'''
      # Removes the common leading whitespace from every line.
      defp gd_dedent(value) do
        if is_binary(value) do
          lines = String.split(value, "\n")

          indent =
            lines
            |> Enum.reject(&(String.trim(&1) == ""))
            |> Enum.map(&(String.length(&1) - String.length(String.trim_leading(&1))))
            |> Enum.min(fn -> 0 end)

          Enum.map_join(lines, "\n", &String.slice(&1, indent, String.length(&1)))
        else
          value
        end
      end
    ''',
    gd_pad_zeros: ~S'''
      defp gd_pad_zeros(value, digits) do
        if is_binary(value) do
          [whole | rest] = String.split(value, ".", parts: 2)
          sign = if String.starts_with?(whole, "-"), do: "-", else: ""
          digits_only = String.trim_leading(whole, "-")
          padded = sign <> String.pad_leading(digits_only, digits, "0")
          Enum.join([padded | rest], ".")
        else
          value
        end
      end
    ''',
    gd_is_valid_int: ~S'''
      defp gd_is_valid_int(value), do: is_binary(value) and match?({_int, ""}, Integer.parse(value))
    ''',
    gd_is_valid_float: ~S'''
      defp gd_is_valid_float(value),
        do: is_binary(value) and match?({_float, ""}, Float.parse(value))
    ''',
    gd_similarity: ~S'''
      defp gd_similarity(value, other) do
        if is_binary(value) and is_binary(other), do: String.jaro_distance(value, other), else: 0.0
      end
    ''',
    gd_md5_text: ~S'''
      defp gd_md5_text(value) do
        if is_binary(value), do: Base.encode16(:crypto.hash(:md5, value), case: :lower), else: ""
      end
    ''',
    gd_sha256_text: ~S'''
      defp gd_sha256_text(value) do
        if is_binary(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower), else: ""
      end
    ''',
    gd_uri_encode: ~S'''
      defp gd_uri_encode(value), do: if(is_binary(value), do: URI.encode(value), else: value)
    ''',
    gd_uri_decode: ~S'''
      defp gd_uri_decode(value), do: if(is_binary(value), do: URI.decode(value), else: value)
    ''',
    gd_min: ~S'''
      # `min`/`max` are variadic in Godot, so they arrive as a list.
      defp gd_min(values), do: Enum.min(values)
    ''',
    gd_max: ~S'''
      defp gd_max(values), do: Enum.max(values)
    ''',
    gd_absf: ~S'''
      defp gd_absf(value), do: abs(value) * 1.0
    ''',
    gd_absi: ~S'''
      defp gd_absi(value), do: value |> abs() |> trunc()
    ''',
    gd_sqrt: ~S'''
      defp gd_sqrt(value), do: :math.sqrt(value)
    ''',
    gd_cbrt: ~S'''
      defp gd_cbrt(value), do: :math.pow(value, 1 / 3)
    ''',
    gd_pow: ~S'''
      defp gd_pow(base, exponent), do: :math.pow(base, exponent)
    ''',
    gd_log: ~S'''
      defp gd_log(value), do: :math.log(value)
    ''',
    gd_exp: ~S'''
      defp gd_exp(value), do: :math.exp(value)
    ''',
    gd_fmod: ~S'''
      defp gd_fmod(a, b), do: :math.fmod(a, b)
    ''',
    gd_fposmod: ~S'''
      # Always non-negative, unlike `fmod`.
      defp gd_fposmod(a, b) do
        result = :math.fmod(a, b)
        if result < 0, do: result + abs(b), else: result
      end
    ''',
    gd_posmod: ~S'''
      defp gd_posmod(a, b) do
        result = rem(a, b)
        if result < 0, do: result + abs(b), else: result
      end
    ''',
    gd_sign: ~S'''
      defp gd_sign(value) do
        cond do
          value > 0 -> if is_integer(value), do: 1, else: 1.0
          value < 0 -> if is_integer(value), do: -1, else: -1.0
          true -> value
        end
      end
    ''',
    gd_signf: ~S'''
      defp gd_signf(value), do: gd_sign(value) * 1.0
    ''',
    gd_signi: ~S'''
      defp gd_signi(value), do: value |> gd_sign() |> trunc()
    ''',
    gd_floorf: ~S'''
      defp gd_floorf(value), do: value |> gd_floor() |> Kernel.*(1.0)
    ''',
    gd_floori: ~S'''
      defp gd_floori(value), do: value |> gd_floor() |> trunc()
    ''',
    gd_ceilf: ~S'''
      defp gd_ceilf(value), do: value |> gd_ceil() |> Kernel.*(1.0)
    ''',
    gd_ceili: ~S'''
      defp gd_ceili(value), do: value |> gd_ceil() |> trunc()
    ''',
    gd_roundf: ~S'''
      defp gd_roundf(value), do: value |> gd_round() |> Kernel.*(1.0)
    ''',
    gd_roundi: ~S'''
      defp gd_roundi(value), do: value |> gd_round() |> trunc()
    ''',
    gd_snapped: ~S'''
      # Rounds to the nearest multiple of `step`; a step of 0 is a no-op, and a
      # vector snaps component-wise.
      defp gd_snapped(value, step) do
        cond do
          gd_vec?(value) and gd_vec?(step) ->
            Map.new(value, fn {k, v} -> {k, gd_snapped(v, Map.get(step, k, 0))} end)

          gd_vec?(value) ->
            Map.new(value, fn {k, v} -> {k, gd_snapped(v, step)} end)

          step == 0 ->
            value

          true ->
            Float.round(value / step) * step
        end
      end
    ''',
    gd_snappedi: ~S'''
      defp gd_snappedi(value, step), do: value |> gd_snapped(step) |> trunc()
    ''',
    gd_nearest_po2: ~S'''
      # The smallest power of two at least as large as `value`; 0 for anything
      # non-positive, as in Godot.
      defp gd_nearest_po2(value) do
        if value <= 0, do: 0, else: gd_next_po2(1, trunc(value))
      end

      defp gd_next_po2(candidate, value) when candidate >= value, do: candidate
      defp gd_next_po2(candidate, value), do: gd_next_po2(candidate * 2, value)
    ''',
    gd_wrapi: ~S'''
      defp gd_wrapi(value, from, to) do
        range = to - from
        if range == 0, do: from, else: from + gd_posmod(value - from, range)
      end
    ''',
    gd_wrapf: ~S'''
      defp gd_wrapf(value, from, to) do
        range = to - from
        if range == 0, do: from, else: from + gd_fposmod(value - from, range)
      end
    ''',
    gd_sin: ~S'''
      defp gd_sin(value), do: :math.sin(value)
    ''',
    gd_cos: ~S'''
      defp gd_cos(value), do: :math.cos(value)
    ''',
    gd_tan: ~S'''
      defp gd_tan(value), do: :math.tan(value)
    ''',
    gd_asin: ~S'''
      defp gd_asin(value), do: :math.asin(value)
    ''',
    gd_acos: ~S'''
      defp gd_acos(value), do: :math.acos(value)
    ''',
    gd_atan: ~S'''
      defp gd_atan(value), do: :math.atan(value)
    ''',
    gd_atan2: ~S'''
      defp gd_atan2(y, x), do: :math.atan2(y, x)
    ''',
    gd_sinh: ~S'''
      defp gd_sinh(value), do: :math.sinh(value)
    ''',
    gd_cosh: ~S'''
      defp gd_cosh(value), do: :math.cosh(value)
    ''',
    gd_tanh: ~S'''
      defp gd_tanh(value), do: :math.tanh(value)
    ''',
    gd_deg_to_rad: ~S'''
      defp gd_deg_to_rad(degrees), do: degrees * :math.pi() / 180.0
    ''',
    gd_rad_to_deg: ~S'''
      defp gd_rad_to_deg(radians), do: radians * 180.0 / :math.pi()
    ''',
    gd_lerp: ~S'''
      # Vectors interpolate component-wise.
      defp gd_lerp(from, to, weight) do
        if gd_vec?(from) and gd_vec?(to),
          do: Map.new(from, fn {k, v} -> {k, gd_lerp(v, Map.get(to, k, 0), weight)} end),
          else: from + (to - from) * weight
      end
    ''',
    gd_lerp_angle: ~S'''
      # Takes the short way round.
      defp gd_lerp_angle(from, to, weight) do
        difference = gd_fposmod(to - from, 2 * :math.pi())
        distance = gd_fposmod(2 * difference, 2 * :math.pi()) - difference
        from + distance * weight
      end
    ''',
    gd_inverse_lerp: ~S'''
      defp gd_inverse_lerp(from, to, value) do
        if to == from, do: 0.0, else: (value - from) / (to - from)
      end
    ''',
    gd_remap: ~S'''
      defp gd_remap(value, in_from, in_to, out_from, out_to) do
        gd_lerp(out_from, out_to, gd_inverse_lerp(in_from, in_to, value))
      end
    ''',
    gd_move_toward: ~S'''
      defp gd_move_toward(from, to, delta) do
        if abs(to - from) <= delta, do: to, else: from + gd_sign(to - from) * delta
      end
    ''',
    gd_ease: ~S'''
      # Godot's easing curve: 1 is linear, >1 eases in, 0<c<1 eases out, and
      # negative values ease in-out.
      defp gd_ease(value, curve) do
        value = gd_clamp(value, 0.0, 1.0)

        cond do
          curve > 0 and curve < 1.0 -> 1.0 - :math.pow(1.0 - value, 1.0 / curve)
          curve > 1.0 -> :math.pow(value, curve)
          curve < 0 and curve > -1.0 -> gd_ease_in_out(value, -curve, true)
          curve < -1.0 -> gd_ease_in_out(value, -curve, false)
          true -> 0.0
        end
      end

      defp gd_ease_in_out(value, curve, inverted) do
        power = if inverted, do: 1.0 / curve, else: curve

        if value < 0.5,
          do: :math.pow(value * 2.0, power) * 0.5,
          else: (1.0 - :math.pow(1.0 - (value - 0.5) * 2.0, power)) * 0.5 + 0.5
      end
    ''',
    gd_pingpong: ~S'''
      defp gd_pingpong(value, length) do
        if length == 0, do: 0.0, else: length - abs(gd_fposmod(value, length * 2) - length)
      end
    ''',
    gd_clamp: ~S'''
      defp gd_clamp(value, low, high) do
        cond do
          value < low -> low
          value > high -> high
          true -> value
        end
      end
    ''',
    gd_clampi: ~S'''
      defp gd_clampi(value, low, high), do: value |> gd_clamp(low, high) |> trunc()
    ''',
    gd_is_equal_approx: ~S'''
      # Godot's tolerance is 1e-5, scaled by magnitude.
      defp gd_is_equal_approx(a, b) do
        tolerance = max(1.0e-5, 1.0e-5 * abs(a))
        abs(a - b) < tolerance
      end
    ''',
    gd_is_zero_approx: ~S'''
      defp gd_is_zero_approx(value), do: abs(value) < 1.0e-5
    ''',
    gd_is_finite: ~S'''
      defp gd_is_finite(value), do: is_number(value) and not gd_is_inf(value) and not gd_is_nan(value)
    ''',
    gd_is_inf: ~S'''
      defp gd_is_inf(value), do: value == :infinity or value == :neg_infinity
    ''',
    gd_is_nan: ~S'''
      defp gd_is_nan(value), do: value != value
    ''',
    gd_is_same: ~S'''
      defp gd_is_same(a, b), do: a === b
    ''',
    gd_hash: ~S'''
      # A stable hash of the value; the number differs from Godot's, which
      # hashes engine representations.
      defp gd_hash(value), do: :erlang.phash2(value)
    ''',
    gd_randi: ~S'''
      defp gd_randi, do: :rand.uniform(4_294_967_296) - 1
    ''',
    gd_randf: ~S'''
      defp gd_randf, do: :rand.uniform()
    ''',
    gd_randi_range: ~S'''
      # Inclusive at both ends, as in Godot.
      defp gd_randi_range(from, to), do: from + :rand.uniform(to - from + 1) - 1
    ''',
    gd_randf_range: ~S'''
      defp gd_randf_range(from, to), do: from + :rand.uniform() * (to - from)
    ''',
    gd_randfn: ~S'''
      defp gd_randfn(mean, deviation), do: mean + :rand.normal() * deviation
    ''',
    gd_randomize: ~S'''
      defp gd_randomize do
        :rand.seed(:exsss)
        nil
      end
    ''',
    gd_seed: ~S'''
      defp gd_seed(value) do
        :rand.seed(:exsss, {value, value, value})
        nil
      end
    ''',
    gd_printraw: ~S'''
      defp gd_printraw(values) do
        IO.write(gd_str_join(values, ""))
        nil
      end
    ''',
    gd_prints: ~S'''
      defp gd_prints(values) do
        IO.puts(gd_str_join(values, " "))
        nil
      end
    ''',
    gd_printt: ~S'''
      defp gd_printt(values) do
        IO.puts(gd_str_join(values, "\t"))
        nil
      end
    ''',
    gd_printerr: ~S'''
      defp gd_printerr(values) do
        require Logger
        Logger.error(gd_str_join(values, ""))
        nil
      end
    ''',
    gd_print_verbose: ~S'''
      defp gd_print_verbose(values) do
        require Logger
        Logger.debug(gd_str_join(values, ""))
        nil
      end
    ''',
    gd_push_error: ~S'''
      defp gd_push_error(values) do
        require Logger
        Logger.error(gd_str_join(values, ""))
        nil
      end
    ''',
    gd_push_warning: ~S'''
      defp gd_push_warning(values) do
        require Logger
        Logger.warning(gd_str_join(values, ""))
        nil
      end
    ''',
    gd_json_stringify: ~S'''
      # OTP's own `json` module, so a compiled script needs no dependency.
      defp gd_json_stringify(value) do
        value |> :json.encode() |> IO.iodata_to_binary()
      rescue
        _error -> nil
      end
    ''',
    gd_json_parse: ~S'''
      # Godot answers null when the text will not parse.
      defp gd_json_parse(text) do
        :json.decode(text)
      rescue
        _error -> nil
      end
    ''',
    gd_unix_time: ~S'''
      defp gd_unix_time, do: System.system_time(:second)
    ''',
    gd_ticks_msec: ~S'''
      defp gd_ticks_msec, do: System.monotonic_time(:millisecond)
    ''',
    gd_ticks_usec: ~S'''
      defp gd_ticks_usec, do: System.monotonic_time(:microsecond)
    ''',
    gd_datetime_dict: ~S'''
      # The same keys Godot uses, so a script reads them the same way.
      defp gd_datetime_dict(unix) do
        at = DateTime.from_unix!(unix)

        %{
          "year" => at.year,
          "month" => at.month,
          "day" => at.day,
          "weekday" => Date.day_of_week(at) |> rem(7),
          "hour" => at.hour,
          "minute" => at.minute,
          "second" => at.second
        }
      end
    ''',
    gd_datetime_string: ~S'''
      defp gd_datetime_string(unix), do: unix |> DateTime.from_unix!() |> DateTime.to_iso8601()
    ''',
    gd_unix_from_string: ~S'''
      defp gd_unix_from_string(text) do
        case DateTime.from_iso8601(text) do
          {:ok, at, _offset} -> DateTime.to_unix(at)
          _error -> 0
        end
      end
    ''',
    gd_vec_map: ~S'''
      # Vector helpers work component-wise, so they serve Vector2, Vector3 and
      # Color without knowing which one they were handed.
      defp gd_vec_map(vector, fun), do: Map.new(vector, fn {k, v} -> {k, fun.(v)} end)
    ''',
    gd_vec_zip: ~S'''
      defp gd_vec_zip(a, b, fun),
        do: Map.new(a, fn {k, v} -> {k, fun.(v, Map.get(b, k, 0))} end)
    ''',
    gd_vec_length_sq: ~S'''
      defp gd_vec_length_sq(vector),
        do: vector |> Map.values() |> Enum.reduce(0.0, fn v, acc -> acc + v * v end)
    ''',
    gd_distance_to: ~S'''
      defp gd_distance_to(a, b), do: a |> gd_vec_zip(b, fn x, y -> x - y end) |> gd_vec_length()
    ''',
    gd_distance_sq_to: ~S'''
      defp gd_distance_sq_to(a, b),
        do: a |> gd_vec_zip(b, fn x, y -> x - y end) |> gd_vec_length_sq()
    ''',
    gd_normalized: ~S'''
      # A zero vector normalises to itself, as in Godot.
      defp gd_normalized(vector) do
        length = gd_vec_length(vector)
        if length == 0.0, do: vector, else: gd_vec_map(vector, &(&1 / length))
      end
    ''',
    gd_is_normalized: ~S'''
      defp gd_is_normalized(vector), do: abs(gd_vec_length_sq(vector) - 1.0) < 1.0e-5
    ''',
    gd_limit_length: ~S'''
      defp gd_limit_length(vector, limit) do
        length = gd_vec_length(vector)
        if length > limit and length > 0.0, do: gd_vec_map(vector, &(&1 / length * limit)), else: vector
      end
    ''',
    gd_dot: ~S'''
      defp gd_dot(a, b),
        do: a |> gd_vec_zip(b, fn x, y -> x * y end) |> Map.values() |> Enum.sum()
    ''',
    gd_cross: ~S'''
      # Vector2's cross product is a scalar; Vector3's is a vector.
      defp gd_cross(a, b) do
        if Map.has_key?(a, :z) do
          %{
            x: a.y * b.z - a.z * b.y,
            y: a.z * b.x - a.x * b.z,
            z: a.x * b.y - a.y * b.x
          }
        else
          a.x * b.y - a.y * b.x
        end
      end
    ''',
    gd_angle: ~S'''
      defp gd_angle(vector), do: :math.atan2(vector.y, vector.x)
    ''',
    gd_angle_to: ~S'''
      defp gd_angle_to(a, b), do: :math.atan2(gd_cross(a, b), gd_dot(a, b))
    ''',
    gd_angle_to_point: ~S'''
      defp gd_angle_to_point(a, b), do: :math.atan2(b.y - a.y, b.x - a.x)
    ''',
    gd_direction_to: ~S'''
      defp gd_direction_to(a, b), do: a |> gd_vec_zip(b, fn x, y -> y - x end) |> gd_normalized()
    ''',
    gd_rotated: ~S'''
      defp gd_rotated(vector, angle) do
        cosine = :math.cos(angle)
        sine = :math.sin(angle)
        %{x: vector.x * cosine - vector.y * sine, y: vector.x * sine + vector.y * cosine}
      end
    ''',
    gd_orthogonal: ~S'''
      defp gd_orthogonal(vector), do: %{x: vector.y, y: -vector.x}
    ''',
    gd_vec_clamp: ~S'''
      defp gd_vec_clamp(vector, low, high) do
        Map.new(vector, fn {k, v} ->
          {k, gd_clamp(v, gd_component(low, k), gd_component(high, k))}
        end)
      end

      # `clamp` takes either two vectors or two numbers.
      defp gd_component(bound, key), do: if(is_map(bound), do: Map.get(bound, key, 0), else: bound)
    ''',
    gd_vec_move_toward: ~S'''
      defp gd_vec_move_toward(from, to, delta) do
        step = gd_vec_zip(to, from, fn t, f -> t - f end)
        length = gd_vec_length(step)

        if length <= delta or length == 0.0,
          do: to,
          else: gd_vec_zip(from, step, fn f, s -> f + s / length * delta end)
      end
    ''',
    gd_vec_abs: ~S'''
      defp gd_vec_abs(vector), do: gd_vec_map(vector, &abs/1)
    ''',
    gd_vec_sign: ~S'''
      defp gd_vec_sign(vector), do: gd_vec_map(vector, &gd_sign/1)
    ''',
    gd_vec_floor: ~S'''
      defp gd_vec_floor(vector), do: gd_vec_map(vector, &gd_floor/1)
    ''',
    gd_vec_ceil: ~S'''
      defp gd_vec_ceil(vector), do: gd_vec_map(vector, &gd_ceil/1)
    ''',
    gd_vec_round: ~S'''
      defp gd_vec_round(vector), do: gd_vec_map(vector, &gd_round/1)
    ''',
    gd_vec_equal_approx: ~S'''
      defp gd_vec_equal_approx(a, b),
        do: a |> gd_vec_zip(b, fn x, y -> abs(x - y) end) |> Map.values() |> Enum.all?(&(&1 < 1.0e-5))
    ''',
    gd_vec_zero_approx: ~S'''
      defp gd_vec_zero_approx(vector),
        do: vector |> Map.values() |> Enum.all?(&(abs(&1) < 1.0e-5))
    ''',
    gd_vec_length: ~S'''
      defp gd_vec_length(vector) do
        vector |> Map.values() |> Enum.reduce(0.0, fn v, acc -> acc + v * v end) |> :math.sqrt()
      end
    ''',
    gd_size: ~S'''
      defp gd_size(value) do
        cond do
          is_binary(value) -> String.length(value)
          gd_vec?(value) -> gd_vec_length(value)
          is_map(value) -> map_size(value)
          is_list(value) -> length(value)
          true -> 0
        end
      end
    ''',
    gd_is_empty: ~S'''
      defp gd_is_empty(value), do: gd_size(value) == 0
    ''',
    gd_keys: ~S'''
      defp gd_keys(map), do: if(is_map(map), do: Map.keys(map), else: [])
    ''',
    gd_values: ~S'''
      defp gd_values(map), do: if(is_map(map), do: Map.values(map), else: [])
    ''',
    gd_front: ~S'''
      defp gd_front(list), do: if(is_list(list), do: List.first(list), else: nil)
    ''',
    gd_back: ~S'''
      defp gd_back(list), do: if(is_list(list), do: List.last(list), else: nil)
    ''',
    gd_to_upper: ~S'''
      defp gd_to_upper(value), do: if(is_binary(value), do: String.upcase(value), else: value)
    ''',
    gd_to_lower: ~S'''
      defp gd_to_lower(value), do: if(is_binary(value), do: String.downcase(value), else: value)
    ''',
    gd_begins_with: ~S'''
      defp gd_begins_with(value, prefix),
        do: is_binary(value) and String.starts_with?(value, prefix)
    ''',
    gd_ends_with: ~S'''
      defp gd_ends_with(value, suffix), do: is_binary(value) and String.ends_with?(value, suffix)
    ''',
    gd_replace: ~S'''
      defp gd_replace(value, from, to) do
        if is_binary(value), do: String.replace(value, from, to), else: value
      end
    ''',
    gd_to_int: ~S'''
      # Godot returns 0 for anything unparseable rather than raising.
      defp gd_to_int(value) do
        cond do
          is_integer(value) -> value
          is_float(value) -> trunc(value)
          is_binary(value) -> value |> Integer.parse() |> gd_parsed(0)
          true -> 0
        end
      end
    ''',
    gd_to_float: ~S'''
      defp gd_to_float(value) do
        cond do
          is_number(value) -> value * 1.0
          is_binary(value) -> value |> Float.parse() |> gd_parsed(0.0)
          true -> 0.0
        end
      end
    ''',
    gd_append: ~S'''
      defp gd_append(list, value), do: if(is_list(list), do: list ++ [value], else: list)
    ''',
    gd_clear: ~S'''
      defp gd_clear(container) do
        cond do
          is_map(container) -> %{}
          is_list(container) -> []
          true -> container
        end
      end
    ''',
    gd_remove_at: ~S'''
      defp gd_remove_at(list, index),
        do: if(is_list(list), do: List.delete_at(list, index), else: list)
    ''',
    gd_sort: ~S'''
      defp gd_sort(list), do: if(is_list(list), do: Enum.sort(list), else: list)
    ''',
    gd_vec: """
      # A value type is a map keyed only by the component names, which is what
      # separates one from an ordinary Dictionary (string keys) at run time.
      defp gd_vec?(value) do
        is_map(value) and map_size(value) > 0 and
          Enum.all?(Map.keys(value), &(&1 in #{inspect(@value_type_keys)}))
      end
    """,
    gd_sub: ~S'''
      defp gd_sub(left, right) do
        if gd_vec?(left) and gd_vec?(right),
          do: Map.merge(left, right, fn _key, a, b -> a - b end),
          else: left - right
      end
    ''',
    gd_mul: ~S'''
      # Vectors scale by a number, in either order.
      defp gd_mul(left, right) do
        cond do
          gd_vec?(left) and is_number(right) -> Map.new(left, fn {k, v} -> {k, v * right} end)
          is_number(left) and gd_vec?(right) -> Map.new(right, fn {k, v} -> {k, left * v} end)
          true -> left * right
        end
      end
    ''',
    gd_while: ~S'''
      # Elixir has no loop, so `while` is tail recursion over the accumulator.
      # The body hands back {:cont, acc} or {:halt, acc}, which is how `break`
      # leaves the loop from any depth.
      defp gd_while(acc, condition, body) do
        if condition.(acc) do
          case body.(acc) do
            {:halt, acc} -> acc
            {:cont, acc} -> gd_while(acc, condition, body)
          end
        else
          acc
        end
      end
    ''',
    gd_range: ~S'''
      # `range(n)` is 0..n-1, `range(a, b)` is a..b-1, and a negative step
      # counts down. Godot returns an Array, so this does too -- a Range would
      # answer `.size()`, `[i]` and `.map()` wrongly rather than loudly. A step
      # of 0 gives an empty Array, again as Godot does.
      defp gd_range(from, to, step) do
        cond do
          step > 0 and from < to -> Enum.to_list(Range.new(from, to - 1, step))
          step < 0 and from > to -> Enum.to_list(Range.new(from, to + 1, step))
          true -> []
        end
      end
    ''',
    gd_index: ~S'''
      # `arr[0]` is Enum.at on a list -- Elixir's Access raises there -- and a
      # plain lookup on a Dictionary, whose keys may be strings or atoms.
      defp gd_index(container, key, default) do
        cond do
          is_list(container) and is_integer(key) ->
            Enum.at(container, key, default)

          is_map(container) ->
            case Map.fetch(container, key) do
              {:ok, value} -> value
              :error -> Map.get(container, to_string(key), default)
            end

          true ->
            default
        end
      end
    ''',
    gd_get: ~S'''
      # Field access works on a struct, an atom-keyed map and a string-keyed
      # Dictionary, because GDScript's `.` reads all three.
      defp gd_get(container, key) do
        if is_map(container) do
          case Map.fetch(container, key) do
            {:ok, value} -> value
            :error -> Map.get(container, Atom.to_string(key))
          end
        else
          nil
        end
      end
    '''
  }

  defp helper_source(name), do: Map.fetch!(@helper_sources, name)

  # Not a helper -- a note from the scan that a context call will need `gd_box`.
  defp marker?(:gd_box_call), do: true
  defp marker?(_name), do: false

  # `gd_truthy` is always emitted when any helper is: the others never appear
  # without a condition or a comparison somewhere in a real script, and an
  # unused private function is a compiler warning, so this scans instead.
  # Helpers call each other, so the requirement set is a closure rather than a
  # list of one-shot checks -- an ordered chain silently missed `gd_parsed`,
  # which only `gd_to_int` pulls in and only `gd_format` pulls *that* in.
  @helper_deps %{
    gd_add: [:gd_vec],
    gd_as: [:gd_is, :gd_str, :gd_to_int, :gd_to_float],
    gd_assert: [:gd_truthy],
    gd_box: [:gd_vec, :gd_ref?, :gd_new],
    gd_format: [:gd_str, :gd_to_int, :gd_to_float],
    gd_deref: [:gd_vec, :gd_ref?, :gd_load],
    gd_is: [:gd_vec],
    gd_is_empty: [:gd_size],
    gd_mod: [:gd_format],
    gd_mul: [:gd_vec],
    gd_print: [:gd_str_join],
    gd_str_all: [:gd_str_join],
    gd_str_join: [:gd_str],
    gd_rebox: [:gd_vec, :gd_ref?, :gd_new],
    gd_sub: [:gd_vec],
    gd_to_float: [:gd_parsed],
    gd_to_int: [:gd_parsed],
    gd_typeof: [:gd_vec],
    gd_size: [:gd_vec, :gd_vec_length],
    gd_distance_to: [:gd_vec_zip, :gd_vec_length],
    gd_distance_sq_to: [:gd_vec_zip, :gd_vec_length_sq],
    gd_normalized: [:gd_vec_map, :gd_vec_length],
    gd_is_normalized: [:gd_vec_length_sq],
    gd_limit_length: [:gd_vec_map, :gd_vec_length],
    gd_dot: [:gd_vec_zip],
    gd_angle_to: [:gd_cross, :gd_dot, :gd_vec_zip],
    gd_direction_to: [:gd_vec_zip, :gd_normalized, :gd_vec_length],
    gd_vec_clamp: [:gd_clamp],
    gd_vec_move_toward: [:gd_vec_zip, :gd_vec_length],
    gd_vec_abs: [:gd_vec_map],
    gd_vec_sign: [:gd_vec_map, :gd_sign],
    gd_vec_floor: [:gd_vec_map, :gd_floor],
    gd_vec_ceil: [:gd_vec_map, :gd_ceil],
    gd_vec_round: [:gd_vec_map, :gd_round],
    gd_vec_equal_approx: [:gd_vec_zip],
    gd_snapped: [:gd_vec],
    gd_snappedi: [:gd_snapped, :gd_vec],
    gd_lerp: [:gd_vec],
    gd_lerp_angle: [:gd_fposmod],
    gd_inverse_lerp: [],
    gd_remap: [:gd_lerp, :gd_inverse_lerp, :gd_vec],
    gd_move_toward: [:gd_sign],
    gd_ease: [:gd_clamp],
    gd_pingpong: [:gd_fposmod],
    gd_posmod: [],
    gd_wrapi: [:gd_posmod],
    gd_wrapf: [:gd_fposmod],
    gd_clampi: [:gd_clamp],
    gd_signf: [:gd_sign],
    gd_signi: [:gd_sign],
    gd_floorf: [:gd_floor],
    gd_floori: [:gd_floor],
    gd_ceilf: [:gd_ceil],
    gd_ceili: [:gd_ceil],
    gd_roundf: [:gd_round],
    gd_roundi: [:gd_round],
    gd_is_finite: [:gd_is_inf, :gd_is_nan],
    gd_printraw: [:gd_str_join],
    gd_prints: [:gd_str_join],
    gd_printt: [:gd_str_join],
    gd_printerr: [:gd_str_join],
    gd_print_verbose: [:gd_str_join],
    gd_push_error: [:gd_str_join],
    gd_push_warning: [:gd_str_join],
    gd_slice: [:gd_size],
    gd_set: [:gd_put],
    gd_merged: [:gd_merge],
    gd_rsplit: [:gd_split],
    gd_capitalize: [:gd_words],
    gd_to_snake_case: [:gd_words],
    gd_to_kebab_case: [:gd_words],
    gd_to_pascal_case: [:gd_words],
    gd_to_camel_case: [:gd_words]
  }

  # The reference helpers are emitted by the expression generator rather than by
  # any node -- `gd_load` appears wherever a read *might* be a reference, and
  # `gd_box` only on the wrappers that actually cross the boundary -- so the AST
  # scan cannot see them. The emitted code can be asked directly, which is exact
  # and cannot drift the way a second copy of the emission rules would. Three
  # separate bugs in this file were that drift.
  @ref_helpers [:gd_new, :gd_load, :gd_ref?, :gd_deref, :gd_box, :gd_rebox, :gd_store]

  # The builtin table and the helper sources it points at, so a test can check
  # that a declared arity still matches the helper it names. Not part of the
  # API; nothing outside the test suite should read these.
  @doc false
  def __tables__, do: %{builtins: @builtins, variadic: @variadic, helpers: @helper_sources}

  defp required_helpers(statements, ref_mode?, emitted) do
    required = statements |> collect_helpers() |> Enum.uniq()

    # These only exist in reference mode; outside it there are no references to
    # box, rebox, snapshot or store, and an emitted-but-unused helper warns.
    required =
      if ref_mode? do
        Enum.filter(@ref_helpers, &calls?(emitted, &1)) ++ required
      else
        required -- ([:gd_spawn, :gd_put, :gd_store, :gd_box, :gd_rebox] ++ @ref_helpers)
      end

    required
    |> Enum.reject(&marker?/1)
    |> close_over_deps()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp calls?(code, helper), do: String.contains?(code, "#{helper}(")

  defp close_over_deps(required) do
    extra = Enum.flat_map(required, &Map.get(@helper_deps, &1, []))
    added = extra -- required

    if added == [], do: required, else: close_over_deps(required ++ added)
  end

  defp collect_helpers(node) when is_list(node), do: Enum.flat_map(node, &collect_helpers/1)

  # Emitted by the class constructor and dispatcher rather than by any AST node.
  defp collect_helpers({:gd_index_marker, _}), do: [:gd_index]
  defp collect_helpers({:gd_store_marker, _}), do: [:gd_store, :gd_put]

  defp collect_helpers({:func, _, params, body, _}) do
    Enum.flat_map(params, fn {_name, default} -> collect_helpers(default) end) ++
      collect_helpers(body)
  end

  defp collect_helpers({:if, clauses, else_body, _}) do
    [:gd_truthy] ++
      Enum.flat_map(clauses, fn {condition, body} ->
        collect_helpers(condition) ++ collect_helpers(body)
      end) ++ collect_helpers(List.wrap(else_body))
  end

  defp collect_helpers({:for, _var, collection, body, _}),
    do: collect_helpers(collection) ++ collect_helpers(body)

  defp collect_helpers({:while, condition, body, _}),
    do: [:gd_truthy, :gd_while] ++ collect_helpers(condition) ++ collect_helpers(body)

  defp collect_helpers({:call, {:ident, "range", _}, args, _}),
    do: [:gd_range | collect_helpers(args)]

  defp collect_helpers({:call, {:ident, "spawn", _}, args, _}),
    do: [:gd_spawn | collect_helpers(args)]

  defp collect_helpers({:call, {:member, {:ident, class, _}, function, _}, args, _})
       when is_map_key(@static_classes, class) do
    case @static_classes |> Map.fetch!(class) |> Map.fetch(function) do
      {:ok, {helper, _required, _defaults}} -> [helper | collect_helpers(args)]
      :error -> collect_helpers(args)
    end
  end

  defp collect_helpers({:call, {:ident, name, _}, args, _}) when is_map_key(@variadic, name),
    do: [String.to_atom(Map.fetch!(@variadic, name)) | collect_helpers(args)]

  defp collect_helpers({:call, {:ident, name, _}, args, _}) when is_map_key(@builtins, name) do
    case Map.fetch!(@builtins, name) do
      {"gd_" <> _ = helper, _arity} -> [String.to_atom(helper) | collect_helpers(args)]
      {_kernel, _arity} -> collect_helpers(args)
    end
  end

  # `a.b()` is a call, not a field read, so it needs no `gd_get` -- and an
  # emitted-but-unused helper is a compiler warning.
  defp collect_helpers({:call, {:member, {:ident, name, _} = object, "callv", _}, args, _})
       when name != "" do
    if context_name?(name),
      do: [:gd_callv, :gd_box_call | collect_helpers(args)],
      else: collect_helpers([object | args])
  end

  defp collect_helpers({:call, {:member, {:ident, name, _} = object, field, _}, args, _}) do
    cond do
      # `Foo.new(...)` is a class constructor, which builds its instance
      # directly rather than boxing a value from gamend. No context exposes a
      # `new`, so the name is enough to tell them apart.
      context_name?(name) and field == @new and API.arities(name, @new) == nil ->
        collect_helpers([object | args])

      context_name?(name) ->
        [:gd_box_call | collect_helpers([object | args])]

      true ->
        method_helpers(field) ++ collect_helpers([object | args])
    end
  end

  defp collect_helpers({:call, {:member, object, field, _}, args, _}),
    do: method_helpers(field) ++ collect_helpers([object | args])

  defp collect_helpers({:var, _, expr, _}), do: collect_helpers(expr)

  defp collect_helpers({:assign, target, op, expr, _}) do
    # The target contributes too: `d[k] += 1` reads the element before storing
    # it, and a nested path resolves through `gd_index` on the way down.
    from_target =
      case target do
        {:index, object, key, _} ->
          read = if op == "=", do: [], else: [:gd_index]
          [:gd_put, :gd_store | read] ++ collect_helpers([object, key])

        _ ->
          []
      end

    # `x += y` builds a `+` that no AST node holds, so its rebox has to be
    # counted here, on the same question the peephole asks at the target.
    rebox =
      if op == "+=" and (assign_target_ref?(target) or ref_possible?(expr)),
        do: [:gd_rebox],
        else: []

    from_target ++ rebox ++ assign_helpers(op) ++ collect_helpers(expr)
  end

  defp collect_helpers({:return, expr, _}), do: collect_helpers(expr)
  defp collect_helpers({:expr, expr, _}), do: collect_helpers(expr)
  defp collect_helpers({:member, object, _, _}), do: [:gd_get | collect_helpers(object)]

  defp collect_helpers({:index, object, index, _}),
    do: [:gd_index | collect_helpers([object, index])]

  defp collect_helpers({:call, callee, args, _}), do: collect_helpers([callee | args])
  defp collect_helpers({:array, elements, _}), do: collect_helpers(elements)

  defp collect_helpers({:dict, pairs, _}),
    do: Enum.flat_map(pairs, fn {key, value} -> collect_helpers([key, value]) end)

  defp collect_helpers({:match, subject, cases, _}) do
    collect_helpers(subject) ++
      Enum.flat_map(cases, fn {_patterns, body} -> collect_helpers(body) end)
  end

  defp collect_helpers({:lambda, _params, body, _}), do: collect_helpers(body)
  # `await` boxes what the task hands back, so it needs `gd_box` too.
  defp collect_helpers({:await, expr, _}), do: [:gd_box_call | collect_helpers(expr)]

  defp collect_helpers({:ternary, condition, then_expr, else_expr, _}),
    do: [:gd_truthy | collect_helpers([condition, then_expr, else_expr])]

  defp collect_helpers({:unop, :not, operand, _}), do: [:gd_truthy | collect_helpers(operand)]
  defp collect_helpers({:unop, _, operand, _}), do: collect_helpers(operand)

  defp collect_helpers({:binop, op, left, right, _}) do
    # `+` only reboxes where an operand could actually be a reference, which is
    # the same question the peephole asks -- so the scan has to ask it too, or
    # `gd_rebox` comes out unused.
    rebox =
      if op == :+ and (ref_possible?(left) or ref_possible?(right)), do: [:gd_rebox], else: []

    rebox ++ binop_helpers(op) ++ collect_helpers([left, right])
  end

  defp collect_helpers(_), do: []

  defp method_helpers(method) do
    case Map.fetch(@methods, method) do
      {:ok, {helper, _required, _defaults, kind, collection?}} ->
        # The mutation wrappers are emitted by codegen, not by any AST node.
        [helper] ++
          if(collection?, do: [:gd_rebox], else: []) ++
          case kind do
            :mutate -> [:gd_mutate]
            :take -> [:gd_take]
            :value -> []
          end

      :error ->
        []
    end
  end

  # The target of a compound assignment is read before it is written, so the
  # same ref-possibility question applies to it.
  defp assign_target_ref?({:index, _object, _key, _line}), do: true
  defp assign_target_ref?(target), do: ref_possible?(target)

  defp binop_helpers(:is), do: [:gd_is]
  defp binop_helpers(:as), do: [:gd_as]
  defp binop_helpers(:+), do: [:gd_add]
  defp binop_helpers(:-), do: [:gd_sub]
  defp binop_helpers(:*), do: [:gd_mul]
  defp binop_helpers(:/), do: [:gd_div]
  defp binop_helpers(:%), do: [:gd_mod]
  defp binop_helpers(op) when op in [:and, :or], do: [:gd_truthy]
  defp binop_helpers(_), do: []

  defp assign_helpers("+="), do: [:gd_add]
  defp assign_helpers("-="), do: [:gd_sub]
  defp assign_helpers("*="), do: [:gd_mul]
  defp assign_helpers("/="), do: [:gd_div]
  defp assign_helpers("%="), do: [:gd_mod]
  defp assign_helpers(_), do: []

  # ── Text ─────────────────────────────────────────────────────────────────

  defp indent(lines, spaces) when is_list(lines),
    do: lines |> Enum.join("\n") |> indent(spaces)

  defp indent(text, spaces) do
    pad = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> pad <> line
    end)
  end

  # Formatting the output is not cosmetic: `Code.format_string!/1` parses it, so
  # a codegen bug that emits invalid Elixir fails here rather than at `mix
  # compile` inside somebody's plugin.
  defp format(source) do
    source
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end
end
