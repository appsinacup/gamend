// The conformance scenario (docs/specs/client-sdks.md), live:
//
//   dotnet run --project examples/Conformance -- http://127.0.0.1:4000 [--protobuf]
//
// 1. `POST /login/device` answers a session; `GET /me` works with its token.
// 2. `POST /refresh` answers a new token, and the next call carries it.
// 3. The socket connects (`vsn=2.0.0`) and joins `user:<id>`.
// 4. A lobby is created, `lobby:<id>` joined, and an update arrives as `updated`.
// 5. A server hook answers; a hook that does not exist answers its error.
// 6. A KV subscription hears a write made through the API.
// 7. A dropped socket reconnects, rejoins its topics, and events resume.
// 8. Leaving the lobby and disconnecting end cleanly.
// 9. (with a peer transport in `CreatePeer`) A WebRTC connection opens both
//    default DataChannels, `events` and `state`, and a hook answers over `events`.
//
// The server needs device sign-in (its default) and the example plugins
// (`GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples`). Step 6 writes as an
// admin: set GAMEND_ADMIN_EMAIL and GAMEND_ADMIN_PASSWORD, or it is skipped.
// Exits non-zero on the first step that fails.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using Gamend;
using Gamend.Net;
using Newtonsoft.Json.Linq;

namespace GamendConformance
{
    // The HTTP transport, noting which token each call carried.
    internal sealed class Recording : IHttpTransport, IDisposable
    {
        private readonly HttpClientTransport _inner = new HttpClientTransport();
        private readonly object _lock = new object();
        private string _authorization = "";

        public void Send(HttpRequest request, Action<HttpResponse> done)
        {
            lock (_lock)
            {
                _authorization = "";
                foreach (var header in request.Headers)
                {
                    if (header.Key == "authorization") _authorization = header.Value;
                }
            }
            _inner.Send(request, done);
        }

        public string LastAuthorization
        {
            get
            {
                lock (_lock)
                {
                    return _authorization;
                }
            }
        }

        public void Dispose()
        {
            _inner.Dispose();
        }
    }

    // The WebSocket transport, with a way to pull the plug the way a network
    // does: the client is told the connection died, not that it closed it.
    internal sealed class Droppable : IWebSocketTransport, IDisposable
    {
        private readonly ClientWebSocketTransport _inner = new ClientWebSocketTransport();
        private readonly object _lock = new object();
        private Action<int, string> _onClose;

        public void Open(string url, WebSocketHandlers handlers)
        {
            lock (_lock)
            {
                _onClose = handlers.OnClose;
            }
            _inner.Open(url, handlers);
        }

        public void SendText(string frame)
        {
            _inner.SendText(frame);
        }

        public void Close()
        {
            _inner.Close();
        }

        public void Drop()
        {
            Action<int, string> onClose;
            lock (_lock)
            {
                onClose = _onClose;
            }
            _inner.Close();
            onClose?.Invoke(1006, "dropped by the conformance run");
        }

        public void Dispose()
        {
            _inner.Dispose();
        }
    }

    internal sealed class StepFailed : Exception
    {
        internal StepFailed(string step, string why)
            : base("FAIL " + step + ": " + why)
        {
        }
    }

    internal static class Program
    {
        // Poll as a game would, once a frame, until `done()` or `seconds`.
        private static bool Await(Client client, Func<bool> done, int seconds = 10)
        {
            var deadline = Stopwatch.StartNew();
            while (!done() && deadline.Elapsed < TimeSpan.FromSeconds(seconds))
            {
                client.Poll();
                Thread.Sleep(16);
            }
            return done();
        }

        // Wait for one call's answer.
        private static T Call<T>(Client client, Task<T> task, string step)
        {
            if (!Await(client, () => task.IsCompleted)) throw new StepFailed(step, "no answer");
            return task.GetAwaiter().GetResult();
        }

        private static void Ok(string line)
        {
            Console.WriteLine("ok   " + line);
        }

