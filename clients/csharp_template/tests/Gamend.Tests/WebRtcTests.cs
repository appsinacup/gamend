using System.Collections.Generic;
using System.Text;
using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    // Signed in, connected, the user channel joined.
    internal sealed class Joined : Harness
    {
        internal Joined(RealtimeFormat format = RealtimeFormat.Json)
            : base(true, format)
        {
            SignedIn();
            Client.Realtime.Connect();
            Socket.Accept();
            Client.Poll();
            Socket.Receive(ReplyTo(A(Socket.TakeFrames()[0]), "ok"));
            Client.Poll();
        }

        internal List<JArray> Frames()
        {
            var output = new List<JArray>();
            foreach (var frame in Socket.TakeFrames()) output.Add(A(frame));
            return output;
        }

        // Offer, answer, one channel open: connected.
        internal Seen<string> ConnectAll()
        {
            var connected = See.Task(Client.WebRtc.Connect());
            Peer.Offer("v=0 offer");
            Client.Poll();
            Socket.Receive(ReplyTo(Frames()[0], "ok"));
            Peer.OpenChannel("events");
            Client.Poll();
            return connected;
        }
    }

    public class WebRtcTests
    {
        private static Proto.Message Envelope
        {
            get { return Proto.Find("RtcEnvelope"); }
        }

        [Fact]
        public void WebRtcNeedsTheUserChannelAndAPeerTransport()
        {
            var h = new Harness();
            var error = See.Task(h.Client.WebRtc.Connect());
            h.Client.Poll();
            Assert.Equal("not_joined", error.Last);
            Assert.False(h.Peer.Opened);
        }

        [Fact]
        public void OfferGoesOverTheUserChannelAndTheAnswerAndCandidatesComeBack()
        {
            var h = new Joined();
            var error = See.Task(h.Client.WebRtc.Connect());
            Assert.True(h.Peer.Opened);
            Assert.Equal("", h.Peer.Protocol);
            Assert.Equal(new List<string> { "stun:stun.l.google.com:19302" }, h.Peer.IceServers);
            Assert.Single(h.Peer.Channels);
            Assert.Equal("events", h.Peer.Channels[0].Label);
            Assert.True(h.Peer.Channels[0].Ordered);
            Assert.Equal(-1, h.Peer.Channels[0].MaxRetransmits);
            Assert.Equal(WebRtcState.Connecting, h.Client.WebRtc.State);

            h.Peer.Offer("v=0 offer");
            h.Peer.Candidate("candidate:1 1 UDP 1 10.0.0.1 5000 typ host", "0");
            h.Client.Poll();
            var sent = h.Frames();
            Assert.Equal(2, sent.Count);
            Assert.Equal("webrtc:offer", (string)sent[0][3]);
            Same(J("{'sdp': 'v=0 offer', 'type': 'offer'}"), sent[0][4]);
            Assert.Equal("webrtc:ice", (string)sent[1][3]);
            Assert.Equal("0", (string)sent[1][4]["sdpMid"]);
            h.Socket.Receive(ReplyTo(sent[0], "ok"));

            h.Socket.Receive(Message("user:u1", "webrtc:answer", J("{'sdp': 'v=0 answer', 'type': 'answer'}")));
            h.Socket.Receive(Message("user:u1", "webrtc:ice", J("{'candidate': 'candidate:2 1 UDP 1 10.0.0.2 6000 typ host', 'sdpMid': '0', 'sdpMLineIndex': 0}")));
            h.Client.Poll();
            Assert.Equal("v=0 answer", h.Peer.Remote.Sdp);
            Assert.Equal("answer", h.Peer.Remote.Type);
            Assert.Single(h.Peer.Candidates);
            Assert.Equal("0", h.Peer.Candidates[0].Mid);
            Assert.Equal(0, error.Calls);

            h.Peer.OpenChannel("events");
            h.Client.Poll();
            Assert.Equal("", error.Last);
            Assert.Equal(WebRtcState.Connected, h.Client.WebRtc.State);
            Assert.True(h.Client.WebRtc.ChannelOpen("events"));
            Assert.False(h.Client.WebRtc.ChannelOpen("state"));
        }

        [Fact]
        public void HooksOverTheEventsChannelJsonMatchedByPluginAndFunction()
        {
            var h = new Joined();
            h.ConnectAll();
            var data = new List<string>();
            h.Client.WebRtc.OnData((label, d, binary) => data.Add(Encoding.UTF8.GetString(d)));
            var got = See.Task(h.Client.WebRtc.CallHook("arena", "move", J("{'x': 1}")));
            var sent = h.Peer.Sent;
            Assert.Single(sent);
            Assert.Equal("events", sent[0].Label);
            Assert.False(sent[0].Binary);
            Same(J("{'type': 'call_hook', 'plugin': 'arena', 'fn': 'move', 'args': [{'x': 1}]}"), Json.Parse(sent[0].Text));

            h.Peer.Receive("events", Q("{'type':'game_event','n':1}"));
            h.Peer.Receive("events", Q("{'type':'hook_reply','plugin':'arena','fn':'move','data':42}"));
            h.Client.Poll();
            Assert.True(got.Last.Ok);
            Assert.Equal(42, (int)got.Last.Data);
            Assert.Single(data);
            Assert.Equal(Q("{'type':'game_event','n':1}"), data[0]);

            got.Watch(h.Client.WebRtc.CallHook("arena", "nope", new JArray()));
            h.Peer.Receive("events", Q("{'type':'hook_error','plugin':'arena','fn':'nope','error':'boom'}"));
            h.Client.Poll();
            Assert.False(got.Last.Ok);
            Assert.Equal("boom", got.Last.Error);
        }

        [Fact]
        public void HooksOverTheEventsChannelProtobufEnvelopesWithRequestIds()
        {
            var h = new Joined(RealtimeFormat.Protobuf);
            h.ConnectAll();
            Assert.Equal("protobuf", h.Peer.Protocol);
            var first = See.Task(h.Client.WebRtc.CallHook("arena", "move", J("[1]")));
            var second = See.Task(h.Client.WebRtc.CallHook("arena", "move", J("[2]")));
            var sent = h.Peer.Sent;
            Assert.Equal(2, sent.Count);
            Assert.True(sent[0].Binary);
            var call = Proto.Decode(Envelope, sent[1].Data, false);
            Assert.NotNull(call);
            Assert.Equal(2, (int)call["call_hook"]["id"]);
            Same(J("[2]"), call["call_hook"]["args"]);

            // Out of order, told apart by id.
            h.Peer.Receive("events", Proto.Encode(Envelope, new JObject { ["hook_reply"] = new JObject { ["id"] = 2, ["data_json"] = "\"two\"" } }), true);
            h.Peer.Receive("events", Proto.Encode(Envelope, new JObject { ["hook_error"] = new JObject { ["id"] = 1, ["error"] = "nope" } }), true);
            h.Client.Poll();
            Assert.True(second.Last.Ok);
            Assert.Equal("two", (string)second.Last.Data);
            Assert.False(first.Last.Ok);
            Assert.Equal("nope", first.Last.Error);
        }

        [Fact]
        public void OfferTheServerRefusesFailsTheConnect()
        {
            var h = new Joined();
            var error = See.Task(h.Client.WebRtc.Connect());
            h.Peer.Offer("v=0");
            h.Client.Poll();
            var offer = h.Frames()[0];
            h.Socket.Receive(ReplyTo(offer, "error", J("{'error': 'webrtc_disabled'}")));
            h.Client.Poll();
            Assert.Equal("webrtc_disabled", error.Last);
            Assert.Equal(WebRtcState.Failed, h.Client.WebRtc.State);
        }

        [Fact]
        public void ConnectionThatNeverOpensAChannelTimesOut()
        {
            var h = new Joined();
            var error = See.Task(h.Client.WebRtc.Connect());
            h.AdvanceSeconds(15);
            Assert.Equal("timeout", error.Last);
            Assert.Equal(WebRtcState.Failed, h.Client.WebRtc.State);
            Assert.True(h.Peer.Closes >= 1);
        }

        [Fact]
        public void CloseTellsTheServerAndLosingTheSocketClosesToo()
        {
            var h = new Joined();
            h.ConnectAll();
            h.Frames();
            h.Client.WebRtc.Close();
            var sent = h.Frames();
            Assert.Single(sent);
            Assert.Equal("webrtc:close", (string)sent[0][3]);
            Assert.Equal(WebRtcState.Closed, h.Client.WebRtc.State);
            Assert.False(h.Peer.Opened);

            h.ConnectAll();
            Assert.Equal(WebRtcState.Connected, h.Client.WebRtc.State);
            var pending = See.Task(h.Client.WebRtc.CallHook("a", "b", new JArray()));
            h.Socket.Drop();
            h.Client.Poll();
            Assert.Equal(WebRtcState.Closed, h.Client.WebRtc.State);
            Assert.Equal("closed", pending.Last.Error);
        }

        [Fact]
        public void TypedHookSendsRawBytesAndAnswersRawBytesInProtobufModeOnly()
        {
            var h = new Joined(RealtimeFormat.Protobuf);
            h.ConnectAll();
            var got = See.Task(h.Client.WebRtc.CallHookRaw("arena", "move", B(0x08, 0x01)));
            var last = h.Peer.Sent[h.Peer.Sent.Count - 1];
            var sent = Proto.Decode(Envelope, last.Data, false);
            Assert.NotNull(sent);
            Assert.Equal(Proto.Base64(B(0x08, 0x01)), (string)sent["call_hook"]["args_raw"]);
            var reply = new JObject { ["hook_reply"] = new JObject { ["id"] = 1, ["data_raw"] = new JValue((object)B(0x10, 0x02)) } };
            h.Peer.Receive("events", Proto.Encode(Envelope, reply), true);
            h.Client.Poll();
            Assert.True(got.Last.Ok);
            Assert.Equal(B(0x10, 0x02), got.Last.Bytes);

            var jsonMode = new Joined();
            jsonMode.ConnectAll();
            got.Watch(jsonMode.Client.WebRtc.CallHookRaw("arena", "move", B('x')));
            jsonMode.Client.Poll();
            Assert.Equal("needs_protobuf", got.Last.Error);
        }
    }
}
