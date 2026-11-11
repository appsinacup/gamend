// HTTP over UnityWebRequest, on every platform Unity builds for, WebGL
// included, with the engine's own proxy and certificate handling.
//
// UnityWebRequest lives on the main thread. A request sent from there starts at
// once; one sent from another thread starts on the main thread's next frame,
// through the SynchronizationContext Unity installs there.
using System;
using System.Threading;
using UnityEngine.Networking;

namespace Gamend.Unity
{
    public sealed class UnityHttpTransport : IHttpTransport
    {
        private readonly SynchronizationContext _main;
        private readonly int _mainThread;

        /// <summary>Make it on the main thread: in `Awake`, `Start`, or anything they call.</summary>
        public UnityHttpTransport()
        {
            _main = SynchronizationContext.Current;
            _mainThread = Thread.CurrentThread.ManagedThreadId;
            if (_main == null)
            {
                throw new InvalidOperationException("UnityHttpTransport must be made on Unity's main thread");
            }
        }

        public void Send(HttpRequest request, Action<HttpResponse> done)
        {
            if (Thread.CurrentThread.ManagedThreadId == _mainThread)
            {
                Start(request, done);
            }
            else
            {
                _main.Post(_ => Start(request, done), null);
            }
        }

        private static void Start(HttpRequest request, Action<HttpResponse> done)
        {
            UnityWebRequest web;
            try
            {
                web = Build(request);
            }
            catch (Exception e)
            {
                // A header UnityWebRequest refuses, a malformed URL: still one
                // completion, as the contract asks.
                done(new HttpResponse { Error = e.Message });
                return;
            }
            // Called at once when the request has already finished.
            web.SendWebRequest().completed += _ => done(Finish(web));
        }

        private static UnityWebRequest Build(HttpRequest request)
        {
            var web = new UnityWebRequest(request.Url, request.Method)
            {
                downloadHandler = new DownloadHandlerBuffer(),
                // Whole seconds; 0 is none.
                timeout = request.Timeout > TimeSpan.Zero ? (int)Math.Ceiling(request.Timeout.TotalSeconds) : 0,
            };
            try
            {
                if (request.Body.Length > 0) web.uploadHandler = new UploadHandlerRaw(request.Body);
                foreach (var header in request.Headers)
                {
#if UNITY_WEBGL && !UNITY_EDITOR
                    // A page may not set it: the browser sends its own, and
                    // logs a refusal for every request that tries.
                    if (string.Equals(header.Key, "user-agent", StringComparison.OrdinalIgnoreCase)) continue;
#endif
                    web.SetRequestHeader(header.Key, header.Value);
                }
            }
            catch
            {
                web.Dispose();
                throw;
            }
            return web;
        }

        private static HttpResponse Finish(UnityWebRequest web)
        {
            try
            {
                var status = (int)web.responseCode;
                // A 4xx or 5xx is a ProtocolError, and a reply like any other.
                if (web.result == UnityWebRequest.Result.ConnectionError || status == 0)
                {
                    var error = string.IsNullOrEmpty(web.error) ? "no reply" : web.error;
                    // HttpClientTransport's word for it, which the SDK's callers see.
                    return new HttpResponse { Error = error == "Request timeout" ? "timeout" : error };
                }
                return new HttpResponse
                {
                    Status = status,
                    Body = web.downloadHandler.data ?? Array.Empty<byte>(),
                };
            }
            finally
            {
                web.Dispose();
            }
        }
    }
}
