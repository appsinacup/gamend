defmodule GamendWeb.AdminLive.SystemServices do
  @moduledoc """
  The Services section of `/admin/system`: for the database, the cache, the
  cluster, TLS and mail, whether it is working and how, which a setting's value
  cannot say. Each card links to the settings behind it. What it shows is
  gathered by `GamendWeb.AdminLive.ServiceDiagnostics`.
  """
  use GamendWeb, :html

  require GamendWeb.AdminLive.BuildEnv, as: BuildEnv

  attr :services, :map, required: true
  attr :can_send_test_email, :boolean, required: true

  @doc "The heading and the cards."
  def services(assigns) do
    ~H"""
    <section id="system-services" class="space-y-3" aria-labelledby="system-services-title">
      <div class="flex items-center gap-2">
        <h2 id="system-services-title" class="text-lg font-semibold">Services</h2>
        <span class="badge badge-info badge-sm">{@services.environment}</span>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <.service
          id="service-database"
          title="Database"
          group="db"
          status={db_label(@services.database.adapter)}
          status_class={db_badge(@services.database.adapter)}
        >
          <.fact label="Source">{db_source_label(@services.database.source)}</.fact>
          <div
            :if={@services.database.adapter != @services.database.configured_adapter}
            id="service-database-mismatch"
            class="alert alert-warning text-sm mt-2"
          >
            Configured for {db_label(@services.database.configured_adapter)}, but this build was compiled for {db_label(
              @services.database.adapter
            )}. Rebuild with GAMEND_DB_ADAPTER={@services.database.configured_adapter}.
          </div>
        </.service>

        <.service
          id="service-cache"
          title="Cache"
          group="cache"
          status={if(@services.cache.enabled?, do: "Enabled", else: "Bypassed")}
          status_class={if(@services.cache.enabled?, do: "badge-success", else: "badge-ghost")}
        >
          <.fact label="Mode">{@services.cache.mode}</.fact>
          <.fact label="L1">local</.fact>
          <.fact label="L2">{@services.cache.l2}</.fact>
          <.fact :if={@services.cache.inclusion_policy} label="Inclusion policy">
            {@services.cache.inclusion_policy}
          </.fact>
        </.service>

        <.service
          id="service-cluster"
          title="Cluster"
          group="cluster"
          status={if(@services.cluster.enabled?, do: "Distributed", else: "Single node")}
          status_class={if(@services.cluster.enabled?, do: "badge-success", else: "badge-ghost")}
        >
          <.fact label="node()">{@services.cluster.node}</.fact>
          <.fact :for={{name, value} <- @services.cluster.variables} label={name}>{value}</.fact>
          <.fact :for={{name, value} <- @services.cluster.fly} label={name}>{value}</.fact>
          <p class="text-xs text-muted mt-2">
            Partitioned L2 caching needs Erlang distribution and clustering. Redis L2 does not.
          </p>
        </.service>

        <.service
          id="service-tls"
          title="HTTPS / TLS"
          group="tls"
          status={if(@services.tls.enabled?, do: "Enabled", else: "Disabled")}
          status_class={if(@services.tls.enabled?, do: "badge-success", else: "badge-ghost")}
        >
          <%= if cert = @services.tls.certificate do %>
            <.fact label="Subject">{cert.subject}</.fact>
            <.fact label="Issuer">{cert.issuer}</.fact>
            <.fact label="Valid from">{cert.not_before}</.fact>
            <.fact label="Valid until">
              <span class={cert.expires_soon? && "text-warning font-semibold"}>
                {cert.not_after}
              </span>
              <span :if={cert.days_remaining != nil} class="text-muted">
                ({cert.days_remaining} days left)
              </span>
            </.fact>
            <.fact label="Serial">{cert.serial}</.fact>
          <% else %>
            <p :if={@services.tls.certfile} class="text-sm text-warning">
              Could not read the certificate file. Check the path and that the server may read it.
            </p>
            <p :if={!@services.tls.certfile} class="text-sm text-muted">
              No certificate configured. TLS is ended in front of this server, or not at all.
            </p>
          <% end %>
        </.service>

        <.service
          id="service-mail"
          title="Email"
          group="mail"
          status={if(@services.mail.smtp?, do: "SMTP", else: "Local")}
          status_class={if(@services.mail.smtp?, do: "badge-success", else: "badge-info")}
        >
          <p class="text-sm">
            <%= if @services.mail.smtp? do %>
              Sent through {@services.mail.relay || "the configured relay"}.
            <% else %>
              Local delivery. Nothing leaves this server.
            <% end %>
            <.link href="/docs/email-setup" class="link link-primary">Email setup guide</.link>
          </p>
          <div class="flex flex-wrap gap-2 mt-3">
            <button
              :if={@can_send_test_email}
              id="service-mail-test"
              type="button"
              phx-click="send_test_email"
              class="btn btn-surface btn-sm"
            >
              Send test email
            </button>
            <a
              :if={@services.environment == BuildEnv.dev()}
              href="/dev/mailbox"
              class="btn btn-ghost btn-sm"
            >
              Mailbox preview
            </a>
          </div>
        </.service>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :group, :string, required: true, doc: "the settings group behind this service"
  attr :status, :string, required: true
  attr :status_class, :string, required: true
  slot :inner_block, required: true

  defp service(assigns) do
    ~H"""
    <div id={@id} class="card bg-base-200 shadow">
      <div class="card-body gap-1">
        <div class="flex items-center justify-between gap-2">
          <h3 class="card-title text-base">
            {@title} <span class={["badge badge-sm", @status_class]}>{@status}</span>
          </h3>
          <.link navigate={"/admin/settings?group=#{@group}"} class="link link-primary text-xs">
            Settings
          </.link>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp fact(assigns) do
    ~H"""
    <div class="grid grid-cols-[minmax(0,2fr)_minmax(0,3fr)] gap-3 text-sm">
      <span class="text-muted break-words">{@label}</span>
      <span class="font-mono text-xs break-all self-center">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  defp db_badge(:postgres), do: "badge-success"
  defp db_badge(:sqlite), do: "badge-info"

  defp db_label(:postgres), do: "Postgres"
  defp db_label(:sqlite), do: "SQLite"

  defp db_source_label(:database_url), do: "GAMEND_DB_URL"
  defp db_source_label(:env_vars), do: "GAMEND_DB_POSTGRES_*"
  defp db_source_label(:repo_config), do: "Repo config"
  defp db_source_label(:sqlite), do: "SQLite file"
end
