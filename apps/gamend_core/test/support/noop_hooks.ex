defmodule Gamend.TestSupport.NoopHooks do
  @moduledoc """
  Test helper for hook modules that override only callbacks under test.

  Pass-through implementations are generated from the `Gamend.Hooks`
  behaviour, so new hooks are picked up automatically:

  - `before_kv_get/2` returns `:public`
  - `on_custom_hook/2` returns `{:error, :not_implemented}`
  - `validate_username/1` and `matchmaking_seat_match/1` return `:default`
    (core's rules)
  - other `before_*` pipeline hooks pass their input through as `{:ok, input}`
  - `after_*` hooks return `:ok`
  """

  defmacro __using__(_opts) do
    callbacks = Gamend.Hooks.behaviour_info(:callbacks)

    defaults =
      for {name, arity} <- callbacks do
        args = Macro.generate_arguments(arity, __MODULE__)
        body = default_body(name, args)

        quote do
          @impl true
          def unquote(name)(unquote_splicing(args)), do: unquote(body)
        end
      end

    quote do
      @behaviour Gamend.Hooks

      unquote(defaults)

      defoverridable unquote(callbacks)
    end
  end

  defp default_body(:before_kv_get, _args), do: :public
  defp default_body(:on_custom_hook, _args), do: quote(do: {:error, :not_implemented})
  defp default_body(:validate_username, _args), do: :default
  defp default_body(:matchmaking_seat_match, _args), do: :default

  defp default_body(name, args) do
    if String.starts_with?(Atom.to_string(name), "before_") do
      case args do
        [single] -> quote(do: {:ok, unquote(single)})
        many -> quote(do: {:ok, {unquote_splicing(many)}})
      end
    else
      :ok
    end
  end
end
