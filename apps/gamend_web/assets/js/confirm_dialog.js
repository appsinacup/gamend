// `data-confirm` asks in the page's own popup (`#gamend-confirm`, the root
// layout), never the browser's alert. A bare `data-confirm` asks the popup's
// own sentence; a value replaces it where the button cannot say the rest.
//
// phoenix_html fires `phoenix.link.click` on the clicked element and each
// ancestor, and its own listener, on `window`, calls `window.confirm`. Stopping
// the event here keeps it from there; cancelling it stops the click, before
// LiveView or a form sees it. A yes clicks the element again, let through.
//
// Answers `ask(text, onYes)`, the same popup for whatever else must ask
// (`unsaved_changes.js`), or null on a page without it.
export function startConfirmDialog(doc = document) {
  const dialog = doc.getElementById("gamend-confirm")
  if (!dialog) return null

  const message = dialog.querySelector("[data-confirm-message]")
  const sentence = message.textContent.trim()
  let onYes = null
  let approved = null

  const ask = (text, yes) => {
    onYes = yes
    message.textContent = text || sentence
    dialog.returnValue = ""
    dialog.showModal()
  }

  doc.addEventListener("phoenix.link.click", (event) => {
    const element = event.target
    if (!element.hasAttribute?.("data-confirm")) return

    event.stopPropagation()
    if (element === approved) return

    event.preventDefault()
    ask(element.getAttribute("data-confirm"), () => {
      // The page may have drawn the button away meanwhile (a round's clock ran out).
      if (!element.isConnected) return

      approved = element
      element.click()
      approved = null
    })
  })

  // The dialog has no padding of its own, so a click reporting the dialog
  // itself landed on the backdrop.
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dialog.close()
  })

  dialog.addEventListener("close", () => {
    const yes = onYes
    onYes = null
    if (dialog.returnValue === "confirm") yes?.()
  })

  return ask
}
