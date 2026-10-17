// Separate esbuild entry: the 3.6MB mermaid bundle is only loaded on demand
// by the MermaidDiagram hook (admin runtime page), never as part of app.js.
//
// The vendored file is mermaid's dist/mermaid.min.js with one line changed:
// its last line reads `__esbuild_esm_mermaid_nm` directly, not through
// `globalThis`, because bundled here that `var` is module-scoped and
// `globalThis.__esbuild_esm_mermaid_nm` is undefined. Re-apply it on update.
import "../vendor/mermaid.min.js"
