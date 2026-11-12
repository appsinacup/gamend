defmodule GamendWeb.A11yContrastTest do
  @moduledoc """
  Guards the WCAG AA contrast of the daisyUI theme tokens in the root
  `assets/css/app.css`.

  The tokens are read straight out of the stylesheet, so recolouring a theme
  without keeping its `--color-x` / `--color-x-content` pair (and link text on
  `base-100`) above 4.5:1 fails here rather than in production.
  """
  use ExUnit.Case, async: true

  @app_css Path.expand("../../../../assets/css/app.css", __DIR__)

  # color-vs-content pairs, plus each color used as text on the page
  # background (markdown links, `link-primary`, `text-error` notes, ...).
  @pairs [
    {"primary", "primary-content"},
    {"success", "success-content"},
    {"warning", "warning-content"},
    {"info", "info-content"},
    {"error", "error-content"},
    {"primary", "base-100"},
    {"success", "base-100"},
    {"warning", "base-100"},
    {"info", "base-100"},
    {"error", "base-100"},
    {"base-content", "base-100"}
  ]

  @min_ratio 4.5

  defmodule Wcag do
    @moduledoc "WCAG relative luminance and contrast, for hex and oklch colors."

    def contrast(color_a, color_b) do
      la = luminance(color_a)
      lb = luminance(color_b)
      (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    end

    # WCAG 2.x relative luminance. `linear_rgb/1` already returns linear-light
    # components, so this is just the Rec. 709 weighted sum.
    def luminance(color) do
      {r, g, b} = linear_rgb(color)
      0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    defp linear_rgb("#" <> hex) when byte_size(hex) == 6 do
      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex
      {srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)}
    end

    defp linear_rgb("oklch(" <> rest) do
      [l, c, h] =
        rest
        |> String.trim_trailing(")")
        |> String.split(~r/[\s\/]+/, trim: true)
        |> Enum.take(3)
        |> Enum.map(&parse_component/1)

      oklch_to_linear_rgb(l, c, h)
    end

    defp parse_component(value) do
      case Float.parse(value) do
        {number, "%"} -> number / 100
        {number, _rest} -> number
      end
    end

    defp srgb_to_linear(hex_channel) do
      c = String.to_integer(hex_channel, 16) / 255

      if c <= 0.04045 do
        c / 12.92
      else
        :math.pow((c + 0.055) / 1.055, 2.4)
      end
    end

    # oklch -> OKLab -> LMS -> linear sRGB (Björn Ottosson's reference matrices).
    defp oklch_to_linear_rgb(l, c, h) do
      h_rad = h * :math.pi() / 180
      a = c * :math.cos(h_rad)
      b = c * :math.sin(h_rad)

      l_ = l + 0.3963377774 * a + 0.2158037573 * b
      m_ = l - 0.1055613458 * a - 0.0638541728 * b
      s_ = l - 0.0894841775 * a - 1.2914855480 * b

      lc = l_ * l_ * l_
      mc = m_ * m_ * m_
      sc = s_ * s_ * s_

      r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
      g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
      bb = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

      {clamp(r), clamp(g), clamp(bb)}
    end

    defp clamp(v), do: v |> max(0.0) |> min(1.0)
  end

  defp theme_tokens(css, theme_name) do
    # Wherever the stylesheet loads the plugin from (`../vendor/` in a host,
    # the app's own vendor dir in this server's).
    [_before, block | _rest] =
      String.split(css, ~r/@plugin "[^"]*daisyui-theme" \{\s*name: "#{theme_name}";/)

    block = block |> String.split("}") |> hd()

    ~r/--color-([a-z0-9-]+):\s*([^;]+);/
    |> Regex.scan(block)
    |> Map.new(fn [_all, name, value] -> {name, String.trim(value)} end)
  end

  for theme <- ["light", "dark"] do
    test "#{theme} theme token pairs meet WCAG AA (>= #{@min_ratio}:1)" do
      css = File.read!(@app_css)
      tokens = theme_tokens(css, unquote(theme))

      for {fg_name, bg_name} <- @pairs do
        fg = Map.fetch!(tokens, fg_name)
        bg = Map.fetch!(tokens, bg_name)
        ratio = Wcag.contrast(fg, bg)

        assert ratio >= @min_ratio,
               "#{unquote(theme)}: #{fg_name} (#{fg}) on #{bg_name} (#{bg}) " <>
                 "is #{Float.round(ratio, 2)}:1, needs #{@min_ratio}:1"
      end
    end
  end
end
