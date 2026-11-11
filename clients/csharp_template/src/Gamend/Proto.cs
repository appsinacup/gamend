// Protobuf realtime events, as `Config.RealtimeFormat = Protobuf` asks the
// server to send them: the binary payloads `proto/gamend_realtime.proto`
// describes, turned back into the payload the event has in JSON mode.
//
// No protobuf library: the file uses a small part of the language (proto3
// scalars, messages, optional, repeated, map<string, V>, oneof), so a field
// table generated from it (`Generated/ProtoSchema.g.cs`) and a wire reader do.
using System;
using System.Collections.Generic;
using System.Text;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    /// <summary>Offered every bytes field that is not `*_json` (a game's own protobuf in
    /// `metadata_pb` or `data_pb`): the message and field it is in, its bytes, and the fields
    /// decoded so far. A value replaces the field, under its name without `_pb`; null leaves it as
    /// base64.</summary>
    internal delegate JToken BytesHook(string message, string field, byte[] bytes, JObject decoded);

    internal static partial class Proto
    {
        internal enum FieldType : byte
        {
            Bool,
            Int32,
            Int64,
            Uint32,
            Uint64,
            Sint32,
            Sint64,
            String,
            Bytes,
            Message,
        }

        /// <summary>Singular: proto3 implicit presence. Optional: explicit presence (and oneof
        /// members). Map: `map&lt;string, type&gt;`.</summary>
        internal enum Label : byte
        {
            Singular,
            Optional,
            Repeated,
            Map,
        }

        internal sealed class Field
        {
            internal readonly uint Number;
            internal readonly string Name;
            internal readonly Label Label;
            /// <summary>The value's type; a map's value type.</summary>
            internal readonly FieldType Type;
            /// <summary>For `FieldType.Message`: its index in `Messages`; -1 otherwise.</summary>
            internal readonly int MessageIndex;

            internal Field(uint number, string name, Label label, FieldType type, int messageIndex)
            {
                Number = number;
                Name = name;
                Label = label;
                Type = type;
                MessageIndex = messageIndex;
            }

            internal Field Renumbered(uint number)
            {
                return new Field(number, Name, Label, Type, MessageIndex);
            }
        }

        internal sealed class Message
        {
            internal readonly string Name;
            internal readonly Field[] Fields;

            internal Message(string name, Field[] fields)
            {
                Name = name;
                Fields = fields;
            }
        }

        private const uint WireVarint = 0;
        private const uint WireFixed64 = 1;
        private const uint WireLength = 2;
        private const uint WireFixed32 = 5;

        // A view of part of a byte array, read from the front.
        private struct Slice
        {
            internal byte[] Data;
            internal int At;
            internal int End;

            internal Slice(byte[] data, int at, int end)
            {
                Data = data;
                At = at;
                End = end;
            }

            internal int Length
            {
                get { return End - At; }
            }

            internal bool Empty
            {
                get { return At >= End; }
            }

            internal byte[] ToArray()
            {
                var bytes = new byte[Length];
                Array.Copy(Data, At, bytes, 0, bytes.Length);
                return bytes;
            }

            internal string Text()
            {
                return Encoding.UTF8.GetString(Data, At, Length);
            }
        }

        private static bool ReadVarint(ref Slice input, out ulong value)
        {
            value = 0;
            for (var shift = 0; shift < 64; shift += 7)
            {
                if (input.Empty) return false;
                var b = input.Data[input.At++];
                value |= (ulong)(b & 0x7F) << shift;
                if ((b & 0x80) == 0) return true;
            }
            return false;
        }

        private static bool ReadLength(ref Slice input, out Slice span)
        {
            span = default(Slice);
            ulong size;
            if (!ReadVarint(ref input, out size) || size > (ulong)input.Length) return false;
            span = new Slice(input.Data, input.At, input.At + (int)size);
            input.At += (int)size;
            return true;
        }

        private static bool Skip(ref Slice input, uint wire)
        {
            switch (wire)
            {
                case WireVarint:
                    ulong ignored;
                    return ReadVarint(ref input, out ignored);
                case WireFixed64:
                    if (input.Length < 8) return false;
                    input.At += 8;
                    return true;
                case WireLength:
                    Slice span;
                    return ReadLength(ref input, out span);
                case WireFixed32:
                    if (input.Length < 4) return false;
                    input.At += 4;
                    return true;
                default:
                    return false;
            }
        }

        private static Field FieldOf(Message message, uint number)
        {
            foreach (var field in message.Fields)
            {
                if (field.Number == number) return field;
            }
            return null;
        }

        private static JToken Scalar(FieldType type, ulong raw)
        {
            unchecked
            {
                switch (type)
                {
                    case FieldType.Bool:
                        return new JValue(raw != 0);
                    case FieldType.Int32:
                        return new JValue((long)(int)raw);
                    case FieldType.Int64:
                        return new JValue((long)raw);
                    case FieldType.Uint32:
                        return new JValue((long)(uint)raw);
                    case FieldType.Uint64:
                        return new JValue(raw);
                    case FieldType.Sint32:
                    case FieldType.Sint64:
                        return new JValue((long)((raw >> 1) ^ (~(raw & 1) + 1)));
                    default:
                        return JValue.CreateNull();
                }
            }
        }

        private static bool EndsWith(string text, string tail)
        {
            return text.EndsWith(tail, StringComparison.Ordinal);
        }

        // A bytes field as the JSON payload has it: `metadata_json` becomes the
        // parsed `metadata` (an empty or unreadable one an empty object); anything
        // else goes to the hook, and stays base64 under its own name when nothing
        // reads it.
        private static void PutBytes(JObject output, Message message, string name, Slice bytes, BytesHook hook)
        {
            if (EndsWith(name, "_json"))
            {
                var parsed = bytes.Empty ? null : Json.Parse(bytes.Text());
                output[name.Substring(0, name.Length - 5)] = parsed ?? new JObject();
                return;
            }
            if (bytes.Empty) return;
            if (hook != null)
            {
                var read = hook(message.Name, name, bytes.ToArray(), output);
                if (read != null)
                {
                    output[EndsWith(name, "_pb") ? name.Substring(0, name.Length - 3) : name] = read;
                    return;
                }
            }
            output[name] = Convert.ToBase64String(bytes.Data, bytes.At, bytes.Length);
        }

        private static JToken DefaultOf(Field field)
        {
            switch (field.Type)
            {
                case FieldType.Bool:
                    return new JValue(false);
                case FieldType.String:
                    return new JValue("");
                case FieldType.Message:
                case FieldType.Bytes:
                    return JValue.CreateNull();
                default:
                    return new JValue(0L);
            }
        }

        private static bool DecodeValue(Field field, uint wire, ref Slice input, bool defaults, BytesHook hook, out JToken value, out Slice bytes)
        {
            value = JValue.CreateNull();
            bytes = default(Slice);
            if (field.Type == FieldType.String || field.Type == FieldType.Bytes || field.Type == FieldType.Message)
            {
                if (wire != WireLength) return false;
                Slice span;
                if (!ReadLength(ref input, out span)) return false;
                if (field.Type == FieldType.String)
                {
                    value = new JValue(span.Text());
                }
                else if (field.Type == FieldType.Bytes)
                {
                    bytes = span;
                }
                else
                {
                    var nested = Decode(Messages[field.MessageIndex], span, defaults, hook);
                    if (nested == null) return false;
                    value = nested;
                }
                return true;
            }
            if (wire != WireVarint) return false;
            ulong raw;
            if (!ReadVarint(ref input, out raw)) return false;
            value = Scalar(field.Type, raw);
            return true;
        }

        // One `map<string, V>` entry: a message whose field 1 is the key, 2 the value.
        private static bool DecodeEntry(Field field, Slice entry, bool defaults, BytesHook hook, out string key, out JToken value)
        {
            key = "";
            value = DefaultOf(field);
            while (!entry.Empty)
            {
                ulong tag;
                if (!ReadVarint(ref entry, out tag)) return false;
                var number = (uint)(tag >> 3);
                var wire = (uint)(tag & 7);
                if (number == 1 && wire == WireLength)
                {
                    Slice span;
                    if (!ReadLength(ref entry, out span)) return false;
                    key = span.Text();
                }
                else if (number == 2)
                {
                    Slice ignored;
                    if (!DecodeValue(field, wire, ref entry, defaults, hook, out value, out ignored)) return false;
                }
                else if (!Skip(ref entry, wire))
                {
                    return false;
                }
            }
            return true;
        }

        internal static Message Find(string name)
        {
            foreach (var message in Messages)
            {
                if (message.Name == name) return message;
            }
            return null;
        }

        /// <summary>`bytes` as JSON with the message's field names, or null when they do not
        /// decode. `defaults` fills the fields a proto3 message leaves out for being zero, as
        /// protobufjs's `toObject({defaults: true})` does; explicitly optional ones stay absent.
        /// `X_json` bytes come out parsed, as `X`; other bytes as base64.</summary>
        internal static JObject Decode(Message message, byte[] bytes, bool defaults, BytesHook hook = null)
        {
            return Decode(message, new Slice(bytes, 0, bytes.Length), defaults, hook);
        }

        private static JObject Decode(Message message, Slice input, bool defaults, BytesHook hook)
        {
            var output = new JObject();
            SortedDictionary<string, Slice> bytesFields = null;
            while (!input.Empty)
            {
                ulong tag;
                if (!ReadVarint(ref input, out tag)) return null;
                var number = (uint)(tag >> 3);
                var wire = (uint)(tag & 7);
                var field = FieldOf(message, number);
                if (field == null)
                {
                    if (!Skip(ref input, wire)) return null;
                    continue;
                }
                if (field.Label == Label.Map)
                {
                    Slice entry;
                    if (wire != WireLength || !ReadLength(ref input, out entry)) return null;
                    string key;
                    JToken entryValue;
                    if (!DecodeEntry(field, entry, defaults, hook, out key, out entryValue)) return null;
                    var map = output[field.Name] as JObject;
                    if (map == null)
                    {
                        map = new JObject();
                        output[field.Name] = map;
                    }
                    map[key] = entryValue;
                    continue;
                }
                JToken value;
                Slice bytes;
                if (!DecodeValue(field, wire, ref input, defaults, hook, out value, out bytes)) return null;
                if (field.Type == FieldType.Bytes)
                {
                    if (bytesFields == null) bytesFields = new SortedDictionary<string, Slice>(StringComparer.Ordinal);
                    bytesFields[field.Name] = bytes;
                }
                else if (field.Label == Label.Repeated)
                {
                    var list = output[field.Name] as JArray;
                    if (list == null)
                    {
                        list = new JArray();
                        output[field.Name] = list;
                    }
                    list.Add(value);
                }
                else
                {
                    output[field.Name] = value;
                }
            }
            if (bytesFields != null)
            {
                foreach (var entry in bytesFields) PutBytes(output, message, entry.Key, entry.Value, hook);
            }

            if (defaults)
            {
                foreach (var field in message.Fields)
                {
                    if (field.Label == Label.Repeated)
                    {
                        if (!output.ContainsKey(field.Name)) output[field.Name] = new JArray();
                    }
                    else if (field.Label == Label.Map)
                    {
                        if (!output.ContainsKey(field.Name)) output[field.Name] = new JObject();
                    }
                    else if (field.Label == Label.Singular)
                    {
                        if (field.Type == FieldType.Bytes)
                        {
                            if (bytesFields == null || !bytesFields.ContainsKey(field.Name))
                            {
                                PutBytes(output, message, field.Name, default(Slice), hook);
                            }
                        }
                        else if (!output.ContainsKey(field.Name) && field.Type != FieldType.Message)
                        {
                            output[field.Name] = DefaultOf(field);
                        }
                    }
                }
            }
            return output;
        }

        private static void PutVarint(List<byte> output, ulong value)
        {
            while (value >= 0x80)
            {
                output.Add((byte)((value & 0x7F) | 0x80));
                value >>= 7;
            }
            output.Add((byte)value);
        }

        private static void PutTag(List<byte> output, uint number, uint wire)
        {
            PutVarint(output, ((ulong)number << 3) | wire);
        }

        private static void PutLength(List<byte> output, uint number, byte[] bytes)
        {
            PutTag(output, number, WireLength);
            PutVarint(output, (ulong)bytes.Length);
            output.AddRange(bytes);
        }

        private static byte[] BytesOf(JToken value)
        {
            if (value.Type == JTokenType.String) return Encoding.UTF8.GetBytes((string)value);
            if (value.Type == JTokenType.Bytes) return (byte[])((JValue)value).Value;
            return null;
        }

        private static void EncodeValue(List<byte> output, Field field, JToken value)
        {
            long n;
            switch (field.Type)
            {
                case FieldType.String:
                case FieldType.Bytes:
                    var bytes = BytesOf(value);
                    if (bytes != null) PutLength(output, field.Number, bytes);
                    return;
                case FieldType.Message:
                    PutLength(output, field.Number, Encode(Messages[field.MessageIndex], value));
                    return;
                case FieldType.Bool:
                    PutTag(output, field.Number, WireVarint);
                    PutVarint(output, value.Type == JTokenType.Boolean && (bool)value ? 1UL : 0UL);
                    return;
                case FieldType.Sint32:
                case FieldType.Sint64:
                    Json.TryLong(value, out n);
                    PutTag(output, field.Number, WireVarint);
                    PutVarint(output, unchecked(((ulong)n << 1) ^ (ulong)(n >> 63)));
                    return;
                default:
                    Json.TryLong(value, out n);
                    PutTag(output, field.Number, WireVarint);
                    PutVarint(output, unchecked((ulong)n));
                    return;
            }
        }

        /// <summary>`value`, keyed by field name, on the wire. A bytes field takes a string or a
        /// `JValue` holding a `byte[]`; fields `value` leaves out are left out.</summary>
        internal static byte[] Encode(Message message, JToken value)
        {
            var output = new List<byte>();
            var o = value as JObject;
            if (o == null) return output.ToArray();
            foreach (var field in message.Fields)
            {
                JToken given;
                if (!o.TryGetValue(field.Name, out given) || given.Type == JTokenType.Null) continue;
                if (field.Label == Label.Repeated)
                {
                    var list = given as JArray;
                    if (list == null) continue;
                    foreach (var item in list) EncodeValue(output, field, item);
                }
                else if (field.Label == Label.Map)
                {
                    var map = given as JObject;
                    if (map == null) continue;
                    var valueField = field.Renumbered(2);
                    foreach (var entry in map.Properties())
                    {
                        var body = new List<byte>();
                        PutLength(body, 1, Encoding.UTF8.GetBytes(entry.Name));
                        EncodeValue(body, valueField, entry.Value);
                        PutLength(output, field.Number, body.ToArray());
                    }
                }
                else
                {
                    EncodeValue(output, field, given);
                }
            }
            return output.ToArray();
        }

        internal static string Base64(byte[] bytes)
        {
            return Convert.ToBase64String(bytes);
        }

        /// <summary>Null when `text` is not base64. Padding is optional.</summary>
        internal static byte[] Unbase64(string text)
        {
            var end = text.Length;
            while (end > 0 && text[end - 1] == '=') end--;
            var output = new List<byte>(end * 3 / 4);
            uint buffer = 0;
            var bits = 0;
            for (var i = 0; i < end; i++)
            {
                var c = text[i];
                int v;
                if (c >= 'A' && c <= 'Z') v = c - 'A';
                else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
                else if (c >= '0' && c <= '9') v = c - '0' + 52;
                else if (c == '+') v = 62;
                else if (c == '/') v = 63;
                else return null;
                buffer = (buffer << 6) | (uint)v;
                bits += 6;
                if (bits >= 8)
                {
                    bits -= 8;
                    output.Add((byte)((buffer >> bits) & 0xFF));
                }
            }
            return output.ToArray();
        }

        // The server's `GamendWeb.EventCodec` table, event by event: which message a
        // binary `event` on a `kind` of topic carries, and whether to fill proto3's
        // left-out zero fields, as the JS client does for those. `*` is any topic.
        private static readonly (string Kind, string Event, string Message, bool Defaults)[] Mappings =
        {
            ("user", "updated", "User", false),
            ("user", "friend_updated", "FriendUpdate", false),
            ("*", "kv_updated", "KvEntry", false),
            ("*", "kv_deleted", "KvEntry", false),
            ("*", "notification_created", "Notification", true),
            ("*", "chat_message_created", "ChatMessage", true),
            ("*", "chat_message_updated", "ChatMessage", true),
            ("*", "chat_message_deleted", "EntityId", false),
            ("*", "group_invite_accepted", "GroupInviteEvent", true),
            ("*", "group_invite_cancelled", "GroupInviteEvent", true),
            ("*", "group_join_request_approved", "GroupInviteEvent", true),
            ("*", "group_join_request_rejected", "GroupInviteEvent", true),
            ("*", "party_invite_accepted", "PartyInviteEvent", true),
            ("*", "party_invite_declined", "PartyInviteEvent", true),
            ("*", "party_invite_cancelled", "PartyInviteEvent", true),
            ("*", "wallet_updated", "WalletChange", true),
            ("*", "inventory_updated", "InventoryChange", true),
            ("*", "chat_muted", "ChatMute", true),
            ("*", "chat_unmuted", "ChatUnmute", true),
            ("*", "quest_progress", "QuestProgress", true),
            ("*", "quest_completed", "QuestProgress", true),
            ("*", "quest_claimed", "QuestProgress", true),
            ("*", "ready_check_started", "ReadyCheckState", true),
            ("*", "ready_check_updated", "ReadyCheckState", true),
            ("*", "ready_check_passed", "ReadyCheckState", true),
            ("*", "ready_check_failed", "ReadyCheckState", true),
            ("lobby", "updated", "Lobby", false),
            ("lobby", "user_joined", "MemberEvent", false),
            ("lobby", "user_left", "MemberEvent", false),
            ("lobby", "user_kicked", "MemberEvent", false),
            ("lobby", "user_online", "MemberEvent", false),
            ("lobby", "user_offline", "MemberEvent", false),
            ("lobby", "host_changed", "HostChanged", true),
            ("lobby", "state_changed", "LobbyStateChanged", true),
            ("lobby", "user_updated", "UserBrief", false),
            ("group", "member_updated", "UserBrief", false),
            ("party", "member_updated", "UserBrief", false),
            ("lobbies", "lobby_created", "Lobby", false),
            ("lobbies", "lobby_updated", "Lobby", false),
            ("lobbies", "lobby_deleted", "EntityId", false),
            ("lobbies", "lobby_membership_changed", "EntityId", false),
            ("group", "updated", "Group", false),
            ("group", "member_joined", "MemberEvent", false),
            ("group", "member_left", "MemberEvent", false),
            ("group", "member_kicked", "MemberEvent", false),
            ("group", "member_promoted", "MemberEvent", false),
            ("group", "member_demoted", "MemberEvent", false),
            ("group", "join_request_approved", "MemberEvent", false),
            ("group", "join_request_rejected", "MemberEvent", false),
            ("group", "member_online", "MemberEvent", false),
            ("group", "member_offline", "MemberEvent", false),
            ("groups", "group_created", "Group", false),
            ("groups", "group_updated", "Group", false),
            ("groups", "group_deleted", "EntityId", false),
            ("party", "updated", "Party", false),
            ("party", "member_joined", "MemberEvent", false),
            ("party", "member_left", "MemberEvent", false),
            ("party", "member_online", "MemberEvent", false),
            ("party", "member_offline", "MemberEvent", false),
            ("party", "disbanded", "PartyRef", false),
            ("user", "tournament_updated", "TournamentEvent", false),
            ("user", "tournament_finished", "TournamentEvent", false),
            ("user", "tournament_match_ready", "TournamentMatchEvent", true),
            ("user", "tournament_match_resolved", "TournamentMatchEvent", true),
            ("user", "match_found", "MatchmakingFound", true),
        };

        /// <summary>The payload of a binary `eventName` on `topic`, or null when this SDK has no
        /// decoder for it (or the bytes do not decode).</summary>
        internal static JObject DecodeBinaryEvent(string topic, string eventName, byte[] bytes, BytesHook hook = null)
        {
            var colon = topic.IndexOf(':');
            var kind = colon < 0 ? topic : topic.Substring(0, colon);
            // A topic-specific row wins over `*`, as in the server's clause order.
            foreach (var wanted in new[] { kind, "*" })
            {
                foreach (var row in Mappings)
                {
                    if (row.Kind != wanted || row.Event != eventName) continue;
                    var message = Find(row.Message);
                    return message == null ? null : Decode(message, bytes, row.Defaults, hook);
                }
            }
            return null;
        }
    }
}
