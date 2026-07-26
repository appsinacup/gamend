// Theme switcher & card collapse/expand — imported by app.js
// Manages data-theme attribute, localStorage persistence, and system preference listening.

const getSystemTheme = () =>
  window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

const syncThemeChrome = (theme) => {
  const actualTheme = theme === "system" ? getSystemTheme() : theme;
  const themeColorMeta = document.querySelector('meta[name="theme-color"]');

  if (themeColorMeta) {
    const lightColor = themeColorMeta.dataset.lightColor || themeColorMeta.content;
    const darkColor = themeColorMeta.dataset.darkColor || lightColor;

    themeColorMeta.setAttribute(
      "content",
      actualTheme === "dark" ? darkColor : lightColor
    );
  }

  const colorSchemeMeta = document.querySelector('meta[name="color-scheme"]');

  if (colorSchemeMeta) {
    colorSchemeMeta.setAttribute("content", actualTheme);
  }
};

const setTheme = (theme) => {
  const actualTheme = theme === "system" ? getSystemTheme() : theme;
  if (theme !== "system") {
    localStorage.setItem("phx:theme", theme);
  } else {
    localStorage.removeItem("phx:theme");
  }
  document.documentElement.setAttribute("data-theme", actualTheme);
  syncThemeChrome(actualTheme);
  // Sync a cookie so the server can render data-theme on full page loads
  document.cookie =
    "phx_theme=" + actualTheme + "; path=/; max-age=31536000; SameSite=Lax";
};

// Set initial theme — default to system preference if no stored preference
const storedTheme = localStorage.getItem("phx:theme");
setTheme(storedTheme || "system");

// Listen for system theme changes (only if no explicit preference is set)
window
  .matchMedia("(prefers-color-scheme: dark)")
  .addEventListener("change", () => {
    if (!localStorage.getItem("phx:theme")) {
      setTheme("system");
    }
  });

window.addEventListener("phx:set-theme", (e) => {
  // Find the button with data-phx-theme attribute (could be the target or its parent)
  const button = e.target.closest("[data-phx-theme]");
  if (button) {
    setTheme(button.dataset.phxTheme);
  }
});

// ---------------------------------------------------------------------------
// Docs deep links
// ---------------------------------------------------------------------------
// The canonical form is /docs/setup?guide=payments, which the server renders
// and can restore after a reconnect. This only upgrades older #fragment links:
// opening the section fires `toggle`, and the GuideDisclosure hook rewrites the
// URL to the query form from there.

const openAnchoredDetails = () => {
  const hash = window.location.hash;
  if (!hash) return;

  const target = document.getElementById(hash.slice(1));
  if (!(target instanceof HTMLDetailsElement)) return;

  target.open = true;
  // Offset so the summary clears the sticky navbar.
  const y = target.getBoundingClientRect().top + window.pageYOffset - 80;
  window.scrollTo({ top: y, behavior: "smooth" });
};

window.addEventListener("load", openAnchoredDetails);
window.addEventListener("hashchange", openAnchoredDetails);
window.addEventListener("phx:page-loading-stop", openAnchoredDetails);
