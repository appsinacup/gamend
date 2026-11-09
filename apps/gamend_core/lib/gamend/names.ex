defmodule Gamend.Names do
  @moduledoc """
  Names a closed set of strings: a macro for each value, so a pattern or a
  guard can name one, and `all/0` for `validate_inclusion/3`.

      defmodule MyApp.Servers.Status do
        use Gamend.Names, ~w(creating running failed)
      end

      require MyApp.Servers.Status, as: Status

      def up?(%Server{status: Status.running()}), do: true

  The list stays in `@all`, for a macro that names part of it. A set that
  holds the value `"all"` has that macro and no `all/0`.
  """

  defmacro __using__(names) do
    quote bind_quoted: [names: names] do
      @all names

      @type t :: String.t()

      for name <- @all do
        defmacro unquote(String.to_atom(name))(), do: unquote(name)
      end

      # literal-ok: the one value that would take all/0's name
      if "all" not in @all do
        @doc "Every value."
        @spec all() :: [t()]
        def all, do: @all
      end
    end
  end
end
