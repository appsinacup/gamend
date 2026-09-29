defmodule Mix.Tasks.Host.ResponsiveImages do
  use Mix.Task

  @moduledoc false

  @shortdoc "Generates the srcset width variants the presentation config asks for"

  alias GamendWeb.ResponsiveImages

  # `"widths": [480, 960]` on a theme/config.json image means the renderer will
  # emit `<base>-480.<ext>` and `<base>-960.<ext>` in a srcset. This task is what
  # puts those files on disk. The renderer drops a width whose file is missing,
  # so a stale run costs bytes rather than broken images — but every width the
  # config names should exist, which is what `--check` asserts.
  #
  # The cutting itself is `GamendWeb.ResponsiveImages`, which a running server
  # also uses to fill in the variants of a project's own static files.
  @config_path "theme/config.json"
  @static_root "priv/static"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [check: :boolean])
    check? = Keyword.get(opts, :check, false)

    planned = planned_variants(File.read!(@config_path))

    if planned == [] do
      Mix.shell().info("No config image declares \"widths\" — nothing to generate.")
      :ok
    else
      tool = if check?, do: nil, else: tool!(planned)

      planned
      |> Enum.map(&ResponsiveImages.resolve(&1, @static_root, check: check?, tool: tool))
      |> report(check?)
    end
  end

  @doc """
  Every `{source, variant, width}` the config's `widths` declarations imply.

  Pure so it can be tested against the real config without touching disk.
  """
  defdelegate planned_variants(json), to: ResponsiveImages

  # Only a source that exists is ever cut, so only then is ImageMagick needed:
  # with no source on disk every entry reports as missing and the tool is never
  # asked for.
  defp tool!(planned) do
    needs_tool? =
      Enum.any?(planned, fn {source, _variant, _width} ->
        File.regular?(Path.join(@static_root, source))
      end)

    case needs_tool? && ResponsiveImages.find_tool() do
      false ->
        nil

      nil ->
        Mix.raise("ImageMagick not found. Install imagemagick to generate responsive images.")

      tool ->
        tool
    end
  end

  defp report(results, check?) do
    Enum.each(results, fn
      {{:failed, output}, variant} -> Mix.shell().error("  failed #{variant}: #{output}")
      {:missing_source, variant} -> Mix.shell().error("  no source for #{variant}")
      {:stale, variant} -> Mix.shell().error("  not generated: #{variant}")
      _ -> :ok
    end)

    tally = Enum.frequencies_by(results, &elem(&1, 0))
    failed = Enum.count(results, &match?({{:failed, _}, _}, &1))

    Mix.shell().info(
      "Responsive images: #{Map.get(tally, :generated, 0)} generated, " <>
        "#{Map.get(tally, :current, 0)} current, " <>
        "#{Map.get(tally, :skipped_upscale, 0)} skipped (would upscale), " <>
        "#{Map.get(tally, :skipped_bigger, 0)} skipped (variant weighed more)"
    )

    stale = Map.get(tally, :stale, 0) + Map.get(tally, :missing_source, 0) + failed

    if stale > 0 do
      Mix.raise(
        if(check?,
          do: "#{stale} responsive image(s) missing — run: mix host.responsive_images",
          else: "#{stale} responsive image(s) could not be generated"
        )
      )
    end

    :ok
  end
end
