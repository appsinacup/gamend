// HTTP over System.Net.Http, for .NET and for Unity outside WebGL.
using System;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace Gamend.Net
{
    public sealed class HttpClientTransport : IHttpTransport, IDisposable
    {
        private readonly HttpClient _client;
        private readonly bool _owned;

        public HttpClientTransport()
            : this(new HttpClient { Timeout = Timeout.InfiniteTimeSpan }, true)
        {
        }

        /// <summary>Over a client the caller keeps. Each request's own timeout still applies.</summary>
        public HttpClientTransport(HttpClient client)
            : this(client, false)
        {
        }

        private HttpClientTransport(HttpClient client, bool owned)
        {
            _client = client;
            _owned = owned;
        }

        public void Send(HttpRequest request, Action<HttpResponse> done)
        {
            _ = SendAsync(request, done);
        }

        private async Task SendAsync(HttpRequest request, Action<HttpResponse> done)
        {
            var reply = new HttpResponse();
            try
            {
                using (var timeout = new CancellationTokenSource(request.Timeout))
                using (var message = Build(request))
                using (var answer = await _client.SendAsync(message, timeout.Token).ConfigureAwait(false))
                {
                    reply.Status = (int)answer.StatusCode;
                    reply.Body = await answer.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
            {
                reply = new HttpResponse { Error = "timeout" };
            }
            catch (Exception e)
            {
                // The contract is one completion, whatever happened: nothing
                // waits on this task, so an exception left in it would be a call
                // that never answers.
                reply = new HttpResponse { Error = e.Message };
            }
            done(reply);
        }

        private static HttpRequestMessage Build(HttpRequest request)
        {
            var message = new HttpRequestMessage(new HttpMethod(request.Method), request.Url);
            if (request.Body.Length > 0) message.Content = new ByteArrayContent(request.Body);
            foreach (var header in request.Headers)
            {
                if (!message.Headers.TryAddWithoutValidation(header.Key, header.Value))
                {
                    message.Content?.Headers.TryAddWithoutValidation(header.Key, header.Value);
                }
            }
            return message;
        }

        public void Dispose()
        {
            if (_owned) _client.Dispose();
        }
    }
}
