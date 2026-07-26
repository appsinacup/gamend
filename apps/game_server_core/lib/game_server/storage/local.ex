defmodule GameServer.Storage.Local do
  @moduledoc """
  Disk-backed storage — the default backend.

  Files live under `STORAGE_LOCAL_DIR` (default `priv/storage`). Readable URLs
  and upload tickets point at the app itself. The upload endpoint is protected
  by the caller's own auth plus a namespace check (a client may only write keys
  under its own id), so the client flow matches S3 without a separate signed
  token — an S3 presigned `PUT` simply ignores the extra auth header.
  """

  @behaviour GameServer.Storage.Adapter

  # How long an upload ticket is nominally valid (seconds) — advisory for clients.
  @upload_ttl 600

  @impl true
  def put(key, data, _opts) do
    path = path_for(key)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, data) do
      {:ok, key}
    end
  end

  @impl true
  def get(key), do: File.read(path_for(key))

  @impl true
  def delete(key) do
    case File.rm(path_for(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(key), do: File.exists?(path_for(key))

  @impl true
  def url(key, _opts), do: "#{base_url()}/storage/#{key}"

  @impl true
  def presigned_upload(key, opts) do
    content_type = Keyword.get(opts, :content_type)
    headers = if content_type, do: %{"content-type" => content_type}, else: %{}

    {:ok,
     %{
       method: "PUT",
       url: "#{base_url()}/storage/upload?key=#{URI.encode_www_form(key)}",
       headers: headers,
       key: key,
       expires_in: @upload_ttl
     }}
  end

  @impl true
  def list(opts) do
    prefix = Keyword.get(opts, :prefix) || ""
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 50)

    all_objects(prefix)
    |> Enum.sort_by(& &1.key)
    |> Enum.slice(offset, limit)
  end

  @impl true
  def usage(opts \\ []) do
    prefix = Keyword.get(opts, :prefix) || ""
    objects = all_objects(prefix)
    %{count: length(objects), bytes: Enum.reduce(objects, 0, &(&1.size + &2))}
  end

  defp all_objects(prefix) do
    root = root_dir()

    if File.dir?(root) do
      root
      |> walk()
      |> Enum.map(fn path ->
        key = Path.relative_to(path, root)
        stat = File.stat!(path, time: :posix)
        %{key: key, size: stat.size, last_modified: DateTime.from_unix!(stat.mtime)}
      end)
      |> Enum.filter(&String.starts_with?(&1.key, prefix))
    else
      []
    end
  end

  defp walk(path) do
    cond do
      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.flat_map(fn entry -> walk(Path.join(path, entry)) end)

      File.regular?(path) ->
        [path]

      true ->
        []
    end
  end

  @doc false
  # Absolute path for a key, with traversal components stripped so a crafted key
  # cannot escape the storage root.
  def path_for(key) do
    safe =
      key
      |> Path.split()
      |> Enum.reject(&(&1 in ["", ".", "..", "/"]))
      |> Path.join()

    Path.join(root_dir(), safe)
  end

  defp root_dir do
    case config()[:dir] do
      nil -> Path.join(to_string(:code.priv_dir(:game_server_core)), "storage")
      dir -> dir
    end
  end

  # Declared so the values are documented and env-fed; the reads below stay as
  # they are, because a setting resolves into exactly the app-env key they
  # already look at.
  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :storage,
    label: "Storage"

  setting(:dir, :string,
    default: "priv/storage",
    doc: "Directory the local adapter writes objects to."
  )

  defp base_url, do: GameServer.Settings.get(GameServer.Storage, :public_url) || ""

  defp config, do: Application.get_env(:game_server_core, __MODULE__, [])
end
