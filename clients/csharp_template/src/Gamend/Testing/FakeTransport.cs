// Transports and a clock a test drives by hand, so a game's own tests can use
// them too.
//
//     var server = new FakeHttp();
//     var clock = new FakeClock();
//     var client = new Client(new Config
//     {
//         BaseUrl = "http://test",
//         Http = server,
//         Clock = clock.Steady,
//         UnixClock = clock.Wall,
//     });
//
//     var task = client.Api.UsersGetCurrentUser();
//     server.Reply(200, "{\"data\": {\"id\": \"u1\"}}");
//     client.Poll();                       // `task` completes here
using System;
using System.Collections.Generic;
using System.Text;

namespace Gamend.Testing
{
    /// <summary>An HTTP transport that answers when told to. Every request is kept, in the order
    /// it was sent; the unanswered ones wait in `Pending`.</summary>
    public sealed class FakeHttp : IHttpTransport
    {
        private sealed class Waiting
        {
            public HttpRequest Request;
            public Action<HttpResponse> Done;
        }

        private readonly object _lock = new object();
        private readonly List<HttpRequest> _sent = new List<HttpRequest>();
        private readonly Queue<Waiting> _waiting = new Queue<Waiting>();

        public void Send(HttpRequest request, Action<HttpResponse> done)
        {
            lock (_lock)
            {
                _sent.Add(request);
                _waiting.Enqueue(new Waiting { Request = request, Done = done });
            }
        }

        /// <summary>Every request sent so far, answered or not.</summary>
        public List<HttpRequest> Sent
        {
            get
            {
                lock (_lock)
                {
                    return new List<HttpRequest>(_sent);
                }
            }
        }

        public int Pending
        {
            get
            {
                lock (_lock)
                {
                    return _waiting.Count;
                }
            }
        }

        /// <summary>The oldest unanswered request. Check `Pending` first.</summary>
        public HttpRequest Next
        {
            get
            {
                lock (_lock)
                {
                    return _waiting.Peek().Request;
                }
            }
        }

        /// <summary>Answer the oldest unanswered request.</summary>
        public void Reply(int status, string body)
        {
            Complete(new HttpResponse { Status = status, Body = Encoding.UTF8.GetBytes(body) });
        }

        /// <summary>Fail the oldest unanswered request, as a transport does when no reply arrives.</summary>
        public void Fail(string error)
        {
            Complete(new HttpResponse { Error = error });
        }

        /// <summary>The value of `name` in `request`'s headers, or empty.</summary>
        public static string Header(HttpRequest request, string name)
        {
            foreach (var header in request.Headers)
            {
                if (header.Key == name) return header.Value;
            }
            return "";
        }

        private void Complete(HttpResponse response)
        {
            Action<HttpResponse> done;
            lock (_lock)
            {
                if (_waiting.Count == 0) return;
                done = _waiting.Dequeue().Done;
            }
            done(response);
        }
    }

    /// <summary>A WebSocket transport the test opens, feeds and drops.</summary>
    public sealed class FakeWebSocket : IWebSocketTransport
    {
        private readonly object _lock = new object();
        private string _url = "";
        private WebSocketHandlers _handlers = new WebSocketHandlers();
        private readonly List<string> _frames = new List<string>();
        private List<string> _unread = new List<string>();
        private bool _opened;
        private int _opens;

        public void Open(string url, WebSocketHandlers handlers)
        {
            lock (_lock)
            {
                _url = url;
                _handlers = handlers;
                _opened = true;
                _opens++;
            }
        }

        public void SendText(string frame)
        {
            lock (_lock)
            {
                _frames.Add(frame);
                _unread.Add(frame);
            }
        }

        public void Close()
        {
            lock (_lock)
            {
                _opened = false;
            }
        }

        public string Url
        {
            get
            {
                lock (_lock)
                {
                    return _url;
                }
            }
        }

        public bool Opened
        {
            get
            {
                lock (_lock)
                {
                    return _opened;
                }
            }
        }

        /// <summary>Every frame the client sent, oldest first.</summary>
        public List<string> Frames
        {
            get
            {
                lock (_lock)
                {
                    return new List<string>(_frames);
                }
            }
        }

        /// <summary>How many times the client opened a connection.</summary>
        public int Opens
        {
            get
            {
                lock (_lock)
                {
                    return _opens;
                }
            }
        }

        /// <summary>The frames sent since the last `TakeFrames`, oldest first.</summary>
        public List<string> TakeFrames()
        {
            lock (_lock)
            {
                var frames = _unread;
                _unread = new List<string>();
                return frames;
            }
        }

        private WebSocketHandlers Handlers
        {
            get
            {
                lock (_lock)
                {
                    return _handlers;
                }
            }
        }

        // The server side: accept, send a frame, drop the connection.
        public void Accept()
        {
            Handlers.OnOpen?.Invoke();
        }

        public void Receive(string frame)
        {
            Handlers.OnText?.Invoke(frame);
        }

        public void ReceiveBinary(byte[] bytes)
        {
            Handlers.OnBinary?.Invoke(bytes);
        }

