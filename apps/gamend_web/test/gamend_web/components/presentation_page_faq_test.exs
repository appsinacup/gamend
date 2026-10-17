defmodule GamendWeb.Components.PresentationPageFaqTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GamendWeb.PresentationPage

  @faq [
    %{"question" => "Is it free?", "answer" => "Yes, with **no ads**."},
    %{"question" => "Which languages?", "answer" => "See the [list](/vocabulary)."},
    # Half an entry is config drift, not a question: left out of both.
    %{"question" => "No answer"}
  ]

  test "a section's faq renders every answer, with its markup" do
    html =
      render_component(&PresentationPage.section/1,
        section: %{"title" => "Questions", "media_layout" => "full", "faq" => @faq}
      )

    assert html =~ "<dt class=\"font-bold\">Is it free?</dt>"
    assert html =~ "<strong>no ads</strong>"
    refute html =~ "No answer"
    # Shown, not folded away: the reader scanned the page for this text.
    refute html =~ "<details"
  end

  test "faq_entries/1 reads a page's questions back in page order" do
    page = %{
      "sections" => [
        %{"title" => "Words"},
        %{"faq" => @faq},
        %{"faq" => [%{"question" => "Last?", "answer" => "Yes."}]}
      ]
    }

    assert [
             %{question: "Is it free?"},
             %{question: "Which languages?"},
             %{question: "Last?", answer: "Yes."}
           ] = PresentationPage.faq_entries(page)

    assert PresentationPage.faq_entries(nil) == []
  end

  test "plain_text/1 keeps the words of rich text and drops its markup" do
    assert PresentationPage.plain_text("Yes, with **no ads**. See the [list](/vocabulary).") ==
             "Yes, with no ads. See the list."
  end
end
