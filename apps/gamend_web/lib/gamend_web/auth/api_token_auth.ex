defmodule GamendWeb.Auth.ApiTokenAuth do
  @moduledoc """
  Accepts a personal API token (`Gamend.Accounts.ApiTokens`) wherever an
  access token is accepted.

  First in both API pipelines. A `Bearer gamend_pat_…` header is verified here
  and handed to Guardian as the current token and the claims an access token
  for the same user would carry — `sub`, `tv`, `typ: "access"`. Guardian's own
  plugs then run unchanged: `VerifyHeader` sees a token already in place and
  skips, `EnsureAuthenticated` passes, and `LoadResource` resolves the user
  through `GamendWeb.Auth.Guardian.resource_from_claims/1`, which is where a
  deactivated account is refused for either kind of token.

  Any other header — a JWT, none at all — passes through untouched. A
  personal token that does not verify is a 401 here, with the same body a bad
  JWT gets: falling through would only reach `VerifyHeader`, which would fail
  it anyway with a less useful reason.
  """

  @behaviour Plug

  alias Gamend.Accounts.ApiTokens
  alias GamendWeb.Auth.ErrorHandler

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    case bearer(conn) do
      token when is_binary(token) ->
        if ApiTokens.token?(token), do: authenticate(conn, token, opts), else: conn

      nil ->
        conn
    end
  end

  defp authenticate(conn, token, opts) do
    case ApiTokens.verify(token) do
      {:ok, user, row} ->
        ApiTokens.touch(row)

        claims = %{
          "sub" => to_string(user.id),
          "tv" => user.token_version,
          "typ" => "access",
          "pat" => row.id
        }

        conn
        |> Guardian.Plug.put_current_token(token)
        |> Guardian.Plug.put_current_claims(claims)

      :error ->
        conn
        |> ErrorHandler.auth_error({:invalid_token, :api_token}, opts)
        |> Plug.Conn.halt()
    end
  end

  defp bearer(conn) do
    Enum.find_value(Plug.Conn.get_req_header(conn, "authorization"), fn header ->
      case Regex.run(~r/\ABearer\s+(\S+)\z/i, String.trim(header)) do
        [_, token] -> token
        _ -> nil
      end
    end)
  end
end
