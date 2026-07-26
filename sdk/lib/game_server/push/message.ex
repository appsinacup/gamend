defmodule GameServer.Push.Message do
  @moduledoc """
  Validated push message struct from GameServer.

  This is a stub module for SDK type definitions. The actual struct
  is provided by GameServer at runtime. `GameServer.Push.send_to_user/3`
  accepts a plain map with these keys — plugins rarely build the struct
  directly.

  ## Fields

  - `title` - Required, capped by `LIMIT_MAX_PUSH_TITLE`
  - `body` - Optional body text, capped by `LIMIT_MAX_PUSH_BODY`
  - `data` - Optional custom key/value map delivered to the app
  - `image` - Optional image URL
  - `sound` - Optional sound name
  - `badge` - Optional iOS badge count
  - `collapse_key` - Optional dedupe key; a newer push replaces an older
    one with the same key on-device
  """

  @type t :: %__MODULE__{
          title: String.t(),
          body: String.t() | nil,
          data: map() | nil,
          image: String.t() | nil,
          sound: String.t() | nil,
          badge: non_neg_integer() | nil,
          collapse_key: String.t() | nil
        }

  defstruct [
    :title,
    :body,
    :data,
    :image,
    :sound,
    :badge,
    :collapse_key
  ]
end
