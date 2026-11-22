defmodule GamendWeb.FileDropComponents do
  @moduledoc """
  Every file field on a Gamend page takes a file dropped on it as well as one
  picked, through `file_drop/1`.

  The zone goes around the field, and the field stays what it was: the native
  input (`live_file_input/1` or a plain `<input type="file">`), so a click, the
  keyboard and a screen reader reach the picker as before.

  Two kinds of field, one component:

    * A LiveView upload (`upload={@uploads.avatar}`): the zone is the upload's
      `phx-drop-target`, so LiveView takes the drop and tracks the files as it
      does a pick, and marks the zone `phx-drop-target-active` while a file is
      over it. With no inner block the component draws the upload's
      `live_file_input/1` itself, with `input_class`.
    * A plain input (the inner block): `assets/js/file_drop.js` sets the
      input's files from the drop (the first only, unless it is `multiple`;
      those its `accept` takes) and fires `input` and `change`, as a pick
      does, and marks the zone `data-file-drop-active` while a file is over
      it. It works on a page with no LiveView, and in markup a script draws
      (`data-file-drop` on the element is all it needs).

  The drop state is `gamend.css`'s `.file-drop`.
  """
  use Phoenix.Component

  attr :upload, Phoenix.LiveView.UploadConfig,
    default: nil,
    doc: "a LiveView upload; the zone is its drop target"

  attr :input_class, :any, default: nil, doc: "the drawn `live_file_input`'s class"
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block,
    doc: "the field itself; left out, the upload's `live_file_input` is drawn"

  def file_drop(assigns) do
    ~H"""
    <div
      class={["file-drop", @class]}
      data-file-drop
      phx-drop-target={@upload && @upload.ref}
      {@rest}
    >
      <%= if @inner_block != [] do %>
        {render_slot(@inner_block)}
      <% else %>
        <.live_file_input upload={@upload} class={@input_class} />
      <% end %>
    </div>
    """
  end
end
