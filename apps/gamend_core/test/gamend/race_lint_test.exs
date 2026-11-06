defmodule Gamend.RaceLintTest do
  use ExUnit.Case, async: true

  alias Gamend.RaceLint

  defp rules(source), do: source |> RaceLint.violations_in("x.ex") |> Enum.map(& &1.rule)

  describe "RACE1-transition-by-struct" do
    test "flags a status written with Repo.update on a struct" do
      assert rules("""
             defmodule M do
               def accept(id) do
                 request = Repo.get(Request, id)
                 if request.status == "pending" do
                   request |> Ecto.Changeset.change(%{status: "accepted"}) |> Repo.update()
                 end
               end
             end
             """) == ["RACE1-transition-by-struct"]
    end

    test "accepts the transition written as compare_and_set" do
      assert rules("""
             defmodule M do
               def accept(id) do
                 from(r in Request, where: r.id == ^id and r.status == "pending")
                 |> Repo.compare_and_set(set: [status: "accepted"])
               end
             end
             """) == []
    end

    test "accepts it inside Lock.serialize, and a plain field write" do
      assert rules("""
             defmodule M do
               def accept(request) do
                 Lock.serialize(:request, request.id, fn ->
                   request |> change(status: "accepted") |> Repo.update()
                 end)
               end

               def rename(request), do: request |> change(title: "x") |> Repo.update()
             end
             """) == []
    end
  end

  describe "RACE2-count-then-insert" do
    test "flags a count and an insert with no lock" do
      assert rules("""
             defmodule M do
               def create(user, attrs) do
                 if count_tokens(user) < Limits.get(:max_tokens) do
                   Repo.insert(Token.changeset(%Token{}, attrs))
                 end
               end
             end
             """) == ["RACE2-count-then-insert"]
    end
  end

  describe "RACE3-cached-gate" do
    test "flags a cached user's field deciding a write" do
      assert rules("""
             defmodule M do
               def seat(user_id, lobby_id) do
                 user = Accounts.get_user(user_id)
                 if is_nil(user.lobby_id) do
                   Repo.update_all(where(User, id: ^user_id), set: [lobby_id: lobby_id])
                 end
               end
             end
             """) == ["RACE3-cached-gate"]
    end

    test "ignores a cached read used only for display" do
      assert rules("""
             defmodule M do
               def notify(user_id) do
                 user = Accounts.get_user(user_id)
                 Repo.insert(%Notice{text: user.display_name})
               end
             end
             """) == []
    end
  end

  test "a race-safe marker with its reason accepts the function" do
    assert rules("""
           defmodule M do
             def accept(request) do
               # race-safe: only called inside accept_all's (:request, id) lock
               request |> change(status: "accepted") |> Repo.update()
             end
           end
           """) == []
  end

  test "a host's own lock helper counts as a guard" do
    source = """
    defmodule M do
      def accept(request) do
        GameCommon.with_user_lock(request.user_id, fn ->
          request |> change(status: "accepted") |> Repo.update()
        end)
      end
    end
    """

    assert [_] = RaceLint.violations_in(source, "x.ex")
    assert [] = RaceLint.violations_in(source, "x.ex", [{:GameCommon, :with_user_lock}])
  end

  test "a call to a guarded helper of the same file counts as a guard, through helpers" do
    source = """
    defmodule M do
      def accept(request) do
        with_pair(request, fn ->
          request |> change(status: "accepted") |> Repo.update()
        end)
      end

      defp with_pair(request, fun), do: in_lock(request.pair, fun)

      defp in_lock(key, fun), do: Lock.serialize(:pair, key, fun)
    end
    """

    assert [] = RaceLint.violations_in(source, "x.ex")

    unguarded = String.replace(source, "Lock.serialize(:pair, key, fun)", "fun.()")
    assert ["RACE1-transition-by-struct"] = rules(unguarded)
  end
end
