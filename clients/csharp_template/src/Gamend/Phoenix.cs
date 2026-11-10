// Phoenix Channels, protocol V2, with no socket in it: refs, joins, the
// heartbeat and frame decoding, fed text, bytes and a clock by `Realtime`.
//
// Wire shape of a text frame, both directions: `[join_ref, ref, topic, event,
// payload]`, refs being stringified counters or null. A binary frame (the
// server's protobuf events) is a kind byte, sizes, then the strings and the
// payload bytes; see `Phoenix.Socket.V2.JSONSerializer`.
using System;
using System.Collections.Generic;
using System.Text;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    internal enum FrameKind
    {
        /// <summary>A server-pushed event on a topic.</summary>
        Message,
        /// <summary>The reply to a join, leave or push, correlated by `Ref`.</summary>
        Reply,
    }

    internal sealed class Frame
    {
        public FrameKind Kind = FrameKind.Message;
        public string Topic = "";
        /// <summary>Message: the event; Reply: empty.</summary>
        public string Event = "";
        /// <summary>Reply: the ref it answers.</summary>
        public string Ref = "";
        /// <summary>Reply: "ok" or "error".</summary>
        public string Status = "";
        /// <summary>Message: the payload; Reply: the response.</summary>
        public JToken Payload = JValue.CreateNull();
        /// <summary>A binary frame's payload, undecoded; null for a text frame.</summary>
        public byte[] Bytes;
    }

    internal sealed class Phoenix
    {
        // Phoenix's own rhythm: a beat every thirty seconds, and a beat still
        // unanswered when the next is due means the server is gone.
        internal const long HeartbeatMs = 30000;

        // Binary frame kinds, as `Phoenix.Socket.V2.JSONSerializer` numbers them.
        private const int KindPush = 0;
        private const int KindReply = 1;
        private const int KindBroadcast = 2;

        private long _nextRef = 1;
        private readonly Dictionary<string, string> _joins = new Dictionary<string, string>();
        private long _lastHeartbeat;
        private string _pendingHeartbeat = "";

        internal Phoenix(long now = 0)
        {
            _lastHeartbeat = now;
        }

        /// <summary>The frame that joins `topic`, and the ref its reply carries.</summary>
        internal (string Ref, string Text) Join(string topic, JToken payload)
        {
            var reference = FreshRef();
            _joins[topic] = reference;
            return (reference, Encode(reference, reference, topic, "phx_join", payload));
        }

        /// <summary>The frame that leaves `topic`, or null when it was never joined.</summary>
        internal (string Ref, string Text)? Leave(string topic)
        {
            string joinRef;
            if (!_joins.TryGetValue(topic, out joinRef)) return null;
            var reference = FreshRef();
            var text = Encode(joinRef, reference, topic, "phx_leave", new JObject());
            _joins.Remove(topic);
            return (reference, text);
        }

        /// <summary>The frame that pushes `eventName` to a joined topic, or null when it was never
        /// joined.</summary>
        internal (string Ref, string Text)? Push(string topic, string eventName, JToken payload)
        {
            string joinRef;
            if (!_joins.TryGetValue(topic, out joinRef)) return null;
            var reference = FreshRef();
            return (reference, Encode(joinRef, reference, topic, eventName, payload));
        }

        internal bool Joined(string topic)
        {
            return _joins.ContainsKey(topic);
        }

        /// <summary>A heartbeat frame when one is due (empty otherwise), or false when the last
        /// one went unanswered: the connection is dead.</summary>
        internal bool Heartbeat(long now, out string frame)
        {
            frame = "";
            if (now - _lastHeartbeat < HeartbeatMs) return true;
            if (_pendingHeartbeat.Length > 0) return false;
            var reference = FreshRef();
            frame = Encode(null, reference, "phoenix", "heartbeat", new JObject());
            _pendingHeartbeat = reference;
            _lastHeartbeat = now;
            return true;
        }

        /// <summary>A text frame, decoded; null for internal traffic (heartbeat replies) and for
        /// text that is not a frame.</summary>
        internal Frame Decode(string text)
        {
            var parts = Json.Parse(text) as JArray;
            if (parts == null || parts.Count != 5) return null;
            var output = new Frame
            {
                Ref = Str(parts[1]),
                Topic = Str(parts[2]),
                Event = Str(parts[3]),
            };

            if (output.Topic == "phoenix")
            {
                if (output.Ref == _pendingHeartbeat) _pendingHeartbeat = "";
                return null;
            }
            if (output.Event == "phx_reply")
            {
                var reply = parts[4];
                output.Kind = FrameKind.Reply;
                output.Event = "";
                output.Status = Json.Text(reply, "status");
                output.Payload = Json.Field(reply, "response");
                return output;
            }
            if (output.Event == "phx_error" || output.Event == "phx_close") _joins.Remove(output.Topic);
            output.Kind = FrameKind.Message;
            output.Payload = parts[4];
            return output;
        }

        /// <summary>A binary frame, decoded; null when it is not one.</summary>
        internal Frame DecodeBinary(byte[] bytes)
        {
            var reader = new Reader(bytes);
            int kind;
            if (!reader.Byte(out kind)) return null;
            var output = new Frame();
            string ignored;
            if (kind == KindPush)
            {
                int joinRefSize, topicSize, eventSize;
                if (!reader.Byte(out joinRefSize) || !reader.Byte(out topicSize) || !reader.Byte(out eventSize)
                    || !reader.Text(joinRefSize, out ignored) || !reader.Text(topicSize, out output.Topic)
                    || !reader.Text(eventSize, out output.Event))
                {
                    return null;
                }
            }
            else if (kind == KindReply)
            {
                int joinRefSize, refSize, topicSize, statusSize;
                if (!reader.Byte(out joinRefSize) || !reader.Byte(out refSize) || !reader.Byte(out topicSize)
                    || !reader.Byte(out statusSize) || !reader.Text(joinRefSize, out ignored)
                    || !reader.Text(refSize, out output.Ref) || !reader.Text(topicSize, out output.Topic)
                    || !reader.Text(statusSize, out output.Status))
                {
                    return null;
                }
                output.Kind = FrameKind.Reply;
            }
            else if (kind == KindBroadcast)
            {
                int topicSize, eventSize;
                if (!reader.Byte(out topicSize) || !reader.Byte(out eventSize)
                    || !reader.Text(topicSize, out output.Topic) || !reader.Text(eventSize, out output.Event))
                {
                    return null;
                }
            }
            else
            {
                return null;
            }
            output.Bytes = reader.Rest();
            return output;
        }

        /// <summary>Forget every join: the socket closed, and a new one starts clean.</summary>
        internal void Reset(long now)
        {
            _joins.Clear();
            _pendingHeartbeat = "";
            _lastHeartbeat = now;
        }

        private string FreshRef()
        {
            return (_nextRef++).ToString(System.Globalization.CultureInfo.InvariantCulture);
        }

        private static string Str(JToken value)
        {
            return value.Type == JTokenType.String ? (string)value : "";
        }

        private static string Encode(string joinRef, string reference, string topic, string eventName, JToken payload)
        {
            var parts = new JArray
            {
                joinRef == null ? JValue.CreateNull() : new JValue(joinRef),
                new JValue(reference),
                new JValue(topic),
                new JValue(eventName),
                payload ?? new JObject(),
            };
            return Json.Dump(parts);
        }

        // Reads length-prefixed pieces off a binary frame, refusing to run past it.
        private sealed class Reader
        {
            private readonly byte[] _bytes;
            private int _at;

            internal Reader(byte[] bytes)
            {
                _bytes = bytes;
            }

            internal bool Byte(out int value)
            {
                value = 0;
                if (_at >= _bytes.Length) return false;
                value = _bytes[_at++];
                return true;
            }

            internal bool Text(int size, out string value)
            {
                value = "";
                if (_bytes.Length - _at < size) return false;
                value = Encoding.UTF8.GetString(_bytes, _at, size);
                _at += size;
                return true;
            }

            internal byte[] Rest()
            {
                var rest = new byte[_bytes.Length - _at];
                Array.Copy(_bytes, _at, rest, 0, rest.Length);
                return rest;
            }
        }
    }
}
