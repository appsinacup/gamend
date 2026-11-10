using System;
using System.Collections.Generic;

namespace Gamend
{
    public enum LogLevel
    {
        Debug,
        Info,
        Warning,
        Error,
    }

    public enum RealtimeFormat
    {
        /// <summary>Every server event as JSON text.</summary>
        Json,
        /// <summary>The events `proto/gamend_realtime.proto` maps as binary protobuf frames,
        /// decoded before they reach `OnEvent`: smaller on the wire, and timestamps arrive as
        /// unix milliseconds (`*_ms`).</summary>
        Protobuf,
    }

    public sealed class Config
    {
        /// <summary>The server root, `https://game.example.com`; paths are appended to it.</summary>
        public string BaseUrl { get; set; } = "";
        /// <summary>Required. `new HttpClientTransport()`, an engine adapter, or a fake.</summary>
        public IHttpTransport Http { get; set; }
        /// <summary>For the realtime layer; unused until it connects.</summary>
        public IWebSocketTransport WebSocket { get; set; }
        /// <summary>For `Client.WebRtc`: an engine's own peer connection. Unused until it connects.</summary>
        public IPeerTransport WebRtc { get; set; }
        public TimeSpan HttpTimeout { get; set; } = TimeSpan.FromSeconds(10);
        /// <summary>Opens a sign-in page for `Auth.SignIn`: the system browser, a web view.
        /// Without it, sign-in through a provider fails.</summary>
        public Action<string> OpenUrl { get; set; }
        /// <summary>Where the SDK's own lines go. Silent without it.</summary>
        public Action<LogLevel, string> Log { get; set; }
        /// <summary>This run's id, sent as `x-gamend-session` so the server files a run's client
        /// and server lines together. Random when empty.</summary>
        public string RunId { get; set; } = "";
        /// <summary>How often `Auth.SignIn` asks whether the player finished at the provider.</summary>
        public TimeSpan SignInPoll { get; set; } = TimeSpan.FromSeconds(1);
        /// <summary>How long `Auth.SignIn` waits for them.</summary>
        public TimeSpan SignInTimeout { get; set; } = TimeSpan.FromSeconds(300);
        /// <summary>How the server sends realtime events.</summary>
        public RealtimeFormat RealtimeFormat { get; set; } = RealtimeFormat.Json;
        /// <summary>How long a join or a push waits for the server's reply.</summary>
        public TimeSpan PushTimeout { get; set; } = TimeSpan.FromSeconds(10);
        /// <summary>ICE servers for WebRTC, as `stun:host:port` or `turn:user:pass@host:port`.</summary>
        public List<string> IceServers { get; set; } = new List<string> { "stun:stun.l.google.com:19302" };
        /// <summary>The DataChannels `WebRtc.Connect` opens. The server answers hook calls on
        /// `events` and holds up to four channels.</summary>
        public List<DataChannelSpec> DataChannels { get; set; } = new List<DataChannelSpec> { new DataChannelSpec("events") };
        /// <summary>How hook calls ride the `events` channel: JSON messages, or protobuf envelopes
        /// with request ids.</summary>
        public RealtimeFormat WebRtcFormat { get; set; } = RealtimeFormat.Json;
        /// <summary>How long `WebRtc.Connect` waits for a channel to open.</summary>
        public TimeSpan WebRtcTimeout { get; set; } = TimeSpan.FromSeconds(15);
        /// <summary>The waits before each reconnect attempt; the last repeats.</summary>
        public List<TimeSpan> ReconnectDelays { get; set; } = new List<TimeSpan>
        {
            TimeSpan.FromMilliseconds(100),
            TimeSpan.FromMilliseconds(500),
            TimeSpan.FromMilliseconds(1000),
            TimeSpan.FromMilliseconds(2000),
            TimeSpan.FromMilliseconds(5000),
            TimeSpan.FromMilliseconds(10000),
        };
        /// <summary>Monotonic milliseconds for timers; a stopwatch when null. Tests pass a fake one.</summary>
        public Func<long> Clock { get; set; }
        /// <summary>Unix seconds, for when a kept session's token lapses; the system clock when null.</summary>
        public Func<long> UnixClock { get; set; }
    }
}
