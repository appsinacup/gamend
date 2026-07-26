// A broken avatar has to fall back to the generic person icon, and the obvious
// way to do that — an `onerror` attribute on the <img> — is an inline event
// handler, which this app's Content-Security-Policy blocks (`script-src` has no
// `unsafe-inline`). The handler silently never ran, so a provider avatar that
// 404s, expires or rate-limits left a broken-image glyph on the page.
//
// One delegated listener instead. `error` does not bubble, so it is registered
// in the capture phase; images that already failed before this script ran are
// swept once at startup.
const MARKER = "data-avatar-fallback"

function showFallback(img) {
  if (!img.hasAttribute(MARKER) || img.dataset.avatarFallbackDone) return
  img.dataset.avatarFallbackDone = "1"
  img.classList.add("hidden")
  img.nextElementSibling?.classList.remove("hidden")
}

export function startAvatarFallback() {
  document.addEventListener(
    "error",
    (event) => {
      const target = event.target
      if (target instanceof HTMLImageElement) showFallback(target)
    },
    true
  )

  // `complete` with no intrinsic width means the load already failed.
  const sweep = () =>
    document
      .querySelectorAll(`img[${MARKER}]`)
      .forEach((img) => img.complete && img.naturalWidth === 0 && showFallback(img))

  sweep()
  window.addEventListener("phx:page-loading-stop", sweep)
}
