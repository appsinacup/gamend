defmodule GamendWeb.AvatarForm do
  @moduledoc """
  The settings page's avatar form (`GamendWeb.UserLive.Settings.AccountTab`)
  and what its icon picker shows lit, for the page and a client alike
  (`GET /api/v1/me/avatar/icon`), so the two never differ.
  """

  import Phoenix.Component, only: [to_form: 2]

  alias Gamend.Accounts.User
  alias GamendWeb.IconPickerComponents

  @doc """
  What the avatar form holds: the icon picked, in its colour; none picked,
  the avatar shown (`User.public_avatar_url/1`), an icon their id gave them
  lit as if picked. A colour with no icon stays on the form for the next.
  """
  @spec form(User.t(), map()) :: Phoenix.HTML.Form.t()
  def form(%User{} = user, picked \\ %{}) do
    url = Gamend.Icons.put_color(picked, "profile_url")["profile_url"]
    shown = if Gamend.Icons.name(url), do: url, else: User.public_avatar_url(user) || ""
    to_form(Map.put(picked, "profile_url", shown), as: :avatar_icon)
  end

  @doc """
  The picker's field. Not `form[:profile_url]` in a template: LiveView redraws
  that only when the icon itself changes, and the colour is a field of its own.
  """
  @spec field(Phoenix.HTML.Form.t()) :: Phoenix.HTML.FormField.t()
  def field(form), do: form[:profile_url]

  @doc """
  What the picker shows lit for `user` before they pick: `{icon, color}`, the
  tile's icon (nil for none: an uploaded picture shown, or an icon that is not
  one of `Gamend.Icons.picks/0`, which no tile is) and the colour's (nil for
  none), the one an icon picked next takes where no icon is lit
  (`IconPickerComponents.lit/1`).
  """
  @spec lit(User.t()) :: {String.t() | nil, String.t() | nil}
  def lit(%User{} = user) do
    {icon, color} = user |> form() |> field() |> IconPickerComponents.lit()
    {if(icon in Gamend.Icons.picks(), do: icon), color}
  end
end
