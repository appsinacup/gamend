using System.Collections.Generic;
using System.Text;
using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    // Signed in as u1 and connected, the user channel joined.
    internal sealed class Connected : Harness
    {
        internal readonly List<Event> Events = new List<Event>();
        internal readonly List<RealtimeState> States = new List<RealtimeState>();

        internal Connected()
        {
            SignedIn();
            Client.Realtime.OnEvent(e => Events.Add(e));
            Client.Realtime.OnState(s => States.Add(s));
            Client.Realtime.Connect();
            Socket.Accept();
            Client.Poll();
            Assert.Single(Socket.TakeFrames());
            Socket.Receive(PhxReply("1", "1", "user:u1", "ok"));
            Client.Poll();
        }
    }

    public class RealtimeTests
    {
        private static byte[] Frame(params object[] parts)
        {
            var bytes = new List<byte>();
            foreach (var part in parts)
            {
                if (part is int) bytes.Add((byte)(int)part);
                else if (part is string) bytes.AddRange(Encoding.UTF8.GetBytes((string)part));
                else bytes.AddRange((byte[])part);
            }
            return bytes.ToArray();
        }

        [Fact]
        public void ConnectionNamesThePlayersTokenTheRunAndTheProtocolVersion()
        {
            var h = new Harness();
            h.SignedIn();
            h.Client.Realtime.Connect();
            Assert.True(h.Socket.Opened);
            Assert.Equal("ws://game.test/socket/websocket?vsn=2.0.0&token=a1&client_session=run-1", h.Socket.Url);
            Assert.Equal(RealtimeState.Connecting, h.Client.Realtime.State);
        }

        [Fact]
        public void ConnectingWithoutAPlayerDoesNothing()
        {
            var h = new Harness();
            h.Client.Realtime.Connect();
            Assert.False(h.Socket.Opened);
            Assert.Equal(RealtimeState.Disconnected, h.Client.Realtime.State);
        }

        [Fact]
        public void OnceOpenItJoinsTheUserChannel()
        {
            var h = new Harness();
            h.SignedIn();
            h.Client.Realtime.Connect();
            h.Socket.Accept();
            h.Client.Poll();
            Assert.Equal(RealtimeState.Connected, h.Client.Realtime.State);
            var frames = h.Socket.TakeFrames();
            Assert.Single(frames);
            Same(J("['1', '1', 'user:u1', 'phx_join', {}]"), A(frames[0]));
            Assert.False(h.Client.Realtime.Joined("user:u1"));
            h.Socket.Receive(PhxReply("1", "1", "user:u1", "ok"));
            h.Client.Poll();
            Assert.True(h.Client.Realtime.Joined("user:u1"));
        }

        [Fact]
        public void ServerEventsArriveNamedInPoll()
        {
            var c = new Connected();
            c.Socket.Receive(Message("user:u1", "updated", J("{'id': 'u1'}")));
            Assert.Empty(c.Events);
            c.Client.Poll();
            Assert.Single(c.Events);
            Assert.Equal(Events.UserUpdated, c.Events[0].Kind);
            Assert.Equal("updated", c.Events[0].Name);
            Assert.Equal("u1", (string)c.Events[0].Payload["id"]);

            c.Socket.Receive(Message("user:u1", "something_new", new JObject()));
            c.Client.Poll();
            Assert.Equal(Events.Message, c.Events[c.Events.Count - 1].Kind);
        }

        [Fact]
        public void HookCallGoesOverTheUserChannelAndAnswersItsDataOrItsError()
        {
            var c = new Connected();
            var got = See.Task(c.Client.Realtime.CallHook("arena", "start", J("[1, 'x']")));
            var frames = c.Socket.TakeFrames();
            Assert.Single(frames);
            Same(J("['1', '2', 'user:u1', 'call_hook', {'plugin': 'arena', 'fn': 'start', 'args': [1, 'x']}]"), A(frames[0]));
            c.Socket.Receive(PhxReply("1", "2", "user:u1", "ok", J("{'data': {'round': 1}}")));
            c.Client.Poll();
            Assert.True(got.Last.Ok);
            Assert.Equal(1, (int)got.Last.Data["round"]);

            got.Watch(c.Client.Realtime.CallHook("arena", "nope", new JArray()));
            c.Socket.Receive(PhxReply("1", "3", "user:u1", "error", J("{'error': 'unknown_function'}")));
            c.Client.Poll();
            Assert.False(got.Last.Ok);
            Assert.Equal("unknown_function", got.Last.Error);
        }

        [Fact]
        public void CommandGoesToItsChannelWithItsEventAndParams()
        {
            var c = new Connected();
            Commands.ResultsList(c.Client.Realtime, O("{'kind': 'match'}"));
            var frames = c.Socket.TakeFrames();
            Assert.Single(frames);
            var sent = A(frames[0]);
            Assert.Equal("user:u1", (string)sent[2]);
            Assert.Equal("results:list", (string)sent[3]);
            Assert.Equal("match", (string)sent[4]["kind"]);

            c.Client.Realtime.JoinLobby("L1");
            frames = c.Socket.TakeFrames();
            Assert.Single(frames);
            var join = A(frames[0]);
            c.Socket.Receive(ReplyTo(join, "ok"));
            c.Client.Poll();

            Commands.LobbyGetServerTime(c.Client.Realtime, "L1");
            frames = c.Socket.TakeFrames();
            Assert.Single(frames);
            sent = A(frames[0]);
            Assert.Equal("lobby:L1", (string)sent[2]);
            Assert.Equal("get_server_time", (string)sent[3]);
        }

        [Fact]
        public void PushNobodyAnswersTimesOutAndOneToAnUnjoinedTopicIsRefused()
        {
            var c = new Connected();
            var got = See.Task(c.Client.Realtime.Push("user:u1", "ping"));
            Assert.Single(c.Socket.TakeFrames());
            c.AdvanceSeconds(10);
            Assert.Equal("timeout", got.Last.Status);
            Assert.False(got.Last.Ok);

            got.Watch(c.Client.Realtime.Push("lobby:x", "ping"));
            Assert.Empty(c.Socket.TakeFrames());
            c.Client.Poll();
            Assert.Equal("not_joined", got.Last.Status);
        }

        [Fact]
        public void TopicsJoinNowOrWhenTheConnectionOpensAndRejoinAfterADropInOrder()
        {
            var h = new Harness();
            h.SignedIn();
            var lobbyJoin = See.Task(h.Client.Realtime.JoinLobby("l1"));
            h.Client.Realtime.Connect();
            h.Socket.Accept();
            h.Client.Poll();
            var frames = h.Socket.TakeFrames();
            Assert.Equal(2, frames.Count);
            Assert.Equal("user:u1", (string)A(frames[0])[2]);
            Assert.Equal("lobby:l1", (string)A(frames[1])[2]);
            h.Socket.Receive(PhxReply("1", "1", "user:u1", "ok"));
            h.Socket.Receive(PhxReply("2", "2", "lobby:l1", "ok"));
            h.Client.Poll();
            Assert.True(lobbyJoin.Last.Ok);

            h.Socket.Drop();
            h.Client.Poll();
            Assert.Equal(RealtimeState.Reconnecting, h.Client.Realtime.State);
            Assert.False(h.Client.Realtime.Joined("lobby:l1"));
            Assert.Equal(1, h.Socket.Opens);
            h.AdvanceMs(100);
            Assert.Equal(2, h.Socket.Opens);
            h.Socket.Accept();
            h.Client.Poll();
            frames = h.Socket.TakeFrames();
            Assert.Equal(2, frames.Count);
            Assert.Equal("user:u1", (string)A(frames[0])[2]);
            Assert.Equal("lobby:l1", (string)A(frames[1])[2]);
            Assert.Equal(RealtimeState.Connected, h.Client.Realtime.State);
        }

        [Fact]
        public void PendingPushFailsWhenTheConnectionDrops()
        {
            var c = new Connected();
            var got = See.Task(c.Client.Realtime.Push("user:u1", "ping"));
            c.Socket.Drop();
            c.Client.Poll();
            Assert.Equal("disconnected", got.Last.Status);
        }

        [Fact]
        public void ConnectionThatNeverOpenedRefreshesTheTokenBeforeTheNextAttempt()
        {
            var h = new Harness();
            h.SignedIn();
            h.Client.Realtime.Connect();
            h.Socket.Fail("handshake refused");
            h.Client.Poll();
            h.AdvanceMs(100);
            // The refresh goes first; the socket waits for it.
            Assert.Equal(1, h.Server.Pending);
            Assert.Equal("http://game.test/api/v1/refresh", h.Server.Next.Url);
            Assert.Equal(1, h.Socket.Opens);
            h.Server.Reply(200, SessionReply(2));
            h.Client.Poll();
            Assert.Equal(2, h.Socket.Opens);
            Assert.Contains("token=a2", h.Socket.Url);
        }

        [Fact]
        public void BackoffGrowsAndHoldsAtItsLastStep()
        {
            var h = new Harness();
            h.SignedIn();
            h.Client.Realtime.Connect();
            h.Socket.Accept();
            h.Client.Poll();
            foreach (var wait in new[] { 100, 500, 1000, 2000, 5000, 10000, 10000 })
            {
                var before = h.Socket.Opens;
                h.Socket.Drop();
                h.Client.Poll();
                h.AdvanceMs(wait - 1);
                Assert.Equal(before, h.Socket.Opens);
                h.AdvanceMs(1);
                if (h.Server.Pending > 0)
                {
                    // A drop that never opened refreshes first.
                    h.Server.Reply(200, SessionReply(1));
                    h.Client.Poll();
                }
                Assert.Equal(before + 1, h.Socket.Opens);
            }
        }

        [Fact]
        public void MissedHeartbeatDropsTheConnectionAndReconnects()
        {
            var c = new Connected();
            c.AdvanceSeconds(30);
            var frames = c.Socket.TakeFrames();
            Assert.Single(frames);
            Assert.Equal("phoenix", (string)A(frames[0])[2]);
            Assert.Equal("heartbeat", (string)A(frames[0])[3]);

            // Answered: the next beat goes out on time.
            var reference = A(frames[0])[1];
            c.Socket.Receive(ReplyFrame(JValue.CreateNull(), reference, "phoenix", "ok"));
            c.AdvanceSeconds(30);
            Assert.Single(c.Socket.TakeFrames());

            // Unanswered: the one after that finds it still pending.
            c.AdvanceSeconds(30);
            Assert.Equal(RealtimeState.Reconnecting, c.Client.Realtime.State);
            c.AdvanceMs(100);
            Assert.Equal(2, c.Socket.Opens);
        }

        [Fact]
        public void ChannelThatErrorsRejoinsAndOneTheServerClosesDoesNot()
        {
            var c = new Connected();
            c.Client.Realtime.JoinLobby("l1");
            c.Socket.TakeFrames();
            c.Socket.Receive(PhxReply("2", "2", "lobby:l1", "ok"));
            c.Client.Poll();

            c.Socket.Receive(Message("lobby:l1", "phx_error", new JObject()));
            c.Client.Poll();
            Assert.False(c.Client.Realtime.Joined("lobby:l1"));
            c.AdvanceSeconds(1);
            var frames = c.Socket.TakeFrames();
            Assert.Single(frames);
            Assert.Equal("phx_join", (string)A(frames[0])[3]);
            var reference = (string)A(frames[0])[1];
            c.Socket.Receive(PhxReply(reference, reference, "lobby:l1", "ok"));
            c.Client.Poll();
            Assert.True(c.Client.Realtime.Joined("lobby:l1"));

            c.Socket.Receive(Message("lobby:l1", "phx_close", new JObject()));
            c.Client.Poll();
            Assert.False(c.Client.Realtime.Joined("lobby:l1"));
            c.AdvanceSeconds(5);
            Assert.Empty(c.Socket.TakeFrames());
        }

        [Fact]
        public void JoinTheServerRefusesForGoodIsDroppedAndSaysWhy()
        {
            var c = new Connected();
            var got = See.Task(c.Client.Realtime.JoinLobby("secret"));
            c.Socket.TakeFrames();
            c.Socket.Receive(PhxReply("2", "2", "lobby:secret", "error", J("{'reason': 'unauthorized'}")));
            c.Client.Poll();
            Assert.False(got.Last.Ok);
            Assert.Equal("unauthorized", got.Last.Error);
            c.AdvanceSeconds(5);
            Assert.Empty(c.Socket.TakeFrames());
        }

        [Fact]
        public void LeavingSendsPhxLeaveAndStopsRejoining()
        {
            var c = new Connected();
            c.Client.Realtime.JoinLobby("l1");
            c.Socket.TakeFrames();
            c.Socket.Receive(PhxReply("2", "2", "lobby:l1", "ok"));
            c.Client.Poll();
            var got = See.Task(c.Client.Realtime.Leave("lobby:l1"));
            var frames = c.Socket.TakeFrames();
            Assert.Single(frames);
            Same(J("['2', '3', 'lobby:l1', 'phx_leave', {}]"), A(frames[0]));
            c.Socket.Receive(PhxReply("2", "3", "lobby:l1", "ok"));
            c.Client.Poll();
            Assert.True(got.Last.Ok);

            c.Socket.Drop();
            c.Client.Poll();
            c.AdvanceMs(100);
            c.Socket.Accept();
            c.Client.Poll();
            frames = c.Socket.TakeFrames();
            Assert.Single(frames);
            Assert.Equal("user:u1", (string)A(frames[0])[2]);
        }

        [Fact]
        public void DisconnectClosesForGoodAndSigningOutDoesTheSame()
        {
            var c = new Connected();
            c.Client.Realtime.Disconnect();
            Assert.Equal(RealtimeState.Disconnected, c.Client.Realtime.State);
            Assert.False(c.Socket.Opened);
            c.AdvanceSeconds(20);
            Assert.Equal(1, c.Socket.Opens);

            var d = new Connected();
            d.Client.Auth.Forget();
            d.Client.Poll();
            Assert.Equal(RealtimeState.Disconnected, d.Client.Realtime.State);
            d.AdvanceSeconds(20);
            Assert.Equal(1, d.Socket.Opens);
        }

        [Fact]
        public void DisconnectAnswersWaitingCallsFromPollNotFromInsideIt()
        {
            var c = new Connected();
            var push = See.Task(c.Client.Realtime.Push("user:u1", "ping"));
            var join = See.Task(c.Client.Realtime.JoinLobby("l1"));
            c.Client.Realtime.Disconnect();
            Assert.Equal(0, push.Calls);
            Assert.Equal(0, join.Calls);
            c.Client.Poll();
            Assert.Equal("disconnected", push.Last.Status);
            Assert.Equal("disconnected", join.Last.Status);
        }

        [Fact]
        public void StateChangesAreAnnouncedInOrder()
        {
            var c = new Connected();
            c.Socket.Drop();
            c.Client.Poll();
            c.AdvanceMs(100);
            c.Socket.Accept();
            c.Client.Poll();
            Assert.Equal(
                new List<RealtimeState> { RealtimeState.Connecting, RealtimeState.Connected, RealtimeState.Reconnecting, RealtimeState.Connected },
                c.States);
        }

        [Fact]
        public void BinaryEventNoDecoderReadsStillArrivesAsBytes()
        {
            var c = new Connected();
            c.Socket.ReceiveBinary(Frame(2, 7, 7, "user:u1", "unknown", B(0x08, 0x01)));
            c.Client.Poll();
            Assert.Single(c.Events);
            Assert.Equal("unknown", c.Events[0].Name);
            Assert.Equal(JTokenType.Null, c.Events[0].Payload.Type);
            Assert.Equal(B(0x08, 0x01), c.Events[0].Bytes);
        }

        [Fact]
        public void TheProtocolRefsJoinRefsAndFrames()
        {
            var p = new Phoenix();
            var (joinRef, join) = p.Join("room:1", J("{'a': 1}"));
            Assert.Equal("1", joinRef);
            Assert.Equal("[\"1\",\"1\",\"room:1\",\"phx_join\",{\"a\":1}]", join);
            var push = p.Push("room:1", "shout", new JObject());
            Assert.NotNull(push);
            Assert.Equal("[\"1\",\"2\",\"room:1\",\"shout\",{}]", push.Value.Text);
            Assert.Null(p.Push("room:2", "shout", new JObject()));
            Assert.Null(p.Decode("not json"));
            Assert.Null(p.Decode("[1,2,3]"));

            var binary = Frame(1, 1, 1, 6, 2, "1", "2", "room:1", "ok", "BYTES");
            var decoded = p.DecodeBinary(binary);
            Assert.NotNull(decoded);
            Assert.Equal(FrameKind.Reply, decoded.Kind);
            Assert.Equal("2", decoded.Ref);
            Assert.Equal("ok", decoded.Status);
            Assert.Equal(Encoding.UTF8.GetBytes("BYTES"), decoded.Bytes);
            var cut = new byte[8];
            System.Array.Copy(binary, cut, 8);
            Assert.Null(p.DecodeBinary(cut));
        }
    }
}
