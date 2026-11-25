defmodule Gamend.Mail.Message do
  @moduledoc """
  What an email says, before it has a look: every email core sends
  (`Gamend.Accounts.UserNotifier`) is one of these, so they all share one
  layout and read as the same site's.

    * `title`: the heading (the subject is set apart, often the same words);
    * `paragraphs`: the text, one string a paragraph;
    * `button`: `{label, url}`, the one thing the email asks you to do;
    * `code`: six digits to type in a game, drawn large;
    * `image`: an absolute URL, drawn under the heading (a blog post's picture);
    * `items`: a digest's notices, `%{title, text, url}` each;
    * `footer`: small lines at the bottom (why you get it, how to stop it).

  `to_text/1` is the plain-text copy every email carries. The HTML copy is the
  website's (`GamendWeb.MailLayout`: the site's name, logo and colour), which
  core reaches by name, as it queues the web's mail jobs by name: a core with
  no website sends the text alone.
  """

  @enforce_keys [:title]
  defstruct title: nil, paragraphs: [], button: nil, code: nil, image: nil, items: [], footer: []

  @type item :: %{title: String.t() | nil, text: String.t() | nil, url: String.t() | nil}
  @type t :: %__MODULE__{
          title: String.t(),
          paragraphs: [String.t()],
          button: {String.t(), String.t()} | nil,
          code: String.t() | nil,
          image: String.t() | nil,
          items: [item()],
          footer: [String.t()]
        }

  @html_layout GamendWeb.MailLayout

  @doc "The plain-text copy: the same words, the button as its link."
  @spec to_text(t()) :: String.t()
  def to_text(%__MODULE__{} = message) do
    footer = if message.footer == [], do: [], else: ["--" | message.footer]

    [message.title]
    |> Kernel.++(message.paragraphs)
    |> Kernel.++([button_text(message.button), message.code])
    |> Kernel.++(Enum.map(message.items, &item_text/1))
    |> Kernel.++(footer)
    |> join("\n\n")
  end

  @doc "The HTML copy, or nil when there is no website to draw it."
  @spec to_html(t()) :: String.t() | nil
  def to_html(%__MODULE__{} = message) do
    # apply/3: core is compiled without the web app, so a direct call to its
    # module warns as undefined.
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    if Code.ensure_loaded?(@html_layout), do: apply(@html_layout, :render, [message])
  end

  defp button_text({label, url}), do: label <> ": " <> url
  defp button_text(nil), do: nil

  defp item_text(item), do: join([item[:title], item[:text], item[:url]], "\n")

  defp join(parts, separator),
    do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(separator)
end
