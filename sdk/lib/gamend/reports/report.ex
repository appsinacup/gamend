defmodule Gamend.Reports.Report do
  @moduledoc """
  Content report struct from Gamend (`Gamend.Reports`).

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - Report ID (string, UUID)
  - `kind` - What it is about: `"page"`, or a kind the host added (string)
  - `topic` - One of the kind's topics, or `nil` (string)
  - `subject_ref` - The kind's short key duplicates group on (string)
  - `subject` - The kind's snapshot of what was reported (map)
  - `data` - The kind's extra fields, such as a suggested correction (map)
  - `description` - What the reporter wrote (string)
  - `email` - Where the reporter asked for a reply, if anywhere (string)
  - `locale` - The reporter's site language (string)
  - `source` - `"web"` or `"api"` (string)
  - `client` - Browser or device facts: user_agent, viewport, screen (map)
  - `attachments` - `%{"files" => [%{"key", "type", "size"}]}` (map)
  - `user_id` - The reporter, `nil` for a visitor (string)
  - `status` - `"open"`, `"fixed"`, `"wontfix"` or `"duplicate"` (string)
  - `resolved_by` - Admin who closed it (string)
  - `resolution_note` - The admin's note (string)
  - `resolved_at` - When it was closed
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type t :: %__MODULE__{
          id: String.t(),
          kind: String.t(),
          topic: String.t() | nil,
          subject_ref: String.t() | nil,
          subject: map(),
          data: map(),
          description: String.t() | nil,
          email: String.t() | nil,
          locale: String.t() | nil,
          source: String.t(),
          client: map(),
          attachments: map(),
          user_id: String.t() | nil,
          status: String.t(),
          resolved_by: String.t() | nil,
          resolution_note: String.t() | nil,
          resolved_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :kind,
    :topic,
    :subject_ref,
    :subject,
    :data,
    :description,
    :email,
    :locale,
    :source,
    :client,
    :attachments,
    :user_id,
    :status,
    :resolved_by,
    :resolution_note,
    :resolved_at,
    :inserted_at,
    :updated_at
  ]
end