        // No peer transport ships with this SDK yet. An engine's own goes here,
        // and step 9 then runs.
        private static IPeerTransport CreatePeer()
        {
            return null;
        }

        private static int Main(string[] args)
        {
            var url = "http://127.0.0.1:4000";
            var protobuf = false;
            foreach (var arg in args)
            {
                if (arg == "--protobuf")
                {
                    protobuf = true;
                }
                else
                {
                    url = arg;
                }
            }
            try
            {
                Run(url, protobuf);
                return 0;
            }
            catch (StepFailed failed)
            {
                Console.Error.WriteLine(failed.Message);
                return 1;
            }
        }

        private static void Run(string url, bool protobuf)
        {
            var wire = new Recording();
            var socket = new Droppable();
            var config = new Config { BaseUrl = url, Http = wire, WebSocket = socket, WebRtc = CreatePeer() };
            if (protobuf)
            {
                config.RealtimeFormat = RealtimeFormat.Protobuf;
                config.WebRtcFormat = RealtimeFormat.Protobuf;
            }
            if (config.WebRtc != null)
            {
                // Both channels the JS and Godot clients open by default, so step 9
                // proves the server takes more than one.
                config.DataChannels = new List<DataChannelSpec> { new DataChannelSpec("events"), new DataChannelSpec("state", false, 0) };
            }
            using (var client = new Client(config))
            {
                Scenario(client, url, protobuf, wire, socket, config.WebRtc != null);
            }
        }

