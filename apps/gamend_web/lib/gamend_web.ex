defmodule GamendWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use GamendWeb, :controller
      use GamendWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  @host_gettext_backend Application.compile_env(
                          :gamend_web,
                          :host_gettext_backend,
                          GamendWeb.Gettext
                        )
  @configured_host_router Application.compile_env(
                            :gamend_web,
                            :host_router,
                            GamendWeb.Router
                          )
  @host_router if Code.ensure_loaded?(@configured_host_router),
                 do: @configured_host_router,
                 else: GamendWeb.Router

  # Add directories that should be served as static at the web root.
  # Adding ".well-known" allows hosting files like
  # /.well-known/apple-app-site-association from priv/static/.well-known
  # so they can be placed/replaced at build time.
  # Resolve the endpoint module at runtime so gamend_web can compile
  # before the runnable host app provides the GamendWeb.Endpoint
  # implementation.
  def endpoint,
    do: Module.concat([GamendWeb, Endpoint])

  # Only the UI library's own compiled output and fonts.
  # Host-owned paths (images, game, favicon.ico, robots.txt, .well-known)
  # are served directly by the host endpoint.
  def static_paths, do: ~w(assets fonts)

  @doc """
  The host's OTP app: the `:host_static_app` a host sets to name itself,
  `:gamend_web` when none does. Its `priv/static` is what the endpoint serves
  and its `priv/starter` is what `gamend starter` copies.
  """
  @spec host_app() :: atom()
  def host_app, do: Application.get_env(:gamend_web, :host_static_app, :gamend_web)

  @doc "The app whose `priv/static/assets` holds the compiled CSS and JS (`:asset_static_app`, else the host app)."
  @spec asset_app() :: atom()
  def asset_app, do: Application.get_env(:gamend_web, :asset_static_app, host_app())

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    backend = @host_gettext_backend

    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: unquote(backend)

      import Plug.Conn

      # The one way to answer a failed changeset. Imported rather than aliased
      # so there is nothing to look up — the forty-six hand-rolled copies this
      # replaced were written because the helper was not in reach.
      import GamendWeb.ChangesetErrors, only: [unprocessable: 2, uniqueness_conflict: 2]

      # The other four response shapes (api-conventions.md, R15).
      import GamendWeb.Reply

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    backend = @host_gettext_backend

    quote do
      # Translation
      use Gettext, backend: unquote(backend)

      import GamendWeb.DocText, only: [doc_text: 1, doc_text: 2]

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import GamendWeb.CoreComponents
      # Dynamic SVG loader component (runtime hero icons)
      import GamendWeb.Components.DynamicIcon

      # Common modules used in templates
      alias GamendWeb.Layouts
      alias GamendWeb.SRI
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    host_router = @host_router

    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: GamendWeb.Endpoint,
        router: unquote(host_router),
        statics: GamendWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
