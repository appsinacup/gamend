// The realtime connection: Phoenix channels over the WebSocket transport.
//
//     client.Realtime.Connect();          // joins user:<id> itself
//     client.Realtime.OnEvent(e =>
//     {
//         if (e.Kind == Events.LobbyUpdated) RefreshLobby(e.Payload);
//     });
//     await client.Realtime.JoinLobby(lobbyId);
//     var hook = await client.Realtime.CallHook("arena", "start");
//
// A dropped connection reconnects on its own, with a fresh token when the old
// one would not do, and rejoins every topic it had; `OnState` says when. Tasks
// complete and listeners run in `Client.Poll()`. The methods are safe to call
// from any thread.
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    public enum RealtimeState
    {
        /// <summary>Not connected, and not trying: before `Connect()`, after `Disconnect()` or a
        /// sign-out.</summary>
        Disconnected,
        /// <summary>Opening the first connection.</summary>
        Connecting,
        /// <summary>Open; topics are (re)joining or joined.</summary>
        Connected,
        /// <summary>The connection dropped; the next attempt is scheduled or under way.</summary>
        Reconnecting,
    }

    /// <summary>A message the server pushed on a topic.</summary>
    public sealed class Event
    {
        public string Topic { get; set; } = "";
        /// <summary>The event as the server named it (`updated`, `user_joined`, ...).</summary>
        public string Name { get; set; } = "";
        /// <summary>What this SDK calls it: one of `Events`, or `Events.Message` for an event the
        /// table does not name.</summary>
        public string Kind { get; set; } = "";
        /// <summary>The payload. A JSON null for a binary payload nothing decoded; see `Bytes`.</summary>
        public JToken Payload { get; set; } = JValue.CreateNull();
        /// <summary>A binary payload this SDK could not decode, as it arrived.</summary>
        public byte[] Bytes { get; set; } = Array.Empty<byte>();
        /// <summary>It arrived as a protobuf frame (`RealtimeFormat.Protobuf`), decoded or not.</summary>
        public bool Binary { get; set; }
    }

    /// <summary>The server's answer to a join, leave or push.</summary>
    public sealed class Reply
    {
        /// <summary>The server said "ok".</summary>
        public bool Ok { get; set; }
        /// <summary>"ok" or "error" from the server; "timeout", "disconnected" or "not_joined" when
        /// no answer came.</summary>
        public string Status { get; set; } = "";
        /// <summary>What the server answered.</summary>
        public JToken Response { get; set; } = JValue.CreateNull();
        /// <summary>Empty when `Ok`; otherwise `response.error` or `response.reason`, or the
        /// status.</summary>
        public string Error { get; set; } = "";
    }

    /// <summary>A server hook's answer.</summary>
    public sealed class HookResult
    {
        public bool Ok { get; set; }
        /// <summary>What the hook returned.</summary>
        public JToken Data { get; set; } = JValue.CreateNull();
        /// <summary>A typed hook's reply bytes (`WebRtc.CallHookRaw`), undecoded.</summary>
        public byte[] Bytes { get; set; } = Array.Empty<byte>();
        /// <summary>Why it failed: the hook's error, `timeout`, `not_joined`, ...</summary>
        public string Error { get; set; } = "";
    }

    public sealed class Realtime
    {
        private sealed class Topic
        {
            public string Name;
            public JObject Params;
            public bool Joined;
            // A join frame is out and its reply has not come.
            public bool Joining;
            // What `Join` callers wait on: the next join reply.
            public List<Action<Reply>> Waiting = new List<Action<Reply>>();
            public long RejoinTimer;
        }

        private sealed class Pending
        {
            public string Topic;
            public bool Join;
            public Action<Reply> Done;
            public long Timer;
        }

        // How long a channel that errored waits before it tries to join again.
        private const long RejoinMs = 1000;

        private readonly Core _core;
        private readonly Phoenix _phoenix = new Phoenix();
        private volatile RealtimeState _state = RealtimeState.Disconnected;
        private bool _wanted;         // Connect() was called and not undone
        private bool _everOpened;     // the current attempt series has opened once
        private bool _lastOpened;     // the last connection opened before it dropped
        private long _generation;
        private int _attempt;
        private long _heartbeatTimer;
        private long _reconnectTimer;
        private string _userId = "";
        private readonly List<Topic> _topics = new List<Topic>();
        private Dictionary<string, Pending> _pending = new Dictionary<string, Pending>();
        private long _nextListener = 1;
        private readonly Listeners<Event> _eventListeners;
        private readonly Listeners<RealtimeState> _stateListeners;
        private readonly Dictionary<string, Func<byte[], JToken>> _metadataDecoders = new Dictionary<string, Func<byte[], JToken>>();
        private readonly Dictionary<string, Func<byte[], JToken>> _kvDecoders = new Dictionary<string, Func<byte[], JToken>>();

        internal Realtime(Core core)
        {
            _core = core;
            _eventListeners = new Listeners<Event>(core.Loop);
            _stateListeners = new Listeners<RealtimeState>(core.Loop);
        }

        private static Reply ReplyOf(string status, JToken response)
        {
            var reply = new Reply { Status = status, Ok = status == "ok", Response = response ?? JValue.CreateNull() };
            if (!reply.Ok) reply.Error = Json.Text(reply.Response, "error", Json.Text(reply.Response, "reason", status));
            return reply;
        }

        private static Reply LocalReply(string status)
        {
            return ReplyOf(status, new JObject());
        }

        public RealtimeState State
        {
            get { return _state; }
        }

        /// <summary>Open the connection for the signed-in player and join `user:&lt;id&gt;`. Stays
        /// connected, reconnecting as needed, until `Disconnect()` or a sign-out.</summary>
        public void Connect()
        {
            lock (_core.Gate)
            {
                if (_wanted) return;
                _wanted = true;
                _everOpened = false;
                _attempt = 0;
                Open();
            }
        }

        /// <summary>Close the connection and forget every topic. No reconnect.</summary>
        public void Disconnect()
        {
            lock (_core.Gate)
            {
                _wanted = false;
                CloseSocket();
                foreach (var topic in _topics) _core.Loop.Cancel(topic.RejoinTimer);
                var waiting = new List<Action<Reply>>();
                foreach (var topic in _topics) waiting.AddRange(topic.Waiting);
                _topics.Clear();
                foreach (var done in waiting) done(LocalReply("disconnected"));
                SetState(RealtimeState.Disconnected);
            }
        }

        private void CloseSocket()
        {
            ++_generation;  // whatever the old socket still reports is about nothing now
            _core.Loop.Cancel(_heartbeatTimer);
            _core.Loop.Cancel(_reconnectTimer);
            _heartbeatTimer = _reconnectTimer = 0;
            _core.Config.WebSocket?.Close();
            foreach (var topic in _topics) topic.Joined = topic.Joining = false;
            FailPending("disconnected");
        }

        private string Url()
        {
            var url = _core.BaseUrl;
            if (url.StartsWith("https://", StringComparison.Ordinal))
            {
                url = "wss://" + url.Substring(8);
            }
            else if (url.StartsWith("http://", StringComparison.Ordinal))
            {
                url = "ws://" + url.Substring(7);
            }
            var session = _core.Auth.Current;
            url += "/socket/websocket?vsn=2.0.0";
            url += "&token=" + Query.Escape(session != null ? session.AccessToken : "");
            url += "&client_session=" + Query.Escape(_core.RunId);
            if (_core.Config.RealtimeFormat == RealtimeFormat.Protobuf) url += "&format=protobuf";
            return url;
        }

        private void Open()
        {
            var socket = _core.Config.WebSocket;
            var session = _core.Auth.Current;
            if (!_wanted) return;
            if (socket == null || session == null)
            {
                _core.Log(LogLevel.Error, socket == null
                    ? "gamend: realtime has no WebSocket transport"
                    : "gamend: realtime needs a signed-in player");
                _wanted = false;
                SetState(RealtimeState.Disconnected);
                return;
            }
            if (_userId.Length > 0 && session.UserId != _userId)
            {
                // Another player: their channels, none of the last one's.
                var waiting = new List<Action<Reply>>();
                foreach (var topic in _topics)
                {
                    _core.Loop.Cancel(topic.RejoinTimer);
                    waiting.AddRange(topic.Waiting);
                }
                _topics.Clear();
                foreach (var done in waiting) done(LocalReply("disconnected"));
            }
            _userId = session.UserId;
            var user = "user:" + _userId;
            if (Find(user) == null) _topics.Insert(0, new Topic { Name = user, Params = new JObject() });

            var generation = ++_generation;
            _lastOpened = false;
            SetState(_everOpened ? RealtimeState.Reconnecting : RealtimeState.Connecting);
            var loop = _core.Loop;
            socket.Open(Url(), new WebSocketHandlers
            {
                OnOpen = () => loop.Post(() => Opened(generation)),
                OnText = text => loop.Post(() => Received(generation, text)),
                OnBinary = bytes => loop.Post(() => ReceivedBinary(generation, bytes)),
                OnClose = (code, reason) => loop.Post(() => Dropped(generation, "closed (" + code + ") " + reason)),
                OnError = error => loop.Post(() => Dropped(generation, error)),
            });
        }

        private void Opened(long generation)
        {
            if (generation != _generation) return;
            _everOpened = _lastOpened = true;
            _attempt = 0;
            _phoenix.Reset(_core.Loop.Now());
            SetState(RealtimeState.Connected);
            foreach (var topic in _topics.ToArray()) SendJoin(topic);
            ScheduleHeartbeat();
        }

        private void SendJoin(Topic topic)
        {
            _core.Loop.Cancel(topic.RejoinTimer);
            topic.RejoinTimer = 0;
            var frame = _phoenix.Join(topic.Name, topic.Params);
            topic.Joining = true;
            topic.Joined = false;
            Track(frame.Ref, topic.Name, true, null);
            _core.Config.WebSocket.SendText(frame.Text);
        }

        private void ScheduleHeartbeat()
        {
            _core.Loop.Cancel(_heartbeatTimer);
            var generation = _generation;
            _heartbeatTimer = _core.Loop.After(Phoenix.HeartbeatMs, () =>
            {
                if (generation != _generation) return;
                string beat;
                if (!_phoenix.Heartbeat(_core.Loop.Now(), out beat))
                {
                    _core.Log(LogLevel.Warning, "gamend: the server missed a heartbeat; reconnecting");
                    CloseSocket();
                    ScheduleReconnect();
                    return;
                }
                if (beat.Length > 0) _core.Config.WebSocket.SendText(beat);
                ScheduleHeartbeat();
            });
        }

        private void Received(long generation, string text)
        {
            if (generation != _generation) return;
            var decoded = _phoenix.Decode(text);
            if (decoded != null) OnFrame(decoded);
        }

        private void ReceivedBinary(long generation, byte[] bytes)
        {
            if (generation != _generation) return;
            var decoded = _phoenix.DecodeBinary(bytes);
            if (decoded != null) OnFrame(decoded);
        }

        private void OnFrame(Frame frame)
        {
            if (frame.Kind == FrameKind.Reply)
            {
                OnReply(frame);
                return;
            }

            if (frame.Event == "phx_error")
            {
                // The channel crashed on the server; Phoenix's clients join it again.
                var topic = Find(frame.Topic);
                if (topic != null)
                {
                    topic.Joined = topic.Joining = false;
                    ScheduleRejoin(frame.Topic);
                }
            }
            else if (frame.Event == "phx_close")
            {
                // The server closed the channel (a kick, a disband): not rejoined.
                Forget(frame.Topic);
            }

            var received = new Event
            {
                Topic = frame.Topic,
                Name = frame.Event,
                Kind = Events.SignalOf(frame.Topic, frame.Event),
                Binary = frame.Bytes != null,
            };
            if (frame.Bytes != null)
            {
                var decoded = Proto.DecodeBinaryEvent(received.Topic, received.Name, frame.Bytes, BytesOf);
                if (decoded != null)
                {
                    received.Payload = decoded;
                }
                else
                {
                    received.Bytes = frame.Bytes;
                    _core.Log(LogLevel.Warning, "gamend: no decoder for the binary " + received.Name + " on " + received.Topic);
                }
            }
            else
            {
                received.Payload = frame.Payload;
            }
            _eventListeners.Fire(received);
        }

        private void OnReply(Frame frame)
        {
            Pending pending;
            if (!_pending.TryGetValue(frame.Ref, out pending)) return;
            _pending.Remove(frame.Ref);
            _core.Loop.Cancel(pending.Timer);
            var reply = ReplyOf(frame.Status, frame.Bytes != null ? null : frame.Payload);
            if (pending.Join)
            {
                List<Action<Reply>> waiting = null;
                var topic = Find(pending.Topic);
                if (topic != null)
                {
                    topic.Joining = false;
                    topic.Joined = reply.Ok;
                    waiting = topic.Waiting;
                    topic.Waiting = new List<Action<Reply>>();
                    if (!reply.Ok)
                    {
                        _core.Log(LogLevel.Warning, "gamend: joining " + pending.Topic + " failed: " + reply.Error);
                        // A refusal the server will repeat: stop asking.
                        if (reply.Error == "unauthorized" || reply.Error == "forbidden"
                            || reply.Error == "not_found" || reply.Error == "invalid topic")
                        {
                            Forget(pending.Topic);
                        }
                        else
                        {
                            ScheduleRejoin(pending.Topic);
                        }
                    }
                }
                if (reply.Ok && pending.Topic == "user:" + _userId) _core.Kv.UserChannelJoined();
                if (waiting != null)
                {
                    foreach (var done in waiting) done(reply);
                }
            }
            pending.Done?.Invoke(reply);
        }

        // A game's own protobuf bytes, read by the decoder it registered. A
        // decoder that throws on bytes it cannot read has answered "nothing".
        private JToken BytesOf(string message, string field, byte[] bytes, JObject decoded)
        {
            Func<byte[], JToken> decoder = null;
            if (field == "metadata_pb")
            {
                // The message a metadata map rides in names whose it is.
                var entity = message == "Lobby" ? "lobby" : message == "Group" ? "group" : message == "Party" ? "party" : "user";
                _metadataDecoders.TryGetValue(entity, out decoder);
            }
            else if (field == "data_pb" && message == "KvEntry")
            {
                decoder = KvDecoderOf(Json.Text(decoded, "key"));
            }
            if (decoder == null) return null;
            try
            {
                return decoder(bytes);
            }
            catch (Exception e)
            {
                _core.Log(LogLevel.Warning, "gamend: a decoder threw on " + field + ": " + e.Message);
                return null;
            }
        }

        private Func<byte[], JToken> KvDecoderOf(string key)
        {
            Func<byte[], JToken> exact;
            if (_kvDecoders.TryGetValue(key, out exact)) return exact;
            Func<byte[], JToken> best = null;
            var bestLength = 0;
            foreach (var entry in _kvDecoders)
            {
                var pattern = entry.Key;
                if (pattern.Length == 0 || pattern[pattern.Length - 1] != '*') continue;
                var prefix = pattern.Length - 1;
                if (prefix >= bestLength && string.CompareOrdinal(key, 0, pattern, 0, prefix) == 0)
                {
                    best = entry.Value;
                    bestLength = prefix;
                }
            }
            return best;
        }

        private void ScheduleRejoin(string name)
        {
            var topic = Find(name);
            if (topic == null) return;
            _core.Loop.Cancel(topic.RejoinTimer);
            var generation = _generation;
            topic.RejoinTimer = _core.Loop.After(RejoinMs, () =>
            {
                if (generation != _generation || _state != RealtimeState.Connected) return;
                var again = Find(name);
                if (again != null && !again.Joined && !again.Joining) SendJoin(again);
            });
        }

        private void Dropped(long generation, string why)
        {
            if (generation != _generation) return;
            _core.Log(LogLevel.Info, "gamend: realtime connection lost: " + why);
            CloseSocket();
            ScheduleReconnect();
        }

        private void ScheduleReconnect()
        {
            if (!_wanted)
            {
                SetState(RealtimeState.Disconnected);
                return;
            }
            SetState(_everOpened ? RealtimeState.Reconnecting : RealtimeState.Connecting);
            var delays = _core.Config.ReconnectDelays;
            var delay = delays == null || delays.Count == 0
                ? 1000
                : (long)delays[Math.Min(_attempt, delays.Count - 1)].TotalMilliseconds;
            ++_attempt;
            var refreshFirst = !_lastOpened;
            _reconnectTimer = _core.Loop.After(delay, () =>
            {
                _reconnectTimer = 0;
                if (!_wanted) return;
                if (!refreshFirst)
                {
                    Open();
                    return;
                }
                // The last attempt never opened: the token may have lapsed while
                // the network was away. Refresh it first; open either way.
                _core.Auth.RefreshThen(_ => Open());
            });
        }

        private void FailPending(string status)
        {
            var pending = _pending;
            _pending = new Dictionary<string, Pending>();
            var waiting = new List<Action<Reply>>();
            foreach (var entry in pending.Values)
            {
                _core.Loop.Cancel(entry.Timer);
                if (entry.Join)
                {
                    // A join waiting on this connection waits on the next one.
                    var topic = Find(entry.Topic);
                    if (topic != null) topic.Joining = false;
                }
                if (entry.Done != null) waiting.Add(entry.Done);
            }
            foreach (var done in waiting) done(LocalReply(status));
        }

        private void Track(string reference, string topic, bool join, Action<Reply> done)
        {
            var pending = new Pending { Topic = topic, Join = join, Done = done };
            pending.Timer = _core.Loop.After((long)_core.Config.PushTimeout.TotalMilliseconds, () =>
            {
                Pending timedOut;
                if (!_pending.TryGetValue(reference, out timedOut)) return;
                _pending.Remove(reference);
                List<Action<Reply>> waiting = null;
                if (timedOut.Join)
                {
                    var joining = Find(timedOut.Topic);
                    if (joining != null)
                    {
                        joining.Joining = false;
                        waiting = joining.Waiting;
                        joining.Waiting = new List<Action<Reply>>();
                        ScheduleRejoin(timedOut.Topic);
                    }
                }
                if (waiting != null)
                {
                    foreach (var waiter in waiting) waiter(LocalReply("timeout"));
                }
                timedOut.Done?.Invoke(LocalReply("timeout"));
            });
            _pending[reference] = pending;
        }

        /// <summary>Join `name`, now or as soon as the connection is open, and again after every
        /// reconnect until `Leave`. The task gets the first join's reply.</summary>
        public Task<Reply> Join(string name, JObject parameters = null)
        {
            return _core.Start<Reply>(done =>
            {
                var topic = Find(name);
                if (topic != null && topic.Joined)
                {
                    _core.Post(() => done(ReplyOf("ok", new JObject())));
                    return;
                }
                if (topic == null)
                {
                    topic = new Topic { Name = name, Params = parameters ?? new JObject() };
                    _topics.Add(topic);
                }
                topic.Waiting.Add(done);
                if (_state == RealtimeState.Connected && !topic.Joining) SendJoin(topic);
            });
        }

        public Task<Reply> Leave(string name)
        {
            return _core.Start<Reply>(done =>
            {
                var topic = Find(name);
                var joined = topic != null && topic.Joined;
                if (topic != null)
                {
                    _core.Loop.Cancel(topic.RejoinTimer);
                    var waiting = topic.Waiting;
                    topic.Waiting = new List<Action<Reply>>();
                    Forget(name);
                    foreach (var waiter in waiting) waiter(LocalReply("left"));
                }
                var frame = joined ? _phoenix.Leave(name) : null;
                if (frame == null)
                {
                    _core.Post(() => done(ReplyOf("ok", new JObject())));
                    return;
                }
                Track(frame.Value.Ref, name, false, done);
                _core.Config.WebSocket.SendText(frame.Value.Text);
            });
        }

        public bool Joined(string name)
        {
            lock (_core.Gate)
            {
                var topic = Find(name);
                return topic != null && topic.Joined;
            }
        }

        public Task<Reply> JoinLobby(string lobbyId)
        {
            return Join("lobby:" + lobbyId);
        }

        public Task<Reply> JoinLobbies()
        {
            return Join("lobbies");
        }

        public Task<Reply> JoinGroup(string groupId)
        {
            return Join("group:" + groupId);
        }

        public Task<Reply> JoinGroups()
        {
            return Join("groups");
        }

        public Task<Reply> JoinParty(string partyId)
        {
            return Join("party:" + partyId);
        }

        /// <summary>Send `eventName` to a joined topic; the task gets the server's reply, or
        /// `timeout` after `Config.PushTimeout`.</summary>
        public Task<Reply> Push(string topic, string eventName, JToken payload = null)
        {
            return _core.Start<Reply>(done => Push(topic, eventName, payload, done));
        }

        internal void Push(string name, string eventName, JToken payload, Action<Reply> done)
        {
            var tracked = Find(name);
            var frame = _state == RealtimeState.Connected && tracked != null && tracked.Joined
                ? _phoenix.Push(name, eventName, payload)
                : null;
            if (frame == null)
            {
                if (done != null) _core.Post(() => done(LocalReply("not_joined")));
                return;
            }
            Track(frame.Value.Ref, name, false, done);
            _core.Config.WebSocket.SendText(frame.Value.Text);
        }

        /// <summary>Call a server hook over the user channel. `args` that is not an array goes as
        /// its one element.</summary>
        public Task<HookResult> CallHook(string plugin, string fn, JToken args = null)
        {
            var payload = new JObject
            {
                ["plugin"] = plugin,
                ["fn"] = fn,
                ["args"] = ArgsOf(args),
            };
            return _core.Start<HookResult>(done => Push(UserTopicCore(), "call_hook", payload, r =>
                done(new HookResult
                {
                    Ok = r.Ok,
                    Data = r.Ok ? Json.Field(r.Response, "data") : JValue.CreateNull(),
                    Error = r.Error,
                })));
        }

        internal static JArray ArgsOf(JToken args)
        {
            var list = args as JArray;
            if (list != null) return list;
            return args == null || args.Type == JTokenType.Null ? new JArray() : new JArray(args);
        }

        /// <summary>Every server event, on every topic. Answers an id for `Off`.</summary>
        public long OnEvent(Action<Event> listener)
        {
            lock (_core.Gate)
            {
                var id = _nextListener++;
                _eventListeners.Add(id, listener);
                return id;
            }
        }

        /// <summary>Every change of `State`.</summary>
        public long OnState(Action<RealtimeState> listener)
        {
            lock (_core.Gate)
            {
                var id = _nextListener++;
                _stateListeners.Add(id, listener);
                return id;
            }
        }

        public void Off(long listener)
        {
            lock (_core.Gate)
            {
                _eventListeners.Remove(listener);
                _stateListeners.Remove(listener);
            }
        }

        /// <summary>`user:&lt;id&gt;` of the signed-in player, or empty.</summary>
        public string UserTopic
        {
            get
            {
                lock (_core.Gate)
                {
                    return UserTopicCore();
                }
            }
        }

        private string UserTopicCore()
        {
            var session = _core.Auth.Current;
            return session != null ? "user:" + session.UserId : "";
        }

        /// <summary>With `RealtimeFormat.Protobuf`, the server sends metadata that fits the game
        /// plugin's registered schema (`UserMeta`, `LobbyMeta`, ...) as bytes, `metadata_pb`. This
        /// reads an entity's (`user`, `lobby`, `group`, `party`) into `metadata`; unread, it stays
        /// base64 as `metadata_pb`. The decoder answers null when the bytes do not decode.</summary>
        public void RegisterMetadataDecoder(string entity, Func<byte[], JToken> decoder)
        {
            lock (_core.Gate)
            {
                _metadataDecoders[entity] = decoder;
            }
        }

        /// <summary>The same for KV data sent as `data_pb` (the plugin's `kv_schemas/0`): an exact
        /// key, or a `prefix*` pattern. An exact key wins over a pattern, a longer pattern over a
        /// shorter one.</summary>
        public void RegisterKvDecoder(string pattern, Func<byte[], JToken> decoder)
        {
            lock (_core.Gate)
            {
                _kvDecoders[pattern] = decoder;
            }
        }

        internal void SessionChanged(Session session)
        {
            if (!_wanted) return;
            if (session == null)
            {
                // Signed out: nothing to be connected as.
                Disconnect();
                return;
            }
            if (session.UserId != _userId)
            {
                // Another player signed in: reconnect as them.
                CloseSocket();
                _everOpened = false;
                _attempt = 0;
                Open();
            }
        }

        private void SetState(RealtimeState state)
        {
            if (_state == state) return;
            _state = state;
            _stateListeners.Fire(state);
        }

        private Topic Find(string name)
        {
            foreach (var topic in _topics)
            {
                if (topic.Name == name) return topic;
            }
            return null;
        }

        private void Forget(string name)
        {
            for (var i = _topics.Count - 1; i >= 0; i--)
            {
                if (_topics[i].Name == name) _topics.RemoveAt(i);
            }
        }
    }
}
