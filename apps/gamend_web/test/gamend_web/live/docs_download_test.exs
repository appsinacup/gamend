defmodule GamendWeb.DocsDownloadTest do
  @moduledoc """
  The offline file a `GamendWeb.DocsLive` module serves, and the button that
  leads to it. Core's router carries no docs route, so the module is called
  as the plug a host's route would call.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Content
  alias GamendWeb.DocsLive

  @collection :download_test_docs
  @empty :download_test_empty

  defmodule GuideLive do
    use GamendWeb.DocsLive,
      collection: :download_test_docs,
      index_path: "/guide",
      item_path: "/guide",
      download_path: "/guide/download"

    @impl GamendWeb.DocsLive
    def index_title, do: "Player guide"
  end

  defmodule EmptyLive do
    use GamendWeb.DocsLive, collection: :download_test_empty
  end

  setup do
    root = Path.join(System.tmp_dir!(), "gamend_download_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "10-start"))
    File.mkdir_p!(Path.join(root, "empty"))
    File.write!(Path.join(root, "10-start/10-one.md"), "# One\n\nHello there.\n")

    Content.register_path(@collection, kind: :dir, path: root)
    Content.register_path(@empty, kind: :dir, path: Path.join(root, "empty"))

    on_exit(fn ->
      Content.unregister_path(@collection)
      Content.unregister_path(@empty)
      File.rm_rf!(root)
    end)

    :ok
  end

  test "a module answers its collection as one downloaded page", %{conn: conn} do
    conn = GuideLive.call(conn, GuideLive.init(:download))

    assert conn.status == 200
    assert [type] = get_resp_header(conn, "content-type")
    assert type =~ "text/html"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "download_test_docs.html"
    assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
    assert conn.resp_body =~ "<title>Player guide"
    assert conn.resp_body =~ "Hello there."
  end

  test "a collection with no guides is a 404", %{conn: conn} do
    assert_raise GamendWeb.NotFoundError, fn ->
      EmptyLive.call(conn, EmptyLive.init(:download))
    end
  end

  describe "the button" do
    @button "a#docs-download[href='/guide/download'][download]"

    test "is on the cards index when the module has a path" do
      assert index(download_path: "/guide/download") |> has?(@button)
      refute index([]) |> has?("#docs-download")
    end

    test "is on the sidebar index when the module has a path" do
      assert sidebar_index(download_path: "/guide/download") |> has?(@button)
      refute sidebar_index([]) |> has?("#docs-download")
    end
  end

  defp index(assigns) do
    render_component(
      &DocsLive.index/1,
      [
        flash: %{},
        categories: Content.list_doc_categories(@collection),
        item_path: "/guide",
        index_path: "/guide",
        title: "Player guide",
        empty_message: "None"
      ] ++ assigns
    )
  end

  defp sidebar_index(assigns) do
    render_component(
      &DocsLive.sidebar_index/1,
      [
        flash: %{},
        tree: Content.doc_tree(@collection),
        item_path: "/guide",
        index_path: "/guide",
        title: "Player guide",
        empty_message: "None"
      ] ++ assigns
    )
  end

  defp has?(html, selector) do
    not (html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.empty?())
  end
end
