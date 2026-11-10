defmodule GamendWeb.GroupIconUpload do
  @moduledoc """
  A group's icon as an image of one's own, beside the site's icons
  (`<.icon_picker>`), as an account's avatar is (`AccountTab`): the groups
  page (`GamendWeb.UserLive.Settings.GroupsTab`, new and edit) and the New
  group dialog (`GamendWeb.NewGroupComponent`) share it.

  Only with `user_image_uploads` on and an account that may upload
  (`Gamend.Accounts.can_upload_avatar?/1`); otherwise no upload is allowed,
  so no file reaches the server. A picked file is shown at once and becomes
  the icon once the group is saved, stored where the API's uploads go
  (`icons/groups/<id>/`), its type what its bytes are.

      socket = GroupIconUpload.allow(socket, user)

      <GroupIconUpload.field id="..." field={@form[:icon_url]} uploads={@group_icon_upload? && @uploads} />

      {socket, group, error} = GroupIconUpload.save(socket, user, group)
  """
  use GamendWeb, :html

  import Phoenix.LiveView,
    only: [allow_upload: 3, cancel_upload: 3, consume_uploaded_entries: 3, uploaded_entries: 2]

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Groups
  alias Gamend.Storage
  alias GamendWeb.Features

  @name :group_icon

  @doc """
  The upload, `:group_icon`, when `user` may upload one, and
  `@group_icon_upload?` saying whether they may. Called once, in a page's
  mount or a component's first update.
  """
  @spec allow(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def allow(socket, user) do
    if allowed?(user) do
      socket
      |> assign(:group_icon_upload?, true)
      |> allow_upload(@name,
        accept: ~w(.png .jpg .jpeg .webp .gif),
        max_entries: 1,
        max_file_size: Gamend.Limits.get(:max_upload_bytes)
      )
    else
      assign(socket, :group_icon_upload?, false)
    end
  end

  @doc "Whether `user` (a `%User{}`, or a map with its `id`) may upload a group's icon."
  @spec allowed?(term()) :: boolean()
  def allowed?(%User{} = user),
    do: Features.enabled?(:user_image_uploads) and Accounts.can_upload_avatar?(user)

  def allowed?(%{id: id}) when is_binary(id), do: allowed?(Accounts.get_user(id))
  def allowed?(_user), do: false

  @doc """
  The picked file made `group`'s icon, `{socket, group, nil}`, the group as
  it is now; nothing picked, the group as it was. `{socket, group, message}`
  when the file was refused, was no image or could not be kept, for the page
  to say.
  """
  @spec save(Phoenix.LiveView.Socket.t(), term(), Groups.Group.t()) ::
          {Phoenix.LiveView.Socket.t(), Groups.Group.t(), String.t() | nil}
  def save(socket, user, group) do
    if socket.assigns[:group_icon_upload?] == true and allowed?(user) do
      case uploaded_entries(socket, @name) do
        # A file refused never finishes, and consuming it would raise.
        {_done, [_ | _]} ->
          {socket, group, refused()}

        _nothing_or_done ->
          results =
            consume_uploaded_entries(socket, @name, fn %{path: path}, _entry ->
              {:ok, store(group.id, File.read!(path))}
            end)

          {group, error} = set(results, user, group)
          {socket, group, error}
      end
    else
      {socket, group, nil}
    end
  end

  @doc "The picked file, `ref`, dropped."
  @spec cancel(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def cancel(socket, ref), do: cancel_upload(socket, @name, ref)

  @doc "Every picked file dropped: a form closed without saving."
  @spec cancel_all(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def cancel_all(%{assigns: %{uploads: %{@name => %{entries: entries}}}} = socket),
    do: Enum.reduce(entries, socket, &cancel_upload(&2, @name, &1.ref))

  def cancel_all(socket), do: socket

  defp store(group_id, data) do
    case Storage.sniff_content_type(data) do
      nil ->
        :not_an_image

      content_type ->
        key = Storage.build_key("icons/groups", group_id, Storage.extension_for(content_type))

        case Storage.put(key, data, content_type: content_type) do
          {:ok, _} -> Storage.url(key)
          {:error, _reason} -> :failed
        end
    end
  end

  defp set([url], user, group) when is_binary(url) do
    case Groups.set_icon_url(user.id, group.id, url) do
      {:ok, group} -> {group, nil}
      {:error, _reason} -> {group, gettext("Failed")}
    end
  end

  defp set([:not_an_image], _user, group), do: {group, refused()}

  defp set([_failed], _user, group), do: {group, gettext("Failed")}
  defp set([], _user, group), do: {group, nil}

  defp refused, do: gettext("File is too large or not a supported image.")

  attr :id, :string, required: true, doc: "the file input's row is `<id>-upload`"
  attr :field, Phoenix.HTML.FormField, required: true, doc: "the form's icon URL field"
  attr :uploads, :any, default: nil, doc: "`@uploads` when the reader may upload, else nil"
  attr :cancel, :string, default: "group_icon_cancel", doc: "the event dropping a file"
  attr :target, :any, default: nil, doc: "a component's `@myself`, for `cancel`"

  @doc """
  The one icon field every form uses, a group's, a server's or a project's: the
  icon as it will be, the file input beside it when the reader may upload one,
  and the site's icons and colours under it (`<.icon_picker>`). The form's
  `phx-change` hears all of it; `allow/3` sets up the upload.

      <GroupIconUpload.field
        id="project-icon"
        field={@form[:icon_url]}
        uploads={@group_icon_upload? && @uploads}
      />
  """
  def field(assigns) do
    ~H"""
    <div id={@id} class="space-y-3">
      <%= if @uploads do %>
        <GamendWeb.GroupIconUpload.input
          id={"#{@id}-upload"}
          uploads={@uploads}
          icon_url={@field.value}
          cancel={@cancel}
          target={@target}
        />
      <% else %>
        <.group_avatar icon_url={@field.value} class="size-16" />
      <% end %>
      <.icon_picker
        field={@field}
        label={gettext("Icon")}
        on_pick={drop_picked_file(@uploads, @cancel, @target)}
      />
    </div>
    """
  end

  # An icon clicked with a file picked means the icon: the file beats it at Save.
  defp drop_picked_file(%{group_icon: %{entries: [%{ref: ref} | _]}}, cancel, target) do
    opts = if target, do: [target: target], else: []
    JS.push(cancel, [value: %{ref: ref}] ++ opts)
  end

  defp drop_picked_file(_uploads, _cancel, _target), do: nil

  attr :uploads, :any, required: true
  attr :icon_url, :string, default: nil, doc: "the icon the form has now, shown with no file"
  attr :cancel, :string, default: "group_icon_cancel", doc: "the event dropping a file"
  attr :target, :any, default: nil, doc: "a component's `@myself`, for `cancel`"
  attr :id, :string, default: nil

  @doc """
  The group's icon as it will be, and the file input beside it: a picked file
  shown in place of the icon, with its name and a way to drop it. A form wants
  `field/1`, which has this and the site's icons.
  """
  def input(assigns) do
    ~H"""
    <div id={@id} class="flex items-center gap-4">
      <%= if @uploads.group_icon.entries == [] do %>
        <.group_avatar icon_url={@icon_url} class="size-16" />
      <% else %>
        <.live_img_preview
          :for={entry <- @uploads.group_icon.entries}
          entry={entry}
          data-icon-backdrop
          class="size-16 shrink-0 rounded-field bg-base-300 object-cover"
        />
      <% end %>
      <div class="min-w-0 space-y-2">
        <.live_file_input
          upload={@uploads.group_icon}
          class="file-input file-input-sm file-input-bordered w-full max-w-xs"
        />
        <div :for={entry <- @uploads.group_icon.entries} class="flex items-center gap-2 text-xs">
          <span class="truncate max-w-[10rem]">{entry.client_name}</span>
          <button
            type="button"
            phx-click={@cancel}
            phx-target={@target}
            phx-value-ref={entry.ref}
            class="btn btn-ghost btn-xs"
            aria-label={gettext("Remove selected file")}
          >
            <.icon name="hero-x-mark-solid" class="w-3 h-3" />
          </button>
          <span :if={upload_errors(@uploads.group_icon, entry) != []} class="text-error">
            {gettext("File is too large or not a supported image.")}
          </span>
        </div>
      </div>
    </div>
    """
  end
end
