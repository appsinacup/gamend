defmodule GamendWeb.SwaggerHTML do
  use GamendWeb, :html

  def index(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Gamend API Documentation</title>
        <link
          rel="stylesheet"
          href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.5/swagger-ui.css"
        />
        <style>
          body { background-color: white !important; color: black !important; margin: 0; }
          .swagger-ui { background-color: white !important; }
          .sdk-bar {
            background: #1e293b;
            color: #f8fafc;
            padding: 12px 24px;
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 8px 16px;
            font-family: system-ui, -apple-system, sans-serif;
            font-size: 14px;
          }
          .sdk-bar span { font-weight: 600; }
          .sdk-bar a {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 14px;
            border-radius: 6px;
            text-decoration: none;
            font-weight: 700;
            font-size: 13px;
            transition: background 0.15s;
          }
          .sdk-bar a.js-sdk { background: #f7df1e; color: #1e293b; }
          .sdk-bar a.js-sdk:hover { background: #e5cd00; }
          .sdk-bar a.godot-sdk { background: #478cbf; color: #fff; }
          .sdk-bar a.godot-sdk:hover { background: #3a7aab; }
          .sdk-bar a.cpp-sdk { background: #00599c; color: #fff; }
          .sdk-bar a.cpp-sdk:hover { background: #004482; }
          .sdk-bar a.unity-sdk { background: #f8fafc; color: #1e293b; }
          .sdk-bar a.unity-sdk:hover { background: #e2e8f0; }
          .sdk-bar a.unreal-sdk { background: #0f0f0f; color: #fff; box-shadow: inset 0 0 0 1px #64748b; }
          .sdk-bar a.unreal-sdk:hover { background: #262626; }
          .sdk-bar a.csharp-sdk { background: #68217a; color: #fff; }
          .sdk-bar a.csharp-sdk:hover { background: #561b65; }
          .sdk-bar a.rust-sdk { background: #b7410e; color: #fff; }
          .sdk-bar a.rust-sdk:hover { background: #99360b; }
          .sdk-bar a svg { width: 16px; height: 16px; }
        </style>
      </head>
      <body>
        <div class="sdk-bar">
          <span>SDKs:</span>
          <a
            href="https://www.npmjs.com/package/@ughuuu/gamend"
            target="_blank"
            rel="noopener"
            class="js-sdk"
          >
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M0 0v24h24V0H0zm6.672 20.4H3.6V6.6h3.072v13.8zm6.528 0H10.2V6.6h6.6v10.2h-3.6v3.6zm7.2 0h-3.072V6.6H20.4v13.8zM13.8 9.672v4.128h-3.6V9.672h3.6z" />
            </svg>
            JS SDK
          </a>
          <a
            href="https://godotengine.org/asset-library/asset/4510"
            target="_blank"
            rel="noopener"
            class="godot-sdk"
          >
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
            </svg>
            Godot SDK
          </a>
          <a
            :for={{slug, label, icon} <- guide_sdks()}
            href={"https://gamend.org/docs/" <> slug}
            target="_blank"
            rel="noopener"
            class={slug}
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d={icon} />
            </svg>
            {label}
          </a>
        </div>
        <div id="swagger-ui"></div>
        <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.5/swagger-ui-bundle.js">
        </script>
        <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.5/swagger-ui-standalone-preset.js">
        </script>
        <script>
          window.onload = function() {
            window.ui = SwaggerUIBundle({
              url: "/api/openapi",
              dom_id: '#swagger-ui',
              presets: [
                SwaggerUIBundle.presets.apis,
                SwaggerUIStandalonePreset
              ],
              layout: "StandaloneLayout",
              theme: "default"
            });
          };
        </script>
      </body>
    </html>
    """
  end

  # The SDKs whose guide is their home: {guide slug, also its class; label; icon path}.
  defp guide_sdks do
    [
      {"unity-sdk", "Unity SDK", "M12 2l9 5v10l-9 5-9-5V7l9-5zM3 7l9 5 9-5M12 12v10"},
      {"unreal-sdk", "Unreal plugin",
       "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM8 7v6a4 4 0 0 0 8 0V7"},
      {"cpp-sdk", "C++ SDK", "M8 6l-6 6 6 6M16 6l6 6-6 6"},
      {"csharp-sdk", "C# SDK", "M10 3L8 21M16 3l-2 18M4 9h17M3 15h17"},
      {"rust-sdk", "Rust SDK",
       "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM9 17V7h4a3 3 0 0 1 0 6H9m4 0l3 4"}
    ]
  end
end
