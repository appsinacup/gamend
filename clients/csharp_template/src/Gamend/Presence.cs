// Who is around: merged user profiles, lobbies and online state, kept up by the
// realtime events as they arrive. A game reads instead of bookkeeping.
//
//     client.Presence.OnUserChanged(id => RedrawNameTag(id, client.Presence.User(id)));
//     var here = client.Presence.Online(friendId);
//
// Updates arrive as partial patches, metadata as sparse sections; they are
// merged, so a profile only grows more complete. The signed-in player's own
// `user:<id>` push carries the whole metadata map and replaces it, which is how
// a key the server deleted disappears.
using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace Gamend
{
    public sealed class Presence
    {
        private readonly Core _core;
        private readonly Dictionary<string, JObject> _users = new Dictionary<string, JObject>();
        private readonly Dictionary<string, JObject> _lobbies = new Dictionary<string, JObject>();
        private readonly Dictionary<string, bool> _online = new Dictionary<string, bool>();
        private readonly Dictionary<string, long> _lastSeen = new Dictionary<string, long>();
        private long _nextListener = 1;
        private readonly Listeners<string> _userListeners;
        private readonly Listeners<JToken> _lobbyListeners;

        internal Presence(Core core)
        {
            _core = core;
            _userListeners = new Listeners<string>(core.Loop);
            _lobbyListeners = new Listeners<JToken>(core.Loop);
            core.Realtime.OnEvent(e => OnEvent(e.Kind, e.Payload));
        }

        private static string IdOf(JToken payload)
        {
            var id = Json.Text(payload, "user_id");
            return id.Length == 0 ? Json.Text(payload, "id") : id;
        }

        private void OnEvent(string kind, JToken payload)
        {
            switch (kind)
            {
                case Events.UserUpdated:
                    ApplyUserUpdate(payload);
                    break;
                case Events.LobbyUpdated:
                {
                    var id = Json.Text(payload, "id");
                    var lobby = payload as JObject;
                    if (id.Length == 0 || lobby == null) return;
                    _lobbies[id] = (JObject)lobby.DeepClone();
                    _lobbyListeners.Fire(lobby);
                    break;
                }
                case Events.LobbyStateChanged:
                {
                    // The flip comes out of band; an `updated` in flight may still
                    // carry the old state, so it is patched in and announced.
                    var id = Json.Text(payload, "lobby_id");
                    if (id.Length == 0) return;
                    JObject lobby;
                    if (!_lobbies.TryGetValue(id, out lobby))
                    {
                        lobby = new JObject { ["id"] = id };
                        _lobbies[id] = lobby;
                    }
                    lobby["state"] = Json.Text(payload, "to");
                    _lobbyListeners.Fire(lobby.DeepClone());
                    break;
                }
                case Events.LobbyMemberJoined:
                case Events.LobbyMemberUpdated:
                case Events.PartyMemberUpdated:
                case Events.GroupMemberUpdated:
                {
                    var id = IdOf(payload);
                    if (id.Length == 0) return;
                    MergeInto(id, payload, false);
                    _userListeners.Fire(id);
                    break;
                }
                case Events.LobbyMemberOnline:
                case Events.PartyMemberOnline:
                case Events.GroupMemberOnline:
                {
                    var id = IdOf(payload);
                    if (id.Length == 0) return;
                    _online[id] = true;
                    _userListeners.Fire(id);
                    break;
                }
                case Events.LobbyMemberOffline:
                case Events.PartyMemberOffline:
                case Events.GroupMemberOffline:
                {
                    var id = IdOf(payload);
                    if (id.Length == 0) return;
                    _online[id] = false;
                    _lastSeen[id] = _core.UnixNow();
                    _userListeners.Fire(id);
                    break;
                }
            }
        }

        private void ApplyUserUpdate(JToken user)
        {
            var self = _core.Auth.CurrentUserId;
            var id = Json.Text(user, "id", self);
            if (id.Length == 0) return;
            // The `user:<id>` push is the one payload with the WHOLE metadata map;
            // a `u`-wrapped body is partial and merges.
            var wrapped = Json.Field(user, "u") as JObject;
            MergeInto(id, wrapped ?? user, wrapped == null);
            if (id == self)
            {
                // The player's own lobby_id is the truth: any other lobby is stale.
                var current = Json.Text(_users[id], "lobby_id");
                foreach (var lobby in new List<string>(_lobbies.Keys))
                {
                    if (lobby != current) _lobbies.Remove(lobby);
                }
            }
            _userListeners.Fire(id);
        }

        private void MergeInto(string id, JToken patch, bool metadataIsWhole)
        {
            JObject existing;
            if (!_users.TryGetValue(id, out existing))
            {
                existing = new JObject { ["id"] = id };
                _users[id] = existing;
            }
            var fields = patch as JObject;
            if (fields == null) return;
            foreach (var field in fields.Properties())
            {
                if (field.Name == "metadata" && field.Value is JObject)
                {
                    existing["metadata"] = metadataIsWhole
                        ? field.Value.DeepClone()
                        : MergeMetadata(Json.Field(existing, "metadata"), field.Value);
                }
                else
                {
                    existing[field.Name] = field.Value.DeepClone();
                }
            }
        }

        /// <summary>Metadata merged one section deep: `{"player": {"hat": "x"}}` sets the hat
        /// without wiping the rest of `player`.</summary>
        public static JObject MergeMetadata(JToken existing, JToken patch)
        {
            var merged = existing is JObject ? (JObject)existing.DeepClone() : new JObject();
            var fields = patch as JObject;
            if (fields == null) return merged;
            foreach (var field in fields.Properties())
            {
                JToken current;
                var section = field.Value as JObject;
                if (section != null && merged.TryGetValue(field.Name, out current) && current is JObject)
                {
                    var target = (JObject)current;
                    foreach (var entry in section.Properties()) target[entry.Name] = entry.Value.DeepClone();
                }
                else
                {
                    merged[field.Name] = field.Value.DeepClone();
                }
            }
            return merged;
        }

        /// <summary>The merged profile, or an empty object. A copy.</summary>
        public JObject User(string userId)
        {
            lock (_core.Gate)
            {
                JObject user;
                return _users.TryGetValue(userId, out user) ? (JObject)user.DeepClone() : new JObject();
            }
        }

        /// <summary>The lobby as last pushed, or an empty object. A copy.</summary>
        public JObject Lobby(string lobbyId)
        {
            lock (_core.Gate)
            {
                JObject lobby;
                return _lobbies.TryGetValue(lobbyId, out lobby) ? (JObject)lobby.DeepClone() : new JObject();
            }
        }

        /// <summary>Online as far as this client knows; the signed-in player always is.</summary>
        public bool Online(string userId)
        {
            lock (_core.Gate)
            {
                if (_core.Auth.Current != null && _core.Auth.CurrentUserId == userId) return true;
                bool online;
                return _online.TryGetValue(userId, out online) && online;
            }
        }

        /// <summary>When an offline player was last seen, in Unix seconds; 0 when unknown.</summary>
        public long LastSeen(string userId)
        {
            lock (_core.Gate)
            {
                long seen;
                return _lastSeen.TryGetValue(userId, out seen) ? seen : 0;
            }
        }

        /// <summary>Record presence learned elsewhere (a friend list, a search result).</summary>
        public void SetOnline(string userId, bool online, long lastSeen = 0)
        {
            lock (_core.Gate)
            {
                _online[userId] = online;
                if (!online && lastSeen > 0) _lastSeen[userId] = lastSeen;
            }
        }

        /// <summary>Merge user data learned elsewhere (a REST answer, a member list).</summary>
        public void CacheUser(string userId, JToken data)
        {
            if (string.IsNullOrEmpty(userId)) return;
            lock (_core.Gate)
            {
                MergeInto(userId, data, false);
                _userListeners.Fire(userId);
            }
        }

        /// <summary>Forget everything. Signing out does it.</summary>
        public void Clear()
        {
            lock (_core.Gate)
            {
                _users.Clear();
                _lobbies.Clear();
                _online.Clear();
                _lastSeen.Clear();
            }
        }

        public long OnUserChanged(Action<string> listener)
        {
            lock (_core.Gate)
            {
                var id = _nextListener++;
                _userListeners.Add(id, listener);
                return id;
            }
        }

        public long OnLobbyChanged(Action<JToken> listener)
        {
            lock (_core.Gate)
            {
                var id = _nextListener++;
                _lobbyListeners.Add(id, listener);
                return id;
            }
        }

        public void Off(long listener)
        {
            lock (_core.Gate)
            {
                _userListeners.Remove(listener);
                _lobbyListeners.Remove(listener);
            }
        }
    }
}
