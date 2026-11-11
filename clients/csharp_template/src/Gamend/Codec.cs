// Reading a reply into a typed value, and writing one back.
//
// `Codec.g.cs` has a `Read<Model>` and a `Write<Model>` for every model; these
// are the pieces they are made of. Reads are lenient and never throw: a field
// that is missing or of the wrong type keeps its default, and only a value that
// is not even the right kind (an object for a model, an array for a list) reads
// as a failure.
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace Gamend.Models
{
    /// <summary>Reads `j` into `value`; false when `j` is not that kind of value.</summary>
    public delegate bool Reader<T>(JToken j, out T value);

    public delegate JToken Writer<T>(T value);

    public static partial class Codec
    {
        public static bool ReadString(JToken j, out string value)
        {
            value = null;
            if (j == null || j.Type != JTokenType.String) return false;
            value = (string)j;
            return true;
        }

        public static bool ReadLong(JToken j, out long value)
        {
            return Json.TryLong(j, out value);
        }

        public static bool ReadDouble(JToken j, out double value)
        {
            return Json.TryDouble(j, out value);
        }

        public static bool ReadBool(JToken j, out bool value)
        {
            value = false;
            if (j == null || j.Type != JTokenType.Boolean) return false;
            value = (bool)j;
            return true;
        }

        public static bool ReadToken(JToken j, out JToken value)
        {
            value = j ?? JValue.CreateNull();
            return true;
        }

        /// <summary>A list of what `item` reads. An item it cannot read is left out.</summary>
        public static Reader<List<T>> ListOf<T>(Reader<T> item)
        {
            return (JToken j, out List<T> value) =>
            {
                value = null;
                var array = j as JArray;
                if (array == null) return false;
                value = new List<T>(array.Count);
                foreach (var element in array)
                {
                    T read;
                    if (item(element, out read)) value.Add(read);
                }
                return true;
            };
        }

        /// <summary>A map of what `item` reads. A value it cannot read is left out.</summary>
        public static Reader<Dictionary<string, T>> MapOf<T>(Reader<T> item)
        {
            return (JToken j, out Dictionary<string, T> value) =>
            {
                value = null;
                var o = j as JObject;
                if (o == null) return false;
                value = new Dictionary<string, T>();
                Fill(o, value, item);
                return true;
            };
        }

        /// <summary>A value that may be null: a JSON null reads as no value, and that is a read.</summary>
        public static Reader<T?> Maybe<T>(Reader<T> inner) where T : struct
        {
            return (JToken j, out T? value) =>
            {
                value = null;
                if (j == null || j.Type == JTokenType.Null) return true;
                T read;
                if (!inner(j, out read)) return false;
                value = read;
                return true;
            };
        }

        /// <summary>`o[key]` when it is there and reads; `fallback` otherwise.</summary>
        internal static T Field<T>(JObject o, string key, Reader<T> read, T fallback)
        {
            JToken token;
            T value;
            return o.TryGetValue(key, out token) && read(token, out value) ? value : fallback;
        }

        internal static void Fill<T>(JObject o, Dictionary<string, T> into, Reader<T> item)
        {
            foreach (var field in o.Properties())
            {
                T read;
                if (item(field.Value, out read)) into[field.Name] = read;
            }
        }

        public static JToken WriteString(string value)
        {
            return value == null ? JValue.CreateNull() : new JValue(value);
        }

        public static JToken WriteLong(long value)
        {
            return new JValue(value);
        }

        public static JToken WriteDouble(double value)
        {
            return new JValue(value);
        }

        public static JToken WriteBool(bool value)
        {
            return new JValue(value);
        }

        public static JToken WriteToken(JToken value)
        {
            return value == null ? JValue.CreateNull() : value.DeepClone();
        }

        public static Writer<List<T>> ListWriter<T>(Writer<T> item)
        {
            return list =>
            {
                if (list == null) return JValue.CreateNull();
                var array = new JArray();
                foreach (var element in list) array.Add(item(element));
                return array;
            };
        }

        public static Writer<Dictionary<string, T>> MapWriter<T>(Writer<T> item)
        {
            return map =>
            {
                if (map == null) return JValue.CreateNull();
                var o = new JObject();
                foreach (var entry in map) o[entry.Key] = item(entry.Value);
                return o;
            };
        }

        public static Writer<T?> MaybeWriter<T>(Writer<T> inner) where T : struct
        {
            return value => value.HasValue ? inner(value.Value) : JValue.CreateNull();
        }
    }
}
