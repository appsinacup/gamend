defmodule GamendWeb.UrlParam do
  @moduledoc """
  The names of query parameters the admin pages and lists read and write.
  """

  @all ~w(page filter sort status user lobby group key source state category active open domain
         locale severity lang session members days currency type title max_members min_members
         max_users min_users is_locked metadata_key metadata_value kind user_id sender_id
         chat_ref_id chat_type content word reported_user_id subject_ref topic)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  defmacro page_size, do: "page-size"

  defmacro page_size_key, do: "page_size"
end
