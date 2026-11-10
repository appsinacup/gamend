using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Gamend.Testing;
using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    public class RestTests
    {
        [Fact]
        public void TaskCompletesInPollNeverInsideTheCallOrTheReply()
        {
            var h = new Harness();
            var task = h.Client.Api.LobbiesLobbyStats();
            var seen = See.Task(task);
            Assert.Equal(1, h.Server.Pending);
            h.Server.Reply(200, Q("{'data': {'total': 3}}"));
            Assert.Equal(0, seen.Calls);
            Assert.False(task.IsCompleted);
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.True(task.IsCompleted);
            Assert.True(seen.Last.Ok);
            Assert.Equal(3, (int)seen.Last.Data["total"]);
        }

        [Fact]
        public void RefusedCallCompletesFromPollNeverSynchronously()
        {
            var h = new Harness();
            var task = h.Client.Api.AuthenticateDeviceLogin(new JObject());
            Assert.False(task.IsCompleted);
            h.Client.Poll();
            Assert.True(task.IsCompleted);
        }

        // What a game loop looks like to `await`: Unity's main thread has a context
        // that would run a posted continuation a frame late.
        private sealed class FrameContext : SynchronizationContext
        {
            internal int Posted;

            public override void Post(SendOrPostCallback d, object state)
            {
                Posted++;
            }
        }

        private static void AssertAwaitRunsInsidePoll()
        {
            var h = new Harness();
            var polling = false;
            var ranInsidePoll = false;
            var thread = -1;
            async Task Caller()
            {
                await h.Client.Api.LobbiesLobbyStats();
                ranInsidePoll = polling;
                thread = Environment.CurrentManagedThreadId;
            }
            var caller = Caller();
            h.Server.Reply(200, "{}");
            Assert.False(caller.IsCompleted);
            polling = true;
            h.Client.Poll();
            polling = false;
            Assert.True(caller.IsCompleted);
            Assert.True(ranInsidePoll);
            Assert.Equal(Environment.CurrentManagedThreadId, thread);
        }

        [Fact]
        public void AwaitContinuesInlineOnTheThreadThatPolls()
        {
            var previous = SynchronizationContext.Current;
            SynchronizationContext.SetSynchronizationContext(null);
            try
            {
                AssertAwaitRunsInsidePoll();
            }
            finally
            {
                SynchronizationContext.SetSynchronizationContext(previous);
            }
        }

        [Fact]
        public void AwaitContinuesInlineUnderTheGameLoopsOwnContext()
        {
            var previous = SynchronizationContext.Current;
            var frame = new FrameContext();
            SynchronizationContext.SetSynchronizationContext(frame);
            try
            {
                AssertAwaitRunsInsidePoll();
                Assert.Equal(0, frame.Posted);
            }
            finally
            {
                SynchronizationContext.SetSynchronizationContext(previous);
            }
        }

        [Fact]
        public void TransportMayCompleteOnAnyThreadAndTheAnswerStillArrivesInPoll()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.LobbiesLobbyStats());
            var other = new Thread(() => h.Server.Reply(200, "{}"));
            other.Start();
            other.Join();
            Assert.Equal(0, seen.Calls);
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
        }

        [Fact]
        public void RepliesRunInTheOrderTheyArrived()
        {
            var h = new Harness();
            var order = new List<string>();
            h.Client.Rest.Send("GET", "/api/v1/a").ContinueWith(_ => order.Add("a"), TaskContinuationOptions.ExecuteSynchronously);
            h.Client.Rest.Send("GET", "/api/v1/b").ContinueWith(_ => order.Add("b"), TaskContinuationOptions.ExecuteSynchronously);
            h.Server.Reply(200, "{}");
            h.Server.Reply(200, "{}");
            h.Client.Poll();
            Assert.Equal(new List<string> { "a", "b" }, order);
        }

        [Fact]
        public void EveryCallNamesTheRunAndOnlyASignedInOneCarriesAToken()
        {
            var h = new Harness();
            h.Client.Api.LobbiesLobbyStats();
            var anonymous = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/lobbies/stats", anonymous.Url);
            Assert.Equal("GET", anonymous.Method);
            Assert.Equal("run-1", FakeHttp.Header(anonymous, "x-gamend-session"));
            Assert.Equal("application/json", FakeHttp.Header(anonymous, "accept"));
            Assert.StartsWith("gamend-csharp/", FakeHttp.Header(anonymous, "user-agent"));
            Assert.Equal("", FakeHttp.Header(anonymous, "authorization"));
            Assert.Empty(anonymous.Body);
            Assert.Equal("", FakeHttp.Header(anonymous, "content-type"));
            h.Server.Reply(200, "{}");

            h.SignedIn();
            h.Client.Api.UsersGetCurrentUser();
            Assert.Equal("Bearer a1", FakeHttp.Header(h.Server.Next, "authorization"));
        }

        [Fact]
        public void BodyGoesAsJsonAndAPostWithoutOneSendsAnEmptyObject()
        {
            var h = new Harness();
            h.Client.Api.LobbiesQuickJoin(O("{'title': 'duel', 'max_users': 2}"));
            var join = h.Server.Next;
            h.Server.Reply(200, "{}");
            Assert.Equal("POST", join.Method);
            Assert.Equal("application/json", FakeHttp.Header(join, "content-type"));
            Same(J("{'title': 'duel', 'max_users': 2}"), Json.Parse(join.BodyText));

            h.Client.Api.LobbiesLeaveLobby();
            var leave = h.Server.Next;
            Assert.Equal("{}", leave.BodyText);
            Assert.Equal("application/json", FakeHttp.Header(leave, "content-type"));
        }

        [Fact]
        public void ErrorReplyCarriesItsCodeAndOneWithNoCodeItsStatus()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.LobbiesGetLobby("x"));
            h.Server.Reply(404, Q("{'error': 'not_found', 'message': 'No such lobby'}"));
            h.Client.Poll();
            Assert.False(seen.Last.Ok);
            Assert.Equal(404, seen.Last.Status);
            Assert.Equal("not_found", seen.Last.Error);
            Assert.Equal("not_found", seen.Last.Code);
            Assert.Equal("No such lobby", seen.Last.Message);

            seen.Watch(h.Client.Api.LobbiesGetLobby("x"));
            h.Server.Reply(502, "<html>bad gateway</html>");
            h.Client.Poll();
            Assert.Equal("http_502", seen.Last.Error);
            Assert.Equal(JTokenType.Null, seen.Last.Body.Type);
            Assert.Equal("<html>bad gateway</html>", seen.Last.Text);
        }

        [Fact]
        public void NoReplyAtAllIsStatus0WithTheTransportsReason()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.LobbiesLobbyStats());
            h.Server.Fail("connection refused");
            h.Client.Poll();
            Assert.Equal(0, seen.Last.Status);
            Assert.Equal("connection refused", seen.Last.Error);
            Assert.False(seen.Last.Ok);
        }

        [Fact]
        public void A401RefreshesOnceAndSendsTheCallAgainWithTheNewToken()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Api.UsersGetCurrentUser());
            h.Server.Reply(401, Q("{'error': 'unauthorized'}"));
            h.Client.Poll();

            Assert.Equal(1, h.Server.Pending);
            var refresh = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/refresh", refresh.Url);
            Same(J("{'refresh_token': 'r1'}"), Json.Parse(refresh.BodyText));
            Assert.Equal("", FakeHttp.Header(refresh, "authorization"));
            h.Server.Reply(200, SessionReply(2));
            h.Client.Poll();

            Assert.Equal(1, h.Server.Pending);
            var retry = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/me", retry.Url);
            Assert.Equal("Bearer a2", FakeHttp.Header(retry, "authorization"));
            h.Server.Reply(200, Q("{'data': {'id': 'u1'}}"));
            h.Client.Poll();

            Assert.Equal(1, seen.Calls);
            Assert.True(seen.Last.Ok);
            Assert.Equal("a2", h.Client.Auth.Session.AccessToken);
        }

        [Fact]
        public void TwoCallsThatMeetA401ShareOneRefresh()
        {
            var h = new Harness();
            h.SignedIn();
            var first = See.Task(h.Client.Api.UsersGetCurrentUser());
            var second = See.Task(h.Client.Api.LobbiesLobbyStats());
            h.Server.Reply(401, "{}");
            h.Server.Reply(401, "{}");
            h.Client.Poll();

            Assert.Equal(1, h.Server.Pending);
            h.Server.Reply(200, SessionReply(2));
            h.Client.Poll();
            Assert.Equal(2, h.Server.Pending);
            h.Server.Reply(200, "{}");
            h.Server.Reply(200, "{}");
            h.Client.Poll();
            Assert.Equal(1, first.Calls);
            Assert.Equal(1, second.Calls);
            Assert.True(first.Last.Ok);
            Assert.True(second.Last.Ok);

            var refreshes = 0;
            foreach (var request in h.Server.Sent)
            {
                if (request.Url == "http://game.test/api/v1/refresh") refreshes++;
            }
            Assert.Equal(1, refreshes);
        }

        [Fact]
        public void RefusedRefreshSignsOutAndHandsTheCallIts401()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Api.UsersGetCurrentUser());
            h.Server.Reply(401, Q("{'error': 'unauthorized'}"));
            h.Client.Poll();
            h.Server.Reply(401, Q("{'error': 'invalid_token'}"));
            h.Client.Poll();

            Assert.Equal(1, seen.Calls);
            Assert.Equal(401, seen.Last.Status);
            Assert.Equal("unauthorized", seen.Last.Error);
            Assert.False(h.Client.Auth.SignedIn);
            Assert.Equal(0, h.Server.Pending);
            h.Client.Poll();
            Assert.Single(h.Changes);
            Assert.Null(h.Changes[0]);
        }

        [Fact]
        public void A401WithNoSessionToRefreshGoesStraightToTheCaller()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.UsersGetCurrentUser());
            h.Server.Reply(401, Q("{'error': 'unauthorized'}"));
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.Equal("unauthorized", seen.Last.Error);
            Assert.Equal(0, h.Server.Pending);
        }

        [Fact]
        public void ClientWithNoTransportAnswersEveryCallWithAnError()
        {
            var client = new Client(new Config { BaseUrl = "http://game.test" });
            var seen = See.Task(client.Api.LobbiesLobbyStats());
            client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.Equal("no HTTP transport configured", seen.Last.Error);
        }

        [Fact]
        public void ReplyThatLandsAfterTheClientIsGoneIsDropped()
        {
            var server = new FakeHttp();
            Seen<Response> seen;
            using (var client = new Client(new Config { BaseUrl = "http://game.test", Http = server }))
            {
                seen = See.Task(client.Api.LobbiesLobbyStats());
                Assert.Equal(1, server.Pending);
            }
            server.Reply(200, "{}");
            Assert.Equal(0, seen.Calls);
        }

        [Fact]
        public void ListenerThatThrowsSurfacesFromPollAndCostsNothingElse()
        {
            var c = new Connected();
            var heard = 0;
            c.Client.Realtime.OnEvent(e => throw new FormatException("the game's bug"));
            c.Client.Realtime.OnEvent(e => heard++);
            var answered = See.Task(c.Client.Api.LobbiesLobbyStats());
            c.Socket.Receive(Message("user:u1", "updated", J("{'id': 'u1'}")));
            c.Server.Reply(200, "{}");
            var thrown = Assert.Throws<FormatException>(() => c.Client.Poll());
            Assert.Equal("the game's bug", thrown.Message);
            Assert.Equal(1, heard);
            Assert.Equal(1, answered.Calls);
            c.Client.Poll();
        }

        [Fact]
        public void BodyIsTheOneTheCallMeantEvenAfterARetry()
        {
            var h = new Harness();
            h.SignedIn();
            var body = O("{'title': 'first'}");
            h.Client.Api.LobbiesQuickJoin(body);
            body["title"] = "changed";
            h.Server.Reply(401, "{}");
            h.Client.Poll();
            h.Server.Reply(200, SessionReply(2));
            h.Client.Poll();
            Same(J("{'title': 'first'}"), Json.Parse(h.Server.Next.BodyText));
        }

        [Fact]
        public void TimerCancelledByAnEarlierTimerInTheSameDrainDoesNotRun()
        {
            var loop = new Loop(() => 10);
            var ran = false;
            long second = 0;
            loop.After(0, () => loop.Cancel(second));
            second = loop.After(0, () => ran = true);
            loop.Drain();
            Assert.False(ran);
        }
    }
}
