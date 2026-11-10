// What every generated call needs: an escaped path segment, a query string, and
// the required-field check.
using System.Text;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    internal static class Query
    {
        /// <summary>Percent-encoding of everything but RFC 3986's unreserved characters, so a
        /// value is safe in a path segment and in a query alike.</summary>
        internal static string Escape(string text)
        {
            if (string.IsNullOrEmpty(text)) return "";
            const string hex = "0123456789ABCDEF";
            var bytes = Encoding.UTF8.GetBytes(text);
            var builder = new StringBuilder(bytes.Length);
            foreach (var b in bytes)
            {
                var unreserved = (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') || (b >= '0' && b <= '9')
                    || b == '-' || b == '_' || b == '.' || b == '~';
                if (unreserved)
                {
                    builder.Append((char)b);
                }
                else
                {
                    builder.Append('%');
                    builder.Append(hex[b >> 4]);
                    builder.Append(hex[b & 0x0F]);
                }
            }
            return builder.ToString();
        }

        /// <summary>Whether `table` carries `key` with a value. A key set to null is absent: the
        /// server would refuse it, and refusing here names the field instead.</summary>
        internal static bool Given(JToken table, string key)
        {
            var o = table as JObject;
            JToken value;
            return o != null && o.TryGetValue(key, out value) && value != null && value.Type != JTokenType.Null;
        }

        /// <summary>`?a=1&amp;b=2` for the keys an operation declares, in the order it declares
        /// them, skipping the ones `options` leaves out. Empty when none are given. A bool is
        /// `true`/`false`, as the server reads it.</summary>
        internal static string Build(JToken options, params string[] allowed)
        {
            StringBuilder builder = null;
            foreach (var key in allowed)
            {
                if (!Given(options, key)) continue;
                builder = builder == null ? new StringBuilder("?") : builder.Append('&');
                builder.Append(Escape(key)).Append('=').Append(Escape(TextOf(options[key])));
            }
            return builder == null ? "" : builder.ToString();
        }

        private static string TextOf(JToken value)
        {
            if (value.Type == JTokenType.String) return (string)value;
            if (value.Type == JTokenType.Boolean) return (bool)value ? "true" : "false";
            return Json.Dump(value);
        }
    }
}
