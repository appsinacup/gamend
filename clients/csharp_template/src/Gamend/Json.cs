// Reading JSON without tripping on it.
//
// `JToken` is the public value type. Its indexer throws on a value that is not
// a container and `(string)token` throws on one that is, so a reply is read
// with the accessors here, which cannot fail, or with the typed models.
using System.IO;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    public static class Json
    {
        /// <summary>`value[key]` as text, or `fallback` when it is missing or not a string.</summary>
        public static string Text(JToken value, string key, string fallback = "")
        {
            var found = Find(value, key);
            return found != null && found.Type == JTokenType.String ? (string)found : fallback;
        }

        /// <summary>`value[key]` as an integer, or `fallback` when it is missing or not a number.</summary>
        public static long Number(JToken value, string key, long fallback = 0)
        {
            long number;
            return TryLong(Find(value, key), out number) ? number : fallback;
        }

        /// <summary>`value[key]`, or a JSON null when it is missing. Never a C# null.</summary>
        public static JToken Field(JToken value, string key)
        {
            return Find(value, key) ?? JValue.CreateNull();
        }

        /// <summary>Serialized for the wire.</summary>
        public static string Dump(JToken value)
        {
            return value == null ? "null" : value.ToString(Formatting.None);
        }

        /// <summary>Parsed, or a C# null when `text` is not JSON. Timestamps stay strings.</summary>
        public static JToken Parse(string text)
        {
            if (string.IsNullOrEmpty(text)) return null;
            try
            {
                using (var reader = new JsonTextReader(new StringReader(text)))
                {
                    // Left to its default the reader turns anything shaped like
                    // a date into a date token, which is no longer the text the
                    // server sent.
                    reader.DateParseHandling = DateParseHandling.None;
                    var token = JToken.ReadFrom(reader);
                    while (reader.Read())
                    {
                        if (reader.TokenType != JsonToken.Comment) return null;
                    }
                    return token;
                }
            }
            catch (JsonException)
            {
                return null;
            }
        }

        private static JToken Find(JToken value, string key)
        {
            var o = value as JObject;
            JToken found;
            return o != null && o.TryGetValue(key, out found) ? found : null;
        }

        internal static bool TryLong(JToken token, out long value)
        {
            value = 0;
            var scalar = token as JValue;
            if (scalar == null) return false;
            if (scalar.Type != JTokenType.Integer && scalar.Type != JTokenType.Float) return false;
            switch (scalar.Value)
            {
                case long l:
                    value = l;
                    return true;
                case int i:
                    value = i;
                    return true;
                case uint u:
                    value = u;
                    return true;
                case ulong ul:
                    value = unchecked((long)ul);
                    return true;
                case double d:
                    if (double.IsNaN(d) || double.IsInfinity(d)) return false;
                    value = (long)d;
                    return true;
                case float f:
                    if (float.IsNaN(f) || float.IsInfinity(f)) return false;
                    value = (long)f;
                    return true;
                case decimal m:
                    value = (long)m;
                    return true;
                default:
                    return false;
            }
        }

        internal static bool TryDouble(JToken token, out double value)
        {
            value = 0;
            var scalar = token as JValue;
            if (scalar == null) return false;
            if (scalar.Type != JTokenType.Integer && scalar.Type != JTokenType.Float) return false;
            switch (scalar.Value)
            {
                case double d:
                    value = d;
                    return true;
                case float f:
                    value = f;
                    return true;
                case decimal m:
                    value = (double)m;
                    return true;
                case long l:
                    value = l;
                    return true;
                case int i:
                    value = i;
                    return true;
                case uint u:
                    value = u;
                    return true;
                case ulong ul:
                    value = ul;
                    return true;
                default:
                    return false;
            }
        }
    }
}
