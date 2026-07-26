defmodule GameServer.Accounts.AvatarMirrorTest do
  use GameServer.DataCase, async: false
  use Oban.Testing, repo: GameServer.Repo

  import GameServer.AccountsFixtures

  alias GameServer.Accounts
  alias GameServer.Accounts.AvatarMirror
  alias GameServer.Storage

  # Enough of a PNG to be distinct bytes; the worker doesn't parse the image.
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>

  setup do
    dir = Path.join(System.tmp_dir!(), "gs_avatar_mirror_#{System.unique_integer([:positive])}")
    old = Application.get_env(:game_server_core, GameServer.Storage.Local)
    Application.put_env(:game_server_core, GameServer.Storage.Local, dir: dir)

    Application.put_env(:game_server_core, :avatar_mirror_req_options,
      plug: {Req.Test, __MODULE__}
    )

    on_exit(fn ->
      File.rm_rf(dir)

      if old,
        do: Application.put_env(:game_server_core, GameServer.Storage.Local, old),
        else: Application.delete_env(:game_server_core, GameServer.Storage.Local)

      Application.delete_env(:game_server_core, :avatar_mirror_req_options)
    end)

    :ok
  end

  test "downloads the provider avatar into our storage and repoints profile_url" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("image/png")
      |> Plug.Conn.send_resp(200, @png)
    end)

    source = "https://cdn.provider.example/avatars/abc.png"
    {:ok, user} = Accounts.update_user_avatar(user_fixture(), source)

    assert :ok =
             AvatarMirror.perform(%Oban.Job{
               args: %{"user_id" => user.id, "source_url" => source}
             })

    reloaded = Accounts.get_user(user.id)
    # profile_url now points at our own storage, namespaced under the user.
    assert reloaded.profile_url =~ "avatars/#{user.id}"

    key = String.replace_leading(reloaded.profile_url, "/storage/", "")
    assert {:ok, @png} = Storage.get(key)
  end

  test "leaves the avatar alone if the user changed it since enqueue" do
    {:ok, user} = Accounts.update_user_avatar(user_fixture(), "/storage/avatars/custom.png")

    assert :ok =
             AvatarMirror.perform(%Oban.Job{
               args: %{"user_id" => user.id, "source_url" => "https://provider.example/old.png"}
             })

    assert Accounts.get_user(user.id).profile_url == "/storage/avatars/custom.png"
  end

  test "creating an OAuth user with a provider avatar enqueues one mirror job" do
    {:ok, user} =
      Accounts.find_or_create_from_discord(%{
        discord_id: "disc-#{System.unique_integer([:positive])}",
        email: unique_user_email(),
        profile_url: "https://cdn.discordapp.com/avatars/123/hash.png"
      })

    assert_enqueued(worker: AvatarMirror, args: %{"user_id" => user.id})
  end
end
