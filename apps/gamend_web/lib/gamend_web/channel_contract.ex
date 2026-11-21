defmodule GamendWeb.ChannelContract do
  @moduledoc """
  Refuses a channel message whose payload does not match its documented
  command, before the channel's `handle_in/3` runs: the channels' twin of
  `GamendWeb.Plugs.RequestContract`.

  A command's keys and their types are its row in
  `GamendWeb.RealtimeCommands`, the registry the SDKs are generated from.
  The payload is checked by `GamendWeb.PayloadContract`. A mismatch is answered
  `{:error, %{error: "validation_failed", errors: %{key => [message]}}}`,
  the shape a 422 has over HTTP, and the channel goes on: a handler that
  crashed on a wrong type took the whole channel and every broadcast it
  carried with it.

  Every core channel has it by `use GamendWeb, :channel`, which wraps
  `handle_in/3` (`__before_compile__/1`). An event the registry does not name
  is left to the channel (its catch-all answers it). The WebRTC data
  channel's `call_hook` is held to the same row (`GamendWeb.WebRTCPeer`).
  """

  require Logger

  alias GamendWeb.PayloadContract
  alias GamendWeb.RealtimeCommands

  @validation_failed "validation_failed"

  @doc "`:ok`, or the errors per key, for `payload` sent as `event` on `topic`."
  @spec check(String.t(), String.t(), term()) :: :ok | {:error, %{String.t() => [String.t()]}}
  def check(topic, event, payload) do
    case RealtimeCommands.find(topic, event) do
      nil -> :ok
      command -> check_command(command, payload)
    end
  end

  @doc "The error code a refused payload is answered with."
  @spec validation_failed() :: String.t()
  def validation_failed, do: @validation_failed

  @doc "The error reply for `errors`, as a channel answers it."
  @spec error_reply(%{String.t() => [String.t()]}) :: map()
  def error_reply(errors), do: %{error: @validation_failed, errors: errors}

  defp check_command(%{required: required, types: types}, payload) do
    declaration =
      Enum.map(types, fn {key, type} ->
        {key, if(key in required, do: type, else: {:optional, type})}
      end)

    PayloadContract.check(declaration, payload)
  end

  @doc "Logs a refused payload at info: the client's mistake, never ours."
  @spec log_refusal(String.t(), String.t(), map()) :: :ok
  def log_refusal(topic, event, errors) do
    Logger.info(fn ->
      "ChannelContract: refused #{inspect(event)} on #{topic}: #{inspect(errors, limit: 10)}"
    end)
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      defoverridable handle_in: 3

      @impl true
      def handle_in(event, payload, socket) do
        case GamendWeb.ChannelContract.check(socket.topic, event, payload) do
          :ok ->
            super(event, payload, socket)

          {:error, errors} ->
            GamendWeb.ChannelContract.log_refusal(socket.topic, event, errors)
            {:reply, {:error, GamendWeb.ChannelContract.error_reply(errors)}, socket}
        end
      end
    end
  end
end
