defmodule GamendWeb.Api.V1.ChatModerationControllerTest do
  # async: false — the blocklist and mute tables are named public ETS tables
  # shared by the whole VM, so a concurrent test would see this one's mutes.
  use GamendWeb.ConnCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Chat
  alias Gamend.Chat.Message
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.Moderation.Cache
  alias Gamend.Groups
  alias Gamend.Lobbies
  alias Gamend.Parties
  alias Gamend.Repo
  alias GamendWeb.Auth.Guardian

  setup do
    Cache.init_table()
    on_exit(fn -> reset_cache() end)
    reset_cache()
    :ok
  end

  defp reset_cache do
    :ets.delete_all_objects(:chat_filter_words)
    # Mutes are chat bans; the test process may own the table and be gone.
    if :ets.whereis(:bans) != :undefined, do: :ets.delete_all_objects(:bans)
    :persistent_term.erase({Cache, :substring_pattern})
    :ok
  end

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp create_user, do: AccountsFixtures.user_fixture()

  defp insert_message(sender, chat_ref_id, content) do
    %Message{sender_id: sender.id}
    |> Message.changeset(%{chat_type: "lobby", chat_ref_id: chat_ref_id, content: content})
    |> Repo.insert!()
  end

  defp hosted_lobby(title) do
    host = create_user()
    member = create_user()
    {:ok, lobby} = Lobbies.create_lobby(%{title: title, host_id: host.id})
    {:ok, _} = Lobbies.join_lobby(member, lobby)

    %{host: host, member: member, lobby: lobby}
  end

  defp hostless_lobby(title) do
    member = create_user()
    {:ok, lobby} = Lobbies.create_lobby(%{title: title, hostless: true})
    {:ok, _} = Lobbies.join_lobby(member, lobby)

    %{member: member, lobby: lobby}
  end

  defp admin_group(title) do
    owner = create_user()
    admin = create_user()
    member = create_user()

    {:ok, group} = Groups.create_group(owner.id, %{"title" => title, "type" => "public"})
    {:ok, _} = Groups.join_group(admin.id, group.id)
    {:ok, _} = Groups.promote_member(owner.id, group.id, admin.id)
    {:ok, _} = Groups.join_group(member.id, group.id)

    %{admin: admin, member: member, group: group}
  end

  defp led_party do
    leader = create_user()
    member = create_user()
    {:ok, party} = Parties.create_party(leader, %{})
    member |> Ecto.Changeset.change(%{party_id: party.id}) |> Repo.update!()

    %{leader: leader, member: member, party: party}
  end

  describe "POST /api/v1/chat/messages/:id/report" do
    setup do
      # Both users are in the lobby the message belongs to. Reporting requires
      # being able to read the message, so a message in a lobby nobody is in is
      # not reportable by anyone — which is the point, but makes for a fixture
      # that does not exercise the endpoint.
      host = create_user()

      {:ok, lobby} =
        Lobbies.create_lobby(%{
          title: "report-#{System.unique_integer([:positive])}",
          host_id: host.id
        })

      reporter = create_user()
      sender = create_user()
      {:ok, _} = Lobbies.join_lobby(reporter, lobby)
      {:ok, _} = Lobbies.join_lobby(sender, lobby)

      message = insert_message(sender, lobby.id, "something rude")

      %{reporter: reporter, sender: sender, message: message, lobby: lobby}
    end

    test "refuses to report a message the caller cannot read" do
      outsider = create_user()
      stranger = create_user()
      unrelated = insert_message(stranger, Ecto.UUID.generate(), "not your conversation")

      conn =
        Phoenix.ConnTest.build_conn()
        |> auth_conn(outsider)
        |> post("/api/v1/chat/messages/#{unrelated.id}/report", %{reason: "abusive"})

      assert json_response(conn, 404)["error"] == "not_found"
      assert Chat.count_reports() == 0
    end

    test "files a report for another player's message", %{
      conn: conn,
      reporter: reporter,
      sender: sender,
      message: message
    } do
      conn =
        conn
        |> auth_conn(reporter)
        |> post("/api/v1/chat/messages/#{message.id}/report", %{reason: "abusive"})

      assert json_response(conn, 200) == %{"ok" => true}

      assert [report] = Chat.list_reports(%{"reporter_id" => reporter.id})
      assert report.status == "open"
      assert report.reason == "abusive"
      assert report.reported_user_id == sender.id
      assert report.content_snapshot == "something rude"
    end

    test "rejects reporting your own message", %{conn: conn, sender: sender, message: message} do
      conn =
        conn
        |> auth_conn(sender)
        |> post("/api/v1/chat/messages/#{message.id}/report", %{reason: "oops"})

      assert json_response(conn, 400)["error"] == "own_message"
      assert Chat.count_reports() == 0
    end

    test "rejects a second report of the same message", %{
      conn: conn,
      reporter: reporter,
      message: message
    } do
      path = "/api/v1/chat/messages/#{message.id}/report"

      assert conn |> auth_conn(reporter) |> post(path, %{}) |> json_response(200)

      conn = conn |> auth_conn(reporter) |> post(path, %{reason: "again"})

      assert json_response(conn, 409)["error"] == "already_reported"
      assert Chat.count_reports() == 1
    end

    test "returns 404 for an unknown message", %{conn: conn, reporter: reporter} do
      conn =
        conn
        |> auth_conn(reporter)
        |> post("/api/v1/chat/messages/#{Ecto.UUID.generate()}/report", %{})

      assert json_response(conn, 404)["error"] == "not_found"
    end

    test "returns 400 for a malformed message id", %{conn: conn, reporter: reporter} do
      conn =
        conn
        |> auth_conn(reporter)
        |> post("/api/v1/chat/messages/not-a-uuid/report", %{})

      assert json_response(conn, 400)["error"] == "invalid_id"
    end
  end

  describe "POST /api/v1/lobbies/mute" do
    test "the host mutes a member of their own lobby", %{conn: conn} do
      %{host: host, member: member, lobby: lobby} = hosted_lobby("mute-lobby-host")

      conn =
        conn
        |> auth_conn(host)
        |> post("/api/v1/lobbies/mute", %{target_user_id: member.id})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["user_id"] == member.id
      assert data["scope"] == "lobby"
      assert data["scope_ref_id"] == lobby.id
      assert data["muted_by"] == host.id

      assert Chat.muted?(member.id, "lobby", lobby.id)
      refute Chat.muted?(member.id, "lobby", Ecto.UUID.generate())
      refute Chat.muted?(host.id, "lobby", lobby.id)

      listed =
        build_conn() |> auth_conn(host) |> get("/api/v1/lobbies/mutes") |> json_response(200)

      assert Enum.map(listed["data"], & &1["user_id"]) == [member.id]
    end

    test "a plain member cannot mute", %{conn: conn} do
      %{member: member, lobby: lobby} = hosted_lobby("mute-lobby-member")
      other = create_user()
      {:ok, _} = Lobbies.join_lobby(other, lobby)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/lobbies/mute", %{target_user_id: other.id})

      assert json_response(conn, 403)["error"] == "not_host"
      refute Chat.muted?(other.id, "lobby", lobby.id)
    end

    test "the pinned WebRTC host of a hostless lobby may mute", %{conn: conn} do
      %{member: member, lobby: lobby} = hostless_lobby("mute-lobby-pinned")
      other = create_user()
      {:ok, _} = Lobbies.join_lobby(other, lobby)

      {:ok, _} =
        Gamend.Signaling.configure(lobby, enabled: true, topology: :star, host_id: member.id)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/lobbies/mute", %{target_user_id: other.id})

      assert json_response(conn, 200)
      assert Chat.muted?(other.id, "lobby", lobby.id)
    end

    test "nobody may mute in a hostless lobby", %{conn: conn} do
      %{member: member, lobby: lobby} = hostless_lobby("mute-lobby-hostless")
      other = create_user()
      {:ok, _} = Lobbies.join_lobby(other, lobby)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/lobbies/mute", %{target_user_id: other.id})

      assert json_response(conn, 403)["error"] == "not_host"
      refute Chat.muted?(other.id, "lobby", lobby.id)
    end
  end

  describe "POST /api/v1/lobbies/unmute" do
    test "the host lifts a mute in their own lobby", %{conn: conn} do
      %{host: host, member: member, lobby: lobby} = hosted_lobby("unmute-lobby-host")
      {:ok, _} = Chat.mute_user(member.id, "lobby", lobby.id)

      conn =
        conn
        |> auth_conn(host)
        |> post("/api/v1/lobbies/unmute", %{target_user_id: member.id})

      assert %{"data" => %{"deleted" => 1}} = json_response(conn, 200)
      refute Chat.muted?(member.id, "lobby", lobby.id)
    end

    test "a plain member cannot unmute", %{conn: conn} do
      %{member: member, lobby: lobby} = hosted_lobby("unmute-lobby-member")
      other = create_user()
      {:ok, _} = Lobbies.join_lobby(other, lobby)
      {:ok, _} = Chat.mute_user(other.id, "lobby", lobby.id)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/lobbies/unmute", %{target_user_id: other.id})

      assert json_response(conn, 403)["error"] == "not_host"
      assert Chat.muted?(other.id, "lobby", lobby.id)
    end
  end

  describe "POST /api/v1/groups/:id/mute" do
    test "a group admin mutes a member", %{conn: conn} do
      %{admin: admin, member: member, group: group} = admin_group("mute-group-admin")

      conn =
        conn
        |> auth_conn(admin)
        |> post("/api/v1/groups/#{group.id}/mute", %{target_user_id: member.id})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["user_id"] == member.id
      assert data["scope"] == "group"
      assert data["scope_ref_id"] == group.id

      assert Chat.muted?(member.id, "group", group.id)
      refute Chat.muted?(member.id, "group", Ecto.UUID.generate())

      listed =
        build_conn()
        |> auth_conn(admin)
        |> get("/api/v1/groups/#{group.id}/mutes")
        |> json_response(200)

      assert Enum.map(listed["data"], & &1["user_id"]) == [member.id]
    end

    test "a plain member cannot mute", %{conn: conn} do
      %{member: member, group: group} = admin_group("mute-group-member")
      other = create_user()
      {:ok, _} = Groups.join_group(other.id, group.id)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/groups/#{group.id}/mute", %{target_user_id: other.id})

      assert json_response(conn, 403)["error"] == "not_group_admin"
      refute Chat.muted?(other.id, "group", group.id)
    end
  end

  describe "POST /api/v1/groups/:id/unmute" do
    test "a group admin lifts a mute", %{conn: conn} do
      %{admin: admin, member: member, group: group} = admin_group("unmute-group-admin")
      {:ok, _} = Chat.mute_user(member.id, "group", group.id)

      conn =
        conn
        |> auth_conn(admin)
        |> post("/api/v1/groups/#{group.id}/unmute", %{target_user_id: member.id})

      assert %{"data" => %{"deleted" => 1}} = json_response(conn, 200)
      refute Chat.muted?(member.id, "group", group.id)
    end

    test "a plain member cannot unmute", %{conn: conn} do
      %{member: member, group: group} = admin_group("unmute-group-member")
      other = create_user()
      {:ok, _} = Groups.join_group(other.id, group.id)
      {:ok, _} = Chat.mute_user(other.id, "group", group.id)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/groups/#{group.id}/unmute", %{target_user_id: other.id})

      assert json_response(conn, 403)["error"] == "not_group_admin"
      assert Chat.muted?(other.id, "group", group.id)
    end
  end

  describe "POST /api/v1/parties/mute" do
    test "the leader mutes a member", %{conn: conn} do
      %{leader: leader, member: member, party: party} = led_party()

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/mute", %{target_user_id: member.id})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["user_id"] == member.id
      assert data["scope"] == "party"
      assert data["scope_ref_id"] == party.id

      assert Chat.muted?(member.id, "party", party.id)
      refute Chat.muted?(member.id, "party", Ecto.UUID.generate())

      listed =
        build_conn() |> auth_conn(leader) |> get("/api/v1/parties/mutes") |> json_response(200)

      assert Enum.map(listed["data"], & &1["user_id"]) == [member.id]
    end

    test "a plain member cannot mute", %{conn: conn} do
      %{member: member, party: party} = led_party()
      other = create_user()
      other |> Ecto.Changeset.change(%{party_id: party.id}) |> Repo.update!()

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/parties/mute", %{target_user_id: other.id})

      assert json_response(conn, 403)["error"] == "not_leader"
      refute Chat.muted?(other.id, "party", party.id)
    end
  end

  describe "POST /api/v1/parties/unmute" do
    test "the leader lifts a mute", %{conn: conn} do
      %{leader: leader, member: member, party: party} = led_party()
      {:ok, _} = Chat.mute_user(member.id, "party", party.id)

      conn =
        conn
        |> auth_conn(leader)
        |> post("/api/v1/parties/unmute", %{target_user_id: member.id})

      assert %{"data" => %{"deleted" => 1}} = json_response(conn, 200)
      refute Chat.muted?(member.id, "party", party.id)
    end

    test "a plain member cannot unmute", %{conn: conn} do
      %{member: member, party: party} = led_party()
      other = create_user()
      other |> Ecto.Changeset.change(%{party_id: party.id}) |> Repo.update!()
      {:ok, _} = Chat.mute_user(other.id, "party", party.id)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/parties/unmute", %{target_user_id: other.id})

      assert json_response(conn, 403)["error"] == "not_leader"
      assert Chat.muted?(other.id, "party", party.id)
    end
  end

  describe "timed mutes" do
    test "stores the expiry and keeps the mute active until then", %{conn: conn} do
      %{host: host, member: member, lobby: lobby} = hosted_lobby("timed-mute-active")
      expires_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      conn =
        conn
        |> auth_conn(host)
        |> post("/api/v1/lobbies/mute", %{
          target_user_id: member.id,
          expires_at: DateTime.to_iso8601(expires_at)
        })

      assert %{"data" => %{"expires_at" => stored}} = json_response(conn, 200)
      assert {:ok, ^expires_at, 0} = DateTime.from_iso8601(stored)

      assert Chat.muted?(member.id, "lobby", lobby.id)
      assert [mute] = Chat.list_mutes(%{"user_id" => member.id})
      assert mute.expires_at == expires_at
    end

    # Expiry is checked on every read, so a timestamp already in the past is the
    # same state as one that lapsed while the server was running.
    test "a mute whose expiry has already passed is refused, and does not apply", %{conn: conn} do
      %{host: host, member: member, lobby: lobby} = hosted_lobby("timed-mute-lapsed")
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      conn =
        conn
        |> auth_conn(host)
        |> post("/api/v1/lobbies/mute", %{
          target_user_id: member.id,
          expires_at: DateTime.to_iso8601(past)
        })

      assert %{"errors" => %{"expires_at" => ["must be in the future"]}} =
               json_response(conn, 422)

      refute Chat.muted?(member.id, "lobby", lobby.id)
    end
  end

  describe "POST /api/v1/chat/messages refused by moderation" do
    test "a muted sender answers 403 muted", %{conn: conn} do
      %{member: member, lobby: lobby} = hostless_lobby("muted-send")
      {:ok, _} = Chat.mute_user(member.id, "lobby", lobby.id)

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/chat/messages", %{
          chat_type: "lobby",
          chat_ref_id: lobby.id,
          content: "let me talk"
        })

      assert json_response(conn, 403)["error"] == "muted"
    end

    test "a blocked word answers 422 blocked_content", %{conn: conn} do
      %{member: member, lobby: lobby} = hostless_lobby("filtered-send")

      {:ok, _} =
        Moderation.create_filter_word(%{"word" => "grief", "severity" => "block"})

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/chat/messages", %{
          chat_type: "lobby",
          chat_ref_id: lobby.id,
          content: "good grief"
        })

      assert json_response(conn, 422)["error"] == "blocked_content"
    end
  end
end
