using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    // Signed in as u1; `Open()` connects and joins the user channel, answering
    // its join and handing back what was sent after it.
    internal sealed class Live : Harness
    {
        internal readonly List<(KvKey Key, KvRow Row)> RowChanges = new List<(KvKey Key, KvRow Row)>();

        internal Live()
        {
            SignedIn();
            Client.Kv.OnChange((key, row) => RowChanges.Add((key, row)));
        }

        internal List<JArray> Open()
        {
            Client.Realtime.Connect();
            Socket.Accept();
            Client.Poll();
            var join = A(Socket.TakeFrames()[0]);
            Socket.Receive(ReplyTo(join, "ok"));
            Client.Poll();
            var sent = new List<JArray>();
            foreach (var frame in Socket.TakeFrames()) sent.Add(A(frame));
            return sent;
        }
    }

    public class HelpersTests
    {
        [Fact]
        public void SubscriptionIsSentOnceTheUserChannelJoinsAndItsReplyFillsTheCache()
        {
            var h = new Live();
            var got = See.Task(h.Client.Kv.Subscribe(new KvKey("progress", "u1")));
            var sent = h.Open();
            Assert.Single(sent);
            Assert.Equal("kv:subscribe", (string)sent[0][3]);
            Same(J("{'key': 'progress', 'user_id': 'u1'}"), sent[0][4]);

            h.Socket.Receive(ReplyTo(sent[0], "ok", J("{'subscribed': true, 'key': 'progress', 'data': {'level': 3}, 'metadata': {}}")));
            h.Client.Poll();
            Assert.True(got.Last.Ok);
            Assert.True(got.Last.Row.Exists);
            Assert.Equal(3, (int)got.Last.Row.Data["level"]);
            Assert.True(h.Client.Kv.Subscribed(new KvKey("progress", "u1")));
            var row = h.Client.Kv.Row(new KvKey("progress", "u1"));
            Assert.NotNull(row);
            Assert.Equal(3, (int)row.Data["level"]);
            Assert.Single(h.RowChanges);
            Assert.Equal("progress", h.RowChanges[0].Key.Key);
        }

        [Fact]
        public void SubscribeReplyForAMissingRowCachesThatItIsMissing()
        {
            var h = new Live();
            h.Open();
            h.Client.Kv.Subscribe("loadout");
            var frames = h.Socket.TakeFrames();
            Assert.Single(frames);
            var frame = A(frames[0]);
            Same(J("{'key': 'loadout'}"), frame[4]);
            h.Socket.Receive(ReplyTo(frame, "ok", J("{'subscribed': true, 'key': 'loadout', 'missing': true}")));
            h.Client.Poll();
            var row = h.Client.Kv.Row("loadout");
            Assert.NotNull(row);
            Assert.False(row.Exists);
        }

        [Fact]
        public void PushesKeepARowCurrentDeletesIncluded()
        {
            var h = new Live();
            h.Open();
            h.Socket.Receive(Message("user:u1", "kv_updated", J("{'key': 'progress', 'user_id': 'u1', 'lobby_id': '', 'data': {'level': 4}, 'metadata': {}}")));
            h.Client.Poll();
            Assert.Equal(4, (int)h.Client.Kv.Row(new KvKey("progress", "u1")).Data["level"]);

            h.Socket.Receive(Message("user:u1", "kv_deleted", J("{'key': 'progress', 'user_id': 'u1', 'lobby_id': ''}")));
            h.Client.Poll();
            Assert.False(h.Client.Kv.Row(new KvKey("progress", "u1")).Exists);
            Assert.Equal(2, h.RowChanges.Count);
        }

        [Fact]
        public void EveryRejoinSendsTheSubscriptionsAgainAndARefusedOneIsDropped()
        {
            var h = new Live();
            h.Client.Kv.Subscribe(new KvKey("progress", "u1"));
            var refused = See.Task(h.Client.Kv.Subscribe("secret"));
            var sent = h.Open();
            Assert.Equal(2, sent.Count);
            h.Socket.Receive(ReplyTo(sent[0], "ok", J("{'missing': true}")));
            h.Socket.Receive(ReplyTo(sent[1], "error", J("{'error': 'forbidden'}")));
            h.Client.Poll();
            Assert.False(refused.Last.Ok);
            Assert.Equal("forbidden", refused.Last.Error);

            h.Socket.Drop();
            h.Client.Poll();
            h.AdvanceMs(100);
            h.Socket.Accept();
            h.Client.Poll();
            var join = A(h.Socket.TakeFrames()[0]);
            h.Socket.Receive(ReplyTo(join, "ok"));
            h.Client.Poll();
            var again = h.Socket.TakeFrames();
            Assert.Single(again);
            Assert.Equal("progress", (string)A(again[0])[4]["key"]);
        }

        [Fact]
        public void UnsubscribingTellsTheServerAndStopsResubscribing()
        {
            var h = new Live();
            h.Client.Kv.Subscribe(new KvKey("progress", "u1"));
            var sent = h.Open();
            h.Socket.Receive(ReplyTo(sent[0], "ok", J("{'missing': true}")));
            h.Client.Poll();
            h.Client.Kv.Unsubscribe(new KvKey("progress", "u1"));
            var frames = h.Socket.TakeFrames();
            Assert.Single(frames);
            Assert.Equal("kv:unsubscribe", (string)A(frames[0])[3]);
            Assert.False(h.Client.Kv.Subscribed(new KvKey("progress", "u1")));
        }

        [Fact]
        public void FetchReadsTheCacheFirstTheApiOtherwiseAndA404CachesTheAbsence()
        {
            var h = new Live();
            var got = See.Task(h.Client.Kv.Fetch(new KvKey("progress", "u1")));
            Assert.Equal(1, h.Server.Pending);
            Assert.Equal("http://game.test/api/v1/kv/progress?user_id=u1", h.Server.Next.Url);
            h.Server.Reply(200, Q("{'data': {'key': 'progress', 'user_id': 'u1', 'lobby_id': '', 'data': {'level': 7}, 'metadata': {}}}"));
            h.Client.Poll();
            Assert.True(got.Last.Ok);
            Assert.Equal(7, (int)got.Last.Row.Data["level"]);

            got.Watch(h.Client.Kv.Fetch(new KvKey("progress", "u1")));
            Assert.Equal(0, h.Server.Pending);
            h.Client.Poll();
            Assert.Equal(7, (int)got.Last.Row.Data["level"]);

            got.Watch(h.Client.Kv.Fetch("nothing"));
            h.Server.Reply(404, Q("{'error': 'not_found'}"));
            h.Client.Poll();
            Assert.True(got.Last.Ok);
            Assert.False(got.Last.Row.Exists);
            Assert.NotNull(h.Client.Kv.Row("nothing"));
        }

        [Fact]
        public void SigningOutForgetsRowsAndSubscriptions()
        {
            var h = new Live();
            h.Open();
            h.Socket.Receive(Message("user:u1", "kv_updated", J("{'key': 'progress', 'user_id': 'u1', 'data': {'a': 1}}")));
            h.Client.Poll();
            Assert.NotNull(h.Client.Kv.Row(new KvKey("progress", "u1")));
            h.Client.Auth.Forget();
            h.Client.Poll();
            Assert.Null(h.Client.Kv.Row(new KvKey("progress", "u1")));
        }

        [Fact]
        public void PresenceMergesProfilesKeepsMetadataSectionsAndTracksWhoIsOnline()
        {
            var h = new Live();
            h.Open();
            var changed = new List<string>();
            h.Client.Presence.OnUserChanged(id => changed.Add(id));

            h.Socket.Receive(Message("lobby:l1", "user_joined", J("{'user_id': 'u2', 'display_name': 'Bea', 'metadata': {'player': {'hat': 'red', 'boots': 'blue'}}}")));
            h.Socket.Receive(Message("lobby:l1", "user_updated", J("{'user_id': 'u2', 'metadata': {'player': {'hat': 'green'}}}")));
            h.Client.Poll();
            var bea = h.Client.Presence.User("u2");
            Assert.Equal("Bea", (string)bea["display_name"]);
            Assert.Equal("green", (string)bea["metadata"]["player"]["hat"]);
            Assert.Equal("blue", (string)bea["metadata"]["player"]["boots"]);

            h.Socket.Receive(Message("lobby:l1", "user_online", J("{'user_id': 'u2'}")));
            h.Client.Poll();
            Assert.True(h.Client.Presence.Online("u2"));
            h.Socket.Receive(Message("lobby:l1", "user_offline", J("{'user_id': 'u2'}")));
            h.Client.Poll();
            Assert.False(h.Client.Presence.Online("u2"));
            Assert.Equal(h.Clock.Wall(), h.Client.Presence.LastSeen("u2"));
            Assert.True(h.Client.Presence.Online("u1"));
            Assert.Equal(4, changed.Count);
        }

        [Fact]
        public void PlayersOwnPushReplacesTheirMetadataAndKeepsOnlyTheirLobby()
        {
            var h = new Live();
            h.Open();
            h.Socket.Receive(Message("lobby:l1", "updated", J("{'id': 'l1', 'title': 'One'}")));
            h.Socket.Receive(Message("lobby:l2", "updated", J("{'id': 'l2', 'title': 'Two'}")));
            h.Client.Presence.CacheUser("u1", J("{'metadata': {'old': 1, 'keep': 1}}"));
            h.Socket.Receive(Message("user:u1", "updated", J("{'id': 'u1', 'lobby_id': 'l2', 'metadata': {'keep': 2}}")));
            h.Client.Poll();
            var me = h.Client.Presence.User("u1");
            Same(J("{'keep': 2}"), me["metadata"]);
            Assert.False(h.Client.Presence.Lobby("l1").HasValues);
            Assert.Equal("Two", (string)h.Client.Presence.Lobby("l2")["title"]);
        }

        [Fact]
        public void MergeMetadataMergesOneSectionDeep()
        {
            var merged = Presence.MergeMetadata(
                J("{'player': {'hat': 'red', 'boots': 'blue'}, 'level': 1}"),
                J("{'player': {'hat': 'green'}, 'level': 2, 'new': true}"));
            Same(J("{'player': {'hat': 'green', 'boots': 'blue'}, 'level': 2, 'new': true}"), merged);
        }

        [Fact]
        public void ACachedRowHandedOutIsACopy()
        {
            var h = new Live();
            h.Open();
            h.Socket.Receive(Message("user:u1", "kv_updated", J("{'key': 'k', 'data': {'a': 1}}")));
            h.Client.Poll();
            ((JObject)h.Client.Kv.Row("k").Data)["a"] = 2;
            Assert.Equal(1, (int)h.Client.Kv.Row("k").Data["a"]);
        }
    }
}
