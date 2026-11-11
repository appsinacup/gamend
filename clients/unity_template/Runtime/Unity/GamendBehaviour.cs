// The Gamend client as a component. It builds the client from the inspector's
// settings, polls it every frame, and disposes of it with the object:
//
//     var client = GamendBehaviour.Instance.Client;
//     var signedIn = await client.Auth.LoginDevice(deviceId);
//     if (signedIn.Ok) client.Realtime.Connect();
//
// It runs before other scripts (DefaultExecutionOrder), so a frame's replies and
// events land before their Update, and an `await` continues on the main thread.
//
// The client is built on first use of `Client`, from `BaseUrl` and the other
// fields as they are then: a script that adds the component can set them first.
// A subclass changes anything else in `Configure`.
using UnityEngine;

namespace Gamend.Unity
{
    [DefaultExecutionOrder(-1000)]
    [DisallowMultipleComponent]
    [AddComponentMenu("Gamend/Gamend Client")]
    [HelpURL("https://gamend.org/docs/unity-sdk")]
    public class GamendBehaviour : MonoBehaviour
    {
        [Tooltip("The server root, such as https://game.example.com.")]
        [SerializeField]
        private string baseUrl = "http://localhost:4000";

        [Tooltip("How the server sends realtime events. Protobuf frames are smaller, and their timestamps arrive as unix milliseconds.")]
        [SerializeField]
        private RealtimeFormat realtimeFormat = RealtimeFormat.Json;

        [Tooltip("The lowest level of the SDK's own lines that reach the Console.")]
        [SerializeField]
        private LogLevel logLevel = LogLevel.Warning;

        [Tooltip("Keep this object, and its connection, when another scene loads. A copy in a scene loaded later removes itself.")]
        [SerializeField]
        private bool keepAcrossScenes = true;

        private Client _client;

        /// <summary>The first enabled one, or the one kept across scenes; null before any has
        /// woken.</summary>
        public static GamendBehaviour Instance { get; private set; }

        /// <summary>The client, built on first use.</summary>
        public Client Client
        {
            get
            {
                if (_client == null) _client = Build();
                return _client;
            }
        }

        /// <summary>Read when the client is built.</summary>
        public string BaseUrl
        {
            get { return baseUrl; }
            set { baseUrl = value; }
        }

        /// <summary>Read when the client is built.</summary>
        public RealtimeFormat RealtimeFormat
        {
            get { return realtimeFormat; }
            set { realtimeFormat = value; }
        }

        public LogLevel LogLevel
        {
            get { return logLevel; }
            set { logLevel = value; }
        }

        // With domain reload off (Enter Play Mode Options), statics outlive the
        // last play session.
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetInstance()
        {
            Instance = null;
        }

        protected virtual void Awake()
        {
            if (Instance != null && Instance != this && Instance.keepAcrossScenes)
            {
                // The scene that made the kept one was loaded again.
                Destroy(gameObject);
                return;
            }
            if (Instance == null) Instance = this;
            if (!keepAcrossScenes) return;
            if (transform.parent == null)
            {
                DontDestroyOnLoad(gameObject);
            }
            else
            {
                Debug.LogWarning("[Gamend] Keep Across Scenes needs the GamendBehaviour on a root object; this one goes with its scene.", this);
            }
        }

        protected virtual void Update()
        {
            if (_client != null) _client.Poll();
        }

        protected virtual void OnDestroy()
        {
            if (Instance == this) Instance = null;
            if (_client == null) return;
            _client.Dispose();
            _client = null;
        }

        /// <summary>Change the configuration before the client is built: ICE servers, timeouts,
        /// another transport.</summary>
        protected virtual void Configure(Config config)
        {
        }

        private Client Build()
        {
            var config = new Config
            {
                BaseUrl = baseUrl,
                Http = new UnityHttpTransport(),
                WebSocket = new UnityWebSocketTransport(),
                RealtimeFormat = realtimeFormat,
                OpenUrl = Application.OpenURL,
                Log = Log,
            };
            Configure(config);
            return new Client(config);
        }

        // Debug's methods are safe from any thread, which a transport's line may
        // come from.
        private void Log(LogLevel level, string line)
        {
            if (level < logLevel) return;
            switch (level)
            {
                case LogLevel.Error:
                    Debug.LogError("[Gamend] " + line);
                    break;
                case LogLevel.Warning:
                    Debug.LogWarning("[Gamend] " + line);
                    break;
                default:
                    Debug.Log("[Gamend] " + line);
                    break;
            }
        }
    }
}
