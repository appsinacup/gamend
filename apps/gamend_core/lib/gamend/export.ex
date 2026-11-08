defmodule Gamend.Export do
  @moduledoc """
  A host's data as files another host can start from: what only the
  application can copy.

    * `gamend.db`: a SQLite database, whole and consistent while the server
      runs (`VACUUM INTO`).
    * `files.tar`: what the local storage adapter holds, `storage/` inside.

  Nothing else, on purpose. A Postgres database needs `pg_dump` of the
  server's major, which the database's container has and the application's
  image does not. Objects on S3 are already off the host. `.env` is a file
  on the host, which a running application does not have.
  `./rebuild.sh --export DIR` (`deploy/gamend-deploy`) gets those and calls
  this for the rest. `Gamend.Release.export/2` is the way in from a shell.
  """

  alias Gamend.Storage

  @database "gamend.db"
  @files "files.tar"

  @doc """
  Writes the files into `dir`, made if missing and private to this user, and
  answers the names it wrote. `files: false` leaves the stored files out, for
  a host whose folders move with it. A running server goes on serving.
  """
  @spec write(Path.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def write(dir, opts \\ []) do
    dir = Path.expand(dir)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(dir, 0o700),
         {:ok, database} <- database(dir),
         {:ok, files} <- files(dir, Keyword.get(opts, :files, true)) do
      {:ok, database ++ files}
    end
  end

  @doc "Whether this host's database is one `write/2` copies: SQLite."
  @spec database?() :: boolean()
  def database?, do: not Gamend.Repo.AdvisoryLock.postgres?()

  defp database(dir) do
    if database?(), do: vacuum_into(Path.join(dir, @database)), else: {:ok, []}
  end

  # VACUUM INTO refuses a file that exists, and a part file is never taken
  # for the whole.
  defp vacuum_into(path) do
    part = path <> ".part"
    _ = File.rm(part)

    case Gamend.Repo.query("VACUUM INTO ?1", [part]) do
      {:ok, _result} -> finish(part, path)
      {:error, error} -> {:error, {:database, Exception.message(error)}}
    end
  end

  defp files(_dir, false), do: {:ok, []}

  defp files(dir, true) do
    root = Path.expand(Storage.Local.root_dir())

    if Storage.adapter() == Storage.Local and match?({:ok, [_ | _]}, File.ls(root)),
      do: tar(root, dir),
      else: {:ok, []}
  end

  # `storage/` inside whatever the folder is called, through a link tar
  # follows: what a Gamend Cloud server's own export holds.
  defp tar(root, dir) do
    links = Path.join(dir, ".links")
    path = Path.join(dir, @files)
    part = path <> ".part"

    try do
      with {:ok, tar} <- tar_executable(),
           :ok <- File.mkdir_p(links),
           :ok <- File.ln_s(root, Path.join(links, "storage")) do
        case System.cmd(tar, ["-chf", part, "-C", links, "storage"], stderr_to_stdout: true) do
          {_out, 0} -> finish(part, path)
          {out, status} -> {:error, {:tar, status, out}}
        end
      end
    after
      _ = File.rm_rf(links)
    end
  end

  defp tar_executable do
    case System.find_executable("tar") do
      nil -> {:error, :tar_not_found}
      tar -> {:ok, tar}
    end
  end

  defp finish(part, path) do
    with :ok <- File.chmod(part, 0o600),
         :ok <- File.rename(part, path) do
      {:ok, [Path.basename(path)]}
    end
  end
end
