// Quick Start: sign in with this device, open the realtime connection, and
// quick-join a lobby, with every event the client hears listed on screen.
//
// Put it on an empty GameObject in any scene (it adds a GamendBehaviour), set
// Base Url on that component to your server, and press Play. A server from
// `mix dev.start` answers on http://localhost:4000.
using System;
using System.Collections.Generic;
using Gamend.Unity;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace Gamend.Samples
{
    [RequireComponent(typeof(GamendBehaviour))]
    public class QuickStart : MonoBehaviour
    {
        private const int MaxLines = 20;
        private const string DeviceKey = "gamend_quick_start_device";

        private readonly List<string> _lines = new List<string>();
        private Client _client;
        private string _lobbyId = "";
        private bool _busy;

        private async void Start()
        {
            _client = GetComponent<GamendBehaviour>().Client;
            _client.Realtime.OnState(state => Print("realtime: " + state));
            _client.Realtime.OnEvent(e => Print(e.Topic + ": " + e.Name));

            Print("signing in to " + _client.BaseUrl);
            var signedIn = await _client.Auth.LoginDevice(DeviceId());
            if (!signedIn.Ok)
            {
                Print("sign-in failed: " + signedIn.Error);
                return;
            }
            Print("signed in as " + signedIn.Session.UserId);
            _client.Realtime.Connect();
        }

        private async void QuickJoin()
        {
            _busy = true;
            var reply = await _client.Api.LobbiesQuickJoin(new JObject
            {
                ["title"] = "Quick Start",
                ["max_users"] = 4,
            });
            _busy = false;
            if (!reply.Ok)
            {
                Print("quick join failed: " + reply.Error);
                return;
            }
            var lobby = reply.As<Models.Lobby>();
            _lobbyId = lobby.Id;
            Print("in lobby " + lobby.Title + " (" + lobby.Id + ")");
            var joined = await _client.Realtime.JoinLobby(lobby.Id);
            Print(joined.Ok ? "listening to the lobby" : "could not listen: " + joined.Error);
        }

        private async void Leave()
        {
            _busy = true;
            await _client.Realtime.Leave("lobby:" + _lobbyId);
            var reply = await _client.Api.LobbiesLeaveLobby();
            _busy = false;
            Print(reply.Ok ? "left the lobby" : "leave failed: " + reply.Error);
            if (reply.Ok) _lobbyId = "";
        }

        private void OnGUI()
        {
            GUILayout.BeginArea(new Rect(16, 16, Mathf.Min(560, Screen.width - 32), Screen.height - 32));
            GUILayout.Label("Gamend Quick Start");
            GUI.enabled = !_busy && _client != null && _client.Auth.SignedIn;
            if (_lobbyId.Length == 0)
            {
                if (GUILayout.Button("Quick join a lobby")) QuickJoin();
            }
            else if (GUILayout.Button("Leave the lobby"))
            {
                Leave();
            }
            GUI.enabled = true;
            foreach (var line in _lines) GUILayout.Label(line);
            GUILayout.EndArea();
        }

        private void Print(string line)
        {
            Debug.Log("[Quick Start] " + line);
            _lines.Add(line);
            if (_lines.Count > MaxLines) _lines.RemoveAt(0);
        }

        // One id per install, so a second Play signs in to the same account.
        private static string DeviceId()
        {
            var id = PlayerPrefs.GetString(DeviceKey, "");
            if (id.Length > 0) return id;
            id = Guid.NewGuid().ToString("N");
            PlayerPrefs.SetString(DeviceKey, id);
            PlayerPrefs.Save();
            return id;
        }
    }
}
