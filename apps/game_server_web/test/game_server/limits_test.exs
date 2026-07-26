defmodule GameServer.LimitsTest do
  use ExUnit.Case, async: true

  alias GameServer.Limits

  describe "defaults/0" do
    test "returns a map with all expected keys" do
      defaults = Limits.defaults()
      assert is_map(defaults)
      assert Map.has_key?(defaults, :max_metadata_size)
      assert Map.has_key?(defaults, :max_page_size)
      assert Map.has_key?(defaults, :max_group_title)
      assert Map.has_key?(defaults, :max_lobby_users)
      assert Map.has_key?(defaults, :max_party_size)
      assert Map.has_key?(defaults, :max_hook_args_size)
      assert Map.has_key?(defaults, :max_kv_value_size)
    end

    test "all default values are integers" do
      for {_key, val} <- Limits.defaults() do
        assert is_integer(val), "Expected integer value, got: #{inspect(val)}"
      end
    end
  end

  describe "get/1" do
    test "returns default value for known key" do
      assert Limits.get(:max_metadata_size) == 16_384
      assert Limits.get(:max_page_size) == 100
    end

    test "raises for unknown key, naming the module and the declared keys" do
      assert_raise ArgumentError, ~r/declares no setting :nonexistent_limit/, fn ->
        Limits.get(:nonexistent_limit)
      end
    end

    test "returns override when set" do
      original = Limits.get(:max_metadata_size)
      current = Application.get_env(:game_server_core, Limits, [])

      try do
        Application.put_env(:game_server_core, Limits, max_metadata_size: 999)
        assert Limits.get(:max_metadata_size) == 999
      after
        Application.put_env(:game_server_core, Limits, current)
      end

      assert Limits.get(:max_metadata_size) == original
    end
  end

  describe "all/0" do
    test "returns a map merging defaults with overrides" do
      current = Application.get_env(:game_server_core, Limits, [])

      try do
        Application.put_env(:game_server_core, Limits, max_page_size: 42)
        all = Limits.all()
        assert all[:max_page_size] == 42
        # Other keys still have defaults
        assert all[:max_metadata_size] == Limits.defaults()[:max_metadata_size]
      after
        Application.put_env(:game_server_core, Limits, current)
      end
    end
  end

  describe "clamp_page_size/2" do
    test "returns default when nil" do
      assert Limits.clamp_page_size(nil) == 25
      assert Limits.clamp_page_size(nil, 10) == 10
    end

    test "parses string" do
      assert Limits.clamp_page_size("50") == 50
    end

    test "returns default for invalid string" do
      assert Limits.clamp_page_size("abc") == 25
    end

    test "clamps to 1 when negative" do
      assert Limits.clamp_page_size(-10) == 1
      assert Limits.clamp_page_size(0) == 1
    end

    test "clamps to max_page_size" do
      max = Limits.get(:max_page_size)
      assert Limits.clamp_page_size(max + 100) == max
    end

    test "passes through valid integer" do
      assert Limits.clamp_page_size(10) == 10
    end
  end

  describe "clamp_page/1" do
    test "returns 1 when nil" do
      assert Limits.clamp_page(nil) == 1
    end

    test "parses string" do
      assert Limits.clamp_page("3") == 3
    end

    test "clamps to 1 when negative or zero" do
      assert Limits.clamp_page(-5) == 1
      assert Limits.clamp_page(0) == 1
    end

    test "returns default for invalid string" do
      assert Limits.clamp_page("xyz") == 1
    end
  end

  describe "validate_metadata_size/3" do
    test "passes when metadata is under limit" do
      changeset =
        {%{}, %{metadata: :map}}
        |> Ecto.Changeset.cast(%{metadata: %{"key" => "val"}}, [:metadata])
        |> Limits.validate_metadata_size(:metadata)

      assert changeset.valid?
    end

    test "fails when metadata is over limit" do
      # Create metadata > 16KB
      big = for i <- 1..500, into: %{}, do: {"key_#{i}", String.duplicate("x", 100)}

      changeset =
        {%{}, %{metadata: :map}}
        |> Ecto.Changeset.cast(%{metadata: big}, [:metadata])
        |> Limits.validate_metadata_size(:metadata)

      refute changeset.valid?
      assert {"is too large" <> _, _} = changeset.errors[:metadata]
    end

    test "passes when field is not changed" do
      changeset =
        {%{}, %{metadata: :map}}
        |> Ecto.Changeset.cast(%{}, [:metadata])
        |> Limits.validate_metadata_size(:metadata)

      assert changeset.valid?
    end

    test "uses custom limit key" do
      # max_kv_value_size defaults to 65_536
      medium = for i <- 1..200, into: %{}, do: {"k#{i}", String.duplicate("x", 100)}

      changeset =
        {%{}, %{value: :map}}
        |> Ecto.Changeset.cast(%{value: medium}, [:value])
        |> Limits.validate_metadata_size(:value, :max_kv_value_size)

      assert changeset.valid?
    end
  end
end
