defmodule GameServerWeb.Uploads do
  @moduledoc """
  The two-step upload every icon and avatar endpoint shares.

  Bytes never pass through the app server. The client asks for a ticket, PUTs
  the file straight to storage, then tells the server which key it wrote:

      POST .../icon/upload_url   -> %{url: ..., key: ..., ...}
      PUT  <ticket.url>          (client -> storage, direct)
      POST .../icon              %{"key" => key}

  ## Why there is no single `POST /uploads`

  Authorization is a property of the *target*, not of uploading: only you may
  set your avatar, only a group admin may set that group's icon, only an admin
  may set a tournament's. A generic endpoint would have to take the target as a
  parameter and re-derive the same checks, so the route stays per-entity and
  only the mechanism is shared — that is what this module is.

  `confirm/5` is the load-bearing half. The key comes from the client, so it is
  confined to the target's own prefix: without that check any caller could pass
  another entity's key (or any object in the bucket) and have it adopted as
  their icon.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  alias GameServer.Storage

  @doc """
  Issues a presigned upload ticket for `prefix/owner_id/<random><ext>`, after
  checking the declared content type is one the server accepts.
  """
  @spec ticket(Plug.Conn.t(), String.t(), String.t(), String.t(), String.t()) :: Plug.Conn.t()
  def ticket(conn, prefix, owner_id, stem, content_type) do
    case Storage.validate_upload(content_type, 0) do
      :ok ->
        key = Storage.build_key(prefix, owner_id, stem <> Storage.extension_for(content_type))
        {:ok, ticket} = Storage.presigned_upload(key, content_type: content_type)
        json(conn, ticket)

      {:error, reason} ->
        error(conn, :bad_request, to_string(reason))
    end
  end

  @doc """
  Validates a client-supplied `key` against `prefix/owner_id/` and confirms the
  object exists, then calls `fun` with its public URL to persist.
  """
  @spec confirm(Plug.Conn.t(), String.t(), String.t(), term(), (String.t() -> Plug.Conn.t())) ::
          Plug.Conn.t()
  def confirm(conn, prefix, owner_id, key, fun) when is_binary(key) do
    cond do
      not String.starts_with?(key, "#{prefix}/#{owner_id}/") ->
        error(conn, :forbidden, "forbidden")

      not Storage.exists?(key) ->
        error(conn, :bad_request, "object_not_found")

      true ->
        fun.(Storage.url(key))
    end
  end

  def confirm(conn, _prefix, _owner_id, _key, _fun), do: error(conn, :bad_request, "missing_key")

  @doc "The content type a client declared, as a string."
  @spec content_type(map()) :: String.t()
  def content_type(params), do: params["content_type"] || ""

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
