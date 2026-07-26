defmodule GameServer.Quests.Reward do
  @moduledoc """
  Quest reward struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `type` - `"currency"` (paid via Economy) or `"item"` (via Inventory)
  - `code` - Currency or item code (string)
  - `amount` - Amount granted (integer, default 1)
  """

  @type t :: %__MODULE__{
          type: String.t(),
          code: String.t(),
          amount: pos_integer()
        }

  defstruct [
    :type,
    :code,
    :amount
  ]
end
