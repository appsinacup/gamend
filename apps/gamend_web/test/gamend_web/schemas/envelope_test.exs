defmodule GamendWeb.Schemas.EnvelopeTest do
  # The response envelopes (`GamendWeb.Schemas.Envelope.build/2`): a page is
  # `{data: [T], meta}`, a single item `{data: T}` with any extra fields
  # beside it, and the title is the module's last segment.
  use ExUnit.Case, async: true

  alias GamendWeb.Schemas.Envelope
  alias GamendWeb.Schemas.PageMeta
  alias OpenApiSpex.Schema

  defmodule Item do
    require OpenApiSpex
    OpenApiSpex.schema(%{title: "Item", type: :object})
  end

  test "a page is a list of its items and the page meta, both required" do
    schema = Envelope.build("ItemPage", page: Item)
    assert schema.title == "ItemPage"
    assert schema.required == [:data, :meta]
    assert %Schema{type: :array, items: Item} = schema.properties.data
    assert schema.properties.meta == PageMeta
    assert schema.description =~ "Item"
  end

  test "a page may name its own description" do
    assert Envelope.build("ItemPage", page: Item, description: "Every item").description ==
             "Every item"
  end

  test "a single item is its data, with extra fields and which of them are required" do
    schema =
      Envelope.build("ItemReply",
        data: Item,
        extra: %{note: %Schema{type: :string}},
        required: [:note]
      )

    assert schema.properties.data == Item
    assert %Schema{type: :string} = schema.properties.note
    assert :data in schema.required and :note in schema.required
  end

  test "an envelope with neither page nor data is a programming error" do
    assert_raise KeyError, fn -> Envelope.build("Nothing", []) end
  end
end
