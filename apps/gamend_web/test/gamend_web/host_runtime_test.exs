defmodule GamendWeb.HostRuntimeTest do
  @moduledoc """
  What `GamendWeb.HostRuntime.config/2` hands Bandit for the HTTP listener.
  """
  use ExUnit.Case, async: true

  test "websockets deflate at level 4, not zlib's default 6" do
    # A recorded visit: 16.9 ms of deflate at 6, 9.9 ms at 4, ~9% more bytes.
    http =
      GamendWeb.HostRuntime.config(:prod, host_root: File.cwd!())
      |> Enum.find_value(fn
        {:gamend_web, GamendWeb.Endpoint, opts} when is_list(opts) -> opts[:http]
        {:gamend_web, opts} when is_list(opts) -> get_in(opts, [GamendWeb.Endpoint, :http])
        _ -> nil
      end)

    assert http[:websocket_options][:deflate_options][:level] == 4
  end
end
