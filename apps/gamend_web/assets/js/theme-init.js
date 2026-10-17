// Theme initializer — runs synchronously before CSS to prevent FOUC.
// This file is a separate esbuild entry point loaded without `defer`.
(function () {
  // A signed-in reader's saved theme (`GamendWeb.Plugs.ColorMode`) is the
  // browser's from now on.
  var saved = document.documentElement.getAttribute("data-theme-saved");
  if (saved === "dark" || saved === "light") localStorage.setItem("phx:theme", saved);
  var t = localStorage.getItem("phx:theme");
  var d =
    t ||
    (window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light");

  var themeColorMeta = document.querySelector('meta[name="theme-color"]');
  if (themeColorMeta) {
    var lightColor = themeColorMeta.dataset.lightColor || themeColorMeta.content;
    var darkColor = themeColorMeta.dataset.darkColor || lightColor;
    themeColorMeta.setAttribute("content", d === "dark" ? darkColor : lightColor);
  }

  var colorSchemeMeta = document.querySelector('meta[name="color-scheme"]');
  if (colorSchemeMeta) {
    colorSchemeMeta.setAttribute("content", d);
  }

  document.documentElement.setAttribute("data-theme", d);
  // Sync a cookie so the server can set data-theme on the next full page load
  document.cookie =
    "phx_theme=" + d + "; path=/; max-age=31536000; SameSite=Lax";
})();
