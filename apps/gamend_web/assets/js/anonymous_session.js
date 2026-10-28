// The anonymous account a page made for a signed-out visitor
// (`GamendWeb.UserAuth.ensure_user/1`) arrives as `phx:gamend:anonymous_session`
// with an encrypted session token. A LiveView cannot write the session cookie,
// so this posts the token to `/users/anonymous_session`, which can, and then
// reconnects the socket: the socket read the session when it connected, and
// until it reconnects every page it mounts would still see a signed-out
// visitor and make a second account.
//
// With `notice`, the page that mounts on the reconnect says "Guest account
// created": a flash put before it would go with the old mount, so the
// reconnect's connect params carry `_guest_created` once
// (`guestNoticeParams/1`, `UserAuth`'s `put_live_guest_notice/1`).
export const ANONYMOUS_SESSION_PATH = "/users/anonymous_session"

let guestNotice = false

export function startAnonymousSession({getLiveSocket, fetchImpl} = {}) {
  window.addEventListener("phx:gamend:anonymous_session", (event) => {
    const token = event?.detail?.token
    if (typeof token !== "string" || token === "") return
    return stampAnonymousSession(token, {getLiveSocket, fetchImpl, notice: event.detail.notice === true})
  })
}

// The connect params of the page LiveView `el` joins: `_guest_created` on the
// main view's first join after a guest account was made, then never again.
export function guestNoticeParams(el) {
  if (!guestNotice || !el?.hasAttribute?.("data-phx-main")) return {}
  guestNotice = false
  return {_guest_created: "1"}
}

export async function stampAnonymousSession(token, {getLiveSocket, fetchImpl, notice = false} = {}) {
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
    if (liveSocket) {
      guestNotice = notice
      liveSocket.disconnect(() => liveSocket.connect())
    }
    return true
  } catch (_error) {
    // Nothing lost: this page already holds the account, and the next page
    // the visitor saves something on makes another one.
    return false
  }
}
