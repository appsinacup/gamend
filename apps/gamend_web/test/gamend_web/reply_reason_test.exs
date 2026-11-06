defmodule GamendWeb.ReplyReasonTest do
  # `reply_reason/2` and the table behind it: what a controller answers for
  # the reasons it does not match itself.
  use ExUnit.Case, async: true

  import GamendWeb.Reply

  alias GamendWeb.ErrorStatus
  alias Plug.Conn.Status

  defp reply(reason) do
    conn = Plug.Test.conn(:post, "/api/v1/things") |> reply_reason(reason)
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  test "an atom answers with its name and the status the table gives it" do
    assert reply(:not_in_party) == {404, %{"error" => "not_in_party"}}
    assert reply(:full) == {403, %{"error" => "full"}}
    assert reply(:state_changed) == {409, %{"error" => "state_changed"}}
  end

  test "a name the rules cover needs no line in the table" do
    assert reply(:lobby_not_found) == {404, %{"error" => "lobby_not_found"}}
    assert reply(:already_queued) == {409, %{"error" => "already_queued"}}

    assert reply(:purchase_already_in_progress) ==
             {409, %{"error" => "purchase_already_in_progress"}}

    assert reply(:steam_not_configured) == {503, %{"error" => "steam_not_configured"}}
  end

  test "a game hook's veto is 403 rejected, its words the message" do
    assert reply({:hook_rejected, "season over"}) ==
             {403, %{"error" => "rejected", "message" => "season over"}}

    assert reply({:hook_rejected, :closed}) ==
             {403, %{"error" => "rejected", "message" => ":closed"}}
  end

  test "a failed changeset is validation_failed" do
    changeset =
      {%{}, %{title: :string}}
      |> Ecto.Changeset.cast(%{}, [:title])
      |> Ecto.Changeset.validate_required([:title])

    assert {422, %{"error" => "validation_failed", "errors" => %{"title" => [_]}}} =
             reply(changeset)
  end

  test "a reason with no status raises and names it" do
    assert_raise GamendWeb.UnmappedReason, ~r/:no_such_reason/, fn -> reply(:no_such_reason) end
    assert_raise GamendWeb.UnmappedReason, ~r/"some text"/, fn -> reply("some text") end
    assert_raise GamendWeb.UnmappedReason, fn -> reply(nil) end
  end

  test "words that mean different things in different places have no status" do
    for reason <- [:invalid, :missing, :disabled, :unavailable] do
      assert ErrorStatus.status(reason) == nil
    end
  end

  test "every status in the table is one Plug knows" do
    for {_reason, status} <- ErrorStatus.statuses() do
      assert is_integer(Status.code(status))
    end
  end
end
