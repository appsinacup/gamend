# Server hooks, in GDScript. `gamend plugin.bundle` compiles this folder into a
# plugin; restart the server (or Admin -> Config -> Reload plugins) to load it.
#
# A func named after a hook runs on that event; any other func is an RPC a game
# client can call. Guide: /docs/gdscript-hooks

func after_user_register(user):
	KV.put("hello_last_player", {"username": user.username})

func hello(name):
	if name == "":
		return "Hello!"
	return "Hello, " + name + "!"
