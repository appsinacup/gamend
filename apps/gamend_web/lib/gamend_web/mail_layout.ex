defmodule GamendWeb.MailLayout do
  @moduledoc """
  The one look of every email (`Gamend.Mail.Message`, sent by
  `Gamend.Accounts.UserNotifier`): the site's logo and name on its brand
  colour, the heading, a picture when there is one, the text, one button,
  then the small print. A sign-in link, a news post and a digest all look
  like the same site's.

  The brand is the site's own theme (`HostLayouts.resolve_theme/1`): its
  `title`, its `logo` and its `brand_color`. Mail clients drop SVG and WebP,
  so a theme whose `logo` is one names a PNG or JPEG as `email_logo`; with
  neither, the header is the name alone. A host sets nothing more. Tables and inline styles only, so
  Gmail, Outlook and Apple Mail draw it alike; no fonts to fetch, no script,
  and it reads with pictures off.
  """

  # :html for the host's catalogue, as `GamendWeb.NotificationEmail`.
  use GamendWeb, :html

  alias Gamend.Mail.Message
  alias GamendWeb.HostLayouts

  require Gamend.UrlScheme, as: UrlScheme

  @fallback_color "#374151"
  @page "#f4f4f5"
  @card "#ffffff"
  @ink "#18181b"
  @muted "#71717a"
  @line "#e4e4e7"
  @font "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

  @doc "The HTML copy of `message`, in the site's look."
  @spec render(Message.t()) :: String.t()
  def render(%Message{} = message) do
    theme = HostLayouts.resolve_theme()
    color = brand_color(theme["brand_color"])

    assigns = %{
      message: message,
      site: theme["title"] || "Gamend",
      site_url: GamendWeb.Endpoint.url(),
      logo: mail_logo(theme),
      color: color,
      on_color: on_color(color),
      preview: List.first(message.paragraphs) || message.title,
      open: gettext("Open"),
      page: @page,
      card: @card,
      ink: @ink,
      muted: @muted,
      line: @line,
      font: @font
    }

    "<!DOCTYPE html>" <>
      (assigns |> mail() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary())
  end

  defp mail(assigns) do
    ~H"""
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light" />
        <meta name="supported-color-schemes" content="light" />
        <title>{@message.title}</title>
      </head>
      <body style={"margin:0;padding:0;background:#{@page};"}>
        <div style="display:none;max-height:0;overflow:hidden;opacity:0;">{@preview}</div>
        <table
          role="presentation"
          width="100%"
          cellpadding="0"
          cellspacing="0"
          border="0"
          style={"background:#{@page};"}
        >
          <tr>
            <td align="center" style="padding:24px 12px;">
              <table
                role="presentation"
                width="100%"
                cellpadding="0"
                cellspacing="0"
                border="0"
                style={"max-width:560px;background:#{@card};border-radius:12px;overflow:hidden;font-family:#{@font};"}
              >
                <tr>
                  <td style={"background:#{@color};padding:16px 24px;"}>
                    <a href={@site_url} style={"color:#{@on_color};text-decoration:none;"}>
                      <img
                        :if={@logo}
                        src={@logo}
                        width="32"
                        height="32"
                        alt=""
                        style="vertical-align:middle;border:0;border-radius:8px;background:#ffffff;padding:3px;"
                      />
                      <span style={"vertical-align:middle;font-size:18px;font-weight:700;color:#{@on_color};#{if @logo, do: "padding-left:10px;"}"}>
                        {@site}
                      </span>
                    </a>
                  </td>
                </tr>
                <tr>
                  <td style="padding:28px 24px 8px;">
                    <h1 style={"margin:0 0 16px;font-size:22px;line-height:1.3;color:#{@ink};"}>
                      {@message.title}
                    </h1>
                    <img
                      :if={@message.image}
                      src={@message.image}
                      width="512"
                      alt=""
                      style="display:block;width:100%;max-width:512px;height:auto;border:0;border-radius:8px;margin:0 0 16px;"
                    />
                    <p
                      :for={paragraph <- @message.paragraphs}
                      style={"margin:0 0 16px;font-size:16px;line-height:1.5;color:#{@ink};"}
                    >
                      {paragraph}
                    </p>
                    <p
                      :if={@message.code}
                      style={"margin:8px 0 24px;font-size:32px;font-weight:700;letter-spacing:8px;font-family:Menlo,Consolas,monospace;color:#{@ink};"}
                    >
                      {@message.code}
                    </p>
                    <.mail_button
                      :if={@message.button}
                      label={elem(@message.button, 0)}
                      url={elem(@message.button, 1)}
                      color={@color}
                      on_color={@on_color}
                    />
                    <table
                      :for={item <- @message.items}
                      role="presentation"
                      width="100%"
                      cellpadding="0"
                      cellspacing="0"
                      border="0"
                      style={"border-top:1px solid #{@line};"}
                    >
                      <tr>
                        <td style="padding:16px 0;">
                          <p
                            :if={item[:title]}
                            style={"margin:0 0 4px;font-size:16px;font-weight:700;color:#{@ink};"}
                          >
                            {item[:title]}
                          </p>
                          <p
                            :if={item[:text] not in [nil, ""]}
                            style={"margin:0 0 8px;font-size:15px;line-height:1.5;color:#{@ink};"}
                          >
                            {item[:text]}
                          </p>
                          <a
                            :if={item[:url]}
                            href={item[:url]}
                            style={"font-size:15px;font-weight:600;color:#{@color};"}
                          >
                            {@open}
                          </a>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr :if={@message.footer != []}>
                  <td style={"padding:16px 24px 24px;border-top:1px solid #{@line};"}>
                    <p
                      :for={line <- @message.footer}
                      style={"margin:0 0 6px;font-size:13px;line-height:1.5;color:#{@muted};"}
                    >
                      {linkify(line, @muted)}
                    </p>
                  </td>
                </tr>
              </table>
              <p style={"margin:16px 0 0;font-family:#{@font};font-size:12px;color:#{@muted};"}>
                <a href={@site_url} style={"color:#{@muted};"}>{@site}</a>
              </p>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  attr :label, :string, required: true
  attr :url, :string, required: true
  attr :color, :string, required: true
  attr :on_color, :string, required: true

  # A table cell as the button, so Outlook draws its colour too.
  defp mail_button(assigns) do
    ~H"""
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;">
      <tr>
        <td style={"background:#{@color};border-radius:8px;"}>
          <a
            href={@url}
            style={"display:inline-block;padding:12px 24px;font-size:16px;font-weight:700;color:#{@on_color};text-decoration:none;border-radius:8px;"}
          >
            {@label}
          </a>
        </td>
      </tr>
    </table>
    """
  end

  # A footer line ends with its link ("Stop these emails: https://…"): drawn
  # as a link, the rest as text.
  defp linkify(line, color) do
    case Regex.run(~r/^(.*?)(https?:\/\/\S+)$/s, line) do
      [_, text, url] ->
        assigns = %{text: String.trim_trailing(text, ": "), url: url, color: color}

        ~H"""
        <a href={@url} style={"color:#{@color};"}>{@text}</a>
        """

      nil ->
        line
    end
  end

  # `email_logo`, else `logo`, when it is a picture mail clients draw.
  defp mail_logo(theme) do
    [theme["email_logo"], theme["logo"]]
    |> Enum.find(&(is_binary(&1) and Path.extname(&1) in ~w(.png .jpg .jpeg .gif)))
    |> absolute()
  end

  defp absolute("/" <> _ = path), do: GamendWeb.Endpoint.static_url() <> path

  defp absolute(url) when is_binary(url) do
    if URI.parse(url).scheme in [UrlScheme.http(), UrlScheme.https()], do: url
  end

  defp absolute(_none), do: nil

  defp brand_color("#" <> hex = color) when byte_size(hex) in [3, 6] do
    if hex =~ ~r/^[0-9a-fA-F]+$/, do: color, else: @fallback_color
  end

  defp brand_color(_other), do: @fallback_color

  # White on a dark brand colour, near-black on a light one.
  defp on_color("#" <> hex) do
    hex =
      if byte_size(hex) == 3,
        do: hex |> String.graphemes() |> Enum.map_join(&(&1 <> &1)),
        else: hex

    [r, g, b] = for <<pair::binary-2 <- hex>>, do: String.to_integer(pair, 16)
    if r * 299 + g * 587 + b * 114 > 150_000, do: @ink, else: "#ffffff"
  end
end
