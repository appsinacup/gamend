defmodule GamendWeb.Http do
  @moduledoc """
  How the endpoint is addressed and who may call it from a browser.

  `PORT` is inherited: every PaaS injects it and renaming it would break
  every such deployment.
  """

  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :http,
    label: "Server & HTTP"

  require Gamend.LocalHost, as: LocalHost

  setting(:port, :integer,
    default: 4000,
    doc: "TCP port the HTTP listener binds."
  )

  setting(:host, :string,
    default: LocalHost.localhost(),
    doc: "Public hostname, used to build URLs and OAuth redirect URIs."
  )

  setting(:scheme, :string,
    doc: "http or https. Defaults to http for localhost, https otherwise."
  )

  setting(:server, :boolean,
    default: false,
    doc: "Start the HTTP listener. Only needed when running as a release."
  )

  # Structured as a list so an entry never has to be parsed out of one string.
  setting(:allowed_origins, :list,
    default: [],
    doc:
      "Browser CORS/WebSocket origin allowlist. Empty allows any origin; the server's own pages always accept its own names. Prefix an entry with `regex:` for a pattern."
  )

  setting(:other_hosts, :list,
    default: [],
    doc:
      "Other names this server answers on, such as a custom domain: its WebSockets accept them as origins. Links keep GAMEND_HTTP_HOST."
  )

  setting(:max_body_bytes, :integer,
    default: 1_048_576,
    doc:
      "Largest request body the server reads (JSON, form or multipart), in bytes. Raise it " <>
        "with any GAMEND_LIMITS_* size above 1 MB, or requests that size are refused first. " <>
        "Local-backend uploads are capped by GAMEND_LIMITS_MAX_UPLOAD_BYTES instead."
  )

  @doc "Largest request body the endpoint parses, in bytes (`max_body_bytes`)."
  @spec max_body_bytes() :: pos_integer()
  def max_body_bytes, do: max(Gamend.Settings.get(__MODULE__, :max_body_bytes), 1)

  @doc """
  Whether a browser `origin` may open a socket, for an allowlist holding a
  `regex:` pattern: Phoenix's `check_origin` takes origins as strings only,
  so `GamendWeb.HostRuntime` hands it this as `{GamendWeb.Http,
  :origin_allowed?, [allowed]}`. A string entry matches as Phoenix matches
  one (`//host`, `https://host`, `//*.host`); a pattern, the whole origin.
  """
  @spec origin_allowed?(URI.t(), [String.t() | Regex.t()]) :: boolean()
  def origin_allowed?(%URI{host: nil}, _allowed), do: false

  def origin_allowed?(%URI{} = origin, allowed) do
    Enum.any?(allowed, fn
      %Regex{} = regex -> Regex.match?(regex, URI.to_string(origin))
      entry -> same_origin?(origin, URI.parse(entry))
    end)
  end

  defp same_origin?(_origin, %URI{host: nil}), do: false

  defp same_origin?(origin, allowed) do
    (is_nil(allowed.scheme) or allowed.scheme == origin.scheme) and
      (is_nil(allowed.port) or allowed.port == origin.port) and
      host_matches?(origin.host, allowed.host)
  end

  defp host_matches?(host, "*." <> parent),
    do: host == parent or String.ends_with?(host, "." <> parent)

  defp host_matches?(host, allowed), do: host == allowed
end
