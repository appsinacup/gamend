// A client over a fake server and a fake clock, for every test.
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Gamend.Testing;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Gamend.Tests
{
    internal static class Wire
    {
        /// <summary>JSON written with single quotes, to keep the tests readable.</summary>
        internal static string Q(string text)
        {
            return text.Replace('\'', '"');
        }

        internal static JToken J(string text)
        {
            var parsed = Json.Parse(Q(text));
            Assert.NotNull(parsed);
            return parsed;
        }

        internal static JObject O(string text)
        {
            return (JObject)J(text);
        }

        internal static JArray A(string text)
        {
            return (JArray)Json.Parse(text);
        }

        internal static byte[] B(params int[] values)
        {
            var bytes = new byte[values.Length];
            for (var i = 0; i < values.Length; i++) bytes[i] = (byte)values[i];
            return bytes;
        }

        internal static void Same(JToken expected, JToken actual)
        {
            Assert.True(JToken.DeepEquals(expected, actual), "expected " + Json.Dump(expected) + ", got " + Json.Dump(actual));
        }

        /// <summary>A sign-in reply with the tokens `a&lt;n&gt;` / `r&lt;n&gt;`.</summary>
        internal static string SessionReply(int n = 1, int expiresIn = 900)
        {
            return Json.Dump(new JObject
            {
                ["data"] = new JObject
                {
                    ["access_token"] = "a" + n,
                    ["refresh_token"] = "r" + n,
                    ["user_id"] = "u1",
                    ["username"] = "ann",
                    ["display_name"] = "Ann",
                    ["expires_in"] = expiresIn,
                },
            });
        }

        internal static string ReplyFrame(JToken joinRef, JToken reference, JToken topic, string status, JToken response = null)
        {
            return Json.Dump(new JArray
            {
                joinRef,
                reference,
                topic,
                "phx_reply",
                new JObject { ["status"] = status, ["response"] = response ?? new JObject() },
            });
        }

        internal static string PhxReply(string joinRef, string reference, string topic, string status, JToken response = null)
        {
            return ReplyFrame(joinRef, reference, topic, status, response);
        }

        internal static string ReplyTo(JArray frame, string status, JToken response = null)
        {
            return ReplyFrame(frame[0], frame[1], frame[2], status, response);
        }

        internal static string Message(string topic, string eventName, JToken payload)
        {
            return Json.Dump(new JArray { JValue.CreateNull(), JValue.CreateNull(), topic, eventName, payload });
        }
    }

    internal class Harness
    {
        internal readonly FakeClock Clock = new FakeClock();
        internal readonly List<string> Opened = new List<string>();
        internal readonly List<Session> Changes = new List<Session>();
        internal readonly FakeHttp Server = new FakeHttp();
        internal readonly FakeWebSocket Socket = new FakeWebSocket();
        internal readonly FakePeer Peer = new FakePeer();
        internal readonly Client Client;

        internal Harness(bool withOpenUrl = true, RealtimeFormat webRtcFormat = RealtimeFormat.Json)
        {
            var config = new Config
            {
                BaseUrl = "http://game.test/",
                Http = Server,
                WebSocket = Socket,
                WebRtc = Peer,
                WebRtcFormat = webRtcFormat,
                RunId = "run-1",
                Clock = Clock.Steady,
                UnixClock = Clock.Wall,
                SignInTimeout = TimeSpan.FromSeconds(5),
            };
            if (withOpenUrl) config.OpenUrl = url => Opened.Add(url);
            Client = new Client(config);
            Client.Auth.OnSessionChanged(session => Changes.Add(session));
        }

        /// <summary>Signed in as `a1`/`r1` without a round trip.</summary>
        internal void SignedIn(long lasts = 900)
        {
            Client.Auth.Restore(new Session
            {
                AccessToken = "a1",
                RefreshToken = "r1",
                UserId = "u1",
                Username = "ann",
                ExpiresIn = 900,
                ExpiresAt = Clock.Wall() + lasts,
            });
        }

        internal void Advance(TimeSpan by)
        {
            Clock.Advance(by);
            Client.Poll();
        }

        internal void AdvanceMs(long ms)
        {
            Advance(TimeSpan.FromMilliseconds(ms));
        }

        internal void AdvanceSeconds(long seconds)
        {
            Advance(TimeSpan.FromSeconds(seconds));
        }
    }

    /// <summary>What a task answered, and how often: counted inside `Poll`, as the task completes.</summary>
    internal sealed class Seen<T>
    {
        internal int Calls;
        internal T Last;

        internal Seen<T> Watch(Task<T> task)
        {
            task.ContinueWith(
                t =>
                {
                    Calls++;
                    Last = t.Result;
                },
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
            return this;
        }
    }

    internal static class See
    {
        internal static Seen<T> Task<T>(Task<T> task)
        {
            return new Seen<T>().Watch(task);
        }
    }
}