        private static void Scenario(Client client, string url, bool protobuf, Recording wire, Droppable socket, bool hasPeer)
        {
            // 1. Device sign-in, then /me with the token it answered.
            var login = Call(client, client.Auth.LoginDevice("csharp-conformance-" + client.RunId), "1 LoginDevice");
            if (!login.Ok) throw new StepFailed("1 LoginDevice", login.Error);
            Ok("1 LoginDevice: user " + login.Session.UserId);

            var me = Call(client, client.Api.UsersGetCurrentUser(), "1 GET /me");
            if (!me.Ok) throw new StepFailed("1 GET /me", me.Error);
            if (Json.Text(me.Data, "id") != login.Session.UserId)
            {
                throw new StepFailed("1 GET /me", "answered another user: " + Json.Dump(me.Data));
            }
            if (wire.LastAuthorization != "Bearer " + login.Session.AccessToken)
            {
                throw new StepFailed("1 GET /me", "did not carry the sign-in token");
            }
            var typedMe = me.As<Gamend.Models.CurrentUser>();
            if (typedMe == null || typedMe.Id != login.Session.UserId)
            {
                throw new StepFailed("1 GET /me", "did not read as Models.CurrentUser");
            }
            Ok("1 GET /me as " + typedMe.Username);

            // 2. Refresh, and the next call carries the new token.
            var refreshed = Call(client, client.Auth.Refresh(), "2 Refresh");
            if (!refreshed.Ok) throw new StepFailed("2 Refresh", refreshed.Error);
            if (refreshed.Session.AccessToken == login.Session.AccessToken)
            {
                throw new StepFailed("2 Refresh", "answered the same access token");
            }
            Ok("2 Refresh: new access token, expires in " + refreshed.Session.ExpiresIn + "s");
            me = Call(client, client.Api.UsersGetCurrentUser(), "2 GET /me");
            if (!me.Ok) throw new StepFailed("2 GET /me", me.Error);
            if (wire.LastAuthorization != "Bearer " + refreshed.Session.AccessToken)
            {
                throw new StepFailed("2 GET /me", "did not carry the refreshed token");
            }
            Ok("2 GET /me with the refreshed token");

            var realtime = client.Realtime;
            var events = new List<Event>();
            realtime.OnEvent(e => events.Add(e));
            // With --protobuf, an event only counts when it came as a decoded binary
            // frame: proof the server honoured the format, not that it was asked.
            Func<string, string, bool> saw = (kind, topic) =>
            {
                foreach (var e in events)
                {
                    if (e.Kind == kind && e.Topic == topic && e.Binary == protobuf && e.Payload.Type != JTokenType.Null) return true;
                }
                return false;
            };

            // 3. Connect; the user channel joins.
            var userTopic = realtime.UserTopic;
            realtime.Connect();
            if (!Await(client, () => realtime.Joined(userTopic))) throw new StepFailed("3 Connect", "user channel not joined");
            Ok("3 connected, joined " + userTopic);

            // 4. A lobby: create it, join its topic, hear its update.
            var lobby = Call(client, client.Api.LobbiesCreateLobby(new JObject { ["title"] = "csharp conformance", ["max_users"] = 2 }), "4 create lobby");
            if (!lobby.Ok) throw new StepFailed("4 create lobby", lobby.Error);
            var typedLobby = lobby.As<Gamend.Models.Lobby>();
            if (typedLobby == null || typedLobby.Id.Length == 0 || typedLobby.MaxUsers != 2 || typedLobby.HostId != login.Session.UserId)
            {
                throw new StepFailed("4 create lobby", "did not read as Models.Lobby: " + Json.Dump(lobby.Data));
            }
            var lobbyTopic = "lobby:" + typedLobby.Id;
            var joined = Call(client, realtime.JoinLobby(typedLobby.Id), "4 join lobby");
            if (!joined.Ok) throw new StepFailed("4 join lobby", joined.Error);
            var renamed = Call(client, client.Api.LobbiesUpdateLobby(new JObject { ["title"] = "csharp conformance (renamed)" }), "4 update lobby");
            if (!renamed.Ok) throw new StepFailed("4 update lobby", renamed.Error);
            if (!Await(client, () => saw(Events.LobbyUpdated, lobbyTopic))) throw new StepFailed("4 lobby updated", "no updated event on " + lobbyTopic);
            Ok("4 joined " + lobbyTopic + ", heard its update" + (protobuf ? " (protobuf)" : ""));

            // 5. A hook that answers, and one that does not exist.
            var hook = Call(client, realtime.CallHook("example_hook", "hello", new JArray("csharp")), "5 CallHook");
            if (!hook.Ok) throw new StepFailed("5 CallHook", hook.Error);
            Ok("5 CallHook example_hook.hello: " + Json.Dump(hook.Data));
            hook = Call(client, realtime.CallHook("example_hook", "no_such_function", new JArray()), "5 failing hook");
            if (hook.Ok) throw new StepFailed("5 failing hook", "a function that does not exist answered ok");
            Ok("5 a missing hook answers its error: " + hook.Error);

            // 6. KV: subscribe, write through the API, hear it.
            var adminEmail = Environment.GetEnvironmentVariable("GAMEND_ADMIN_EMAIL");
            var adminPassword = Environment.GetEnvironmentVariable("GAMEND_ADMIN_PASSWORD");
            if (adminEmail == null || adminPassword == null)
            {
                Console.WriteLine("skip 6 kv: set GAMEND_ADMIN_EMAIL and GAMEND_ADMIN_PASSWORD to write as admin");
            }
            else
            {
                KvStep(client, url, adminEmail, adminPassword);
            }

            // 7. Pull the plug: it reconnects, rejoins, and events flow again.
            var states = new List<RealtimeState>();
            realtime.OnState(s => states.Add(s));
            socket.Drop();
            // The drop is news on the next poll, like everything else.
            if (!Await(client, () => realtime.State == RealtimeState.Reconnecting)) throw new StepFailed("7 reconnect", "the drop was not noticed");
            if (!Await(client, () => realtime.State == RealtimeState.Connected && realtime.Joined(userTopic) && realtime.Joined(lobbyTopic)))
            {
                throw new StepFailed("7 reconnect", "did not rejoin " + userTopic + " and " + lobbyTopic);
            }
            if (states.Count == 0 || states[0] != RealtimeState.Reconnecting) throw new StepFailed("7 reconnect", "no Reconnecting state was announced");
            events.Clear();
            renamed = Call(client, client.Api.LobbiesUpdateLobby(new JObject { ["title"] = "csharp conformance (after the drop)" }), "7 update lobby");
            if (!renamed.Ok) throw new StepFailed("7 update lobby", renamed.Error);
            if (!Await(client, () => saw(Events.LobbyUpdated, lobbyTopic))) throw new StepFailed("7 events resume", "no updated event after the reconnect");
            Ok("7 dropped, reconnected, rejoined both topics, events resumed");

            if (hasPeer)
            {
                WebRtcStep(client);
            }
            else
            {
                Console.WriteLine("skip 9 webrtc: no peer transport");
            }

            // 8. Leave the lobby and disconnect.
            var left = Call(client, client.Api.LobbiesLeaveLobby(), "8 leave lobby");
            if (!left.Ok) throw new StepFailed("8 leave lobby", left.Error);
            Call(client, realtime.Leave(lobbyTopic), "8 leave topic");
            realtime.Disconnect();
            if (realtime.State != RealtimeState.Disconnected) throw new StepFailed("8 disconnect", "still connected");
            Ok("8 left the lobby and disconnected");
        }

