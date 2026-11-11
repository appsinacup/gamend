// The REST layer: one authenticated JSON caller for the whole API.
//
// `Api` is generated over it, one method per operation; call it directly for a
// path `Api` does not know yet. An authenticated call that answers 401 while a
// refresh token is in hand refreshes the session once and is sent again, so an
// expired access token heals without the caller seeing it.
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    /// <summary>What a call sends: nothing, a JSON value, or raw bytes.</summary>
    public sealed class Body
    {
        public static readonly Body None = new Body(Array.Empty<byte>(), "");

        internal byte[] Bytes { get; }
        internal string ContentType { get; }

        private Body(byte[] bytes, string contentType)
        {
            Bytes = bytes;
            ContentType = contentType;
        }

        /// <summary>A JSON body, serialized now: a retry sends what the call meant, whatever the
        /// caller did to `value` since. A null is an empty object.</summary>
        public static Body Of(JToken value)
        {
            var text = value == null || value.Type == JTokenType.Null ? "{}" : Json.Dump(value);
            return new Body(Encoding.UTF8.GetBytes(text), "application/json");
        }

        public static Body Raw(byte[] bytes, string contentType = "application/octet-stream")
        {
            return new Body(bytes ?? Array.Empty<byte>(), contentType);
        }
    }

    public sealed class Rest
    {
        private sealed class Call
        {
            public string Method;
            public string Path;
            public Body Body;
            public Action<Response> Done;
            public bool Authenticated;
            public bool Retried;
        }

        private readonly Core _core;

        internal Rest(Core core)
        {
            _core = core;
        }

        /// <summary>`method` on `path` (`/api/v1/...`, query included) with the session's bearer
        /// token when there is one.</summary>
        public Task<Response> Send(string method, string path, Body body = null)
        {
            return _core.Start<Response>(done => Send(true, method, path, body, done));
        }

        /// <summary>The same without the bearer token and without the refresh on 401: sign-in and
        /// refresh themselves go this way.</summary>
        public Task<Response> SendAnonymous(string method, string path, Body body = null)
        {
            return _core.Start<Response>(done => Send(false, method, path, body, done));
        }

        internal void Send(bool authenticated, string method, string path, Body body, Action<Response> done)
        {
            lock (_core.Gate)
            {
                Start(new Call
                {
                    Method = method,
                    Path = path,
                    Body = body ?? Body.None,
                    Done = done,
                    Authenticated = authenticated,
                });
            }
        }

        /// <summary>The error a call gets when the SDK will not send it, on the next `Poll`:
        /// `&lt;call&gt; needs `&lt;field&gt;``.</summary>
        internal Task<Response> Refuse(string call, string field)
        {
            var message = call + " needs `" + field + "`";
            _core.Log(LogLevel.Error, "gamend: " + message);
            var source = new TaskCompletionSource<Response>();
            _core.Post(() => source.TrySetResult(new Response { Error = message }));
            return source.Task;
        }

        private static bool CarriesBody(string method)
        {
            return method == "POST" || method == "PUT" || method == "PATCH";
        }

        private void Start(Call call)
        {
            var request = new HttpRequest
            {
                Method = call.Method,
                Url = _core.BaseUrl + call.Path,
                Timeout = _core.Config.HttpTimeout,
            };
            AddHeader(request, "accept", "application/json");
            AddHeader(request, "user-agent", "gamend-csharp/" + GamendVersion.Value);
            AddHeader(request, "x-gamend-session", _core.RunId);
            if (call.Authenticated)
            {
                var bearer = _core.Auth.Bearer();
                if (bearer.Length > 0) AddHeader(request, "authorization", bearer);
            }
            if (call.Body.ContentType.Length > 0)
            {
                request.Body = call.Body.Bytes;
                AddHeader(request, "content-type", call.Body.ContentType);
            }
            else if (CarriesBody(call.Method))
            {
                request.Body = Encoding.UTF8.GetBytes("{}");
                AddHeader(request, "content-type", "application/json");
            }

            var loop = _core.Loop;
            var http = _core.Config.Http;
            if (http == null)
            {
                var reply = new HttpResponse { Error = "no HTTP transport configured" };
                loop.Post(() => Finish(call, reply));
                return;
            }
            // The transport completes on its own thread; the reply crosses to
            // the game thread through the inbox, and is dropped there if the
            // client is gone.
            http.Send(request, reply => loop.Post(() => Finish(call, reply)));
        }

        private static void AddHeader(HttpRequest request, string name, string value)
        {
            request.Headers.Add(new KeyValuePair<string, string>(name, value));
        }

        private void Finish(Call call, HttpResponse reply)
        {
            var response = new Response { Status = reply.Status, Bytes = reply.Body ?? Array.Empty<byte>() };
            if (response.Bytes.Length > 0)
            {
                response.Text = Encoding.UTF8.GetString(response.Bytes);
                var parsed = Json.Parse(response.Text);
                if (parsed != null) response.Body = parsed;
            }
            if (response.Status == 0)
            {
                response.Error = string.IsNullOrEmpty(reply.Error) ? "no reply" : reply.Error;
            }
            else if (response.Status < 200 || response.Status >= 300)
            {
                var code = response.Code;
                response.Error = code.Length == 0 ? "http_" + response.Status : code;
            }

            if (response.Status == 401 && call.Authenticated && !call.Retried)
            {
                call.Retried = true;
                _core.Auth.RefreshThen(refreshed =>
                {
                    if (refreshed)
                    {
                        Start(call);
                    }
                    else
                    {
                        call.Done(response);
                    }
                });
                return;
            }
            call.Done(response);
        }
    }
}
