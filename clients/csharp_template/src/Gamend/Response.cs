// What a call answered.
//
// Every Gamend reply is one of four shapes: `{data}`, `{data, meta}`,
// `{ok: true}` or `{error, message?, errors?}`. `Data`, `Meta`, `Code` and
// `Message` read them without touching `Body` directly.
using System;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    public sealed class Response
    {
        /// <summary>The HTTP status; 0 when no reply arrived (the transport failed, or the SDK
        /// refused to send the call because a required field was missing).</summary>
        public int Status { get; set; }
        /// <summary>The decoded body; a JSON null when it was empty or not JSON.</summary>
        public JToken Body { get; set; } = JValue.CreateNull();
        /// <summary>The body as it arrived, decoded as UTF-8.</summary>
        public string Text { get; set; } = "";
        /// <summary>The body as it arrived: the bytes of a download, for one.</summary>
        public byte[] Bytes { get; set; } = Array.Empty<byte>();
        /// <summary>Empty on success. Otherwise the server's error code (`not_found`,
        /// `validation_failed`, ...), `http_&lt;status&gt;` when it gave none, or what went wrong
        /// before a reply arrived.</summary>
        public string Error { get; set; } = "";

        public bool Ok
        {
            get { return Status >= 200 && Status < 300 && Error.Length == 0; }
        }

        /// <summary>`body.data`: the object or list the call answered. A JSON null otherwise.</summary>
        public JToken Data
        {
            get { return Json.Field(Body, "data"); }
        }

        /// <summary>`body.meta` of a paged list: page, page_size, total_count, ...</summary>
        public JToken Meta
        {
            get { return Json.Field(Body, "meta"); }
        }

        /// <summary>`body.error`, the machine-readable code; empty on success.</summary>
        public string Code
        {
            get { return Json.Text(Body, "error"); }
        }

        /// <summary>`body.message`, the human-readable one, when the server sent it.</summary>
        public string Message
        {
            get { return Json.Text(Body, "message"); }
        }

        /// <summary>`body.errors`: `{field: [messages]}` for `validation_failed`.</summary>
        public JToken Errors
        {
            get { return Json.Field(Body, "errors"); }
        }

        /// <summary>`Data` as a typed value: `As&lt;Models.Lobby&gt;()`, or
        /// `As&lt;List&lt;string&gt;&gt;()`. The type's default (null, for a class) when it is not
        /// that kind of value at all; a field that is missing keeps its default. Ask for `long?`
        /// rather than `long` to tell a zero from nothing.</summary>
        public T As<T>()
        {
            var value = ReaderOf<T>()(Data);
            return value == null ? default(T) : (T)value;
        }

        /// <summary>A page of `T` with its `Meta`: `Page&lt;Models.Lobby&gt;()` for `GET /lobbies`.
        /// Null when the body is not an object.</summary>
        public Models.Page<T> Page<T>()
        {
            if (!(Body is JObject)) return null;
            var read = ReaderOf<T>();
            var page = new Models.Page<T>();
            var items = Data as JArray;
            if (items != null)
            {
                foreach (var item in items)
                {
                    var value = read(item);
                    if (value != null) page.Data.Add((T)value);
                }
            }
            Models.PageMeta meta;
            if (Models.Codec.ReadPageMeta(Meta, out meta)) page.Meta = meta;
            return page;
        }

        private static Func<JToken, object> ReaderOf<T>()
        {
            Func<JToken, object> read;
            if (Models.Codec.Readers.TryGetValue(typeof(T), out read)) return read;
            throw new InvalidOperationException("Gamend has no reader for " + typeof(T).Name);
        }
    }
}
