// A WebSocket over System.Net.WebSockets, for .NET and for Unity outside WebGL.
//
// One connection at a time. `ClientWebSocket` allows a single send in flight, so
// frames wait in a queue and go one by one.
using System;
using System.Collections.Generic;
using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Gamend.Net
{
    public sealed class ClientWebSocketTransport : IWebSocketTransport, IDisposable
    {
        private sealed class Connection
        {
            public readonly ClientWebSocket Socket = new ClientWebSocket();
            public readonly CancellationTokenSource Cancel = new CancellationTokenSource();
            public readonly object Lock = new object();
            // A null frame is the close handshake, last in line.
            public readonly Queue<string> Outgoing = new Queue<string>();
            public WebSocketHandlers Handlers;
            public bool Sending;
            public volatile bool Closing;
        }

        private const int ReceiveBuffer = 16 * 1024;
        private static readonly TimeSpan CloseGrace = TimeSpan.FromSeconds(2);

        private readonly object _lock = new object();
        private Connection _current;

        public void Open(string url, WebSocketHandlers handlers)
        {
            var connection = new Connection { Handlers = handlers };
            Connection previous;
            lock (_lock)
            {
                previous = _current;
                _current = connection;
            }
            if (previous != null) Stop(previous);
            _ = Run(connection, url);
        }

        public void SendText(string frame)
        {
            Connection connection;
            lock (_lock)
            {
                connection = _current;
            }
            if (connection != null) Enqueue(connection, frame);
        }

        public void Close()
        {
            Connection connection;
            lock (_lock)
            {
                connection = _current;
                _current = null;
            }
            if (connection != null) Stop(connection);
        }

        public void Dispose()
        {
            Close();
        }

        private void Stop(Connection connection)
        {
            connection.Closing = true;
            if (connection.Socket.State == WebSocketState.Open)
            {
                Enqueue(connection, null);
            }
            else
            {
                connection.Cancel.Cancel();
            }
        }

        private async Task Run(Connection connection, string url)
        {
            try
            {
                await connection.Socket.ConnectAsync(new Uri(url), connection.Cancel.Token).ConfigureAwait(false);
                connection.Handlers.OnOpen?.Invoke();
                await Receive(connection).ConfigureAwait(false);
            }
            catch (Exception e)
            {
                if (!connection.Closing) connection.Handlers.OnError?.Invoke(e.Message);
            }
            finally
            {
                connection.Socket.Dispose();
            }
        }

        private static async Task Receive(Connection connection)
        {
            var buffer = new byte[ReceiveBuffer];
            var message = new MemoryStream();
            while (true)
            {
                var part = await connection.Socket
                    .ReceiveAsync(new ArraySegment<byte>(buffer), connection.Cancel.Token)
                    .ConfigureAwait(false);
                if (part.MessageType == WebSocketMessageType.Close)
                {
                    if (connection.Closing) return;
                    connection.Handlers.OnClose?.Invoke(
                        part.CloseStatus.HasValue ? (int)part.CloseStatus.Value : 1005,
                        part.CloseStatusDescription ?? "");
                    return;
                }
                message.Write(buffer, 0, part.Count);
                if (!part.EndOfMessage) continue;
                var bytes = message.ToArray();
                message.SetLength(0);
                if (part.MessageType == WebSocketMessageType.Text)
                {
                    connection.Handlers.OnText?.Invoke(Encoding.UTF8.GetString(bytes));
                }
                else
                {
                    connection.Handlers.OnBinary?.Invoke(bytes);
                }
            }
        }

        private static void Enqueue(Connection connection, string frame)
        {
            lock (connection.Lock)
            {
                connection.Outgoing.Enqueue(frame);
                if (connection.Sending) return;
                connection.Sending = true;
            }
            _ = Pump(connection);
        }

        private static async Task Pump(Connection connection)
        {
            try
            {
                while (true)
                {
                    string frame;
                    lock (connection.Lock)
                    {
                        if (connection.Outgoing.Count == 0)
                        {
                            connection.Sending = false;
                            return;
                        }
                        frame = connection.Outgoing.Dequeue();
                    }
                    if (frame == null)
                    {
                        await CloseHandshake(connection).ConfigureAwait(false);
                        return;
                    }
                    var bytes = Encoding.UTF8.GetBytes(frame);
                    await connection.Socket
                        .SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, connection.Cancel.Token)
                        .ConfigureAwait(false);
                }
            }
            catch (Exception e)
            {
                lock (connection.Lock)
                {
                    connection.Outgoing.Clear();
                    connection.Sending = false;
                }
                if (!connection.Closing) connection.Handlers.OnError?.Invoke(e.Message);
            }
        }

        private static async Task CloseHandshake(Connection connection)
        {
            try
            {
                using (var grace = new CancellationTokenSource(CloseGrace))
                {
                    await connection.Socket
                        .CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "", grace.Token)
                        .ConfigureAwait(false);
                }
            }
            catch (Exception)
            {
                // Saying goodbye is a courtesy: a socket already gone has nothing
                // left to tell, and it is being closed either way.
            }
            finally
            {
                connection.Cancel.Cancel();
            }
        }
    }
}
