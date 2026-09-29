# sdk_tools (gamend_plugin_tools)

Internal helper Mix tasks shared by plugin projects.

Currently provides:
- `mix plugin.bundle`
- `mix gamend.gdscript.new` and `mix gamend.gdscript.compile`, over the GDScript
  transpiler `Gamend.GDScript`

The Gamend host also depends on this package at runtime, so a release (which has
no Mix) ships `Gamend.GDScript` and can build a GDScript plugin in-process. The
Mix tasks compile into the release too; nothing calls them there.
