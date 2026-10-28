defmodule GamendWeb.NewGroupComponent do
  @moduledoc """
  A group made without leaving the page: a dialog asking its name, and its
  type when the host allows more than one (`Gamend.Groups.types/0`, the
  first picked), and the group made from it (`Gamend.Groups.create_group/2`),
  its maker its admin. The page then hears
  `{GamendWeb.NewGroupComponent, {:created, group}}` and puts the group
  where it was wanted. Forge's project forms and Gamend Cloud's server forms
  offer the groups a person admins as the owner, and this beside them, so a
  first group is one name away.

  Render it outside the page's own form, which cannot hold another:

      <.live_component module={GamendWeb.NewGroupComponent} id="new-team" user={@user} />

  and open it from anywhere on the page with `open_button/1`, which may sit
  inside that form.
  """
  use GamendWeb, :live_component

  alias Gamend.Groups
  alias Gamend.Groups.Group
  alias GamendWeb.GroupLabels
  alias GamendWeb.LiveHelpers

  @fields ["title", "type"]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(open?: false, error: nil, types: Groups.types())
     |> assign_form(Groups.change_group(%Group{}))}
  end

  @impl true
  def handle_event("open", _params, socket) do
    {:noreply,
     socket
     |> assign(open?: true, error: nil, types: Groups.types())
     |> assign_form(Groups.change_group(%Group{}))}
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :open?, false)}

  def handle_event("validate", %{"group" => params}, socket) do
    changeset =
      %Group{}
      |> Groups.change_group(Map.take(params, @fields))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("create", %{"group" => params}, socket) do
    case Groups.create_group(socket.assigns.user.id, Map.take(params, @fields)) do
      {:ok, group} ->
        send(self(), {__MODULE__, {:created, group}})
        {:noreply, assign(socket, :open?, false)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}

      {:error, reason} ->
        {:noreply, assign(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :group))

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div
        :if={@open?}
        class="modal modal-open"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <div class="modal-box">
          <h3 id={"#{@id}-title"} class="text-lg font-semibold">{gettext("New group")}</h3>
          <.form
            for={@form}
            id={"#{@id}-form"}
            phx-change="validate"
            phx-submit="create"
            phx-target={@myself}
            class="mt-4 space-y-3"
          >
            <.input
              field={@form[:title]}
              type="text"
              label={gettext("Name")}
              autocomplete="off"
              phx-debounce="300"
              phx-mounted={JS.focus()}
            />
            <div :if={length(@types) > 1}>
              <.input
                field={@form[:type]}
                type="select"
                label={gettext("Type")}
                options={GroupLabels.type_options(@types)}
              />
              <p class="mt-1 text-xs text-base-content/60">{GroupLabels.types_hint(@types)}</p>
            </div>
            <p :if={@error} class="text-sm text-error">{@error}</p>
            <div class="modal-action">
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="close"
                phx-target={@myself}
              >
                {gettext("Cancel")}
              </button>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Create")}</button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop" phx-click="close" phx-target={@myself}></div>
      </div>
    </div>
    """
  end

  attr :target, :string, required: true, doc: "the dialog's DOM id, with its `#`"
  attr :id, :string, default: nil
  attr :class, :string, default: "btn btn-ghost btn-sm"

  @doc "The button that opens the dialog: New team, or New group."
  def open_button(assigns) do
    ~H"""
    <button type="button" id={@id} class={@class} phx-click="open" phx-target={@target}>
      <.icon name="hero-plus" class="size-4" />
      {gettext("New group")}
    </button>
    """
  end
end
