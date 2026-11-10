// The client: configuration, transports, and the one place results arrive.
//
//     var client = new Client(new Config
//     {
//         BaseUrl = "https://game.example.com",
//         Http = new HttpClientTransport(),
//     });
//
//     var signedIn = await client.Auth.LoginDevice("device-123");
//     if (!signedIn.Ok) return;
//     var reply = await client.Api.LobbiesQuickJoin(new JObject { ["title"] = "duel" });
//
//     // Once per frame, on the game thread:
//     client.Poll();
//
// I/O never runs on the game thread, and results never arrive anywhere else:
// transports complete into an inbox that `Poll` drains, in arrival order, along
// with the timers (token refresh, sign-in polling, heartbeats, reconnects). A
// task never completes inside the call that started it.
using System;

namespace Gamend
{
    public sealed class Client : IDisposable
    {
        private readonly Core _core;

        public Client(Config config)
        {
            _core = new Core(config);
        }

        /// <summary>Every operation of the REST API, one method each.</summary>
        public Api Api
        {
            get { return _core.Api; }
        }

        /// <summary>Signing in, and staying signed in.</summary>
        public Auth Auth
        {
            get { return _core.Auth; }
        }

        /// <summary>The authenticated caller `Api` is built on, for a path it lacks.</summary>
        public Rest Rest
        {
            get { return _core.Rest; }
        }

        /// <summary>The realtime connection: channels, events, server hooks.</summary>
        public Realtime Realtime
        {
            get { return _core.Realtime; }
        }

        /// <summary>Live key-value rows over the realtime connection, and their cache.</summary>
        public Kv Kv
        {
            get { return _core.Kv; }
        }

        /// <summary>Who is around, as the realtime events tell it.</summary>
        public Presence Presence
        {
            get { return _core.Presence; }
        }

        /// <summary>WebRTC DataChannels to the server, signaled over the user channel.</summary>
        public WebRtc WebRtc
        {
            get { return _core.WebRtc; }
        }

        /// <summary>The transport the realtime layer drives; null when none was given.</summary>
        public IWebSocketTransport WebSocket
        {
            get { return _core.Config.WebSocket; }
        }

        public string BaseUrl
        {
            get { return _core.BaseUrl; }
        }

        public string RunId
        {
            get { return _core.RunId; }
        }

        /// <summary>Run what arrived since the last call: replies, then due timers. Call it once
        /// per frame on the game thread. Every task completes in here, and an `await` on one
        /// continues in here too.</summary>
        public void Poll()
        {
            _core.Loop.Drain();
        }

        /// <summary>Stop: a reply still on its way finds nothing to complete, and the transports
        /// the client was given are disposed when they can be.</summary>
        public void Dispose()
        {
            _core.Loop.Close();
            (_core.Config.WebRtc as IDisposable)?.Dispose();
            (_core.Config.Http as IDisposable)?.Dispose();
            (_core.Config.WebSocket as IDisposable)?.Dispose();
        }
    }
}
