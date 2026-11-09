defmodule Gamend.ReadyChecks.CheckReason do
  @moduledoc """
  Why a ready check ended without passing.
  """

  use Gamend.Names, ~w(timeout declined reset cancelled)
end