        /// <summary>The connection fails before or after opening, as a transport reports it.</summary>
        public void Fail(string error)
        {
            Handlers.OnError?.Invoke(error);
        }

        public void Drop(int code = 1006, string reason = "")
        {
            lock (_lock)
            {
                _opened = false;
            }
            Handlers.OnClose?.Invoke(code, reason);
        }
    }

    /// <summary>A WebRTC peer the test drives: it records what the client asks of it, and plays
    /// the connection's side of the story on command.</summary>
    public sealed class FakePeer : IPeerTransport
    {
        public sealed class SentData
        {
            public string Label;
            public byte[] Data;
            public bool Binary;

            public string Text
            {
                get { return Encoding.UTF8.GetString(Data); }
            }
        }

        private readonly object _lock = new object();
        private PeerHandlers _handlers = new PeerHandlers();
        private List<string> _iceServers = new List<string>();
        private List<DataChannelSpec> _channels = new List<DataChannelSpec>();
        private string _protocol = "";
        private (string Sdp, string Type) _remote = ("", "");
        private readonly List<(string Candidate, string Mid)> _candidates = new List<(string Candidate, string Mid)>();
        private readonly List<SentData> _sent = new List<SentData>();
        private bool _opened;
        private int _closes;

        public void Open(IReadOnlyList<string> iceServers, IReadOnlyList<DataChannelSpec> channels, string protocol, PeerHandlers handlers)
        {
            lock (_lock)
            {
                _iceServers = new List<string>(iceServers);
                _channels = new List<DataChannelSpec>(channels);
                _protocol = protocol;
                _handlers = handlers;
                _opened = true;
            }
        }

        public void SetRemoteDescription(string sdp, string type)
        {
            lock (_lock)
            {
                _remote = (sdp, type);
            }
        }

        public void AddRemoteCandidate(string candidate, string mid)
        {
            lock (_lock)
            {
                _candidates.Add((candidate, mid));
            }
        }

        public bool Send(string label, byte[] data, bool binary)
        {
            lock (_lock)
            {
                _sent.Add(new SentData { Label = label, Data = data, Binary = binary });
                return true;
            }
        }

        public void Close()
        {
            lock (_lock)
            {
                _opened = false;
                _closes++;
            }
        }

        public bool Opened
        {
            get { lock (_lock) { return _opened; } }
        }

        public int Closes
        {
            get { lock (_lock) { return _closes; } }
        }

        public string Protocol
        {
            get { lock (_lock) { return _protocol; } }
        }

        public List<string> IceServers
        {
            get { lock (_lock) { return new List<string>(_iceServers); } }
        }

        public List<DataChannelSpec> Channels
        {
            get { lock (_lock) { return new List<DataChannelSpec>(_channels); } }
        }

        /// <summary>The remote description set: SDP and type.</summary>
        public (string Sdp, string Type) Remote
        {
            get { lock (_lock) { return _remote; } }
        }

        public List<(string Candidate, string Mid)> Candidates
        {
            get { lock (_lock) { return new List<(string Candidate, string Mid)>(_candidates); } }
        }

        public List<SentData> Sent
        {
            get { lock (_lock) { return new List<SentData>(_sent); } }
        }

        private PeerHandlers Handlers
        {
            get { lock (_lock) { return _handlers; } }
        }

        // The connection's side.
        public void Offer(string sdp)
        {
            Handlers.OnLocalDescription?.Invoke(sdp, "offer");
        }

        public void Candidate(string candidate, string mid)
        {
            Handlers.OnLocalCandidate?.Invoke(candidate, mid);
        }

        public void State(string state)
        {
            Handlers.OnState?.Invoke(state);
        }

        public void OpenChannel(string label)
        {
            Handlers.OnChannelOpen?.Invoke(label);
        }

        public void CloseChannel(string label)
        {
            Handlers.OnChannelClose?.Invoke(label);
        }

        public void Receive(string label, byte[] data, bool binary)
        {
            Handlers.OnMessage?.Invoke(label, data, binary);
        }

        public void Receive(string label, string text)
        {
            Receive(label, Encoding.UTF8.GetBytes(text), false);
        }
    }

    /// <summary>Both clocks a `Config` takes, moved by hand.</summary>
    public sealed class FakeClock
    {
        private readonly object _lock = new object();
        private long _steady;
        private long _unixMs;

        public FakeClock(long unixSeconds = 1800000000)
        {
            _unixMs = unixSeconds * 1000;
            Steady = () =>
            {
                lock (_lock)
                {
                    return _steady;
                }
            };
            Wall = () =>
            {
                lock (_lock)
                {
                    return _unixMs / 1000;
                }
            };
        }

        /// <summary>For `Config.Clock`.</summary>
        public Func<long> Steady { get; }

        /// <summary>For `Config.UnixClock`.</summary>
        public Func<long> Wall { get; }

        public void Advance(TimeSpan by)
        {
            lock (_lock)
            {
                var ms = (long)by.TotalMilliseconds;
                _steady += ms;
                _unixMs += ms;
            }
        }
    }
}
