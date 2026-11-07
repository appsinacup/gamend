defmodule Mix.Tasks.Gamend.Gen.DockerfileTest do
  # The one Dockerfile every app shares, rendered from what its mix.exs says.
  # Whether the repository's own Dockerfile is in sync is CI's `--check`, run
  # from the root project; here it is what each input becomes.
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gamend.Gen.Dockerfile

  @inputs %{
    app: :gamend_host,
    release: :gamend_host,
    named_release?: false,
    db_adapter: "sqlite",
    plugins_dir: "modules/plugins",
    build_args: [],
    path_deps: [],
    config_files: ["config/config.exs", "config/prod.exs"]
  }

  defp render(overrides), do: Dockerfile.render(Map.merge(@inputs, overrides))

  defp lines(dockerfile), do: String.split(dockerfile, "\n")

  test "the defaults name the release, the adapter and the plugins dir" do
    lines = lines(render(%{}))

    assert "ARG RELEASE=gamend_host" in lines
    assert "ARG GAMEND_DB_ADAPTER=sqlite" in lines
    assert "ARG GAMEND_CONTENT_PLUGINS_DIR=modules/plugins" in lines
    assert ~s(CMD ["sh", "-c", "exec gamend-release-start \\"$GAMEND_RELEASE\\""]) in lines
    assert ~s(CMD ["gamend-start"]) in lines
  end

  test "the release is the last stage, so a bare build is what a host runs" do
    stages = for "FROM " <> from <- lines(render(%{})), do: from

    assert List.last(stages) == "${RUNNER_IMAGE} AS release"
    assert "builder AS full" in stages
  end

  test "the release build writes what it declares beside it" do
    assert render(%{}) =~
             ~s|"bin/${RELEASE}" eval 'if Code.ensure_loaded?(Gamend.Release.Metadata), do: Gamend.Release.Metadata.write()'|
  end

  test "path dependencies' mix.exs come before deps.get, the source after" do
    lines =
      lines(render(%{path_deps: ["apps/gamend_core", "modules/plugins/polyglot_hook"]}))

    index = &Enum.find_index(lines, fn line -> line == &1 end)
    deps_get = index.("RUN mix deps.get")

    assert index.("COPY apps/gamend_core/mix.exs apps/gamend_core/") < deps_get

    assert index.("COPY modules/plugins/polyglot_hook/mix.exs modules/plugins/polyglot_hook/") <
             deps_get

    assert deps_get < index.("COPY . .")
  end

  test "compile-time config is copied by name, and none means no copy" do
    assert "COPY config/config.exs config/prod.exs config/" in lines(render(%{}))
    refute Enum.any?(lines(render(%{config_files: []})), &String.starts_with?(&1, "COPY config"))
  end

  test "an app's build args sit with SYNC, before the asset step" do
    lines = lines(render(%{build_args: ["ENGINE_TAG=nightly"], app: :forge, release: :forge}))
    index = &Enum.find_index(lines, fn line -> line == &1 end)

    assert index.("ARG SYNC=0") < index.("ARG ENGINE_TAG=nightly")
    assert Enum.any?(lines, &(&1 =~ "gamend-copy-static forge --require"))
    assert "ARG RELEASE=forge" in lines
  end

  test "a release `releases:` names is assembled by name, else the app's own" do
    assert render(%{named_release?: true}) =~
             ~s(RUN mix release "${RELEASE}" --overwrite && gamend-stage-release "${RELEASE}")

    assert render(%{}) =~ ~s(RUN mix release --overwrite && gamend-stage-release "${RELEASE}")
  end

  test "the version is declared after every dependency compiles" do
    lines = lines(render(%{}))
    index = &Enum.find_index(lines, fn line -> line == &1 end)

    assert index.("RUN mix deps.compile --skip-local-deps") <
             index.("ENV GAMEND_CONTENT_APP_VERSION=${GAMEND_CONTENT_APP_VERSION}")
  end
end
