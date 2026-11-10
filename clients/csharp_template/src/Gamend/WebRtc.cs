// WebRTC DataChannels to the server: lower latency than the socket for game
// traffic, signaled over the realtime user channel.
//
//     client.Realtime.Connect();
//     var error = await client.WebRtc.Connect();
//     if (error.Length > 0) return;
//     var hook = await client.WebRtc.CallHook("arena", "move", new JObject { ["x"] = 1 });
//
// The server is the other peer. One channel by default: `events`, reliable and
// ordered, which hook calls ride on (`Config.DataChannels` adds more, up to the
// server's four). The peer connection is an interface, `IPeerTransport`, that
// an engine brings its own of; this SDK ships none yet.
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    public enum WebRtcState
    {
        Closed,
        Connecting,
        Connected,
        Failed,
    }

    public sealed class WebRtc
    {
        private sealed class Call
        {
            public uint Id;          // protobuf: the envelope's request id
            public string Plugin;    // JSON: replies are matched by these, oldest first
            public string Fn;
            public Action<HookResult> Done;
            public long Timer;
        }

        private readonly Core _core;
        private volatile WebRtcState _state = WebRtcState.Closed;
        private long _generation;
        private Action<string> _connecting;
        private long _connectTimer;
        private Dictionary<string, bool> _open = new Dictionary<string, bool>();
        private List<Call> _calls = new List<Call>();
        private uint _nextCall = 1;
        private long _nextListener = 1;
        private readonly Listeners<ValueTuple<string, byte[], bool>> _dataListeners;
        private readonly Listeners<WebRtcState> _stateListeners;
        private readonly Listeners<ValueTuple<string, bool>> _channelListeners;

        internal WebRtc(Core core)
        {
            _core = core;
            _dataListeners = new Listeners<ValueTuple<string, byte[], bool>>(core.Loop);
            _stateListeners = new Listeners<WebRtcState>(core.Loop);
            _channelListeners = new Listeners<ValueTuple<string, bool>>(core.Loop);
            core.Realtime.OnEvent(Signal);
            core.Realtime.OnState(s =>
            {
                // The server's peer lives in the user channel's process: when the
                // socket goes, so does the other end of this connection.
                if (s != RealtimeState.Connected && _state != WebRtcState.Closed) Close();
            });
        }

        private bool Protobuf
        {
            get { return _core.Config.WebRtcFormat == RealtimeFormat.Protobuf; }
        }

        public WebRtcState State
        {
            get { return _state; }
        }

        /// <summary>Offer a connection to the server over the user channel (join it first:
        /// `Realtime.Connect`). The task gets "" once a channel is open, or why not: `not_joined`,
        /// `no_transport`, the server's refusal, `failed`, `timeout`.</summary>
        public Task<string> Connect()
        {
            return _core.Start<string>(done =>
            {
                var peer = _core.Config.WebRtc;
                var user = _core.Realtime.UserTopic;
                var refused = "";
                if (peer == null)
                {
                    refused = "no_transport";
                }
                else if (!_core.Realtime.Joined(user))
                {
                    refused = "not_joined";
                }
                if (refused.Length > 0)
                {
                    _core.Post(() => done(refused));
                    return;
                }
                if (_state != WebRtcState.Closed) Close();

                var generation = ++_generation;
                _connecting = done;
                _open = new Dictionary<string, bool>();
                SetState(WebRtcState.Connecting);
                _connectTimer = _core.Loop.After((long)_core.Config.WebRtcTimeout.TotalMilliseconds, () =>
                {
                    if (generation != _generation || _connecting == null) return;
                    FinishConnect("timeout");
                    Close();
                    SetState(WebRtcState.Failed);
                });

                var loop = _core.Loop;
                peer.Open(_core.Config.IceServers, _core.Config.DataChannels, Protobuf ? "protobuf" : "", new PeerHandlers
                {
                    OnLocalDescription = (sdp, type) => loop.Post(() => LocalDescription(generation, sdp, type)),
                    OnLocalCandidate = (candidate, mid) => loop.Post(() => LocalCandidate(generation, candidate, mid)),
                    OnState = s => loop.Post(() => PeerState(generation, s)),
                    OnChannelOpen = label => loop.Post(() => ChannelOpened(generation, label)),
                    OnChannelClose = label => loop.Post(() => ChannelClosed(generation, label)),
                    OnMessage = (label, data, binary) => loop.Post(() => Message(generation, label, data, binary)),
                });
            });
        }

        /// <summary>Close the connection and tell the server.</summary>
        public void Close()
        {
            lock (_core.Gate)
            {
                if (_state == WebRtcState.Closed) return;
                ++_generation;
                _core.Loop.Cancel(_connectTimer);
                _connectTimer = 0;
                _core.Config.WebRtc?.Close();
                var user = _core.Realtime.UserTopic;
                if (_core.Realtime.Joined(user)) _core.Realtime.Push(user, "webrtc:close", new JObject(), null);
                FinishConnect("closed");
                FailCalls("closed");
                var wasOpen = _open;
                _open = new Dictionary<string, bool>();
                foreach (var channel in wasOpen)
                {
                    if (channel.Value) _channelListeners.Fire(ValueTuple.Create(channel.Key, false));
                }
                SetState(WebRtcState.Closed);
            }
        }

        private void LocalDescription(long generation, string sdp, string type)
        {
            if (generation != _generation) return;
            _core.Realtime.Push(_core.Realtime.UserTopic, "webrtc:offer", new JObject { ["sdp"] = sdp, ["type"] = type }, reply =>
            {
                if (generation != _generation || reply.Ok) return;
                FinishConnect(reply.Error);
                Close();
                SetState(WebRtcState.Failed);
            });
        }

        private void LocalCandidate(long generation, string candidate, string mid)
        {
            if (generation != _generation) return;
            var payload = new JObject { ["candidate"] = candidate, ["sdpMid"] = mid, ["sdpMLineIndex"] = 0 };
            _core.Realtime.Push(_core.Realtime.UserTopic, "webrtc:ice", payload, null);
        }

        private void Signal(Event received)
        {
            if (received.Topic != _core.Realtime.UserTopic || _state == WebRtcState.Closed) return;
            var peer = _core.Config.WebRtc;
            if (peer == null) return;
            if (received.Name == "webrtc:answer")
            {
                peer.SetRemoteDescription(Json.Text(received.Payload, "sdp"), Json.Text(received.Payload, "type", "answer"));
            }
            else if (received.Name == "webrtc:ice")
            {
                var candidate = Json.Text(received.Payload, "candidate");
                if (candidate.Length == 0) return;
                var mid = Json.Text(received.Payload, "sdpMid");
                if (mid.Length == 0) mid = Json.Number(received.Payload, "sdpMLineIndex").ToString(System.Globalization.CultureInfo.InvariantCulture);
                peer.AddRemoteCandidate(candidate, mid);
            }
        }

        private void PeerState(long generation, string peer)
        {
            if (generation != _generation) return;
            if (peer == "connected")
            {
                SetState(WebRtcState.Connected);
            }
            else if (peer == "failed" || peer == "closed" || peer == "disconnected")
            {
                FinishConnect(peer);
                FailCalls(peer);
                SetState(peer == "failed" ? WebRtcState.Failed : WebRtcState.Closed);
            }
        }

        private void ChannelOpened(long generation, string label)
        {
            if (generation != _generation) return;
            _open[label] = true;
            SetState(WebRtcState.Connected);
            FinishConnect("");
            _channelListeners.Fire(ValueTuple.Create(label, true));
        }

        private void ChannelClosed(long generation, string label)
        {
            if (generation != _generation) return;
            _open[label] = false;
            if (label == "events") FailCalls("closed");
            _channelListeners.Fire(ValueTuple.Create(label, false));
        }

        private void Message(long generation, string label, byte[] data, bool binary)
        {
            if (generation != _generation) return;
            if (label == "events" && HookReply(data, binary)) return;
            _dataListeners.Fire(ValueTuple.Create(label, data, binary));
        }

        // A hook reply on `events`, matched to its call. False for anything else.
        private bool HookReply(byte[] data, bool binary)
        {
            Call call;
            var result = new HookResult();
            if (Protobuf)
            {
                if (!binary) return false;
                var envelope = Proto.Find("RtcEnvelope");
                var decoded = envelope != null ? Proto.Decode(envelope, data, false) : null;
                if (decoded == null) return false;
                JToken body;
                if (decoded.TryGetValue("hook_reply", out body))
                {
                    result.Ok = true;
                    if (body is JObject && ((JObject)body).ContainsKey("data_raw"))
                    {
                        // A typed hook's reply: the bytes as the plugin encoded them.
                        result.Bytes = Proto.Unbase64(Json.Text(body, "data_raw")) ?? Array.Empty<byte>();
                    }
                    else
                    {
                        result.Data = Json.Field(body, "data");
                    }
                }
                else if (decoded.TryGetValue("hook_error", out body))
                {
                    result.Error = Json.Text(body, "error", "hook_error");
                }
                else
                {
                    return false;
                }
                var id = unchecked((uint)Json.Number(body, "id"));
                call = _calls.Find(c => c.Id == id);
            }
            else
            {
                if (binary) return false;
                var message = Json.Parse(Encoding.UTF8.GetString(data));
                var type = Json.Text(message, "type");
                if (type != "hook_reply" && type != "hook_error") return false;
                var plugin = Json.Text(message, "plugin");
                var fn = Json.Text(message, "fn");
                call = _calls.Find(c => c.Plugin == plugin && c.Fn == fn);
                result.Ok = type == "hook_reply";
                if (result.Ok)
                {
                    result.Data = Json.Field(message, "data");
                }
                else
                {
                    result.Error = Json.Text(message, "error", "hook_error");
                }
            }
            if (call == null) return true;
            _calls.Remove(call);
            _core.Loop.Cancel(call.Timer);
            call.Done(result);
            return true;
        }

        /// <summary>Call a server hook over the `events` channel. `args` that is not an array goes
        /// as its one element.</summary>
        public Task<HookResult> CallHook(string plugin, string fn, JToken args = null)
        {
            return StartCall(plugin, fn, Realtime.ArgsOf(args), null, false);
        }

        /// <summary>Call a typed hook with the game's own encoded request (`&lt;FnName&gt;Request`,
        /// registered by the plugin); the task gets the reply's bytes in `HookResult.Bytes`. Needs
        /// `WebRtcFormat = Protobuf`; the server relays the bytes without decoding them.</summary>
        public Task<HookResult> CallHookRaw(string plugin, string fn, byte[] request)
        {
            return StartCall(plugin, fn, null, request, true);
        }

        private Task<HookResult> StartCall(string plugin, string fn, JArray args, byte[] raw, bool isRaw)
        {
            return _core.Start<HookResult>(done =>
            {
                var call = new Call { Plugin = plugin, Fn = fn, Done = done };
                var refused = "not_open";
                var sent = false;
                var peer = _core.Config.WebRtc;
                if (isRaw && !Protobuf)
                {
                    refused = "needs_protobuf";
                }
                else if (peer != null && ChannelOpen("events"))
                {
                    if (Protobuf)
                    {
                        call.Id = _nextCall++;
                        var body = new JObject { ["id"] = call.Id, ["plugin"] = plugin, ["fn"] = fn };
                        if (isRaw)
                        {
                            body["args_raw"] = new JValue((object)raw);
                        }
                        else
                        {
                            body["args_json"] = Json.Dump(args);
                        }
                        var envelope = new JObject { ["call_hook"] = body };
                        sent = peer.Send("events", Proto.Encode(Proto.Find("RtcEnvelope"), envelope), true);
                    }
                    else
                    {
                        var message = new JObject { ["type"] = "call_hook", ["plugin"] = plugin, ["fn"] = fn, ["args"] = args };
                        sent = peer.Send("events", Encoding.UTF8.GetBytes(Json.Dump(message)), false);
                    }
                }
                if (!sent)
                {
                    _core.Post(() => done(new HookResult { Error = refused }));
                    return;
                }
                call.Timer = _core.Loop.After((long)_core.Config.PushTimeout.TotalMilliseconds, () =>
                {
                    if (!_calls.Remove(call)) return;
                    call.Done(new HookResult { Error = "timeout" });
                });
                _calls.Add(call);
            });
        }

        public bool ChannelOpen(string label)
        {
            lock (_core.Gate)
            {
                bool open;
                return _open.TryGetValue(label, out open) && open;
            }
        }

        /// <summary>Send on a channel; false when it is not open.</summary>
        public bool Send(string label, byte[] data, bool binary = false)
        {
            lock (_core.Gate)
            {
                var peer = _core.Config.WebRtc;
                return peer != null && ChannelOpen(label) && peer.Send(label, data, binary);
            }
        }

        /// <summary>Send text on a channel; false when it is not open.</summary>
        public bool Send(string label, string text)
        {
            return Send(label, Encoding.UTF8.GetBytes(text), false);
        }

        private void FinishConnect(string error)
        {
            _core.Loop.Cancel(_connectTimer);
            _connectTimer = 0;
            var done = _connecting;
            _connecting = null;
            done?.Invoke(error);
        }

        private void FailCalls(string error)
        {
            var calls = _calls;
            _calls = new List<Call>();
            foreach (var call in calls)
            {
                _core.Loop.Cancel(call.Timer);
                call.Done(new HookResult { Error = error });
            }
        }

        private void SetState(WebRtcState state)
        {
            if (_state == state) return;
            _state = state;
            _stateListeners.Fire(state);
        }

        /// <summary>What arrives on any channel, hook replies aside: its label, the data, and
        /// whether it came as binary.</summary>
        public long OnData(Action<string, byte[], bool> listener)
        {
            lock (_core.Gate)
            {
                var id = _nextListener++;
                _dataListeners.Add(id, d => listener(d.Item1, d.Item2, d.Item3));
                return id;
            }
        }

        public long OnState(Action<WebRtcState> listener)
        {
            lock (_core.Gate)
            {
                var id = _nextListener++;
                _stateListeners.Add(id, listener);
                return id;
            }
        }

        /// <summary>A channel opened (`true`) or closed.</summary>
        public long OnChannel(Action<string, bool> listener)
        {
            lock (_core.Gate)
            {
                var id = _nextListener++;
                _channelListeners.Add(id, c => listener(c.Item1, c.Item2));
                return id;
            }
        }

        public void Off(long listener)
        {
            lock (_core.Gate)
            {
                _dataListeners.Remove(listener);
                _stateListeners.Remove(listener);
                _channelListeners.Remove(listener);
            }
        }
    }
}
