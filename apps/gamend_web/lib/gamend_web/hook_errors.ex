defmodule GamendWeb.HookErrors do
  @moduledoc """
  How a game hook's `{:error, reason}` reaches a client, over
  `POST /api/v1/hooks/call` and the user channel's `call_hook` alike.

  A hook that raised is a bug in the plugin, not in the request: it answers
  `exception` with no detail, because the message carries whatever the plugin
  touched (a query, a constraint name), and `Gamend.Hooks` has already logged
  it with its stack trace. Arguments none of the hook's clauses accept are the
  caller's mistake: `function_clause`. Anything else is the hook's own refusal:
  a snake_case atom is the code a game switches on, and any other term is
  `hook_error`, or its kind, with the detail as the message.
  """

  require GamendWeb.HookErrorCode, as: HookErrorCode

  @doc "The error code, and the message when there is one, for a hook's error reason."
  @spec describe(term()) :: {String.t(), String.t() | nil}
  def describe({:exception, _message}), do: {HookErrorCode.exception(), nil}

  def describe({:function_clause, message}) when is_binary(message),
    do: {"function_clause", message}

  def describe({kind, reason}) when is_atom(kind) do
    if code?(kind),
      do: {Atom.to_string(kind), inspect(reason)},
      else: {HookErrorCode.hook_error(), inspect({kind, reason})}
  end

  def describe(reason) when is_atom(reason) do
    if code?(reason),
      do: {Atom.to_string(reason), nil},
      else: {HookErrorCode.hook_error(), inspect(reason)}
  end

  def describe(reason) when is_binary(reason), do: {HookErrorCode.hook_error(), reason}
  def describe(reason), do: {HookErrorCode.hook_error(), inspect(reason)}

  @doc "The error body for a hook's error reason: `%{error: code}`, plus `message` when there is one."
  @spec reply(term()) :: %{required(:error) => String.t(), optional(:message) => String.t()}
  def reply(reason) do
    case describe(reason) do
      {code, nil} -> %{error: code}
      {code, message} -> %{error: code, message: message}
    end
  end

  defp code?(atom), do: Atom.to_string(atom) =~ ~r/^[a-z][a-z0-9_]*$/
end
