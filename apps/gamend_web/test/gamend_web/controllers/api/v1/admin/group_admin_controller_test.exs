defmodule GamendWeb.Api.V1.Admin.GroupAdminControllerTest.HooksRefuse do
  def before_group_update(_group, _attrs), do: {:error, :update_blocked}
  def before_group_delete(_group), do: {:error, "The hall is closed"}
end

defmodule GamendWeb.Api.V1.Admin.GroupAdminControllerTest do
  # Admin groups. Every answer here also passes `GamendWeb.ResponseContract`.
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    {:ok, admin} = Accounts.update_user(AccountsFixtures.user_fixture(), %{is_admin: true})
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    owner = AccountsFixtures.user_fixture()

    {:ok, group} =
      Groups.create_group(owner.id, %{
        "title" => "admin-group-#{System.unique_integer([:positive])}",
        "type" => "hidden"
      })

    %{admin_conn: put_req_header(conn, "authorization", "Bearer " <> token), group: group}
  end

  test "lists every group, hidden ones included", ctx do
    body =
      ctx.admin_conn |> get("/api/v1/admin/groups", %{type: "hidden"}) |> json_response(200)

    assert Enum.any?(body["data"], &(&1["id"] == ctx.group.id))
    assert body["meta"]["total_count"] >= 1
  end

  test "update answers the group under data", ctx do
    body =
      ctx.admin_conn
      |> patch("/api/v1/admin/groups/#{ctx.group.id}", %{description: "curated", slowdown: 5})
      |> json_response(200)

    assert %{"id" => id, "description" => "curated", "slowdown" => 5} = body["data"]
    assert id == ctx.group.id
  end

  test "delete", ctx do
    assert ctx.admin_conn |> delete("/api/v1/admin/groups/#{ctx.group.id}") |> json_response(200) ==
             %{"ok" => true}

    resp = ctx.admin_conn |> delete("/api/v1/admin/groups/#{ctx.group.id}") |> json_response(404)
    assert resp["error"] == "not_found"
  end

  describe "a game hook's veto" do
    setup do
      original = Application.get_env(:gamend_core, :hooks_module)

      on_exit(fn ->
        if original,
          do: Application.put_env(:gamend_core, :hooks_module, original),
          else: Application.delete_env(:gamend_core, :hooks_module)
      end)

      Application.put_env(
        :gamend_core,
        :hooks_module,
        GamendWeb.Api.V1.Admin.GroupAdminControllerTest.HooksRefuse
      )
    end

    # The update answered 500: only a changeset had a clause.
    test "of an update is 403 rejected", ctx do
      assert %{"error" => "rejected", "message" => ":update_blocked"} =
               ctx.admin_conn
               |> patch("/api/v1/admin/groups/#{ctx.group.id}", %{description: "nope"})
               |> json_response(403)
    end

    test "of a delete is 403 rejected with the hook's words", ctx do
      assert %{"error" => "rejected", "message" => "The hall is closed"} =
               ctx.admin_conn
               |> delete("/api/v1/admin/groups/#{ctx.group.id}")
               |> json_response(403)

      assert Groups.get_group(ctx.group.id)
    end
  end
end
