defmodule GamendWeb.RewardComponents do
  @moduledoc """
  What a quest pays, one reward. Out of `GamendWeb.CoreComponents`, so an edit
  here recompiles only the pages that draw it; imported through
  `html_helpers`.
  """
  use Phoenix.Component

  import GamendWeb.CoreComponents, only: [icon: 1]

  require Gamend.Quests.RewardType, as: RewardType

  attr :type, :string, required: true, doc: "`currency` or `item`"
  attr :code, :string, required: true
  attr :amount, :integer, required: true
  attr :name, :string, default: nil, doc: "an item's name, when its code is not one"

  @doc """
  What a quest pays, one reward. A host that draws its rewards its own way
  names that component, so a coin or a title on core's pages is the one on
  its own:

      config :gamend_web, :reward_component, {MyHost.UI, :core_reward}

  It is called with `%{type: _, code: _, amount: _, name: _}`. With none, a
  plain badge.
  """
  def reward_chip(assigns) do
    case Application.get_env(:gamend_web, :reward_component) do
      {module, function} ->
        apply(module, function, [
          %{
            __changed__: nil,
            type: assigns.type,
            code: assigns.code,
            amount: assigns.amount,
            name: assigns.name
          }
        ])

      nil ->
        ~H"""
        <span class="badge badge-sm badge-ghost gap-1">
          <.icon
            name={
              if @type == RewardType.currency(), do: "hero-currency-dollar-solid", else: "hero-cube-solid"
            }
            class="w-3 h-3"
          />
          {reward_text(@amount, @name || @code, @name)}
        </span>
        """
    end
  end

  # An item with a name is that name alone for one; else the amount and it.
  defp reward_text(1, label, name) when is_binary(name), do: label
  defp reward_text(amount, label, _name), do: "#{amount} #{label}"
end
