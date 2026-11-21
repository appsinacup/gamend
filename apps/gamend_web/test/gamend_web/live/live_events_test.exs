defmodule GamendWeb.LiveEventsTest do
  @moduledoc """
  Every event a core LiveView handles is declared (`GamendWeb.LiveEvents`),
  and every declaration names an event something handles.

  An undeclared event runs as written, unchecked; a declaration no handler
  matches is one a renamed event left behind.
  """
  use ExUnit.Case, async: true

  @modules :gamend_web
           |> Application.spec(:modules)
           |> Enum.filter(
             &(Code.ensure_loaded?(&1) and function_exported?(&1, :__live_events__, 1))
           )

  test "core has modules with events" do
    assert length(@modules) > 30
  end

  test "every handled event is declared" do
    undeclared =
      for module <- @modules,
          event <- module.__live_events__(:handled),
          not Map.has_key?(module.__live_events__(:declared), event) do
        "#{inspect(module)}: #{event}"
      end

    assert undeclared == [],
           "handled with no `event` declaration:\n  " <> Enum.join(undeclared, "\n  ")
  end

  test "every declaration is handled" do
    unhandled =
      for module <- @modules,
          event <- Map.keys(module.__live_events__(:declared)),
          event not in module.__live_events__(:handled) do
        "#{inspect(module)}: #{event}"
      end

    assert unhandled == [], "declared, handled by no clause:\n  " <> Enum.join(unhandled, "\n  ")
  end

  describe "the check" do
    defmodule Sample do
      use Phoenix.LiveView
      use GamendWeb.LiveEvents

      event("delete", id: :string)
      event("save", user: {:map_of, :string}, note: {:optional, :string})

      def render(assigns), do: ~H""
      def handle_event("delete", %{"id" => id}, socket), do: {:noreply, assign(socket, :id, id)}
      def handle_event("save", _params, socket), do: {:noreply, assign(socket, :saved, true)}
      def handle_event("free", params, socket), do: {:noreply, assign(socket, :free, params)}
    end

    setup do
      %{socket: %Phoenix.LiveView.Socket{}}
    end

    test "passes matching params to the handler", %{socket: socket} do
      assert {:noreply, %{assigns: %{id: "7"}}} =
               Sample.handle_event("delete", %{"id" => "7"}, socket)

      assert {:noreply, %{assigns: %{saved: true}}} =
               Sample.handle_event("save", %{"user" => %{}, "note" => nil}, socket)
    end

    test "refuses a wrong type or a missing key before the handler", %{socket: socket} do
      for params <- [%{"id" => ["7"]}, %{"id" => %{"a" => 1}}, %{}, %{"id" => 7}] do
        assert {:noreply, %{assigns: assigns}} = Sample.handle_event("delete", params, socket)
        refute Map.has_key?(assigns, :id)
      end

      assert {:noreply, %{assigns: assigns}} =
               Sample.handle_event("save", %{"user" => "x"}, socket)

      refute Map.has_key?(assigns, :saved)
    end

    test "lets an undeclared event through", %{socket: socket} do
      assert {:noreply, %{assigns: %{free: [1]}}} = Sample.handle_event("free", [1], socket)
    end

    test "records the events it handles" do
      assert Sample.__live_events__(:handled) == ["delete", "save", "free"]
      assert Map.keys(Sample.__live_events__(:declared)) |> Enum.sort() == ["delete", "save"]
    end
  end
end
