using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    // A connected client in protobuf mode that hands back what listeners saw.
    internal sealed class Pb : Harness
    {
        internal readonly List<Event> Events = new List<Event>();

        internal Pb()
        {
            SignedIn();
            Client.Realtime.OnEvent(e => Events.Add(e));
            Client.Realtime.Connect();
            Socket.Accept();
            Client.Poll();
        }

        internal JToken Receive(string topic, string eventName, string messageName, JToken value)
        {
            var body = Proto.Encode(Proto.Find(messageName), value);
            var frame = new List<byte> { 2, (byte)topic.Length, (byte)eventName.Length };  // broadcast
            frame.AddRange(System.Text.Encoding.UTF8.GetBytes(topic));
            frame.AddRange(System.Text.Encoding.UTF8.GetBytes(eventName));
            frame.AddRange(body);
            Socket.ReceiveBinary(frame.ToArray());
            Client.Poll();
            return Events[Events.Count - 1].Payload;
        }
    }

    public class ProtoTests
    {
        private static Proto.Message Msg(string name)
        {
            var found = Proto.Find(name);
            Assert.NotNull(found);
            return found;
        }

        private static JValue Raw(params int[] values)
        {
            return new JValue((object)B(values));
        }

        [Fact]
        public void TheWireFormatDecodesStringsVarintsZigzag()
        {
            // WalletChange{currency: "coins", balance: 150, delta: -5}, by hand.
            var wire = B(0x0A, 5, 'c', 'o', 'i', 'n', 's', 0x10, 0x96, 0x01, 0x18, 0x09);
            var decoded = Proto.Decode(Msg("WalletChange"), wire, true);
            Assert.NotNull(decoded);
            Same(J("{'currency': 'coins', 'balance': 150, 'delta': -5}"), decoded);

            Assert.Null(Proto.Decode(Msg("WalletChange"), B(0x0A, 9, 'c'), true));
        }

        [Fact]
        public void EncodeAndDecodeAgreeMapsAndNestedMessagesIncluded()
        {
            var lobby = O("{'id': 'l1', 'title': 'Duel', 'max_users': 4, 'hostless': false, 'members': [{'id': 'u1', 'username': 'ann'}, {'id': 'u2'}]}");
            lobby["metadata_json"] = "{\"map\":\"dunes\"}";
            var wire = Proto.Encode(Msg("Lobby"), lobby);
            var back = Proto.Decode(Msg("Lobby"), wire, false);
            Assert.NotNull(back);
            Assert.Equal("l1", (string)back["id"]);
            Assert.Equal(4, (int)back["max_users"]);
            Assert.False((bool)back["hostless"]);  // optional: present because it was sent
            Assert.Equal(2, ((JArray)back["members"]).Count);
            Assert.Equal("ann", (string)back["members"][0]["username"]);
            Same(J("{'map': 'dunes'}"), back["metadata"]);
            Assert.False(back.ContainsKey("metadata_json"));
            Assert.False(back.ContainsKey("host_id"));

            var found = J("{'lobby_id': 'l9', 'match_params': {'mode': 'duel', 'region': 'eu'}}");
            var parameters = Proto.Decode(Msg("MatchmakingFound"), Proto.Encode(Msg("MatchmakingFound"), found), true);
            Assert.NotNull(parameters);
            Same(found, parameters);
        }

        [Fact]
        public void DefaultsFillWhatProto3LeavesOutAndNeverAnOptionalField()
        {
            var chat = Proto.Decode(Msg("ChatMessage"), new byte[0], true);
            Assert.NotNull(chat);
            Assert.Equal("", (string)chat["id"]);
            Assert.Equal(0, (int)chat["inserted_at_ms"]);
            Same(new JObject(), chat["metadata"]);
            Assert.False(chat.ContainsKey("updated_at_ms"));
            Assert.False(chat.ContainsKey("sender_email"));

            var user = Proto.Decode(Msg("User"), new byte[0], false);
            Assert.NotNull(user);
            Assert.False(user.HasValues);
        }

        [Fact]
        public void BinaryEventsDecodeByTopicAndEventAsTheServerMapsThem()
        {
            var kv = O("{'key': 'progress', 'user_id': 'u1'}");
            kv["data_json"] = "{\"level\":3}";
            kv["metadata_json"] = "{}";
            var decoded = Proto.DecodeBinaryEvent("user:u1", "kv_updated", Proto.Encode(Msg("KvEntry"), kv));
            Assert.NotNull(decoded);
            Same(J("{'key': 'progress', 'user_id': 'u1', 'data': {'level': 3}, 'metadata': {}}"), decoded);

            // `updated` is a User on user:, a Lobby on lobby:.
            var lobby = Proto.DecodeBinaryEvent("lobby:l1", "updated", Proto.Encode(Msg("Lobby"), J("{'id': 'l1', 'title': 'T'}")));
            Assert.NotNull(lobby);
            Assert.Equal("T", (string)lobby["title"]);
            Assert.Null(Proto.DecodeBinaryEvent("lobby:l1", "unmapped", new byte[0]));

            var entry = O("{'key': 'k'}");
            entry["data_pb"] = Raw(1, 2);
            var pb = Proto.DecodeBinaryEvent("user:u1", "kv_updated", Proto.Encode(Msg("KvEntry"), entry));
            Assert.NotNull(pb);
            Assert.Equal("AQI=", (string)pb["data_pb"]);
        }

        [Fact]
        public void BinaryFrameOnAProtobufConnectionReachesListenersDecoded()
        {
            var h = new Pb();
            var body = Proto.Encode(Msg("WalletChange"), J("{'currency': 'coins', 'balance': 10, 'delta': 2}"));
            var frame = new List<byte> { 0, 1, 7, 14 };  // push
            frame.AddRange(System.Text.Encoding.UTF8.GetBytes("1"));
            frame.AddRange(System.Text.Encoding.UTF8.GetBytes("user:u1"));
            frame.AddRange(System.Text.Encoding.UTF8.GetBytes("wallet_updated"));
            frame.AddRange(body);
            h.Socket.ReceiveBinary(frame.ToArray());
            h.Client.Poll();
            Assert.Single(h.Events);
            Assert.Equal(Events.WalletUpdated, h.Events[0].Kind);
            Same(J("{'currency': 'coins', 'balance': 10, 'delta': 2}"), h.Events[0].Payload);
            Assert.Empty(h.Events[0].Bytes);
        }

        [Fact]
        public void Base64()
        {
            Assert.Equal("", Proto.Base64(new byte[0]));
            Assert.Equal("Zg==", Proto.Base64(B('f')));
            Assert.Equal("Zm8=", Proto.Base64(B('f', 'o')));
            Assert.Equal("Zm9v", Proto.Base64(B('f', 'o', 'o')));
        }

        [Fact]
        public void GamesKvBytesReadThroughItsDecoderExactKeyFirstThenLongestPrefix()
        {
            var h = new Pb();
            h.Client.Realtime.RegisterKvDecoder("match:*", b => new JObject { ["by"] = "match", ["size"] = b.Length });
            h.Client.Realtime.RegisterKvDecoder("match:final:*", b => new JObject { ["by"] = "final" });
            h.Client.Realtime.RegisterKvDecoder("match:final:7", b => new JObject { ["by"] = "exact" });
            JToken Kv(string key)
            {
                var entry = new JObject { ["key"] = key, ["data_pb"] = Raw(0x08, 0x2A) };
                return h.Receive("user:u1", "kv_updated", "KvEntry", entry);
            }
            Same(J("{'by': 'match', 'size': 2}"), Kv("match:1")["data"]);
            Assert.Equal("final", (string)Kv("match:final:1")["data"]["by"]);
            Assert.Equal("exact", (string)Kv("match:final:7")["data"]["by"]);
            var unread = (JObject)Kv("loadout");
            Assert.Equal("CCo=", (string)unread["data_pb"]);
            Assert.False(unread.ContainsKey("data"));
        }

        [Fact]
        public void GamesMetadataBytesReadThroughItsEntitysDecoder()
        {
            var h = new Pb();
            h.Client.Realtime.RegisterMetadataDecoder("lobby", b => new JObject { ["hat_bytes"] = b.Length });
            var meta = B(0x0A, 3, 'r', 'e', 'd');
            var lobby = (JObject)h.Receive("lobby:l1", "updated", "Lobby", new JObject { ["id"] = "l1", ["metadata_pb"] = new JValue((object)meta) });
            Same(J("{'hat_bytes': 5}"), lobby["metadata"]);
            Assert.False(lobby.ContainsKey("metadata_pb"));

            // No decoder for users: the bytes stay, base64.
            var user = h.Receive("user:u1", "updated", "User", new JObject { ["id"] = "u1", ["metadata_pb"] = new JValue((object)meta) });
            Assert.Equal(Proto.Base64(meta), (string)user["metadata_pb"]);
        }

        [Fact]
        public void DecoderThatThrowsLeavesTheBytesAsBase64()
        {
            var h = new Pb();
            h.Client.Realtime.RegisterKvDecoder("k", b => throw new System.FormatException("bad"));
            var payload = h.Receive("user:u1", "kv_updated", "KvEntry", new JObject { ["key"] = "k", ["data_pb"] = Raw(1) });
            Assert.Equal("AQ==", (string)payload["data_pb"]);
        }

        [Fact]
        public void Unbase64UndoesBase64()
        {
            foreach (var text in new[] { new byte[0], B('f'), B('f', 'o'), B('f', 'o', 'o'), B(0x00, 0xFF, 0x10) })
            {
                Assert.Equal(text, Proto.Unbase64(Proto.Base64(text)));
            }
            Assert.Null(Proto.Unbase64("not base64!"));
        }
    }
}
