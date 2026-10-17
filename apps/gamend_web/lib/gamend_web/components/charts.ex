defmodule GamendWeb.Charts do
  @moduledoc """
  Small charts drawn on the server: a column per day (`bars/1`), a line for a
  rate (`line/1`) and a sparkline (`spark/1`). No JavaScript and no chart
  library; one series each, in the theme's `primary`, so a chart needs no
  legend (its title says what it plots) and follows the dark theme.

  Every point is `{label, value}` (a `Date` label is printed `MM-DD`), oldest
  first. Hovering a column shows its label and value; the numbers themselves
  belong in a table beside the chart, which every admin page that draws one
  has. Values are counts (`format: :count`, `12,840`) or rates in 0..1
  (`format: :percent`, `4.1%`); `nil` is "no value" (a gap in a line, no
  column).

      <.bars id="active" title="Active" points={for r <- @series, do: {r.day, r.active}} />
      <.line id="stick" title="Stickiness" points={…} format={:percent} />
      <.spark points={…} />
  """
  use Phoenix.Component

  import GamendWeb.CoreComponents, only: [eyebrow: 1]

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :points, :list, required: true, doc: "`[{label, value}]`, oldest first"
  attr :format, :atom, default: :count, values: [:count, :percent]
  attr :summary, :string, default: nil, doc: "beside the title: a total, the latest value"
  attr :class, :any, default: nil, doc: "layout only"

  @doc "A column per point, from one baseline, with the scale's top and the first and last label."
  def bars(assigns) do
    max = assigns.points |> Enum.map(&value_of/1) |> scale_max(assigns.format)
    assigns = assign(assigns, max: max, columns: columns(assigns.points, max, assigns.format))

    ~H"""
    <figure id={@id} class={["min-w-0 space-y-1", @class]}>
      <figcaption class="flex items-baseline justify-between gap-2">
        <.eyebrow tag="span">{@title}</.eyebrow>
        <span :if={@summary} class="text-sm tabular-nums text-muted">{@summary}</span>
      </figcaption>
      <.frame max={@max} format={@format} points={@points}>
        <div class="absolute inset-0 flex items-end gap-[2px]" role="img" aria-label={@title}>
          <div
            :for={col <- @columns}
            class="group relative flex h-full min-w-0 flex-1 items-end justify-center"
          >
            <div
              :if={col.height}
              class="w-full max-w-6 rounded-t bg-primary/80 group-hover:bg-primary"
              style={"height: #{col.height}%"}
            />
            <.hover_label text={col.text} />
          </div>
        </div>
      </.frame>
    </figure>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :points, :list, required: true, doc: "`[{label, value | nil}]`, oldest first"
  attr :format, :atom, default: :percent, values: [:count, :percent]
  attr :summary, :string, default: nil
  attr :class, :any, default: nil

  @doc "A 2px line through the points; a `nil` breaks it."
  def line(assigns) do
    max = assigns.points |> Enum.map(&value_of/1) |> scale_max(assigns.format)
    n = length(assigns.points)

    assigns =
      assign(assigns,
        max: max,
        columns: columns(assigns.points, max, assigns.format),
        width: max(n - 1, 1),
        segments: segments(assigns.points, max)
      )

    ~H"""
    <figure id={@id} class={["min-w-0 space-y-1", @class]}>
      <figcaption class="flex items-baseline justify-between gap-2">
        <.eyebrow tag="span">{@title}</.eyebrow>
        <span :if={@summary} class="text-sm tabular-nums text-muted">{@summary}</span>
      </figcaption>
      <.frame max={@max} format={@format} points={@points}>
        <svg
          class="absolute inset-0 h-full w-full overflow-visible text-primary"
          viewBox={"0 0 #{@width} 100"}
          preserveAspectRatio="none"
          role="img"
          aria-label={@title}
        >
          <polyline
            :for={segment <- @segments}
            points={segment}
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linejoin="round"
            stroke-linecap="round"
            vector-effect="non-scaling-stroke"
          />
        </svg>
        <div class="absolute inset-0 flex">
          <div :for={col <- @columns} class="group relative h-full min-w-0 flex-1">
            <.hover_label text={col.text} />
          </div>
        </div>
      </.frame>
    </figure>
    """
  end

  attr :points, :list, required: true, doc: "`[{label, value}]`, oldest first"
  attr :format, :atom, default: :count, values: [:count, :percent]
  attr :class, :any, default: "h-6 w-28"

  @doc "A row of thin columns with no axis, for a table cell."
  def spark(assigns) do
    max = assigns.points |> Enum.map(&value_of/1) |> scale_max(assigns.format)
    assigns = assign(assigns, columns: columns(assigns.points, max, assigns.format))

    ~H"""
    <div class={["flex items-end gap-px", @class]} aria-hidden="true">
      <div :for={col <- @columns} class="group relative flex h-full min-w-0 flex-1 items-end">
        <div
          :if={col.height}
          class="w-full rounded-t-sm bg-primary/70"
          style={"height: #{col.height}%"}
        />
        <.hover_label text={col.text} />
      </div>
    </div>
    """
  end

  # The plot area: the scale's top as a hairline with its value, the
  # baseline, and the first and last label under it.
  attr :max, :any, required: true
  attr :format, :atom, required: true
  attr :points, :list, required: true
  slot :inner_block, required: true

  defp frame(assigns) do
    ~H"""
    <div class="relative mt-3 h-28 border-b border-base-300">
      <div class="absolute inset-x-0 top-0 border-t border-base-300" />
      <span class="absolute -top-2.5 end-0 z-[1] bg-base-100 ps-1 text-[11px] tabular-nums text-muted">
        {format(@max, @format)}
      </span>
      {render_slot(@inner_block)}
    </div>
    <div :if={@points != []} class="flex justify-between text-[11px] tabular-nums text-muted">
      <span>{label(@points |> List.first() |> elem(0))}</span>
      <span>{label(@points |> List.last() |> elem(0))}</span>
    </div>
    """
  end

  attr :text, :string, required: true

  defp hover_label(assigns) do
    ~H"""
    <span class="pointer-events-none absolute bottom-full start-1/2 z-10 mb-1 hidden -translate-x-1/2 whitespace-nowrap rounded bg-base-content px-1.5 py-0.5 text-xs text-base-100 group-hover:block rtl:translate-x-1/2">
      {@text}
    </span>
    """
  end

  # ── geometry ──────────────────────────────────────────────────────────────

  defp columns(points, max, format) do
    Enum.map(points, fn {label, value} ->
      %{
        height: height(value, max),
        text: "#{label(label)}: #{format(value, format)}"
      }
    end)
  end

  # A column's height in %, at least a sliver for any value above zero, so
  # a 1 beside a 2,000 is still seen.
  defp height(nil, _max), do: nil
  defp height(value, _max) when value <= 0, do: nil
  defp height(value, max), do: max(value / max * 100, 1.5)

  # The line's runs between `nil`s, each as an SVG `points` string; y is
  # flipped (0 at the bottom).
  defp segments(points, max) do
    points
    |> Enum.with_index()
    |> Enum.chunk_by(fn {{_label, value}, _i} -> is_nil(value) end)
    |> Enum.reject(fn [{{_label, value}, _i} | _] -> is_nil(value) end)
    |> Enum.map(fn run ->
      run =
        case run do
          [{{_label, value}, i}] -> [{{nil, value}, i - 0.2}, {{nil, value}, i + 0.2}]
          run -> run
        end

      Enum.map_join(run, " ", fn {{_label, value}, i} -> "#{i},#{100 - value / max * 100}" end)
    end)
  end

  defp value_of({_label, value}), do: value

  # The scale's top: the largest value rounded up to 1, 2 or 5 × 10ⁿ (a rate
  # to the next 10%), never 0.
  defp scale_max(values, :percent) do
    top = values |> Enum.reject(&is_nil/1) |> Enum.max(fn -> 0 end)
    min(max(Float.ceil(top * 10) / 10, 0.1), 1.0)
  end

  defp scale_max(values, :count) do
    top = values |> Enum.reject(&is_nil/1) |> Enum.max(fn -> 0 end)
    nice(top)
  end

  defp nice(top) when top <= 1, do: 1

  defp nice(top) do
    magnitude = :math.pow(10, floor(:math.log10(top)))
    step = Enum.find([1, 2, 5, 10], &(&1 * magnitude >= top))
    round(step * magnitude)
  end

  @doc "A count with thousands separators, or a rate as a percent; `nil` is a dash."
  @spec format(number() | nil, :count | :percent) :: String.t()
  def format(nil, _format), do: "—"
  def format(rate, :percent), do: "#{Float.round(rate * 100.0, 1)}%"

  def format(n, :count) when is_float(n), do: n |> Float.round(1) |> Float.to_string()

  def format(n, :count) when is_integer(n) and n < 0, do: "-" <> format(-n, :count)

  def format(n, :count) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp label(%Date{} = day), do: Calendar.strftime(day, "%m-%d")
  defp label(label), do: to_string(label)
end
