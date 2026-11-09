# `Gamend.Names`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/names.ex#L1)

Names a closed set of strings: a macro for each value, so a pattern or a
guard can name one, and `all/0` for `validate_inclusion/3`.

    defmodule MyApp.Servers.Status do
      use Gamend.Names, ~w(creating running failed)
    end

    require MyApp.Servers.Status, as: Status

    def up?(%Server{status: Status.running()}), do: true

The list stays in `@all`, for a macro that names part of it. A set that
holds the value `"all"` has that macro and no `all/0`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
