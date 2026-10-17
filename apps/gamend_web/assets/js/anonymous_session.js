// The anonymous account a page made for a signed-out visitor
// (`GamendWeb.UserAuth.ensure_user/1`) arrives as `phx:gamend:anonymous_session`
// with an encrypted session token. A LiveView cannot write the session cookie,
// so this posts the token to `/users/anonymous_session`, which can, and then
// reconnects the socket: the socket read the session when it connected, and
// until it reconnects every page it mounts would still see a signed-out
// visitor and make a second account.
export const ANONYMOUS_SESSION_PATH = "/users/anonymous_session"

export function startAnonymousSession({getLiveSocket, fetchImpl} = {}) {
  window.addEventListener("phx:gamend:anonymous_session", (event) => {
    const token = event?.detail?.token
    if (typeof token !== "string" || token === "") return
    return stampAnonymousSession(token, {getLiveSocket, fetchImpl})
  })
}

export async function stampAnonymousSession(token, {getLiveSocket, fetchImpl} = {}) {
  const csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
  const post = fetchImpl || ((...args) => fetch(...args))

  try {
    const response = await post(ANONYMOUS_SESSION_PATH, {
      method: "POST",
      credentials: "same-origin",
      headers: {"content-type": "application/json", "x-csrf-token": csrf},
      body: JSON.stringify({token}),
    })

    if (!response.ok) return false

    const liveSocket = getLiveSocket?.()
    if (liveSocket) liveSocket.disconnect(() => liveSocket.connect())
    return true
  } catch (_error) {
    // Nothing lost: this page already holds the account, and the next page
    // the visitor saves something on makes another one.
    return false
  }
}
