using System.Collections.Generic;
using Gamend.Testing;
using Newtonsoft.Json.Linq;
using Xunit;
using static Gamend.Tests.Wire;

namespace Gamend.Tests
{
    public class AuthTests
    {
        private static readonly string PendingReply =
            Q("{'data': {'status': 'pending', 'error': '', 'message': '', 'session': null}}");

        [Fact]
        public void DeviceSignInKeepsTheSessionAndHandsItToTheGame()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.LoginDevice("device-123"));
            var request = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/login/device", request.Url);
            Same(J("{'device_id': 'device-123'}"), Json.Parse(request.BodyText));
            Assert.Equal("", FakeHttp.Header(request, "authorization"));
            h.Server.Reply(200, SessionReply());
            h.Client.Poll();

            Assert.Equal(1, seen.Calls);
            Assert.True(seen.Last.Ok);
            Assert.Equal("u1", seen.Last.Session.UserId);
            Assert.Equal("ann", seen.Last.Session.Username);
            Assert.Equal(h.Clock.Wall() + 900, seen.Last.Session.ExpiresAt);
            Assert.True(h.Client.Auth.SignedIn);
            // The listener runs in the poll after the one that signed in.
            h.Client.Poll();
            Assert.Single(h.Changes);
            Assert.Equal("a1", h.Changes[0].AccessToken);

