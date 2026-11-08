defmodule Gamend.GDScript.Lexer do
  @moduledoc """
  GDScript source text into a flat token list.

  Indentation is significant in GDScript, so the lexer is line-oriented: it
  tracks an indent stack and emits `:indent` / `:dedent` tokens, the same shape
  a Python lexer produces. Everything downstream then works on a flat stream
  with explicit block delimiters.

  A token is `{type, value, line}`. Types:

    * `:ident` `:int` `:float` `:string` — literals and names
    * `:keyword` — a reserved word (`func`, `var`, `if`, …)
    * `:op` — an operator or delimiter
    * `:newline` `:indent` `:dedent` `:eof` — structure

  Blank lines and comment-only lines produce no tokens at all, and newlines
  inside brackets are swallowed so a call can wrap across lines.
  """

  alias Gamend.GDScript.CompileError

  @nofile "nofile"

  # Unsupported constructs are keywords too. Lexing `for` as an identifier
  # would produce "expected end of line, got `x`"; as a keyword the parser can
  # say "`for` is not supported server-side" and name the line.
  @keywords ~w(func var const if elif else return true false null and or not pass
               for while break continue match class_name extends signal await
               yield static enum export onready tool is as class)

  # Longest first: `==` must win over `=`, `->` over `-`.
  @operators [
    "==",
    "!=",
    "<=",
    ">=",
    "+=",
    "-=",
    "*=",
    "/=",
    "%=",
    ":=",
    "&&",
    "||",
    "->",
    "+",
    "-",
    "*",
    "/",
    "%",
    "<",
    ">",
    "=",
    "(",
    ")",
    "[",
    "]",
    "{",
    "}",
    ",",
    ":",
    ".",
    "!"
  ]

  @tab_width 4

  @doc """
  Tokenize `source`. Raises `Gamend.GDScript.CompileError` on bad input.
  """
  @spec tokenize(String.t(), String.t()) :: [tuple()]
  def tokenize(source, file \\ @nofile) do
    state = %{
      file: file,
      tokens: [],
      indents: [0],
      # Depth of (), [] and {} -- while > 0, line breaks are not statement ends.
      depth: 0
    }

    source
    |> String.split(~r/\r\n|\r|\n/)
    |> Enum.with_index(1)
    |> Enum.reduce(state, &lex_line/2)
    |> close_blocks()
    |> then(fn state -> Enum.reverse([{:eof, nil, 0} | state.tokens]) end)
  end

  # ── Lines ────────────────────────────────────────────────────────────────

  defp lex_line({raw, line}, %{depth: depth} = state) when depth > 0 do
    # Continuation of a bracketed expression: no indent handling. It still has
    # to end the statement, though -- this is the line on which the brackets
    # may close, and `end_statement/2` is a no-op while any are still open.
    # Without it a wrapped call runs straight into the next statement.
    {content, _indent} = split_indent(raw)

    content
    |> lex_content(line, state)
    |> end_statement(line)
  end

  defp lex_line({raw, line}, state) do
    {content, indent} = split_indent(raw)

    if blank_or_comment?(content) do
      state
    else
      state
      |> apply_indent(indent, line)
      |> then(&lex_content(content, line, &1))
      |> end_statement(line)
    end
  end

  # A statement only ends here when brackets are balanced -- `f(` on this line
  # means the expression continues onto the next one.
  defp end_statement(%{depth: 0} = state, line), do: emit(state, {:newline, nil, line})
  defp end_statement(state, _line), do: state

  defp split_indent(raw) do
    expanded = String.replace(raw, "\t", String.duplicate(" ", @tab_width))
    trimmed = String.trim_leading(expanded, " ")
    {trimmed, String.length(expanded) - String.length(trimmed)}
  end

  defp blank_or_comment?(""), do: true
  defp blank_or_comment?("#" <> _), do: true
  defp blank_or_comment?(_), do: false

  defp apply_indent(%{indents: [current | _]} = state, indent, _line) when indent == current do
    state
  end

  defp apply_indent(%{indents: [current | _] = indents} = state, indent, line)
       when indent > current do
    %{state | indents: [indent | indents]} |> emit({:indent, nil, line})
  end

  defp apply_indent(%{indents: indents} = state, indent, line) do
    # Pop every level deeper than the new indent, then insist we landed exactly
    # on one. Anything else is a misaligned block, which GDScript rejects too.
    {popped, rest} = Enum.split_while(indents, &(&1 > indent))

    case rest do
      [^indent | _] ->
        Enum.reduce(popped, %{state | indents: rest}, fn _, acc ->
          emit(acc, {:dedent, nil, line})
        end)

      _ ->
        raise CompileError,
          file: state.file,
          line: line,
          message: "unindent does not match any enclosing block"
    end
  end

  defp close_blocks(%{indents: indents} = state) do
    Enum.reduce(Enum.drop(indents, -1), %{state | indents: [0]}, fn _, acc ->
      emit(acc, {:dedent, nil, 0})
    end)
  end

  # ── Within a line ────────────────────────────────────────────────────────

  defp lex_content("", _line, state), do: state
  defp lex_content(" " <> rest, line, state), do: lex_content(rest, line, state)
  defp lex_content("#" <> _, _line, state), do: state

  defp lex_content(<<quote_char, _::binary>> = content, line, state)
       when quote_char in [?", ?'] do
    {value, rest} = read_string(content, line, state)
    lex_content(rest, line, emit(state, {:string, value, line}))
  end

  defp lex_content(<<c, _::binary>> = content, line, state) when c >= ?0 and c <= ?9 do
    {token, rest} = read_number(content, line)
    lex_content(rest, line, emit(state, token))
  end

  defp lex_content(<<c, _::binary>> = content, line, state)
       when (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or c == ?_ or c == ?@ do
    {word, rest} = read_word(content)
    type = if word in @keywords, do: :keyword, else: :ident
    lex_content(rest, line, emit(state, {type, word, line}))
  end

  defp lex_content(content, line, state) do
    case Enum.find(@operators, &String.starts_with?(content, &1)) do
      nil ->
        <<c::utf8, _::binary>> = content

        raise CompileError,
          file: state.file,
          line: line,
          message: "unexpected character #{inspect(<<c::utf8>>)}"

      op ->
        rest = binary_part(content, byte_size(op), byte_size(content) - byte_size(op))
        lex_content(rest, line, emit(track_depth(state, op), {:op, op, line}))
    end
  end

  defp track_depth(state, op) when op in ["(", "[", "{"], do: %{state | depth: state.depth + 1}

  defp track_depth(state, op) when op in [")", "]", "}"],
    do: %{state | depth: max(state.depth - 1, 0)}

  defp track_depth(state, _op), do: state

  # ── Readers ──────────────────────────────────────────────────────────────

  defp read_word(content) do
    split_while(content, fn c ->
      (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or (c >= ?0 and c <= ?9) or c == ?_ or
        c == ?@
    end)
  end

  defp read_number(content, line) do
    {int_part, rest} = split_while(content, &((&1 >= ?0 and &1 <= ?9) or &1 == ?_))
    digits = String.replace(int_part, "_", "")

    case rest do
      <<?., c, _::binary>> when c >= ?0 and c <= ?9 ->
        {frac, rest2} =
          rest |> binary_part(1, byte_size(rest) - 1) |> split_while(&(&1 >= ?0 and &1 <= ?9))

        {{:float, String.to_float(digits <> "." <> frac), line}, rest2}

      _ ->
        {{:int, String.to_integer(digits), line}, rest}
    end
  end

  defp read_string(<<quote_char, rest::binary>>, line, state) do
    read_string(rest, quote_char, line, state, [])
  end

  defp read_string(<<>>, _quote_char, line, state, _acc) do
    raise CompileError, file: state.file, line: line, message: "unterminated string"
  end

  defp read_string(<<?\\, escaped, rest::binary>>, quote_char, line, state, acc) do
    read_string(rest, quote_char, line, state, [unescape(escaped) | acc])
  end

  defp read_string(<<c, rest::binary>>, quote_char, _line, _state, acc) when c == quote_char do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp read_string(<<c::utf8, rest::binary>>, quote_char, line, state, acc) do
    read_string(rest, quote_char, line, state, [<<c::utf8>> | acc])
  end

  defp unescape(?n), do: "\n"
  defp unescape(?t), do: "\t"
  defp unescape(?r), do: "\r"
  defp unescape(?0), do: <<0>>
  defp unescape(c), do: <<c>>

  defp split_while(binary, fun), do: split_while(binary, fun, 0)

  defp split_while(binary, fun, index) do
    case binary do
      <<_::binary-size(^index), c, _::binary>> ->
        if fun.(c),
          do: split_while(binary, fun, index + 1),
          else: {binary_part(binary, 0, index), rest_from(binary, index)}

      _ ->
        {binary, ""}
    end
  end

  defp rest_from(binary, index), do: binary_part(binary, index, byte_size(binary) - index)

  defp emit(state, token), do: %{state | tokens: [token | state.tokens]}
end
