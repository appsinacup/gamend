defmodule Gamend.Config do
  @moduledoc """
  Typed reads of environment variables a plugin declared via `env_vars/0`.

  `System.get_env/1` always returns a string, so every caller ends up writing
  its own `== "true"` or `String.to_integer/1` — and each one invents its own
  answer for a missing or malformed value. Declaring the variable once gives
  the coercion a single home:

      def env_vars do
        [%{name: "MYGAME_DIFFICULTY", default: "normal", description: "..."},
         %{name: "MYGAME_MAX_BOTS", default: 8, description: "..."},
         %{name: "MYGAME_TUTORIAL", default: true, description: "..."}]
      end

      Config.get("MYGAME_MAX_BOTS")   #=> 8      (integer, from the default)
      Config.get("MYGAME_TUTORIAL")   #=> true   (boolean)

  The type is inferred from the declared default, so `default: 8` reads as an
  integer without a separate `:type` key. Declare `:type` explicitly only when
  the default cannot carry it — typically a secret with `default: nil`.

  A value that does not parse falls back to the default and logs, because a
  typo in an env var should not take the server down at read time.
  """

  alias Gamend.Hooks.Declarations

  require Logger

  @falsy ~w(0 false FALSE False no off)
  @truthy ~w(1 true TRUE True yes on)

  @type value :: String.t() | integer() | float() | boolean() | nil

  @doc """
  Reads a declared variable, coerced to its declared type.

  Returns the declared default when unset, and raises for a name no plugin
  declared — an undeclared read is a bug, not a runtime condition.
  """
  @spec get(String.t()) :: value()
  def get(name) when is_binary(name) do
    case declaration(name) do
      nil ->
        raise ArgumentError,
              "#{name} is not declared by any plugin's env_vars/0; " <>
                "declare it or use System.get_env/1"

      declared ->
        read(name, declared)
    end
  end

  @doc """
  Reads a variable, coerced to match `default`, whether declared or not.

  For core and host code, which has no plugin declaration to hang types on.
  """
  @spec get(String.t(), value()) :: value()
  def get(name, default) when is_binary(name) do
    read(name, %{default: default, type: infer_type(default)})
  end

  @doc "The inferred or declared type of a value: `:string`, `:integer`, `:float`, `:boolean`."
  @spec infer_type(value()) :: :string | :integer | :float | :boolean
  def infer_type(value) when is_boolean(value), do: :boolean
  def infer_type(value) when is_integer(value), do: :integer
  def infer_type(value) when is_float(value), do: :float
  def infer_type(_value), do: :string

  defp declaration(name) do
    Enum.find(Declarations.env_vars(), &(&1.name == name))
  end

  defp read(name, %{default: default} = declared) do
    type = Map.get(declared, :type) || infer_type(default)

    case System.get_env(name) do
      nil -> default
      "" -> default
      raw -> cast(raw, type, name, default)
    end
  end

  defp cast(raw, :boolean, _name, _default) when raw in @truthy, do: true
  defp cast(raw, :boolean, _name, _default) when raw in @falsy, do: false

  defp cast(raw, :integer, name, default) do
    case Integer.parse(raw) do
      {int, ""} -> int
      _ -> bad_value(name, raw, :integer, default)
    end
  end

  defp cast(raw, :float, name, default) do
    case Float.parse(raw) do
      {float, ""} -> float
      _ -> bad_value(name, raw, :float, default)
    end
  end

  defp cast(raw, :string, _name, _default), do: raw
  defp cast(raw, type, name, default), do: bad_value(name, raw, type, default)

  defp bad_value(name, raw, type, default) do
    Logger.warning("#{name}=#{inspect(raw)} is not a valid #{type}; using #{inspect(default)}")
    default
  end
end
