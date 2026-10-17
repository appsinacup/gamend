defmodule GamendWeb.Reports.KindUI do
  @moduledoc """
  How a report kind looks: on `/report` and in the admin queue.

  A `Gamend.Reports.Kind` names this module in its `ui/0`. A host's kind is
  usually one module implementing both behaviours, with `ui/0` answering
  `__MODULE__`.

  ## On `/report`

  The page draws the kind as a card (`c:label/0`, `c:description/0`,
  `c:icon/0`). Once picked, it draws, top to bottom:

    1. the **subject component** (`c:subject_component/0`), a
       `Phoenix.LiveComponent` that owns how the subject is chosen — a search,
       a picker, a plain field. It renders its own `<form>` (it sits outside
       the page's), is given `id`, `query` (the page's URL params, for deep
       links), `topic`, `locale` and `current_scope`, and tells the page what
       is chosen with `send(self(), {:report_subject, subject})`, where
       `subject` is the map `Gamend.Reports.Kind.cast/2` will read under
       `"subject"`, or nil when nothing is chosen. It may also pick the
       topic, `send(self(), {:report_topic, topic})`, when its own control
       implies one (a "this word is missing" button);
    2. the kind's topics as chips (`c:topic_label/1`, `c:topic_icon/1`);
    3. the kind's extra **fields** for the picked topic (`c:fields/1`), sent
       under `"data"`;
    4. core's own: description, images, send.

  ## In the queue

  `c:admin_subject/1` draws what a report is about (gets `report`), and
  `c:subject_label/1` is the same in a few words, for lists and the reply a
  reporter receives. `c:export/1` turns a set of reports into a file an
  admin downloads, for a kind whose fixes happen somewhere else (a
  spreadsheet, a translation tool).
  """

  @typedoc """
  An extra field: `name` is the key under `"data"`; `type` is `:text` or
  `:textarea`.
  """
  @type field :: %{
          required(:name) => String.t(),
          required(:label) => String.t(),
          optional(:type) => :text | :textarea,
          optional(:placeholder) => String.t(),
          optional(:max) => pos_integer()
        }

  @doc "The card's title (\"A word\"), in the reader's language."
  @callback label() :: String.t()

  @doc "The card's line under the title, in the reader's language."
  @callback description() :: String.t()

  @doc "The card's icon, a heroicon name (`\"hero-language\"`)."
  @callback icon() :: String.t()

  @doc "A topic's chip label, in the reader's language."
  @callback topic_label(topic :: String.t()) :: String.t()

  @doc "A topic's chip icon, or nil."
  @callback topic_icon(topic :: String.t()) :: String.t() | nil

  @doc "Extra fields for the picked topic (nil when none is picked)."
  @callback fields(topic :: String.t() | nil) :: [field()]

  @doc "The LiveComponent that picks the subject, or nil when there is nothing to pick."
  @callback subject_component() :: module() | nil

  @doc "What a report is about, in a few words (\"ardei = pepper\"), or nil."
  @callback subject_label(Gamend.Reports.Report.t()) :: String.t() | nil

  @doc "What a report is about, drawn for the admin queue. Gets `report`."
  @callback admin_subject(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  What to tell the reporter when the kind's `cast/2` refused (`reason` is
  what it answered), in their language. nil for core's generic "check what
  you entered".
  """
  @callback error_message(reason :: term()) :: String.t() | nil

  @doc "A download of these reports: `{filename, content_type, body}`, or nil."
  @callback export([Gamend.Reports.Report.t()]) :: {String.t(), String.t(), iodata()} | nil

  @optional_callbacks topic_label: 1,
                      topic_icon: 1,
                      fields: 1,
                      subject_component: 0,
                      subject_label: 1,
                      admin_subject: 1,
                      error_message: 1,
                      export: 1

  @doc "`ui.topic_label(topic)`, or the topic itself when the kind has none."
  @spec topic_label(module() | nil, String.t()) :: String.t()
  def topic_label(ui, topic) do
    if exports?(ui, :topic_label, 1), do: ui.topic_label(topic), else: topic
  end

  @doc "`ui.topic_icon(topic)`, or nil."
  @spec topic_icon(module() | nil, String.t()) :: String.t() | nil
  def topic_icon(ui, topic) do
    if exports?(ui, :topic_icon, 1), do: ui.topic_icon(topic), else: nil
  end

  @doc "`ui.fields(topic)`, or none."
  @spec fields(module() | nil, String.t() | nil) :: [field()]
  def fields(ui, topic) do
    if exports?(ui, :fields, 1), do: ui.fields(topic), else: []
  end

  @doc "`ui.subject_component()`, or nil."
  @spec subject_component(module() | nil) :: module() | nil
  def subject_component(ui) do
    if exports?(ui, :subject_component, 0), do: ui.subject_component(), else: nil
  end

  @doc "`ui.subject_label(report)`, falling back to the report's subject key, else `\"\"`."
  @spec subject_label(module() | nil, Gamend.Reports.Report.t()) :: String.t()
  def subject_label(ui, report) do
    label = if exports?(ui, :subject_label, 1), do: ui.subject_label(report)
    label || report.subject_ref || ""
  end

  @doc "`ui.error_message(reason)`, or nil."
  @spec error_message(module() | nil, term()) :: String.t() | nil
  def error_message(ui, reason) do
    if exports?(ui, :error_message, 1), do: ui.error_message(reason), else: nil
  end

  @doc "Whether `ui` can export."
  @spec export?(module() | nil) :: boolean()
  def export?(ui), do: exports?(ui, :export, 1)

  @doc "Whether `ui` draws its own admin row."
  @spec admin_subject?(module() | nil) :: boolean()
  def admin_subject?(ui), do: exports?(ui, :admin_subject, 1)

  # A module not yet loaded answers false to `function_exported?/3`, which in
  # dev (modules load on first call) would hide a kind's UI until something
  # else happened to call it.
  defp exports?(nil, _fun, _arity), do: false

  defp exports?(ui, fun, arity),
    do: Code.ensure_loaded?(ui) and function_exported?(ui, fun, arity)
end
