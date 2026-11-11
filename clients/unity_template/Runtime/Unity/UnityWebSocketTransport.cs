// The realtime connection's socket. On WebGL it is the browser's WebSocket,
// reached through GamendWebSocket.jslib, since a WebGL player has no sockets of
// its own; everywhere else, the editor included, it is System.Net.WebSockets
// (`Gamend.Net.ClientWebSocketTransport`).
//
// One connection at a time: `Open` replaces the one before it.
using System;
#if UNITY_WEBGL && !UNITY_EDITOR
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using AOT;
using UnityEngine;
#endif

namespace Gamend.Unity
{
    public sealed class UnityWebSocketTransport : IWebSocketTransport, IDisposable
    {
#if UNITY_WEBGL && !UNITY_EDITOR
        private delegate void OpenCallback(int id);
        private delegate void DataCallback(int id, IntPtr data, int length, int binary);
        private delegate void ErrorCallback(int id, IntPtr text, int length);
        private delegate void CloseCallback(int id, int code, IntPtr reason, int length);

        [DllImport("__Internal")]
        private static extern void GamendWebSocketInit(OpenCallback open, DataCallback data, ErrorCallback error, CloseCallback close);

        [DllImport("__Internal")]
        private static extern void GamendWebSocketOpen(int id, string url);

        [DllImport("__Internal")]
        private static extern void GamendWebSocketSend(int id, string frame);

        [DllImport("__Internal")]
        private static extern void GamendWebSocketClose(int id);

        // WebGL has one thread, so these need no lock. A connection is here from
        // `Open` until it closes or is closed: an event for an id not here is
        // from a connection already let go, and reaches nobody.
        private static readonly Dictionary<int, WebSocketHandlers> Connections = new Dictionary<int, WebSocketHandlers>();
        private static bool _initialized;
        private static int _lastId;

        private int _id;

        public void Open(string url, WebSocketHandlers handlers)
        {
            Close();
            if (!_initialized)
            {
                GamendWebSocketInit(OnOpen, OnData, OnError, OnClose);
                _initialized = true;
            }
            _id = ++_lastId;
            Connections[_id] = handlers;
            GamendWebSocketOpen(_id, url);
        }

        public void SendText(string frame)
        {
            if (_id != 0) GamendWebSocketSend(_id, frame);
        }

        public void Close()
        {
            if (_id == 0) return;
            Connections.Remove(_id);
            GamendWebSocketClose(_id);
            _id = 0;
        }

        public void Dispose()
        {
            Close();
        }

        [MonoPInvokeCallback(typeof(OpenCallback))]
        private static void OnOpen(int id)
        {
            WebSocketHandlers handlers;
            if (!Connections.TryGetValue(id, out handlers)) return;
            Guard(() => handlers.OnOpen?.Invoke());
        }

        [MonoPInvokeCallback(typeof(DataCallback))]
        private static void OnData(int id, IntPtr data, int length, int binary)
        {
            WebSocketHandlers handlers;
            if (!Connections.TryGetValue(id, out handlers)) return;
            var bytes = Copy(data, length);
            Guard(() =>
            {
                if (binary != 0)
                {
                    handlers.OnBinary?.Invoke(bytes);
                }
                else
                {
                    handlers.OnText?.Invoke(Encoding.UTF8.GetString(bytes));
                }
            });
        }

        [MonoPInvokeCallback(typeof(ErrorCallback))]
        private static void OnError(int id, IntPtr text, int length)
        {
            WebSocketHandlers handlers;
            if (!Connections.TryGetValue(id, out handlers)) return;
            var message = Encoding.UTF8.GetString(Copy(text, length));
            Guard(() => handlers.OnError?.Invoke(message));
        }

        [MonoPInvokeCallback(typeof(CloseCallback))]
        private static void OnClose(int id, int code, IntPtr reason, int length)
        {
            WebSocketHandlers handlers;
            if (!Connections.TryGetValue(id, out handlers)) return;
            Connections.Remove(id);
            var text = Encoding.UTF8.GetString(Copy(reason, length));
            Guard(() => handlers.OnClose?.Invoke(code, text));
        }

        // The jslib frees the bytes when the call returns.
        private static byte[] Copy(IntPtr data, int length)
        {
            var bytes = new byte[length];
            if (length > 0) Marshal.Copy(data, bytes, 0, length);
            return bytes;
        }

        // An exception must not unwind into the browser's event handler, which
        // would take the player down with it.
        private static void Guard(Action call)
        {
            try
            {
                call();
            }
            catch (Exception e)
            {
                Debug.LogException(e);
            }
        }
#else
        private readonly Gamend.Net.ClientWebSocketTransport _socket = new Gamend.Net.ClientWebSocketTransport();

        public void Open(string url, WebSocketHandlers handlers)
        {
            _socket.Open(url, handlers);
        }

        public void SendText(string frame)
        {
            _socket.SendText(frame);
        }

        public void Close()
        {
            _socket.Close();
        }

        public void Dispose()
        {
            _socket.Dispose();
        }
#endif
    }
}
