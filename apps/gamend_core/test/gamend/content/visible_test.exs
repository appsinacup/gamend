defmodule Gamend.Content.VisibleTest do
  @moduledoc """
  A collection registered with `:visible` leaves out the guides the hook
  answers false for, everywhere a guide is found: the index, the tree,
  previous/next, `get_doc/2` and its HTML. A category left empty goes too.
  """
  use ExUnit.Case, async: false

  alias Gamend.Content

  @flat :visible_test_flat
  @tree :visible_test_tree

  @doc false
  def visible?(%{meta: %{"feature" => "hidden"}}), do: false
  def visible?(_doc), do: true

  setup do
    root = Path.join(System.tmp_dir!(), "gamend_visible_#{System.unique_integer([:positive])}")

    write(root, "10-start/10-one.md", "# One\n\nShown.\n")
    write(root, "10-start/20-two.md", "---\nfeature: hidden\n---\n# Two\n\nHidden.\n")
    write(root, "10-start/30-three.md", "# Three\n\nShown.\n")
    write(root, "20-game/10-four.md", "---\nfeature: hidden\n---\n# Four\n\nHidden.\n")

    for {name, nesting} <- [{@flat, :flat}, {@tree, :tree}] do
      Content.register_path(name,
        kind: :dir,
        path: root,
        nesting: nesting,
        visible: {__MODULE__, :visible?}
      )
    end

    on_exit(fn ->
      Content.unregister_path(@flat)
      Content.unregister_path(@tree)
      File.rm_rf!(root)
    end)

    :ok
  end

  test "a hidden guide is in no listing, and its category goes when empty" do
    assert [%{guides: guides}] = Content.list_doc_categories(@flat)
    assert Enum.map(guides, & &1.slug) == ["one", "three"]
    assert Enum.map(Content.list_docs(@flat), & &1.slug) == ["one", "three"]

    slugs = @tree |> Content.list_docs() |> Enum.map(& &1.slug)
    refute Enum.any?(slugs, &String.ends_with?(&1, ["two", "four"]))
  end

  test "it is not found, has no HTML, and previous/next step over it" do
    assert Content.get_doc(@flat, "two") == nil
    assert Content.doc_html(@flat, "two") == nil
    assert Content.doc_html(@flat, "one") =~ "Shown."

    {_prev, next} = Content.doc_neighbours(@flat, "one")
    assert next.slug == "three"
  end

  test "the hook runs on every call, so a switch takes effect at once" do
    assert Content.get_doc(@flat, "two") == nil

    root = @flat |> Content.path()
    Content.register_path(@flat, kind: :dir, path: root)
    assert Content.get_doc(@flat, "two")
  end

  defp write(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