        private static void KvStep(Client client, string url, string adminEmail, string adminPassword)
        {
            var key = "csharp_conformance_" + client.RunId;
            var subscribed = Call(client, client.Kv.Subscribe(key), "6 kv subscribe");
            if (!subscribed.Ok) throw new StepFailed("6 kv subscribe", subscribed.Error);

            using (var admin = new Client(new Config { BaseUrl = url, Http = new HttpClientTransport() }))
            {
                var adminLogin = Call(admin, admin.Auth.LoginEmail(adminEmail, adminPassword), "6 admin login");
                if (!adminLogin.Ok) throw new StepFailed("6 admin login", adminLogin.Error);
                // A game SDK ships no admin API, so this goes through `Rest`.
                var body = new JObject { ["key"] = key, ["data"] = new JObject { ["score"] = 42 } };
                var written = Call(admin, admin.Rest.Send("PUT", "/api/v1/admin/kv", Body.Of(body)), "6 kv write");
                if (!written.Ok) throw new StepFailed("6 kv write", written.Error);
                var heard = Await(client, () =>
                {
                    var row = client.Kv.Row(key);
                    return row != null && row.Exists && Json.Number(row.Data, "score") == 42;
                });
                if (!heard) throw new StepFailed("6 kv_updated", "the write never arrived");
                Ok("6 kv subscribe heard the admin write to " + key);
                admin.Rest.Send("DELETE", "/api/v1/admin/kv?key=" + Uri.EscapeDataString(key));
                Await(admin, () => false, 1);
            }
        }

        private static void WebRtcStep(Client client)
        {
            // 9. WebRTC: the server is the other peer; a hook answers over `events`.
            var error = client.WebRtc.Connect();
            if (!Await(client, () => error.IsCompleted, 20)) throw new StepFailed("9 webrtc", "no answer");
            var why = error.GetAwaiter().GetResult();
            if (why.Length > 0) throw new StepFailed("9 webrtc", why);
            if (!Await(client, () => client.WebRtc.ChannelOpen("events") && client.WebRtc.ChannelOpen("state")))
            {
                throw new StepFailed("9 webrtc", "the events and state channels did not both open");
            }
            var overRtc = Call(client, client.WebRtc.CallHook("example_hook", "hello", new JArray("rtc")), "9 webrtc CallHook");
            if (!overRtc.Ok) throw new StepFailed("9 webrtc CallHook", overRtc.Error);
            Ok("9 webrtc connected, both channels open, example_hook.hello over events: " + Json.Dump(overRtc.Data));
            client.WebRtc.Close();
        }
    }
}
