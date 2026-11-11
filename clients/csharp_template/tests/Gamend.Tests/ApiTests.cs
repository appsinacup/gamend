using Gamend.Testing;
using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    public class ApiTests
    {
        [Fact]
        public void MissingRequiredBodyFieldRefusesTheCallNamingTheField()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.AuthenticateDeviceLogin(new JObject()));
            Assert.Equal(0, h.Server.Pending);
            Assert.Equal(0, seen.Calls);
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.Equal(0, seen.Last.Status);
            Assert.Equal("AuthenticateDeviceLogin needs `device_id`", seen.Last.Error);

            // Null is as good as missing.
            h.Client.Api.AuthenticateDeviceLogin(new JObject { ["device_id"] = null });
            Assert.Equal(0, h.Server.Pending);
        }

        [Fact]
        public void MissingRequiredQueryKeyRefusesTheCallToo()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.ChatChatUnreadCount(new JObject()));
            h.Client.Poll();
            Assert.Equal("ChatChatUnreadCount needs `chat_type`", seen.Last.Error);
            Assert.Equal(0, h.Server.Pending);
        }

        [Fact]
        public void EmptyPathParameterRefusesTheCall()
        {
            // `GET /lobbies/` is another operation; sending it would answer the
            // wrong question without saying so.
            var h = new Harness();
            var seen = See.Task(h.Client.Api.LobbiesGetLobby(null));
            h.Client.Poll();
            Assert.Equal("LobbiesGetLobby needs `id`", seen.Last.Error);
            Assert.Equal(0, h.Server.Pending);
        }

        [Fact]
        public void PathParametersAreEscaped()
        {
            var h = new Harness();
            h.Client.Api.LobbiesGetLobby("a b/c");
            Assert.Equal("http://game.test/api/v1/lobbies/a%20b%2Fc", h.Server.Next.Url);
        }

        [Fact]
        public void QueryGoesInTheOrderTheOperationDeclaresOrNotAtAll()
        {
            var h = new Harness();
            h.Client.Api.LobbiesListLobbies(O("{'page_size': 5, 'title': 'duel'}"));
            Assert.Equal("http://game.test/api/v1/lobbies?title=duel&page_size=5", h.Server.Next.Url);
            h.Server.Reply(200, "{}");
            h.Client.Api.LobbiesListLobbies();
            Assert.Equal("http://game.test/api/v1/lobbies", h.Server.Next.Url);
        }

        [Fact]
        public void UploadSendsItsBytesAsTheyAre()
        {
            // The one operation with a binary body is the admin's, and a game SDK
            // ships no admin API; `Rest.Send` is what the generated method calls.
            var h = new Harness();
            h.Client.Rest.Send("PUT", "/api/v1/admin/storage/object?key=maps%2Fa.bin", Body.Raw(B(1, 2)));
            var request = h.Server.Next;
            Assert.Equal("PUT", request.Method);
            Assert.Equal("http://game.test/api/v1/admin/storage/object?key=maps%2Fa.bin", request.Url);
            Assert.Equal(B(1, 2), request.Body);
            Assert.Equal("application/octet-stream", FakeHttp.Header(request, "content-type"));
        }

        [Fact]
        public void PagedListReadsThroughDataAndMeta()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Api.LobbiesListLobbies());
            h.Server.Reply(200, Q("{'data': [{'id': 'l1'}], 'meta': {'page': 1, 'total_count': 1}}"));
            h.Client.Poll();
            Assert.Equal(JTokenType.Array, seen.Last.Data.Type);
            Assert.Single(seen.Last.Data);
            Assert.Equal(1, Json.Number(seen.Last.Meta, "total_count"));
            Assert.Equal(JTokenType.Null, Json.Field(seen.Last.Body, "missing").Type);
        }
    }
}
