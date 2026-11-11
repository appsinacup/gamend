// The only place a network library appears. The core speaks to these
// interfaces (HTTP, WebSocket, and a WebRTC peer); `Gamend.Net` ships
// HttpClient and ClientWebSocket implementations, an engine plugs in its own
// (Unity's UnityWebRequest and a jslib socket on WebGL), and the unit tests use
// `Gamend.Testing`.
//
// A transport may complete on any thread. The client hands every completion to
// the game thread through its inbox, so an implementation never needs to.
using System;
using System.Collections.Generic;
using System.Text;

namespace Gamend
{
    public sealed class HttpRequest
    {
        /// <summary>GET, POST, PUT, PATCH or DELETE.</summary>
        public string Method { get; set; } = "";
        public string Url { get; set; } = "";
        /// <summary>Empty for none.</summary>
        public byte[] Body { get; set; } = Array.Empty<byte>();
        public List<KeyValuePair<string, string>> Headers { get; set; } = new List<KeyValuePair<string, string>>();
        public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(10);

        /// <summary>`Body` as text.</summary>
        public string BodyText
        {
            get { return Encoding.UTF8.GetString(Body); }
        }
    }

    public sealed class HttpResponse
    {
        /// <summary>0 when no reply arrived.</summary>
        public int Status { get; set; }
        public byte[] Body { get; set; } = Array.Empty<byte>();
        /// <summary>Why no reply arrived; empty when one did.</summary>
        public string Error { get; set; } = "";
    }

    public interface IHttpTransport
    {
        /// <summary>Send `request`; call `done` exactly once, from any thread. A 4xx or 5xx is a
        /// reply like any other, not an `Error`.</summary>
        void Send(HttpRequest request, Action<HttpResponse> done);
    }

    public sealed class WebSocketHandlers
    {
        public Action OnOpen { get; set; }
        public Action<string> OnText { get; set; }
        /// <summary>A binary frame: the server's protobuf events, when asked for.</summary>
        public Action<byte[]> OnBinary { get; set; }
        /// <summary>The connection ended, whoever ended it. It may or may not come for a
        /// `Close()` the client asked for.</summary>
        public Action<int, string> OnClose { get; set; }
        /// <summary>The connection failed, opening or open. `OnClose` may follow.</summary>
        public Action<string> OnError { get; set; }
    }

    public interface IWebSocketTransport
    {
        /// <summary>Connect to `url` (`ws://` or `wss://`). The handlers may run on any thread.
        /// Reconnecting is the caller's business, not the transport's.</summary>
        void Open(string url, WebSocketHandlers handlers);
        void SendText(string frame);
        void Close();
    }

    /// <summary>A WebRTC DataChannel to open.</summary>
    public sealed class DataChannelSpec
    {
        public string Label { get; }
        public bool Ordered { get; }
        /// <summary>-1: reliable. 0 or more: give up on a message after that many retries.</summary>
        public int MaxRetransmits { get; }

        public DataChannelSpec(string label, bool ordered = true, int maxRetransmits = -1)
        {
            Label = label;
            Ordered = ordered;
            MaxRetransmits = maxRetransmits;
        }
    }

    /// <summary>What a peer connection reports, from any thread.</summary>
    public sealed class PeerHandlers
    {
        /// <summary>The offer to send: its SDP and type (`offer`).</summary>
        public Action<string, string> OnLocalDescription { get; set; }
        /// <summary>An ICE candidate (`candidate:...`) and its media id.</summary>
        public Action<string, string> OnLocalCandidate { get; set; }
        /// <summary>`connecting`, `connected`, `disconnected`, `failed` or `closed`.</summary>
        public Action<string> OnState { get; set; }
        public Action<string> OnChannelOpen { get; set; }
        public Action<string> OnChannelClose { get; set; }
        /// <summary>The channel's label, the data, and whether it came as binary.</summary>
        public Action<string, byte[], bool> OnMessage { get; set; }
    }

    public interface IPeerTransport
    {
        /// <summary>Create the connection with `channels` (each negotiated with `protocol`, empty
        /// or `protobuf`) and make the offer.</summary>
        void Open(IReadOnlyList<string> iceServers, IReadOnlyList<DataChannelSpec> channels, string protocol, PeerHandlers handlers);
        void SetRemoteDescription(string sdp, string type);
        void AddRemoteCandidate(string candidate, string mid);
        /// <summary>False when the channel is not open.</summary>
        bool Send(string label, byte[] data, bool binary);
        void Close();
    }
}
