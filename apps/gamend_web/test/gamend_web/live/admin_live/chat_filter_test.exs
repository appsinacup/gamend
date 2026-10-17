defmodule GamendWeb.AdminLive.ChatFilterTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.Moderation.Cache
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    on_exit(fn -> Cache.reload_words() end)
    %{admin: admin}
  end

  defp page(conn, admin, path \\ ~p"/admin/chat/filter") do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(path)
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp word(text),
    do: Enum.find(Moderation.list_filter_words(%{"word" => text}), &(&1.word == text))

  defp add(view, text, attrs \\ %{}) do
    view
    |> form(
      "#chat-filter-word-form",
      Map.merge(%{"word" => text, "severity" => "block", "match_mode" => "substring"}, attrs)
    )
    |> render_change()

    view |> element("#chat-filter-word-form button[phx-click=save_word]") |> render_click()
  end

  test "a word added is listed, blocks a phrase in the test box, and is deleted from its row", %{
    conn: conn,
    admin: admin
  } do
    view = page(conn, admin)
    add(view, "zorpfluxen")

    saved = word("zorpfluxen")
    assert has_element?(view, "#filter-word-#{saved.id}")

    view |> form("#chat-filter-test-form", %{"phrase" => "you zorpfluxen!"}) |> render_change()
    assert assigns(view).test_result

    render_click(view, "delete_word", %{"id" => saved.id})
    refute word("zorpfluxen")
    refute has_element?(view, "#filter-word-#{saved.id}")
  end

  test "a word is edited in place; cancel leaves the form blank", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    add(view, "grumpwizet")
    saved = word("grumpwizet")

    render_click(view, "edit_word", %{"id" => saved.id})
    assert assigns(view).word_form["id"] == saved.id
    render_change(view, "word_form_change", %{"severity" => "mask", "match_mode" => "exact"})
    render_submit(view, "save_word", %{})
    assert word("grumpwizet").severity == "mask"

    render_click(view, "edit_word", %{"id" => saved.id})
    render_click(view, "cancel_edit", %{})
    assert assigns(view).word_form["id"] == nil
  end

  test "an empty word, or a word that no longer exists, is refused", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    before = length(Moderation.list_filter_words())
    add(view, "   ")
    assert length(Moderation.list_filter_words()) == before

    render_click(view, "edit_word", %{"id" => Ecto.UUID.generate()})
    render_click(view, "delete_word", %{"id" => Ecto.UUID.generate()})
    assert assigns(view).word_form["id"] == nil
  end

  test "the filters narrow the list by word and severity", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    add(view, "zarfplonkiq", %{"severity" => "flag"})

    view
    |> form("#chat-filter-filters", %{"word" => "zarfplonk", "severity" => "flag"})
    |> render_change()

    assert Enum.map(assigns(view).words, & &1.word) == ["zarfplonkiq"]

    render_change(view, "filter", %{"word" => "zarfplonk", "severity" => "block"})
    assert assigns(view).words == []
  end

  test "a bundled list is imported and removed", %{conn: conn, admin: admin} do
    view = page(conn, admin)

    case Moderation.bundled_languages() do
      [] ->
        render_submit(view, "import_list", %{})

      [lang | _] ->
        view
        |> form("#chat-filter-import-form", %{"lang" => lang, "severity" => "flag"})
        |> render_change()

        render_submit(view, "import_list", %{})
        assert Moderation.list_filter_words(%{"lang" => lang}) != []

        render_click(view, "remove_list", %{})
        assert Moderation.list_filter_words(%{"lang" => lang}) == []
    end
  end

  test "an unknown bundled language is said, nothing imported", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    before = length(Moderation.list_filter_words())
    render_change(view, "import_change", %{"lang" => "zz-none"})
    render_submit(view, "import_list", %{})
    assert length(Moderation.list_filter_words()) == before
  end

  test "a word in the URL fills the form; an empty phrase tests nothing; the pager works", %{
    conn: conn,
    admin: admin
  } do
    view = page(conn, admin, ~p"/admin/chat/filter?word=%20boogle%20")
    assert assigns(view).word_form["word"] == "boogle"

    render_change(view, "test_change", %{"phrase" => "  "})
    assert assigns(view).test_result == nil

    render_click(view, "next_page", %{})
    render_click(view, "prev_page", %{})
    render_click(view, "page_size", %{"size" => "50"})
    render_click(view, "refresh", %{})
    assert assigns(view).page_size == 50
  end
end
