defmodule Mix.Tasks.Gamend.Contract.Lint do
  @shortdoc "Checks that every API route, socket message and LiveView event has a schema"

  @moduledoc """
  Fails on a way in or out of the server that no schema holds: an `/api/v1`
  route with no OpenAPI operation, an OpenAPI schema that says nothing of its
  value without saying why, a server event sent as JSON only (no protobuf
  message), a channel command or a LiveView event that is not declared. See
  `GamendWeb.ContractLint` for each rule and for the `x-free-form` mark that
  accepts a value no schema can say.

  Run from the repository root, in the engine or in a host built on it: the
  host's router and its own modules are read, never a dependency's.

      mix gamend.contract.lint           # fail on an offense
      mix gamend.contract.lint --free    # also list the marked free-form values
  """

  use Mix.Task

  alias GamendWeb.ContractLint

  @requirements ["compile", "app.config"]

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [free: :boolean])

    if opts[:free] do
      for {where, reason} <- ContractLint.free_forms(),
          do: Mix.shell().info("free  #{where}: #{reason}")
    end

    case ContractLint.offenses() do
      [] ->
        Mix.shell().info("Contract lint: clean")

      offenses ->
        Enum.each(offenses, fn %{rule: rule, where: where, text: text} ->
          Mix.shell().error("[#{rule}] #{where}: #{text}")
        end)

        Mix.raise(
          "#{length(offenses)} way(s) in or out with no schema (GamendWeb.ContractLint): " <>
            "type each one, or mark a value no schema can say `x-free-form: <why>`"
        )
    end
  end
end
