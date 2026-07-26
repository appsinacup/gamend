defmodule GameServer.SettingsHelpers do
  @moduledoc """
  Set a declared setting for the duration of a test.

  Settings resolve from `Application` config, not from the environment, so a
  test that used to `System.put_env/2` sets the value here instead. Merging
  rather than replacing keeps sibling keys in the same provider intact.
  """

  @spec put(atom(), module(), atom(), term()) :: :ok
  def put(app, module, key, value) do
    Application.put_env(app, module, Keyword.put(current(app, module), key, value))
  end

  @spec delete(atom(), module(), atom()) :: :ok
  def delete(app, module, key) do
    Application.put_env(app, module, Keyword.delete(current(app, module), key))
  end

  @spec get(atom(), module(), atom()) :: term()
  def get(app, module, key), do: Keyword.get(current(app, module), key)

  defp current(app, module), do: Application.get_env(app, module, [])
end
