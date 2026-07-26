defmodule Mix.Tasks.Gamend.Api.Lint do
  @shortdoc "Checks the API conventions (docs/specs/api-conventions.md)"

  @moduledoc """
  Enforces the naming and serialization conventions mechanically.

      mix gamend.api.lint          # report violations, exit 1 if any
      mix gamend.api.lint --list   # list the rules and exit

  Run from the umbrella root; CI runs it alongside credo. See
  `GameServer.ApiConventions` for what each rule checks and why.
  """

  use Mix.Task

  alias GameServer.ApiConventions

  @rules [
    {"R1-null-string", "A nullable string/map field is serialized without `|| \"\"`"},
    {"R2-derive-encoder", "A schema with nullable strings uses @derive Jason.Encoder"},
    {"R3-instant-suffix", "A `:utc_datetime` field is not named `*_at`"},
    {"R4-duration-unit", "A duration setting does not name its unit"},
    {"R5-path-underscore", "A route path contains a hyphen"},
    {"R6-schema-nullable", "An OpenAPI string field declares `nullable: true`"},
    {"R7-meta-helper", "A controller builds pagination meta by hand"},
    {"R8-page-params", "A controller reads page params without Pagination.params/1"},
    {"R9-doc-route", "A guide/spec documents an API route that does not exist"}
  ]

  @impl true
  def run(argv) do
    if "--list" in argv do
      Mix.shell().info("API convention rules:\n")
      for {id, desc} <- @rules, do: Mix.shell().info("  #{id}  #{desc}")
    else
      report(ApiConventions.violations())
    end
  end

  defp report([]) do
    Mix.shell().info("API conventions: clean (#{length(@rules)} rules)")
  end

  defp report(violations) do
    for {rule, group} <- Enum.group_by(violations, & &1.rule) do
      Mix.shell().error("\n#{rule} (#{length(group)})")

      for v <- group do
        Mix.shell().error("  #{Path.relative_to_cwd(v.file)}:#{v.line}\n      #{v.message}")
      end
    end

    Mix.raise("#{length(violations)} API convention violation(s)")
  end
end
