using System;
using System.Collections.Generic;
using Gamend.Models;
using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    public class ModelsTests
    {
        [Fact]
        public void ReplyReadsAsItsModel()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.LobbiesGetLobby("l1"));
            h.Server.Reply(200, Q(@"{'data': {
                'id': 'l1', 'title': 'Duel', 'max_users': 2, 'hostless': false, 'state': 'playing',
                'state_changed_at': null, 'metadata': {'map': 'dunes'},
                'members': [{'id': 'u1', 'username': 'ann'}, {'id': 'u2', 'username': 'bea'}]}}"));
            h.Client.Poll();
            var lobby = seen.Last.As<Lobby>();
            Assert.NotNull(lobby);
            Assert.Equal("l1", lobby.Id);
            Assert.Equal(2, lobby.MaxUsers);
            Assert.Equal("playing", lobby.State);
            Assert.Null(lobby.StateChangedAt);
            Assert.Equal("dunes", (string)lobby.Metadata["map"]);
            Assert.Equal(2, lobby.Members.Count);
            Assert.Equal("bea", lobby.Members[1].Username);
            // Left out: the default.
            Assert.Equal("", lobby.HostId);
            Assert.Equal(0, lobby.SpectatorCount);
        }

        [Fact]
        public void PageReadsItsItemsAndMetaAndAListOfStringsReadsToo()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.LobbiesListLobbies());
            h.Server.Reply(200, Q(@"{'data': [{'id': 'a'}, {'id': 'b'}],
                'meta': {'page': 1, 'page_size': 25, 'total_count': 2, 'total_pages': 1,
                         'has_more': false, 'count': 2}}"));
            h.Client.Poll();
            var page = seen.Last.Page<Lobby>();
            Assert.NotNull(page);
            Assert.Equal(2, page.Data.Count);
            Assert.Equal(2, page.Meta.TotalCount);
            Assert.False(page.Meta.HasMore);

            seen.Watch(h.Client.Api.AuthenticateListAuthProviders());
            h.Server.Reply(200, Q("{'data': ['google', 'steam']}"));
            h.Client.Poll();
            Assert.Equal(new List<string> { "google", "steam" }, seen.Last.As<List<string>>());
        }

        [Fact]
        public void ReadsNeverThrowWrongKindsKeepDefaultsAndANonObjectIsNoModel()
        {
            Lobby lobby;
            Assert.True(Codec.ReadLobby(J("{'id': 7, 'max_users': 'two', 'members': 'nobody', 'title': 'ok'}"), out lobby));
            Assert.Equal("", lobby.Id);
            Assert.Equal(0, lobby.MaxUsers);
            Assert.Empty(lobby.Members);
            Assert.Equal("ok", lobby.Title);
            Assert.False(Codec.ReadLobby(new JArray(), out lobby));

            Assert.Null(new Response().As<Lobby>());
        }

        [Fact]
        public void ModelWritesBackToTheJsonItRead()
        {
            var source = J("{'id': 'l1', 'title': 'Duel', 'max_users': 2, 'state_changed_at': '2026-09-19T10:00:00Z'}");
            Lobby lobby;
            Assert.True(Codec.ReadLobby(source, out lobby));
            var written = Codec.WriteLobby(lobby);
            Assert.Equal("l1", (string)written["id"]);
            Assert.Equal(2, (int)written["max_users"]);
            // A timestamp is the text the server sent, never a parsed date.
            Assert.Equal(JTokenType.String, written["state_changed_at"].Type);
            Assert.Equal("2026-09-19T10:00:00Z", (string)written["state_changed_at"]);
            Assert.Equal("", (string)written["host_id"]);
            Lobby again;
            Assert.True(Codec.ReadLobby(written, out again));
            Same(written, Codec.WriteLobby(again));
        }

        [Fact]
        public void MapShapedAnswerReadsAsAMap()
        {
            var r = new Response { Status = 200, Body = J("{'data': {'coins': 120, 'gems': 3}}") };
            var wallet = r.As<WalletBalances>();
            Assert.NotNull(wallet);
            Assert.Equal(120, wallet["coins"]);
            Assert.Equal(3, wallet["gems"]);
            Assert.Equal(120, r.As<Dictionary<string, long>>()["coins"]);

            LobbyStats stats;
            Assert.True(Codec.ReadLobbyStats(J("{'by_state': {'playing': 2, 'created': 1}, 'lobbies_total': 3}"), out stats));
            Assert.Equal(2, stats.ByState["playing"]);
            Assert.Equal(3, stats.LobbiesTotal);
            Same(J("{'coins': 120, 'gems': 3}"), Codec.WriteWalletBalances(wallet));
        }

        [Fact]
        public void ScalarsAndNullablesReadThroughTheTable()
        {
            Assert.Equal(7, new Response { Body = J("{'data': 7}") }.As<long>());
            Assert.Null(new Response { Body = J("{'data': 'x'}") }.As<long?>());
            Assert.Equal(7L, new Response { Body = J("{'data': 7}") }.As<long?>());
            Assert.Equal("x", new Response { Body = J("{'data': 'x'}") }.As<string>());
            Assert.True(new Response { Body = J("{'data': true}") }.As<bool>());
        }

        [Fact]
        public void TypeWithNoReaderIsABugAndSaysSo()
        {
            Assert.Throws<InvalidOperationException>(() => new Response().As<Uri>());
        }

        [Fact]
        public void NullableValueFieldsAreEmptyUntilGiven()
        {
            TournamentEntry entry;
            Assert.True(Codec.ReadTournamentEntry(J("{'seed': 4, 'bracket_index': null}"), out entry));
            Assert.Equal(4L, entry.Seed);
            Assert.Null(entry.BracketIndex);

            Assert.True(Codec.ReadTournamentEntry(new JObject(), out entry));
            Assert.Null(entry.Seed);
            Assert.Equal(JTokenType.Null, Codec.WriteTournamentEntry(entry)["seed"].Type);
        }
    }
}
