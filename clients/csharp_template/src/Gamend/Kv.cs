// Live key-value rows: subscribe once, read any time, hear every change.
//
//     client.Kv.Subscribe(new KvKey("progress", userId));
//     client.Kv.OnChange((key, row) =>
//     {
//         if (key.Key == "progress" && row.Exists) Show(row.Data);
//     });
//     var progress = client.Kv.Row(new KvKey("progress", userId));
//
// A subscription outlives the connection: every time the user channel (re)joins,
// each one is sent again and its reply refreshes the row. The cache also takes
// `Fetch` results, so a game can paint what it knows before the socket is up.
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    /// <summary>Which row: a key, global or scoped to a user or a lobby.</summary>
    public sealed class KvKey
    {
        public string Key { get; }
        public string UserId { get; }
        public string LobbyId { get; }

        public KvKey(string key, string userId = "", string lobbyId = "")
        {
            Key = key ?? "";
            UserId = userId ?? "";
            LobbyId = lobbyId ?? "";
        }

        public static implicit operator KvKey(string key)
        {
            return new KvKey(key);
        }

        public override bool Equals(object obj)
        {
            var other = obj as KvKey;
            return other != null && Key == other.Key && UserId == other.UserId && LobbyId == other.LobbyId;
        }

        public override int GetHashCode()
        {
            return HashCode.Combine(Key, UserId, LobbyId);
        }
    }

    /// <summary>A row as the cache knows it.</summary>
    public sealed class KvRow
    {
        /// <summary>False: the server said there is no such row (yet).</summary>
        public bool Exists { get; set; }
        public JToken Data { get; set; } = JValue.CreateNull();
        public JToken Metadata { get; set; } = JValue.CreateNull();

        internal KvRow Copy()
        {
            return new KvRow { Exists = Exists, Data = Data.DeepClone(), Metadata = Metadata.DeepClone() };
        }
    }

    public sealed class KvResult
    {
        public bool Ok { get; set; }
        public KvRow Row { get; set; } = new KvRow();
        /// <summary>Why not: the server's code (`forbidden`, `invalid_key`), or the transport's.</summary>
        public string Error { get; set; } = "";
    }

    public sealed class Kv
    {
        // The default comparers are built by reflection on the runtime's side;
        // handing the collections these keeps IL2CPP out of it.
        private sealed class KeyOrder : IComparer<KvKey>, IEqualityComparer<KvKey>
        {
            public int Compare(KvKey a, KvKey b)
            {
                var order = string.CompareOrdinal(a.Key, b.Key);
                if (order != 0) return order;
                order = string.CompareOrdinal(a.UserId, b.UserId);
                return order != 0 ? order : string.CompareOrdinal(a.LobbyId, b.LobbyId);
            }

            public bool Equals(KvKey a, KvKey b)
            {
                return a.Equals(b);
            }

            public int GetHashCode(KvKey key)
            {
                return key.GetHashCode();
            }
        }

        private static readonly KeyOrder Order = new KeyOrder();

        private readonly Core _core;
        private readonly Dictionary<KvKey, KvRow> _rows = new Dictionary<KvKey, KvRow>(Order);
        private readonly SortedDictionary<KvKey, List<Action<KvResult>>> _subscriptions =
            new SortedDictionary<KvKey, List<Action<KvResult>>>(Order);
        private readonly Dictionary<KvKey, bool> _confirmed = new Dictionary<KvKey, bool>(Order);
        private long _nextListener = 1;
        private readonly Listeners<ValueTuple<KvKey, KvRow>> _listeners;

        internal Kv(Core core)
        {
            _core = core;
            _listeners = new Listeners<ValueTuple<KvKey, KvRow>>(core.Loop);
            core.Realtime.OnEvent(e => OnEvent(e.Kind, e.Payload));
        }

        private static JObject ScopePayload(KvKey key)
        {
            var payload = new JObject { ["key"] = key.Key };
            if (key.UserId.Length > 0) payload["user_id"] = key.UserId;
            if (key.LobbyId.Length > 0) payload["lobby_id"] = key.LobbyId;
            return payload;
        }

        private static KvKey KeyOf(JToken payload)
        {
            return new KvKey(Json.Text(payload, "key"), Json.Text(payload, "user_id"), Json.Text(payload, "lobby_id"));
        }

        /// <summary>Subscribe to a row: `kv_updated` and `kv_deleted` keep it current from now on,
        /// over every reconnect, until `Unsubscribe`. The task gets the current row, or why the
        /// server refused (a refusal is not retried).</summary>
        public Task<KvResult> Subscribe(KvKey key)
        {
            return _core.Start<KvResult>(done =>
            {
                List<Action<KvResult>> waiting;
                var fresh = !_subscriptions.TryGetValue(key, out waiting);
                if (fresh)
                {
                    waiting = new List<Action<KvResult>>();
                    _subscriptions[key] = waiting;
                }
                waiting.Add(done);
                if (fresh && _core.Realtime.Joined(_core.Realtime.UserTopic)) SendSubscribe(key);
            });
        }

        public void Unsubscribe(KvKey key)
        {
            lock (_core.Gate)
            {
                if (!_subscriptions.Remove(key)) return;
                _confirmed.Remove(key);
                var topic = _core.Realtime.UserTopic;
                if (_core.Realtime.Joined(topic)) _core.Realtime.Push(topic, "kv:unsubscribe", ScopePayload(key), null);
            }
        }

        public bool Subscribed(KvKey key)
        {
            lock (_core.Gate)
            {
                bool confirmed;
                return _confirmed.TryGetValue(key, out confirmed) && confirmed;
            }
        }

        private void SendSubscribe(KvKey key)
        {
            _core.Realtime.Push(_core.Realtime.UserTopic, "kv:subscribe", ScopePayload(key), reply =>
            {
                List<Action<KvResult>> waiting;
                if (!_subscriptions.TryGetValue(key, out waiting)) return;  // unsubscribed meanwhile
                _subscriptions[key] = new List<Action<KvResult>>();
                var result = new KvResult();
                if (reply.Ok)
                {
                    _confirmed[key] = true;
                    result.Ok = true;
                    var missing = Json.Field(reply.Response, "missing");
                    result.Row.Exists = missing.Type != JTokenType.Boolean || !(bool)missing;
                    result.Row.Data = Json.Field(reply.Response, "data");
                    result.Row.Metadata = Json.Field(reply.Response, "metadata");
                    Store(key, result.Row);
                }
                else
                {
                    result.Error = reply.Error;
                    if (reply.Status == "error")
                    {
                        // Forbidden or invalid: asking again will not change the answer.
                        _subscriptions.Remove(key);
                        _core.Log(LogLevel.Warning, "gamend: kv subscribe to " + key.Key + " refused: " + reply.Error);
                    }
                }
                foreach (var done in waiting) done(result);
            });
        }

        internal void UserChannelJoined()
        {
            // A fresh join means the server forgot every subscription.
            _confirmed.Clear();
            foreach (var key in new List<KvKey>(_subscriptions.Keys)) SendSubscribe(key);
        }

        /// <summary>The row as last seen, or null when this client never learned it. A copy.</summary>
        public KvRow Row(KvKey key)
        {
            lock (_core.Gate)
            {
                KvRow row;
                return _rows.TryGetValue(key, out row) ? row.Copy() : null;
            }
        }

        /// <summary>The row from the cache, or `GET /api/v1/kv/{key}` when it is not there (or
        /// `force`). A 404 caches "no such row"; a failure caches nothing.</summary>
        public Task<KvResult> Fetch(KvKey key, bool force = false)
        {
            return _core.Start<KvResult>(done =>
            {
                KvRow cached;
                if (!force && _rows.TryGetValue(key, out cached))
                {
                    var hit = new KvResult { Ok = true, Row = cached.Copy() };
                    _core.Post(() => done(hit));
                    return;
                }
                var options = new JObject();
                if (key.UserId.Length > 0) options["user_id"] = key.UserId;
                if (key.LobbyId.Length > 0) options["lobby_id"] = key.LobbyId;
                var path = "/api/v1/kv/" + Query.Escape(key.Key) + Query.Build(options, "user_id", "lobby_id");
                _core.Rest.Send(true, "GET", path, Body.None, r =>
                {
                    var result = new KvResult();
                    if (r.Ok)
                    {
                        result.Ok = true;
                        result.Row.Exists = true;
                        result.Row.Data = Json.Field(r.Data, "data");
                        result.Row.Metadata = Json.Field(r.Data, "metadata");
                        Store(key, result.Row);
                    }
                    else if (r.Status == 404)
                    {
                        // The server's word that there is no row.
                        result.Ok = true;
                        Store(key, result.Row);
                    }
                    else
                    {
                        result.Error = r.Error;
                    }
                    done(result);
                });
            });
        }

        private void Store(KvKey key, KvRow row)
        {
            // The cache keeps its own: `row` goes on to the caller and the listeners.
            _rows[key] = row.Copy();
            _listeners.Fire(ValueTuple.Create(key, row));
        }

        private void OnEvent(string kind, JToken payload)
        {
            if (kind == Events.KvUpdated)
            {
                Store(KeyOf(payload), new KvRow
                {
                    Exists = true,
                    Data = Json.Field(payload, "data"),
                    Metadata = Json.Field(payload, "metadata"),
                });
            }
            else if (kind == Events.KvDeleted)
            {
                Store(KeyOf(payload), new KvRow());
            }
        }

        /// <summary>Every change to a cached row, from any source. Answers an id for `Off`.</summary>
        public long OnChange(Action<KvKey, KvRow> listener)
        {
            lock (_core.Gate)
            {
                var id = _nextListener++;
                _listeners.Add(id, change => listener(change.Item1, change.Item2));
                return id;
            }
        }

        public void Off(long listener)
        {
            lock (_core.Gate)
            {
                _listeners.Remove(listener);
            }
        }

        /// <summary>Forget every row and subscription. Signing out does it.</summary>
        public void Clear()
        {
            lock (_core.Gate)
            {
                _rows.Clear();
                _subscriptions.Clear();
                _confirmed.Clear();
            }
        }
    }
}
