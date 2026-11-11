using Newtonsoft.Json.Linq;

namespace Gamend
{
    /// <summary>A signed-in identity: the token pair and who it belongs to.</summary>
    public sealed class Session
    {
        public string AccessToken { get; set; } = "";
        public string RefreshToken { get; set; } = "";
        public string UserId { get; set; } = "";
        /// <summary>Empty when the sign-in did not say (OAuth).</summary>
        public string Username { get; set; } = "";
        public string DisplayName { get; set; } = "";
        /// <summary>The access token's lifetime in seconds, as the server said (900 by default).</summary>
        public long ExpiresIn { get; set; }
        /// <summary>When the access token lapses, in Unix seconds; 0 when unknown.</summary>
        public long ExpiresAt { get; set; }

        /// <summary>For keeping it where the platform keeps secrets, and `FromJson` back.</summary>
        public JObject ToJson()
        {
            return new JObject
            {
                ["access_token"] = AccessToken,
                ["refresh_token"] = RefreshToken,
                ["user_id"] = UserId,
                ["username"] = Username,
                ["display_name"] = DisplayName,
                ["expires_in"] = ExpiresIn,
                ["expires_at"] = ExpiresAt,
            };
        }

        /// <summary>A session from `ToJson`'s output or a sign-in reply's `data`; null when there
        /// is no `access_token`. `now` (Unix seconds) turns a reply's `expires_in` into `ExpiresAt`
        /// when the value carries no `expires_at`.</summary>
        public static Session FromJson(JToken value, long now = 0)
        {
            var token = Json.Text(value, "access_token");
            if (token.Length == 0) return null;
            var session = new Session
            {
                AccessToken = token,
                RefreshToken = Json.Text(value, "refresh_token"),
                UserId = Json.Text(value, "user_id"),
                Username = Json.Text(value, "username"),
                DisplayName = Json.Text(value, "display_name"),
                ExpiresIn = Json.Number(value, "expires_in"),
                ExpiresAt = Json.Number(value, "expires_at"),
            };
            if (session.ExpiresAt == 0 && session.ExpiresIn > 0 && now > 0)
            {
                session.ExpiresAt = now + session.ExpiresIn;
            }
            return session;
        }

        internal Session Copy()
        {
            return new Session
            {
                AccessToken = AccessToken,
                RefreshToken = RefreshToken,
                UserId = UserId,
                Username = Username,
                DisplayName = DisplayName,
                ExpiresIn = ExpiresIn,
                ExpiresAt = ExpiresAt,
            };
        }
    }
}
