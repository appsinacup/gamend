defmodule Gamend.Reports.Kind do
  @moduledoc """
  What a report can be about.

  Core ships one kind, `"page"` (`Gamend.Reports.Kinds.Page`): something on a
  page is broken or wrong. A host adds its own by implementing this behaviour
  and listing the module:

      config :gamend_core, :report_kinds, [MyGame.Reports.Word]

  A kind owns two things: which **topics** a report on it may pick ("the
  translation is wrong", "the audio is wrong"), and how a submitted subject is
  **checked and snapshotted** (`c:cast/2`). Everything else — storage, limits,
  the admin queue, attachments, the API — is core's and the same for every
  kind.

  ## `cast/2`

  Gets the kind-specific params as sent (`"subject"` and `"data"` maps, plus
  `"topic"`) and the context (`:user_id`, `:locale`, `:source`). Answers:

      {:ok, %{subject_ref: "ro/1234", subject: %{...}, data: %{...}}}

  `subject_ref` is the short key duplicates group on, nil when nothing groups
  them. `subject` is the snapshot shown in the queue — take it now, because
  what was reported may be renamed or removed by the time anyone reads it.
  `data` is the kind's extra fields, already trimmed and capped. An
  `{:error, reason}` is shown to the reporter as "check what you entered".

  ## The web side

  `c:ui/0` names the module that draws the kind on `/report` and in the admin
  queue (`GamendWeb.Reports.KindUI`). A kind with no UI is API-only: a game
  client can file it, and nobody can from the website.
  """

  @typedoc "What `cast/2` answers on success."
  @type cast_result :: %{
          required(:subject_ref) => String.t() | nil,
          required(:subject) => map(),
          required(:data) => map()
        }

  @doc "The kind's key, stored on every report (`\"word\"`). Lowercase, no spaces."
  @callback key() :: String.t()

  @doc "The topics a report may pick, in display order. `[]` for none."
  @callback topics() :: [String.t()]

  @doc "How many images a report may carry (0 = none)."
  @callback max_attachments() :: non_neg_integer()

  @doc "Whether a report must say something in its description."
  @callback description_required?(topic :: String.t() | nil) :: boolean()

  @doc "Check and snapshot a submitted subject. See the module doc."
  @callback cast(params :: map(), context :: map()) :: {:ok, cast_result()} | {:error, term()}

  @doc "The module that draws this kind (`GamendWeb.Reports.KindUI`), nil for API-only."
  @callback ui() :: module() | nil

  @optional_callbacks description_required?: 1, ui: 0
end
