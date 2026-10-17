defmodule GamendWeb.Crawlers.DNS do
  @moduledoc """
  The DNS lookups behind `GamendWeb.Crawlers.Verify`, through `:inet_res`
  (the system's resolvers, with a timeout). Replaceable for tests:
  `config :gamend_web, GamendWeb.Crawlers, resolver: MyResolver`.
  """

  @timeout 3_000

  @doc "The address's PTR names, or `{:error, reason}` (`:nxdomain` when it has none)."
  @spec reverse(:inet.ip_address()) :: {:ok, [String.t()]} | {:error, term()}
  def reverse(ip) do
    case :inet_res.gethostbyaddr(ip, @timeout) do
      {:ok, {:hostent, name, aliases, _type, _length, _addresses}} ->
        {:ok, Enum.map([name | aliases], &to_string/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The addresses a name resolves to in one family; `[]` when it resolves to none."
  @spec forward(String.t(), :inet | :inet6) :: [:inet.ip_address()]
  def forward(host, family) do
    case :inet_res.gethostbyname(String.to_charlist(host), family, @timeout) do
      {:ok, {:hostent, _name, _aliases, _type, _length, addresses}} -> addresses
      {:error, _reason} -> []
    end
  end
end
