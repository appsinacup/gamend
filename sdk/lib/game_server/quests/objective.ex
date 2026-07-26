defmodule GameServer.Quests.Objective do
  @moduledoc """
  Quest objective struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime.

  ## Fields

  - `event` - Event name the objective counts (string)
  - `target` - Occurrences required to complete (integer, default 1)
  - `params` - Optional match constraints on the event meta (map)
  """

  @type t :: %__MODULE__{
          event: String.t(),
          target: pos_integer(),
          params: map()
        }

  defstruct [
    :event,
    :target,
    :params
  ]
end
