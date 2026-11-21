defmodule GamendWeb.Schemas.HookSignature do
  @moduledoc "One arity of a callable hook function."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "HookSignature",
    description: "A hook function at one arity",
    type: :object,
    properties: %{
      arity: %Schema{type: :integer},
      signature: %Schema{type: :string, description: "`fn_name(arg, ...)`"},
      doc: %Schema{type: :string, description: "Empty when undocumented"},
      example_args: %Schema{type: :string, description: "A JSON array to start `args` from"}
    },
    required: [:arity, :signature, :doc, :example_args]
  })
end

defmodule GamendWeb.Schemas.HookFunction do
  @moduledoc """
  A function a client may call through `POST /hooks/call`, as `plugin` and
  `fn` name it there.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.HookSignature
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    %{
      title: "HookFunction",
      description: "A callable hook function",
      type: :object,
      properties: %{
        plugin: %Schema{type: :string},
        fn: %Schema{type: :string, description: "The function name, as `call_hook` takes it"},
        dynamic: %Schema{
          type: :boolean,
          description: "Registered at runtime rather than compiled"
        },
        arities: %Schema{type: :array, items: %Schema{type: :integer}},
        signatures: %Schema{type: :array, items: HookSignature},
        meta:
          GamendWeb.Schemas.FreeForm.object(
            "a dynamic function's registration, as its plugin made it",
            description: "A dynamic function's registration; `{}` otherwise"
          )
      },
      required: [:plugin, :fn, :dynamic, :arities, :signatures, :meta]
    },
    # `fn` is reserved in Elixir, so no struct can carry it.
    struct?: false
  )
end

defmodule GamendWeb.Schemas.HookFunctionPage do
  @moduledoc "A page of callable hook functions."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.HookFunction
end

defmodule GamendWeb.Schemas.HookCallResponse do
  @moduledoc """
  What the hook returned, under `data`. Untyped on purpose: a typed hook (with
  registered `<Fn>Request`/`<Fn>Reply` schemas) answers an object, an untyped
  one whatever it returned.
  """
  use GamendWeb.Schemas.Envelope,
    data: GamendWeb.Schemas.FreeForm.value("the plugin function's own return value"),
    description: "The hook's return value under `data`"
end
