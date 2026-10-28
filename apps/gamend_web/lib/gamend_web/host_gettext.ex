defmodule GamendWeb.HostGettext do
  @moduledoc """
  A host's gettext backend that falls back to core's.

  `config :gamend_web, host_gettext_backend: MyHost.Gettext` makes every
  page translate through the host's backend, core's own pages too: they are
  compiled with it (`use GamendWeb, :live_view`). A plain backend knows only
  the host's catalogue, so core's strings would read in English. This one
  looks a string up in the host's catalogue (`priv/gettext` of `otp_app`)
  and, when it is not there, in core's (`GamendWeb.Gettext`), in the same
  locale and domain:

      defmodule GamendCloud.Gettext do
        use GamendWeb.HostGettext, otp_app: :gamend_cloud
      end

  So a host translates what it renders, a string of its own that repeats one
  of core's (`Save`) needs no entry of its own, and an entry it does hold
  wins over core's.
  """

  defmacro __using__(opts) do
    quote do
      use Gettext.Backend, unquote(opts)

      @impl Gettext.Backend
      def handle_missing_translation(locale, domain, msgctxt, msgid, bindings),
        do: GamendWeb.Gettext.lgettext(locale, domain, msgctxt, msgid, bindings)

      @impl Gettext.Backend
      def handle_missing_plural_translation(
            locale,
            domain,
            msgctxt,
            msgid,
            msgid_plural,
            n,
            bindings
          ),
          do:
            GamendWeb.Gettext.lngettext(
              locale,
              domain,
              msgctxt,
              msgid,
              msgid_plural,
              n,
              bindings
            )
    end
  end
end