            h.Client.Api.UsersGetCurrentUser();
            Assert.Equal("Bearer a1", FakeHttp.Header(h.Server.Next, "authorization"));
        }

        [Fact]
        public void RefusedSignInSaysWhyAndKeepsNothing()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.LoginEmail("ann@example.com", "wrong"));
            Same(J("{'email': 'ann@example.com', 'password': 'wrong'}"), Json.Parse(h.Server.Next.BodyText));
            h.Server.Reply(401, Q("{'error': 'invalid_credentials'}"));
            h.Client.Poll();
            Assert.False(seen.Last.Ok);
            Assert.Equal("invalid_credentials", seen.Last.Error);
            Assert.Equal(401, seen.Last.Response.Status);
            Assert.False(h.Client.Auth.SignedIn);
            Assert.Empty(h.Changes);
        }

        [Fact]
        public void RegisterSendsNoPasswordAndAUsernameOnlyWhenThereIsOne()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.RegisterEmail("ann@example.com"));
            var plain = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/register", plain.Url);
            Same(J("{'email': 'ann@example.com'}"), Json.Parse(plain.BodyText));
            Assert.Equal("", FakeHttp.Header(plain, "authorization"));
            h.Server.Reply(201, Q("{'data': {'user_id': 'u1', 'username': 'ann', 'display_name': '', 'email_confirmed': false}}"));
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.True(seen.Last.Ok);
            Assert.False((bool)seen.Last.Data["email_confirmed"]);

            h.Client.Auth.RegisterEmail("bob@example.com", "bob");
            Same(J("{'email': 'bob@example.com', 'username': 'bob'}"), Json.Parse(h.Server.Next.BodyText));
        }

        [Fact]
        public void RegisteringIsNotASignIn()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Auth.RegisterEmail("ann@example.com"));
            // Even an answer that carried tokens would not be taken as a session.
            h.Server.Reply(201, SessionReply(2));
            h.Client.Poll();
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.Equal("a1", h.Client.Auth.Session.AccessToken);
            Assert.Empty(h.Changes);
        }

        [Fact]
        public void EmailedCodeConfirmsTheRegistrationSetsThePasswordAndSignsIn()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.ConfirmRegistration("ann@example.com", "042137", "secret-pass"));
            var request = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/register/confirm", request.Url);
            Same(J("{'email': 'ann@example.com', 'code': '042137', 'password': 'secret-pass'}"), Json.Parse(request.BodyText));
            Assert.Equal("", FakeHttp.Header(request, "authorization"));
            h.Server.Reply(200, SessionReply());
            h.Client.Poll();
            Assert.True(seen.Last.Ok);
            Assert.True(h.Client.Auth.SignedIn);

            seen.Watch(h.Client.Auth.ConfirmRegistration("ann@example.com", "000000", "secret-pass"));
            h.Server.Reply(401, Q("{'error': 'invalid_code'}"));
            h.Client.Poll();
            Assert.False(seen.Last.Ok);
            Assert.Equal("invalid_code", seen.Last.Error);
        }

        [Fact]
        public void NewCodeIsAskedForWithTheAddressAlone()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.ResendConfirmation("ann@example.com"));
            var request = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/register/resend", request.Url);
            Same(J("{'email': 'ann@example.com'}"), Json.Parse(request.BodyText));
            h.Server.Reply(200, Q("{'ok': true}"));
            h.Client.Poll();
            Assert.True(seen.Last.Ok);
        }

        [Fact]
        public void SteamSignsInWithATicketAndAnAnswerWithNoTokenSignsNobodyIn()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Auth.LoginSteam("14000000"));
            var request = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/auth/steam/callback", request.Url);
            Same(J("{'code': '14000000'}"), Json.Parse(request.BodyText));
            Assert.Equal("", FakeHttp.Header(request, "authorization"));
            // An answer with no token signed nobody in.
            h.Server.Reply(200, Q("{'data': {'linked': true, 'provider': 'steam'}}"));
            h.Client.Poll();
            Assert.False(seen.Last.Ok);
            Assert.Equal("no_session", seen.Last.Error);
        }

        [Fact]
        public void AccessTokenIsRefreshedWhenThreeQuartersOfItAreGone()
        {
            var h = new Harness();
            h.Client.Auth.LoginDevice("d");
            h.Server.Reply(200, SessionReply(1, 900));
            h.Client.Poll();
            Assert.Equal(0, h.Server.Pending);

            h.AdvanceSeconds(674);
            Assert.Equal(0, h.Server.Pending);
            h.AdvanceSeconds(1);
            Assert.Equal(1, h.Server.Pending);
            Assert.Equal("http://game.test/api/v1/refresh", h.Server.Next.Url);
            h.Server.Reply(200, SessionReply(2, 900));
            h.Client.Poll();
            Assert.Equal("a2", h.Client.Auth.Session.AccessToken);

            // The next refresh counts from the new token.
            h.AdvanceSeconds(674);
            Assert.Equal(0, h.Server.Pending);
            h.AdvanceSeconds(1);
            Assert.Equal(1, h.Server.Pending);
        }

        [Fact]
        public void RefreshThatCannotReachTheServerKeepsTheSessionAndTriesAgain()
        {
            var h = new Harness();
            h.SignedIn(30);  // lapses within the margin: refreshed on the next poll
            h.Client.Poll();
            Assert.Equal(1, h.Server.Pending);
            h.Server.Fail("timeout");
            h.Client.Poll();
            Assert.True(h.Client.Auth.SignedIn);
            Assert.Equal(0, h.Server.Pending);
            h.AdvanceSeconds(30);
            Assert.Equal(1, h.Server.Pending);
        }

        [Fact]
        public void RestoredSessionIsNotAnnouncedBackToTheGame()
        {
            var h = new Harness();
            h.SignedIn();
            h.Client.Poll();
            Assert.Empty(h.Changes);
            Assert.Equal("ann", h.Client.Auth.Session.Username);
        }

        [Fact]
        public void ExplicitRefreshReportsTheNewSession()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Auth.Refresh());
            h.Server.Reply(200, SessionReply(3));
            h.Client.Poll();
            Assert.True(seen.Last.Ok);
            Assert.Equal("a3", seen.Last.Session.AccessToken);

            var signedOut = new Harness();
            seen.Watch(signedOut.Client.Auth.Refresh());
            Assert.Equal(1, seen.Calls);
            signedOut.Client.Poll();
            Assert.Equal(2, seen.Calls);
            Assert.Equal("not_signed_in", seen.Last.Error);
        }

        [Fact]
        public void ExplicitRefreshWithoutARefreshTokenStillAnswersFromPoll()
        {
            var h = new Harness();
            h.Client.Auth.Restore(new Session { AccessToken = "a1", UserId = "u1" });
            var seen = See.Task(h.Client.Auth.Refresh());
            Assert.Equal(0, seen.Calls);
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.Equal("refresh_failed", seen.Last.Error);
        }

        [Fact]
        public void LogoutRevokesOnTheServerAndForgetsHereWhateverItAnswered()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Auth.Logout());
            var request = h.Server.Next;
            Assert.Equal("DELETE", request.Method);
            Assert.Equal("http://game.test/api/v1/logout", request.Url);
            Assert.Equal("Bearer a1", FakeHttp.Header(request, "authorization"));
            h.Server.Fail("offline");
            h.Client.Poll();
            Assert.False(seen.Last.Ok);
            Assert.False(h.Client.Auth.SignedIn);
            h.Client.Poll();
            Assert.Single(h.Changes);
            Assert.Null(h.Changes[0]);
        }

        [Fact]
        public void ProviderSignInOpensItsPageAndWaitsForTheServerToResolveIt()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.SignIn("google"));
            var start = h.Server.Next;
            Assert.Equal("GET", start.Method);
            Assert.Equal("http://game.test/api/v1/auth/google", start.Url);
            h.Server.Reply(200, Q("{'data': {'authorization_url': 'https://accounts.test/o', 'session_id': 's 1'}}"));
            h.Client.Poll();
            Assert.Single(h.Opened);
            Assert.Equal("https://accounts.test/o", h.Opened[0]);
            Assert.Equal(0, h.Server.Pending);

            h.AdvanceSeconds(1);
            Assert.Equal(1, h.Server.Pending);
            Assert.Equal("http://game.test/api/v1/auth/session/s%201", h.Server.Next.Url);
            h.Server.Reply(200, PendingReply);
            h.Client.Poll();
            Assert.Equal(0, seen.Calls);

            h.AdvanceSeconds(1);
            Assert.Equal(1, h.Server.Pending);
            h.Server.Reply(200, Q(@"{'data': {'status': 'completed', 'error': '', 'message': '', 'session': {
                'access_token': 'oa', 'refresh_token': 'or', 'user_id': 'u9', 'username': 'u',
                'display_name': '', 'expires_in': 900}}}"));
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.True(seen.Last.Ok);
            Assert.Equal("u9", seen.Last.Session.UserId);
            Assert.Equal("oa", h.Client.Auth.Session.AccessToken);
        }

        [Fact]
        public void SignInTheServerRefusesEndsWithItsCode()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.SignIn("discord"));
            h.Server.Reply(200, Q("{'data': {'authorization_url': 'https://d.test', 'session_id': 's1'}}"));
            h.Client.Poll();
            h.AdvanceSeconds(1);
            h.Server.Reply(200, Q(@"{'data': {'status': 'error', 'error': 'account_not_activated',
                'message': 'Pending activation', 'session': null}}"));
            h.Client.Poll();
            Assert.False(seen.Last.Ok);
            Assert.Equal("account_not_activated", seen.Last.Error);
            Assert.Equal("", seen.Last.Response.Message);
            Assert.Equal("Pending activation", Json.Text(seen.Last.Response.Data, "message"));
        }

        [Fact]
        public void SignInAlreadyCollectedAnswersNoSession()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.SignIn("discord"));
            h.Server.Reply(200, Q("{'data': {'authorization_url': 'https://d.test', 'session_id': 's1'}}"));
            h.Client.Poll();
            h.AdvanceSeconds(1);
            h.Server.Reply(200, Q("{'data': {'status': 'completed', 'error': '', 'message': '', 'session': null}}"));
            h.Client.Poll();
            Assert.Equal("no_session", seen.Last.Error);
            Assert.False(h.Client.Auth.SignedIn);
        }

        [Fact]
        public void LinkingOpensTheProvidersPageAsTheSignedInPlayer()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Auth.Link("google"));
            var start = h.Server.Next;
            Assert.Equal("POST", start.Method);
            Assert.Equal("http://game.test/api/v1/me/providers/google/authorize", start.Url);
            Assert.Equal("Bearer a1", FakeHttp.Header(start, "authorization"));
            h.Server.Reply(200, Q("{'data': {'authorization_url': 'https://g.test', 'session_id': 'k1'}}"));
            h.Client.Poll();
            Assert.Equal(new List<string> { "https://g.test" }, h.Opened);

            h.AdvanceSeconds(1);
            var poll = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/me/providers/sessions/k1", poll.Url);
            Assert.Equal("Bearer a1", FakeHttp.Header(poll, "authorization"));
            h.Server.Reply(200, Q("{'data': {'status': 'pending', 'error': '', 'message': '', 'provider': 'google'}}"));
            h.Client.Poll();
            h.AdvanceSeconds(1);
            h.Server.Reply(200, Q("{'data': {'status': 'completed', 'error': '', 'message': '', 'provider': 'google'}}"));
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.True(seen.Last.Ok);
            // Linking leaves the session as it was.
            Assert.Equal("a1", h.Client.Auth.Session.AccessToken);
        }

        [Fact]
        public void LinkTheServerRefusesEndsWithItsCode()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Auth.Link("google"));
            h.Server.Reply(200, Q("{'data': {'authorization_url': 'https://g.test', 'session_id': 'k1'}}"));
            h.Client.Poll();
            h.AdvanceSeconds(1);
            h.Server.Reply(200, Q(@"{'data': {'status': 'error', 'error': 'provider_already_linked',
                'message': 'Linked to another account', 'provider': 'google'}}"));
            h.Client.Poll();
            Assert.False(seen.Last.Ok);
            Assert.Equal("provider_already_linked", seen.Last.Error);
        }

        [Fact]
        public void SteamTicketLinksSteamToTheSignedInAccount()
        {
            var h = new Harness();
            h.SignedIn();
            var seen = See.Task(h.Client.Auth.LinkSteam("14000000"));
            var request = h.Server.Next;
            Assert.Equal("http://game.test/api/v1/me/providers/steam", request.Url);
            Same(J("{'code': '14000000'}"), Json.Parse(request.BodyText));
            Assert.Equal("Bearer a1", FakeHttp.Header(request, "authorization"));
            h.Server.Reply(200, Q("{'data': {'id': 'u1', 'linked_providers': {'steam': true}}}"));
            h.Client.Poll();
            Assert.True(seen.Last.Ok);
            Assert.True((bool)seen.Last.Data["linked_providers"]["steam"]);
        }

        [Fact]
        public void SignInNobodyFinishesTimesOut()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.SignIn("google"));
            h.Server.Reply(200, Q("{'data': {'authorization_url': 'https://g.test', 'session_id': 's1'}}"));
            h.Client.Poll();
            for (var i = 0; i < 10 && seen.Calls == 0; i++)
            {
                h.AdvanceSeconds(1);
                if (h.Server.Pending > 0)
                {
                    h.Server.Reply(200, PendingReply);
                    h.Client.Poll();
                }
            }
            Assert.Equal(1, seen.Calls);
            Assert.Equal("timeout", seen.Last.Error);
        }

        [Fact]
        public void CancelledSignInSaysSoAndIgnoresWhatArrivesAfter()
        {
            var h = new Harness();
            var seen = See.Task(h.Client.Auth.SignIn("google"));
            h.Server.Reply(200, Q("{'data': {'authorization_url': 'https://g.test', 'session_id': 's1'}}"));
            h.Client.Poll();
            h.Client.Auth.CancelSignIn();
            Assert.Equal(0, seen.Calls);
            h.Client.Poll();
            Assert.Equal(1, seen.Calls);
            Assert.Equal("cancelled", seen.Last.Error);
            h.AdvanceSeconds(2);
            Assert.Equal(0, h.Server.Pending);
        }

        [Fact]
        public void SignInWithoutAWayToOpenThePageFails()
        {
            var h = new Harness(withOpenUrl: false);
            var seen = See.Task(h.Client.Auth.SignIn("google"));
            Assert.Equal(0, h.Server.Pending);
            h.Client.Poll();
            Assert.Equal("no open_url configured", seen.Last.Error);
        }

        [Fact]
        public void SessionSurvivesARoundTripThroughJson()
        {
            var session = new Session
            {
                AccessToken = "a",
                RefreshToken = "r",
                UserId = "u",
                Username = "n",
                DisplayName = "N",
                ExpiresIn = 900,
                ExpiresAt = 1234,
            };
            var back = Session.FromJson(session.ToJson());
            Assert.NotNull(back);
            Same(session.ToJson(), back.ToJson());

            Assert.Null(Session.FromJson(J("{'refresh_token': 'r'}")));
            var fresh = Session.FromJson(J("{'access_token': 'a', 'expires_in': 60}"), 1000);
            Assert.Equal(1060, fresh.ExpiresAt);
        }
    }
}
