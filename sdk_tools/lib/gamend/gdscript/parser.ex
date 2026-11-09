defmodule Gamend.GDScript.Parser do
  @moduledoc """
  Token stream into an AST. Recursive descent, precedence climbing for
  expressions.

  Statement nodes:

      {:func, name, params, body, line}
      {:var, name, expr, line}          # var x = expr  (declares)
      {:assign, target, op, expr, line} # x = expr / x += expr
      {:if, [{cond, body}, ...], else_body, line}
      {:match, subject, [{patterns, body}, ...], line}
      {:for, var, collection, body, line}
      {:while, condition, body, line}
      {:break, line}
      {:continue, line}
      {:return, expr | nil, line}
      {:expr, expr, line}
      {:pass, line}

  Expression nodes:

      {:int | :float | :string | :bool, value, line}
      {:null, line}
      {:ident, name, line}
      {:binop, op, lhs, rhs, line}
      {:unop, op, operand, line}
      {:call, callee, args, line}
      {:ternary, condition, then_expr, else_expr, line}
      {:enum, name | nil, [{member, value}], line}
      {:signal, name, line}
      {:class, name, parent | nil, body, line}
      {:class_name, name, line}
      {:lambda, params, body, line}
      {:await, expr, line}
      {:member, object, field, line}
      {:index, object, index, line}
      {:array, elements, line}
      {:dict, [{key, value}], line}

  `if` keeps its `elif` chain as a flat clause list rather than nesting, so
  codegen can compute one assigned-variable set across every branch.
  """

  alias Gamend.GDScript.CompileError
  require Gamend.GDScript.Word, as: Word

  @match "match"
  @break Word.break()
  @continue Word.continue()
  @class "class"
  @static "static"

  @doc "Parse tokens into a list of top-level statements."
  @spec parse([tuple()], String.t()) :: [tuple()]
  def parse(tokens, file \\ Word.nofile()) do
    {statements, rest} = parse_statements(tokens, %{file: file, top_level?: true})

    case rest do
      [{:eof, _, _}] -> statements
      [token | _] -> unexpected(token, %{file: file}, "expected a top-level declaration")
    end
  end

  # ── Statements ───────────────────────────────────────────────────────────

  defp parse_statements(tokens, state, acc \\ [])

  defp parse_statements([{:newline, _, _} | rest], state, acc),
    do: parse_statements(rest, state, acc)

  defp parse_statements([{type, _, _} | _] = tokens, _state, acc) when type in [:eof, :dedent],
    do: {Enum.reverse(acc), tokens}

  defp parse_statements(tokens, state, acc) do
    {statement, rest} = parse_statement(tokens, state)
    parse_statements(rest, state, [statement | acc])
  end

  # `static func` is an ordinary function server-side: there is no instance for
  # it to be static against.
  defp parse_statement([{:keyword, @static, _}, {:keyword, "func", _} | _] = tokens, state),
    do: parse_statement(tl(tokens), state)

  # `class_name X` names the script's own class in Godot. Here the module is
  # the class and its name comes from the file, so this is accepted and dropped.
  defp parse_statement([{:keyword, "class_name", line} | rest], state) do
    {name, rest} = expect_ident(rest, state)
    {{:class_name, name, line}, expect_newline(rest, state)}
  end

  defp parse_statement([{:keyword, @class, line} | rest], state) do
    {name, rest} = expect_ident(rest, state)

    {parent, rest} =
      case rest do
        [{:keyword, "extends", _} | after_extends] ->
          {parent, after_parent} = expect_ident(after_extends, state)
          {parent, after_parent}

        _ ->
          {nil, rest}
      end

    {body, rest} =
      rest
      |> expect_op(":", state)
      |> expect_newline(state)
      |> expect(:indent, state)
      |> parse_statements(%{state | top_level?: false})

    {{:class, name, parent, body, line}, expect(rest, :dedent, state)}
  end

  defp parse_statement([{:keyword, "enum", line} | rest], state) do
    {name, rest} =
      case rest do
        [{:ident, name, _} | after_name] -> {name, after_name}
        _ -> {nil, rest}
      end

    rest = expect_op(rest, "{", state)
    {members, rest} = parse_enum_members(rest, state, [], 0)
    {{:enum, name, members, line}, expect_newline(rest, state)}
  end

  defp parse_statement([{:keyword, "signal", line} | rest], state) do
    {name, rest} = expect_ident(rest, state)

    rest =
      case rest do
        [{:op, "(", _} | after_paren] ->
          {_params, after_params} = parse_params(after_paren, state, [])
          after_params

        _ ->
          rest
      end

    {{:signal, name, line}, expect_newline(rest, state)}
  end

  defp parse_statement([{:keyword, "func", line} | rest], state) do
    {name, rest} = expect_ident(rest, state)
    rest = expect_op(rest, "(", state)
    {params, rest} = parse_params(rest, state, [])
    # An optional `-> Type` return annotation is parsed and discarded; keeping
    # it in the grammar now means adding checks later is not a grammar change.
    rest = skip_return_type(rest, state)
    {body, rest} = parse_block(rest, state)
    {{:func, name, params, body, line}, rest}
  end

  defp parse_statement([{:keyword, decl, line} | rest], state) when decl in ["var", "const"] do
    # A top-level `var` is per-instance state in Godot, and the server has no
    # instance for it to belong to. `const` folds into the code that uses it.
    if state.top_level? and decl == "var" do
      raise CompileError,
        file: state.file,
        line: line,
        message: "a top-level `var` has no meaning server-side -- use `const`, or a `func`"
    end

    {name, rest} = expect_ident(rest, state)
    rest = skip_type_hint(rest, state)

    case rest do
      [{:op, op, _} | after_op] when op in ["=", ":="] ->
        {expr, rest} = parse_expression(after_op, state)
        {{declaration(state), name, expr, line}, expect_newline(rest, state)}

      _ ->
        # `var x` with no initializer is `nil`, as in GDScript.
        {{declaration(state), name, {:null, line}, line}, expect_newline(rest, state)}
    end
  end

  defp parse_statement([{:keyword, "if", line} | rest], state) do
    {clauses, else_body, rest} = parse_if_chain(rest, state, [])
    {{:if, clauses, else_body, line}, rest}
  end

  defp parse_statement([{:keyword, @match, line} | rest], state) do
    {subject, rest} = parse_expression(rest, state)

    rest =
      rest
      |> expect_op(":", state)
      |> expect_newline(state)
      |> expect(:indent, state)

    {cases, rest} = parse_match_cases(rest, state, [])
    {{:match, subject, cases, line}, expect(rest, :dedent, state)}
  end

  defp parse_statement([{:keyword, "for", line} | rest], state) do
    {var, rest} = expect_ident(rest, state)
    rest = skip_type_hint(rest, state)
    rest = expect_keyword(rest, "in", state)
    {collection, rest} = parse_expression(rest, state)
    {body, rest} = parse_block(rest, state)
    {{:for, var, collection, body, line}, rest}
  end

  defp parse_statement([{:keyword, "while", line} | rest], state) do
    {condition, rest} = parse_expression(rest, state)
    {body, rest} = parse_block(rest, state)
    {{:while, condition, body, line}, rest}
  end

  defp parse_statement([{:keyword, @break, line} | rest], state),
    do: {{:break, line}, expect_newline(rest, state)}

  defp parse_statement([{:keyword, @continue, line} | rest], state),
    do: {{:continue, line}, expect_newline(rest, state)}

  defp parse_statement([{:keyword, "return", line} | rest], state) do
    case rest do
      [{:newline, _, _} | after_newline] ->
        {{:return, nil, line}, after_newline}

      _ ->
        {expr, rest} = parse_expression(rest, state)
        {{:return, expr, line}, expect_newline(rest, state)}
    end
  end

  defp parse_statement([{:keyword, "pass", line} | rest], state) do
    {{:pass, line}, expect_newline(rest, state)}
  end

  defp parse_statement([{:keyword, word, line} | _], state) do
    raise CompileError,
      file: state.file,
      line: line,
      message: "`#{word}` is not supported server-side"
  end

  defp parse_statement(tokens, state) do
    {expr, rest} = parse_expression(tokens, state)

    case rest do
      [{:op, op, line} | after_op] when op in ["=", "+=", "-=", "*=", "/=", "%="] ->
        {value, rest} = parse_expression(after_op, state)
        assert_assignable(expr, state, line)
        {{:assign, expr, op, value, line}, expect_newline(rest, state)}

      _ ->
        {{:expr, expr, line_of(expr)}, expect_newline(rest, state)}
    end
  end

  # A bare name, or an element through `[]`. Element assignment is a mutation
  # through a reference, which the per-hook heap in the codegen supports.
  defp assert_assignable({:ident, _, _}, _state, _line), do: :ok
  defp assert_assignable({:index, _, _, _}, _state, _line), do: :ok

  defp assert_assignable(_other, state, line) do
    raise CompileError,
      file: state.file,
      line: line,
      message:
        "only a variable or an element (`d[key] = value`) can be assigned; " <>
          "assign to `d[\"field\"]` rather than `d.field`"
  end

  defp parse_match_cases([{:newline, _, _} | rest], state, acc),
    do: parse_match_cases(rest, state, acc)

  defp parse_match_cases([{type, _, _} | _] = tokens, _state, acc) when type in [:dedent, :eof],
    do: {Enum.reverse(acc), tokens}

  defp parse_match_cases(tokens, state, acc) do
    {patterns, rest} = parse_match_patterns(tokens, state, [])
    {body, rest} = parse_block(rest, state)
    parse_match_cases(rest, state, [{patterns, body} | acc])
  end

  defp parse_match_patterns(tokens, state, acc) do
    {pattern, rest} = parse_match_pattern(tokens, state)
    acc = [pattern | acc]

    case rest do
      [{:op, ",", _} | after_comma] -> parse_match_patterns(after_comma, state, acc)
      _ -> {Enum.reverse(acc), rest}
    end
  end

  # Literals, `var name` and `_`. GDScript also destructures arrays and
  # dictionaries in a pattern; that is refused rather than half-supported.
  defp parse_match_pattern([{:ident, "_", line} | rest], _state), do: {{:wildcard, line}, rest}

  defp parse_match_pattern([{:keyword, "var", line} | rest], state) do
    {name, rest} = expect_ident(rest, state)
    {{:bind, name, line}, rest}
  end

  defp parse_match_pattern([{type, value, line} | rest], _state)
       when type in [:int, :float, :string],
       do: {{:literal, {type, value, line}, line}, rest}

  defp parse_match_pattern([{:op, "-", line}, {type, value, _} | rest], _state)
       when type in [:int, :float],
       do: {{:literal, {type, -value, line}, line}, rest}

  defp parse_match_pattern([{:keyword, word, line} | rest], _state)
       when word in ["true", "false"],
       do: {{:literal, {:bool, word == "true", line}, line}, rest}

  defp parse_match_pattern([{:keyword, "null", line} | rest], _state),
    do: {{:literal, {:null, line}, line}, rest}

  # `Tier.GOLD` or a bare `MAX`: a constant reference. It is still a `{:member,
  # ...}` here -- constant folding runs after parsing -- and codegen refuses it
  # if it did not fold to a literal.
  defp parse_match_pattern(
         [{:ident, name, line}, {:op, ".", _}, {:ident, member, _} | rest],
         _state
       ),
       do: {{:literal, {:member, {:ident, name, line}, member, line}, line}, rest}

  defp parse_match_pattern([{:ident, name, line} | rest], _state) when name != "_",
    do: {{:literal, {:ident, name, line}, line}, rest}

  defp parse_match_pattern([{:op, "[", line} | rest], state) do
    {elements, open?, rest} = parse_pattern_list(rest, state, "]", [])
    {{:array_pattern, elements, open?, line}, rest}
  end

  defp parse_match_pattern([{:op, "{", line} | rest], state) do
    {pairs, open?, rest} = parse_dict_pattern(rest, state, [])
    {{:dict_pattern, pairs, open?, line}, rest}
  end

  defp parse_match_pattern([token | _], state),
    do:
      unexpected(
        token,
        state,
        "expected a literal, `var name`, `_`, `[...]` or `{...}` in a match pattern"
      )

  # `enum {A, B}` numbers from 0; `enum {A = 5, B}` continues from the last
  # explicit value, as in Godot.
  defp parse_enum_members([{:op, "}", _} | rest], _state, acc, _next),
    do: {Enum.reverse(acc), rest}

  defp parse_enum_members(tokens, state, acc, next) do
    {name, rest} = expect_ident(tokens, state)

    {value, rest} =
      case rest do
        [{:op, "=", _}, {:int, value, _} | after_value] -> {value, after_value}
        _ -> {next, rest}
      end

    acc = [{name, value} | acc]

    case rest do
      [{:op, ",", _} | after_comma] -> parse_enum_members(after_comma, state, acc, value + 1)
      [{:op, "}", _} | after_brace] -> {Enum.reverse(acc), after_brace}
      [token | _] -> unexpected(token, state, "expected `,` or `}` in enum")
    end
  end

  defp declaration(%{top_level?: true}), do: :const
  defp declaration(_state), do: :var

  # A trailing `..` matches any extra elements or keys, as in Godot; without it
  # the pattern has to account for the whole collection.
  defp parse_pattern_list([{:op, close, _} | rest], _state, close, acc),
    do: {Enum.reverse(acc), false, rest}

  defp parse_pattern_list([{:op, ".", _}, {:op, ".", _} | rest], state, close, acc),
    do: {Enum.reverse(acc), true, expect_op(rest, close, state)}

  defp parse_pattern_list(tokens, state, close, acc) do
    {pattern, rest} = parse_match_pattern(tokens, state)
    acc = [pattern | acc]

    case rest do
      [{:op, ",", _} | after_comma] -> parse_pattern_list(after_comma, state, close, acc)
      [{:op, ^close, _} | after_close] -> {Enum.reverse(acc), false, after_close}
      [token | _] -> unexpected(token, state, "expected `,` or `#{close}`")
    end
  end

  defp parse_dict_pattern([{:op, "}", _} | rest], _state, acc),
    do: {Enum.reverse(acc), false, rest}

  defp parse_dict_pattern([{:op, ".", _}, {:op, ".", _} | rest], state, acc),
    do: {Enum.reverse(acc), true, expect_op(rest, "}", state)}

  defp parse_dict_pattern(tokens, state, acc) do
    {key, rest} = parse_match_pattern(tokens, state)

    {value, rest} =
      case rest do
        [{:op, ":", _} | after_colon] -> parse_match_pattern(after_colon, state)
        _ -> {{:wildcard, 0}, rest}
      end

    acc = [{key, value} | acc]

    case rest do
      [{:op, ",", _} | after_comma] -> parse_dict_pattern(after_comma, state, acc)
      [{:op, "}", _} | after_brace] -> {Enum.reverse(acc), false, after_brace}
      [token | _] -> unexpected(token, state, "expected `,` or `}` in a dictionary pattern")
    end
  end

  defp parse_if_chain(tokens, state, acc) do
    {condition, rest} = parse_expression(tokens, state)
    {body, rest} = parse_block(rest, state)
    acc = [{condition, body} | acc]

    case rest do
      [{:keyword, "elif", _} | after_elif] ->
        parse_if_chain(after_elif, state, acc)

      [{:keyword, "else", _} | after_else] ->
        {else_body, rest} = parse_block(after_else, state)
        {Enum.reverse(acc), else_body, rest}

      _ ->
        {Enum.reverse(acc), nil, rest}
    end
  end

  # A block is `:` NEWLINE INDENT statements DEDENT, or the single-line form
  # `if ready: return true` that GDScript also allows.
  defp parse_block(tokens, state) do
    case expect_op(tokens, ":", state) do
      [{:newline, _, _} | _] = rest ->
        rest
        |> expect_newline(state)
        |> expect(:indent, state)
        |> parse_statements(%{state | top_level?: false})
        |> then(fn {statements, rest} -> {statements, expect(rest, :dedent, state)} end)

      rest ->
        {statement, rest} = parse_statement(rest, %{state | top_level?: false})
        {[statement], rest}
    end
  end

  # A lambda body, which differs from a block in one way: a lambda is an
  # *expression*, so the statement containing it still needs its terminator.
  # The single-line form leaves it alone; the indented form has to put one back,
  # because the dedent swallowed it.
  defp parse_lambda_body(tokens, state) do
    case expect_op(tokens, ":", state) do
      [{:newline, _, _} | _] = rest ->
        {statements, rest} =
          rest
          |> expect_newline(state)
          |> expect(:indent, state)
          |> parse_statements(%{state | top_level?: false})

        {statements, [{:newline, nil, 0} | expect(rest, :dedent, state)]}

      rest ->
        {statement, rest} = parse_lambda_statement(rest, state)
        {[statement], rest}
    end
  end

  defp parse_lambda_statement([{:keyword, "return", line} | rest], state) do
    {expr, rest} = parse_expression(rest, state)
    {{:return, expr, line}, rest}
  end

  # Inside brackets the lexer emits no line structure at all -- everything
  # between `(` and `)` is one logical line -- so a lambda there has to be the
  # single-expression form. Saying that beats "expected an expression, got
  # `var`".
  defp parse_lambda_statement([{:keyword, word, line} | _], state)
       when word in ["var", "const", "if", "for", "while", @match, "pass", @break, @continue] do
    raise CompileError,
      file: state.file,
      line: line,
      message:
        "a multi-line lambda cannot be written inside brackets -- " <>
          "assign it to a variable first, then pass the variable"
  end

  defp parse_lambda_statement(tokens, state) do
    {expr, rest} = parse_expression(tokens, state)
    {{:return, expr, line_of(expr)}, rest}
  end

  defp parse_params([{:op, ")", _} | rest], _state, acc), do: {Enum.reverse(acc), rest}

  defp parse_params(tokens, state, acc) do
    {name, rest} = expect_ident(tokens, state)
    rest = skip_type_hint(rest, state)

    {default, rest} =
      case rest do
        [{:op, "=", _} | after_eq] ->
          {expr, rest} = parse_expression(after_eq, state)
          {expr, rest}

        _ ->
          {nil, rest}
      end

    acc = [{name, default} | acc]

    case rest do
      [{:op, ",", _} | after_comma] -> parse_params(after_comma, state, acc)
      [{:op, ")", _} | after_paren] -> {Enum.reverse(acc), after_paren}
      [token | _] -> unexpected(token, state, "expected `,` or `)` in parameter list")
    end
  end

  # `: int` on a var or param. Parsed and dropped -- see the func note above.
  defp skip_type_hint([{:op, ":", _}, {:ident, _, _} | rest], _state), do: skip_type_args(rest)
  defp skip_type_hint(tokens, _state), do: tokens

  defp skip_return_type([{:op, "->", _}, {:ident, _, _} | rest], _state), do: skip_type_args(rest)
  defp skip_return_type(tokens, _state), do: tokens

  # `Array[int]`, `Dictionary[String, int]` -- parsed and dropped with the rest
  # of the annotation.
  defp skip_type_args([{:op, "[", _} | rest]), do: drop_until_close(rest, 1)
  defp skip_type_args(tokens), do: tokens

  defp drop_until_close([{:op, "[", _} | rest], depth), do: drop_until_close(rest, depth + 1)
  defp drop_until_close([{:op, "]", _} | rest], 1), do: rest
  defp drop_until_close([{:op, "]", _} | rest], depth), do: drop_until_close(rest, depth - 1)
  defp drop_until_close([_token | rest], depth), do: drop_until_close(rest, depth)
  defp drop_until_close([], _depth), do: []

  # ── Expressions ──────────────────────────────────────────────────────────

  # Lowest precedence first; each level parses the level above it.
  @levels [
    [{"is", :is}, {"as", :as}],
    [{"or", :or}, {"||", :or}],
    [{"and", :and}, {"&&", :and}],
    [{"==", :==}, {"!=", :!=}, {"<", :<}, {">", :>}, {"<=", :<=}, {">=", :>=}],
    [{"+", :+}, {"-", :-}],
    [{"*", :*}, {"/", :/}, {"%", :%}]
  ]

  # `value if condition else other` sits below every binary operator.
  defp parse_expression(tokens, state) do
    {expr, rest} = parse_binary(tokens, state, 0)

    case rest do
      [{:keyword, "if", line} | after_if] ->
        {condition, rest} = parse_binary(after_if, state, 0)
        rest = expect_keyword(rest, "else", state)
        {otherwise, rest} = parse_expression(rest, state)
        {{:ternary, condition, expr, otherwise, line}, rest}

      _ ->
        {expr, rest}
    end
  end

  defp parse_binary(tokens, state, level) when level >= length(@levels) do
    parse_unary(tokens, state)
  end

  defp parse_binary(tokens, state, level) do
    {left, rest} = parse_binary(tokens, state, level + 1)
    parse_binary_rest(left, rest, state, level)
  end

  defp parse_binary_rest(left, tokens, state, level) do
    operators = Enum.at(@levels, level)

    case tokens do
      [{type, text, line} | rest] when type in [:op, :keyword] ->
        case List.keyfind(operators, text, 0) do
          {_, op} ->
            {right, rest} = parse_binary(rest, state, level + 1)
            parse_binary_rest({:binop, op, left, right, line}, rest, state, level)

          nil ->
            {left, tokens}
        end

      _ ->
        {left, tokens}
    end
  end

  defp parse_unary([{:keyword, "await", line} | rest], state) do
    {operand, rest} = parse_unary(rest, state)
    {{:await, operand, line}, rest}
  end

  defp parse_unary([{:keyword, "not", line} | rest], state) do
    {operand, rest} = parse_unary(rest, state)
    {{:unop, :not, operand, line}, rest}
  end

  defp parse_unary([{:op, "!", line} | rest], state) do
    {operand, rest} = parse_unary(rest, state)
    {{:unop, :not, operand, line}, rest}
  end

  defp parse_unary([{:op, "-", line} | rest], state) do
    {operand, rest} = parse_unary(rest, state)
    {{:unop, :-, operand, line}, rest}
  end

  defp parse_unary(tokens, state) do
    {primary, rest} = parse_primary(tokens, state)
    parse_postfix(primary, rest, state)
  end

  # Calls, member access and indexing chain left-to-right: `a.b(c)[d]`.
  defp parse_postfix(expr, [{:op, ".", line} | rest], state) do
    {field, rest} = expect_ident(rest, state)
    parse_postfix({:member, expr, field, line}, rest, state)
  end

  defp parse_postfix(expr, [{:op, "(", line} | rest], state) do
    {args, rest} = parse_args(rest, state, [])
    parse_postfix({:call, expr, args, line}, rest, state)
  end

  defp parse_postfix(expr, [{:op, "[", line} | rest], state) do
    {index, rest} = parse_expression(rest, state)
    parse_postfix({:index, expr, index, line}, expect_op(rest, "]", state), state)
  end

  defp parse_postfix(expr, tokens, _state), do: {expr, tokens}

  defp parse_primary([{:int, value, line} | rest], _state), do: {{:int, value, line}, rest}
  defp parse_primary([{:float, value, line} | rest], _state), do: {{:float, value, line}, rest}
  defp parse_primary([{:string, value, line} | rest], _state), do: {{:string, value, line}, rest}
  defp parse_primary([{:ident, name, line} | rest], _state), do: {{:ident, name, line}, rest}

  defp parse_primary([{:keyword, "true", line} | rest], _state), do: {{:bool, true, line}, rest}
  defp parse_primary([{:keyword, "false", line} | rest], _state), do: {{:bool, false, line}, rest}
  defp parse_primary([{:keyword, "null", line} | rest], _state), do: {{:null, line}, rest}

  defp parse_primary([{:keyword, "func", line} | rest], state) do
    rest = expect_op(rest, "(", state)
    {params, rest} = parse_params(rest, state, [])
    rest = skip_return_type(rest, state)
    {body, rest} = parse_lambda_body(rest, state)
    {{:lambda, params, body, line}, rest}
  end

  defp parse_primary([{:op, "(", _} | rest], state) do
    {expr, rest} = parse_expression(rest, state)
    {expr, expect_op(rest, ")", state)}
  end

  defp parse_primary([{:op, "[", line} | rest], state) do
    {elements, rest} = parse_list(rest, state, "]", [])
    {{:array, elements, line}, rest}
  end

  defp parse_primary([{:op, "{", line} | rest], state) do
    {pairs, rest} = parse_dict(rest, state, [])
    {{:dict, pairs, line}, rest}
  end

  defp parse_primary([token | _], state), do: unexpected(token, state, "expected an expression")

  defp parse_args(tokens, state, acc), do: parse_list(tokens, state, ")", acc)

  defp parse_list([{:op, close, _} | rest], _state, close, acc), do: {Enum.reverse(acc), rest}

  defp parse_list(tokens, state, close, acc) do
    {expr, rest} = parse_expression(tokens, state)
    acc = [expr | acc]

    case rest do
      [{:op, ",", _} | after_comma] -> parse_list(after_comma, state, close, acc)
      [{:op, ^close, _} | after_close] -> {Enum.reverse(acc), after_close}
      [token | _] -> unexpected(token, state, "expected `,` or `#{close}`")
    end
  end

  defp parse_dict([{:op, "}", _} | rest], _state, acc), do: {Enum.reverse(acc), rest}

  defp parse_dict(tokens, state, acc) do
    {key, rest} = parse_expression(tokens, state)
    rest = expect_op(rest, ":", state)
    {value, rest} = parse_expression(rest, state)
    acc = [{key, value} | acc]

    case rest do
      [{:op, ",", _} | after_comma] -> parse_dict(after_comma, state, acc)
      [{:op, "}", _} | after_brace] -> {Enum.reverse(acc), after_brace}
      [token | _] -> unexpected(token, state, "expected `,` or `}` in dictionary")
    end
  end

  # ── Token helpers ────────────────────────────────────────────────────────

  defp expect_ident([{:ident, name, _} | rest], _state), do: {name, rest}
  defp expect_ident([token | _], state), do: unexpected(token, state, "expected a name")

  defp expect_keyword([{:ident, word, _} | rest], word, _state), do: rest
  defp expect_keyword([{:keyword, word, _} | rest], word, _state), do: rest

  defp expect_keyword([token | _], word, state),
    do: unexpected(token, state, "expected `#{word}`")

  defp expect_op([{:op, op, _} | rest], op, _state), do: rest
  defp expect_op([token | _], op, state), do: unexpected(token, state, "expected `#{op}`")

  defp expect([{type, _, _} | rest], type, _state), do: rest

  defp expect([token | _], type, state),
    do: unexpected(token, state, "expected #{describe_type(type)}")

  defp expect_newline([{:newline, _, _} | rest], _state), do: rest
  defp expect_newline([{:eof, _, _}] = tokens, _state), do: tokens
  defp expect_newline([{:dedent, _, _} | _] = tokens, _state), do: tokens

  defp expect_newline([{:op, op, _} | _] = tokens, _state) when op in [")", "]", "}", ","],
    do: tokens

  defp expect_newline([token | _], state), do: unexpected(token, state, "expected end of line")

  defp describe_type(:indent), do: "an indented block"
  defp describe_type(:dedent), do: "the end of a block"
  defp describe_type(other), do: to_string(other)

  defp unexpected({type, value, line}, state, expectation) do
    raise CompileError,
      file: state.file,
      line: line,
      message: "#{expectation}, got #{describe(type, value)}"
  end

  defp describe(:eof, _), do: "end of file"
  defp describe(:newline, _), do: "end of line"
  defp describe(:indent, _), do: "an indent"
  defp describe(:dedent, _), do: "a dedent"
  defp describe(_type, value), do: "`#{value}`"

  defp line_of(expr), do: expr |> Tuple.to_list() |> List.last()
end
