Code.require_file("../../../../config/dotenv.exs", __DIR__)

defmodule Gamend.Settings.EnvFileTest do
  use ExUnit.Case, async: false

  alias Gamend.Hooks.Declarations
  alias Gamend.Settings
  alias Gamend.Settings.EnvFile

  defmodule Sample do
    use Gamend.Settings.Provider,
      app: :gamend_core,
      group: :env_file_sample,
      label: "Env file sample"

    setting(:token, :string, secret: true)
    setting(:hosts, :list, default: [])
    setting(:tier, :atom, default: :low, values: [:low, :high])
    setting(:enabled, :boolean, default: false)
    setting(:days, :integer, default: 30)
    setting(:note, :string)
  end

  setup do
    Settings.add_provider(Sample)

    on_exit(fn ->
      Application.delete_env(:gamend_core, Sample)
      Settings.remove_provider(Sample)
      Enum.each(names(), &System.delete_env/1)
    end)

    :ok
  end

  defp put(values), do: Application.put_env(:gamend_core, Sample, values)
  defp names, do: Enum.map(Settings.all(), & &1.env) |> Enum.filter(&sample?/1)
  defp sample?(text), do: String.contains?(text, "ENV_FILE_SAMPLE_")
  defp env(key), do: Enum.find(Settings.group(:env_file_sample), &(&1.key == key)).env
  defp lines, do: String.split(EnvFile.render(), "\n")

  # Only the sample's lines: loading the whole file would put every setting the
  # test environment configures into this VM's environment.
  defp load_back(%{tmp_dir: dir}) do
    path = Path.join(dir, "gamend.env")
    File.write!(path, lines() |> Enum.filter(&sample?/1) |> Enum.join("\n"))
    Enum.each(names(), &System.delete_env/1)
    Gamend.Dotenv.load(path)
  end

  test "writes a configured setting's running value, secrets included" do
    put(token: "s3cret", hosts: ["a.test", "b.test"], tier: :high, enabled: true, days: 7)

    assert "#{env(:token)}=s3cret" in lines()
    assert "#{env(:hosts)}=a.test,b.test" in lines()
    assert "#{env(:tier)}=high" in lines()
    assert "#{env(:enabled)}=true" in lines()
    assert "#{env(:days)}=7" in lines()
  end

  test "comments out a setting on its default" do
    assert "# #{env(:days)}=30" in lines()
    assert "# #{env(:token)}=" in lines()
  end

  test "comments out a setting configured to nothing" do
    put(token: nil, hosts: [])

    assert "# #{env(:token)}=" in lines()
    assert "# #{env(:hosts)}=" in lines()
  end

  describe "a plugin's variables" do
    defmodule VarsPlugin do
      def env_vars do
        [
          %{name: "ENV_FILE_SAMPLE_BOTS", default: 8, description: "Bots per match"},
          %{name: "ENV_FILE_SAMPLE_KEY", default: "", description: "A key", secret: true}
        ]
      end
    end

    setup do
      Declarations.refresh([
        %{name: "my_game", status: :ok, hooks_module: VarsPlugin, modules: []}
      ])

      on_exit(fn ->
        Declarations.refresh([])
        System.delete_env("ENV_FILE_SAMPLE_KEY")
      end)
    end

    test "are written under the plugin, with what is set" do
      System.put_env("ENV_FILE_SAMPLE_KEY", "s3cret")

      assert "# Plugin: my_game" in lines()
      assert "ENV_FILE_SAMPLE_KEY=s3cret" in lines()
      assert "# ENV_FILE_SAMPLE_BOTS=8" in lines()
    end
  end

  describe "read back by the .env loader" do
    @describetag :tmp_dir

    for {name, value} <- [
          {"a PEM key", "-----BEGIN KEY-----\nabc\n-----END KEY-----\n"},
          {"a key written with escaped line breaks",
           "-----BEGIN KEY-----\\nabc\\n-----END KEY-----"},
          {"JSON holding both", ~s({"key": "a\\nb",\n "other": "c"})},
          {"surrounding spaces", "  padded  "},
          {"a comment sign and an equals sign", "a#b=c"},
          {"two backslashes before an n", "a\\\\nb"}
        ] do
      test "keeps #{name}", context do
        value = unquote(value)
        put(token: value)

        load_back(context)

        assert System.get_env(env(:token)) == value
      end
    end
  end

  for {name, value} <- [
        {"starts with a quote", ~s("abc)},
        {"ends with a quote", ~s(abc")},
        {"has a backslash before a line break", "a\\\nb"}
      ] do
    test "says so, rather than corrupt it, when a value #{name}" do
      put(token: unquote(value))

      assert "# #{env(:token)} holds text a .env file cannot carry: set it by hand" in lines()
    end
  end
end
