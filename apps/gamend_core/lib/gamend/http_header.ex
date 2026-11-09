defmodule Gamend.HttpHeader do
  @moduledoc """
  The header names core and its HTTP clients send.
  """

  use Gamend.Names, ~w(accept authorization)

  defmacro content_type, do: "content-type"

  defmacro user_agent, do: "user-agent"

  defmacro cache_control, do: "cache-control"

  defmacro x_github_api_version, do: "x-github-api-version"
end
