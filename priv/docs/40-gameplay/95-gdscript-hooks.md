---
icon: hero-code-bracket
---

# GDScript hooks

Write server hooks in GDScript instead of Elixir. The script is **compiled** to
Elixir source and then to BEAM bytecode, so it runs at the same speed as a
hand-written plugin: there is no interpreter, no bridge and no Godot on the
server.

```sh
mix gamend.gdscript.new my_game
cd my_game && mix deps.get && mix bundle
```

Copy the directory into your plugin directory and restart. That is the whole
setup; everything below is detail.

## What a hook looks like

```gdscript
func after_user_register(user):
	var bonus = 100
	var tier = "standard"

	if user.metadata:
		bonus += 50
		tier = "referred"

	Economy.grant(user.id, "gold", bonus, opts({"reason": "welcome"}))
	Notifications.admin_create_notification(user.id, user.id, {
		"title": "Welcome!",
		"content": "You start with " + str(bonus) + " gold.",
		"metadata": {"type": "my_game_welcome", "tier": tier},
	})
```

Every callback in the [`Gamend.Hooks`](https://docs.gamend.org/Gamend.Hooks.html)
list works. Write a `func` with the callback's name. Any other `func` is
callable as an RPC.

## Calling gamend

`Context.function(...)` becomes `Gamend.Context.function(...)`. The context list
is generated from the SDK, so anything an Elixir plugin can call, a script can
call. A typo, an unknown function or a wrong argument count is a **compile
error naming the line**:

```
my_game.gd:7: `Economy.grant` takes 3 or 4 argument(s), called with 2
my_game.gd:9: `Economy` has no function `grnt` -- did you mean `grant`?
```

### `opts({...})` for keyword arguments

Many functions take options such as `reason` and `idempotency_key`. GDScript has no
syntax for those, and they cannot be inferred: a trailing Dictionary is often a
real payload (the notification above). So they are spelled explicitly:

```gdscript
Economy.grant(user.id, "gold", 100, opts({"reason": "welcome"}))
Inventory.grant_item(user.id, "potion", 1, opts({"idempotency_key": "quest:" + quest_id}))
```

A Dictionary *without* `opts()` stays a map.

## What is supported

| Works | Rejected at compile time |
|---|---|
| `func`, default arguments, `return` | `class_name`, `extends`, inner classes |
| `var`, `const`, `=` `+=` `-=` `*=` `/=` `%=` | `signal` (use `Realtime.push_to_user`) |
| `if` / `elif` / `else`, `match` (incl. `[a, b]` and `{"k": v}` patterns) | `Node`, `Resource`, any other engine type |
| ternary (`x if c else y`), `is`, `as`, `assert()` | `preload`, `load`, `@onready`, `@tool` |
| `for`, `while`, `break`, `continue`, `range()` | `_ready`, `_process` — there is no frame loop |
| lambdas, `spawn()`, `await`, `signal` / `.emit()` | `Thread`, `WorkerThreadPool` |
| inner `class` with `extends`, `Foo.new(...)` | `set` / `get` property accessors |
| `Context.callv(name, args)` | |
| `const` and `enum` at the top level, `static func` | a top-level `var` (no instance to hold it) |
| `Array`, `Dictionary` (**by reference**), `Vector2`, `Vector3`, `Color` | |
| `d[k] = v`, `d[k] += 1`, `xs[i] = v` | `d.key = v` — use `d["key"] = v` |
| methods — see below | |
| `and` / `or` / `not`, comparisons, arithmetic, `%` formatting | |
| single-line bodies (`if ready: return true`) | |
| type hints and typed arrays (parsed, not enforced) | |
| `str`, `len`, `print`, `abs`, `min`, `max`, `floor`, `ceil`, `round`, `typeof` | |

Nothing is silently approximated. If a construct is not translated exactly, the
compiler refuses it with a file and line.

## `match`

```gdscript
match reward.kind:
	"gold", "gems":
		Economy.grant(user_id, reward.kind, reward.amount, opts({"reason": "quest"}))
	"item":
		Inventory.grant_item(user_id, reward.code, 1, opts({"reason": "quest"}))
	var unknown:
		print("unhandled reward: " + unknown)
```

Patterns are literals, `var name` to bind, `_` to catch everything, and
comma-separated alternatives. Array and dictionary patterns are not supported.
As in Godot, a `match` that matches nothing simply does nothing.

## Lambdas, `spawn()` and `await`

```gdscript
var double = func(x): return x * 2
print(double.call(4))
```

A lambda captures by value, exactly as in Godot. The multi-line form works when
it is assigned to a variable; inside brackets only the single-expression form
fits, because everything between `(` and `)` is one logical line.

### `spawn()` is a server extension, not GDScript

Godot has no `spawn`. There, `await` waits on a **signal** or on a coroutine,
and nothing emits signals on the server, so `await` would have nothing to wait
for on its own. `spawn()` is what gives it something: it runs a lambda
concurrently, and `await` collects the result. Two independent lookups then
cost one round trip instead of two:

```gdscript
var gold = spawn(func(): return Economy.balance(user_id, "gold"))
var items = spawn(func(): return Inventory.count_items(user_id))
return {"gold": await gold, "items": await items}
```

This is one place the server beats the engine: a suspended task is a BEAM
process, so thousands can be in flight at once, where Godot needs `Thread` or
`WorkerThreadPool` for the same thing. Two caveats: a spawned lambda does
**not** inherit the hook's caller, so `Hooks.caller_user()` inside one returns
nothing, and `await` gives up after 30 seconds.

## Value types

`Vector2`, `Vector3` and `Color` are constructed like functions and are plain
Dictionaries underneath, so `v.x` reads a component and storing one gives the
obvious `{"x": 1, "y": 2}` JSON:

```gdscript
var offset = Vector2(1, 2) + Vector2(3, 4)   # {"x": 4, "y": 6}
var doubled = offset * 2                      # {"x": 8, "y": 12}
```

`+`, `-` and `*` work component-wise (and scale by a number). There is no
`v[0]` and no other engine method: these are data, not the engine's types.

## More than one script

A script that names itself is reachable from every other script in the plugin,
exactly as in Godot:

```gdscript
# rewards.gd
class_name Rewards

func starter_gold(referred):
	return 150 if referred else 100
```

```gdscript
# my_game.gd
func after_user_register(user):
	var bonus = Rewards.starter_gold(user.metadata)
	Economy.grant(user.id, "gold", bonus, opts({"reason": "welcome"}))
```

All of `scripts/*.gd` compile together, so a wrong name or argument count
across files is a compile error like any other. A script *without*
`class_name` is private to itself.

Arrays and Dictionaries stay references across a script boundary, so a callee in
another script mutates the caller's collection, as it would in Godot. One
consequence: if any script mutates in place, every script in the plugin
compiles in reference mode. The boundary is still crossed only where gamend
calls in, not on each cross-script call.

## Built-in functions

The `@GlobalScope` functions that mean something without an engine:

| | |
|---|---|
| Arithmetic | `abs` `absf` `absi` `sqrt` `cbrt` `pow` `log` `exp` `fmod` `fposmod` `posmod` `sign` `signf` `signi` `floor` `ceil` `round` (and the `f`/`i` variants) `snapped` `nearest_po2` `wrapi` `wrapf` |
| Trigonometry | `sin` `cos` `tan` `asin` `acos` `atan` `atan2` `sinh` `cosh` `tanh` `deg_to_rad` `rad_to_deg` |
| Interpolation | `lerp` `lerp_angle` `inverse_lerp` `remap` `move_toward` `ease` `pingpong` |
| Comparison | `clamp` `clampi` `min` `max` `is_equal_approx` `is_zero_approx` `is_finite` `is_inf` `is_nan` `is_same` |
| Randomness | `randi` `randf` `randi_range` `randf_range` `randfn` `seed` `randomize` |
| Output | `print` `printraw` `prints` `printt` `printerr` `print_verbose` `push_error` `push_warning` |
| Other | `str` `len` `range` `typeof` `int` `float` `hash` `assert` |

`min`, `max`, `str` and the whole `print` family take any number of arguments,
as in Godot, so `print("score: ", score)` reads the way you would write it, and
`prints` joins with spaces where `printt` joins with tabs. `print` and
`printraw` go to stdout; `printerr` and `push_error` log at error level,
`push_warning` at warning, `print_verbose` at debug.

`range()` returns an Array, so it can be held, indexed and mapped rather than
only walked:

```gdscript
for i in range(0, 10, 2):     # 0 2 4 6 8, and a negative step counts down
	pass

var indexes = range(3)
indexes.size()                # 3
indexes.map(func(i): return i * i)
```

Anything else is a compile error naming the line: `clamp(a, b)` says `clamp`
takes 3 arguments rather than failing somewhere in the generated Elixir.

## JSON and Time

```gdscript
var text = JSON.stringify({"score": 10})     # {"score":10}
var back = JSON.parse_string(text)           # null if it will not parse

var now = Time.get_unix_time_from_system()
var parts = Time.get_datetime_dict_from_unix_time(now)   # year, month, day, …
```

Also `Time.get_ticks_msec()`, `get_ticks_usec()`,
`get_datetime_string_from_unix_time()` and `get_unix_time_from_datetime_string()`.

## Vectors

`Vector2`, `Vector3` and `Color` carry their methods:

```gdscript
var here = Vector2(3.0, 4.0)
here.length()                 # 5.0
here.distance_to(target)
here.normalized()
here.direction_to(target)
```

`length` `length_squared` `distance_to` `distance_squared_to` `normalized`
`is_normalized` `limit_length` `dot` `cross` `angle` `angle_to`
`angle_to_point` `direction_to` `rotated` `orthogonal` `lerp` `clamp`
`snapped` `move_toward` `abs` `sign` `floor` `ceil` `round`
`is_equal_approx` `is_zero_approx`.

`cross` gives a scalar on a Vector2 and a vector on a Vector3, as in Godot, and
`length()` still counts characters when the receiver is a String.

## Methods

Taken from the Godot class reference, including the optional arguments and
their defaults.

| On | Methods |
|---|---|
| Array | `all` `any` `append` `append_array` `back` `clear` `count` `duplicate` `erase` `fill` `filter` `find` `find_custom` `front` `get` `has` `insert` `is_empty` `map` `max` `min` `pick_random` `pop_at` `pop_back` `pop_front` `push_back` `push_front` `reduce` `remove_at` `resize` `reverse` `rfind` `rfind_custom` `set` `shuffle` `size` `slice` `sort` `sort_custom` |
| Dictionary | `clear` `duplicate` `erase` `find_key` `get` `get_or_add` `has` `has_all` `is_empty` `keys` `merge` `merged` `set` `size` `values` |
| String | `begins_with` `capitalize` `contains` `containsn` `count` `dedent` `ends_with` `erase` `find` `indent` `insert` `is_empty` `is_valid_float` `is_valid_int` `join` `left` `length` `lpad` `lstrip` `md5_text` `pad_zeros` `repeat` `replace` `replacen` `reverse` `rfind` `right` `rpad` `rsplit` `rstrip` `sha256_text` `similarity` `slice` `split` `strip_edges` `substr` `to_camel_case` `to_float` `to_int` `to_kebab_case` `to_lower` `to_pascal_case` `to_snake_case` `to_upper` `trim_prefix` `trim_suffix` `uri_decode` `uri_encode` |

The higher-order ones take a lambda, as in Godot. Note that `reduce` hands the
callable `(accumulator, element)`:

```gdscript
var doubled = xs.map(func(x): return x * 2)
var total   = xs.reduce(func(acc, x): return acc + x, 0)
xs.sort_custom(func(a, b): return a > b)
```

The receiver's type is checked at run time, so `size()` works on all three and
`erase` means three different things. `to_int()` and `to_float()` return `0`
for anything unparseable rather than raising, as in Godot. An unknown method is
a compile error with a suggestion:

```
my_game.gd:4: unknown method `.bnd()` -- did you mean `find`?
```

Not carried over, and refused rather than approximated: the deep form of
`duplicate` and `slice` (it would have to rebuild every nested collection), the
typed-array machinery (`is_typed`, `make_read_only`, …), the path and buffer
families (`get_base_dir`, `to_utf8_buffer`, …) and the static constructors
(`String.chr`, `String.num`).

Two smaller things: `has` on an Array of nested collections compares by
reference rather than contents, and a Dictionary does **not** preserve
insertion order here, so `keys()` and iteration come back in an arbitrary order,
unlike Godot.

## Classes

An inner class groups data with the functions that work on it:

```gdscript
class Reward:
	var kind = "gold"
	var amount = 0

	func _init(k, a):
		kind = k
		amount = a

	func describe():
		return "%s x%d" % [kind, amount]

class BonusReward extends Reward:
	func describe():
		return "bonus " + kind

func summary():
	var r = Reward.new("gems", 3)
	return r.describe()          # "gems x3"
```

Inside a method a bare name is a field unless a parameter or local shadows it,
exactly as in Godot. `extends` inherits fields, `_init` and methods, and an
override wins. An instance is a Dictionary underneath, so returning one hands
gamend plain data.

`class_name` is accepted at the top level and dropped: the module is the
class, and its name comes from the file.

## Calling by name

`Context.callv(name, args)` resolves the name at run time, against the same
table the compiler checks against, so a name outside it raises rather than
reaching an arbitrary function:

```gdscript
Economy.callv(which, [user_id, "gold", 5])
```

The trade is that a typo becomes a run-time error instead of a build one, so
prefer the direct form where you can.

## Signals

A `signal` declared anywhere in a plugin can be emitted from one hook and
awaited in another:

```gdscript
signal level_up(user_id, level)

func after_score_submitted(score):
	if score.value > 1000:
		level_up.emit(score.user_id, 5)

func watch():
	var payload = await level_up      # ["user-1", 5], or null after 30s
```

Signals are scoped to the plugin, so two plugins may use the same name without
hearing each other, and they ride the server's pub/sub, so an emit reaches
every node in a cluster. `await` **subscribes at function entry**, not where
the `await` sits, so a signal emitted in between is not missed.

A signal with no listener is dropped, as in Godot. `Gamend.Signals` is a normal
context, so Elixir plugins can join in.

## Constants and enums

```gdscript
const MAX_PLAYERS = 4
enum Tier { BRONZE, SILVER = 10, GOLD }
enum { RED, GREEN, BLUE }
```

Both fold into the code that uses them, so they cost nothing at run time. A
`const` must be a number, string, boolean or null. Return a collection from a
`func` instead. A top-level `var` is refused: it is per-instance state in
Godot, and the server has no instance to hold it.

## Arrays and Dictionaries are references, as in Godot

A function mutates its caller's collection, two names can point at the same
one, and `+` makes a new one, all exactly as in the engine:

```gdscript
func bump(counts, key):
	if counts.has(key):
		counts[key] += 1
	else:
		counts[key] = 1

func tally(items):
	var counts = {}
	for item in items:
		bump(counts, item)      # mutates `counts` itself
	return counts
```

Collections live on a small heap belonging to the hook's own process, so one
hook can never see another's, and nothing has to be freed: it dies with the
call. A script that never mutates a collection in place compiles with no heap
at all and pays nothing.

Two limits worth knowing:

- A `spawn()`ed lambda runs in its own process and sees a **snapshot**.
  Mutations inside it do not travel back.
- Assigning to a field (`d.key = v`) is a compile error; write `d["key"] = v`.

## What is not here

Nothing below exists, and a script using it gets a compile error rather than a
surprise:

- **Types**: `Vector2i` `Vector3i` `Vector4` `Vector4i` `Rect2` `Rect2i`
  `Transform2D` `Transform3D` `Basis` `Quaternion` `Plane` `AABB`. Only
  `Vector2`, `Vector3` and `Color` are carried.
- **Classes**: `RegEx`, `RandomNumberGenerator` (the global `randi`/`randf`
  cover most of it), `Marshalls`, `var_to_str` / `str_to_var`.
- **Aliases**: `StringName` and the `Packed*Array` family. A `split()` returns
  a plain Array, and type hints are discarded anyway.
- **Everything engine-side**: `Node` `Resource` `Object` `Input` `Engine` `OS`
  `ProjectSettings`, physics, rendering, and the servers.
- **Everything the BEAM does differently**: `Thread` `Mutex` `Semaphore`
  `WorkerThreadPool`: use `spawn()` / `await`.

## Performance

A hook compiled from GDScript runs about **2-3x** a hand-written Elixir one,
which is a few hundred nanoseconds against a Task the server spends ~3
microseconds spawning. For a hook that reads a payload, decides something and
calls gamend, the language you wrote it in does not show up in a profile.

Two things do:

- **`xs.append(v)` in a loop copies the Array each time.** In Godot an Array is
  contiguous and that is amortised O(1); on the BEAM it is O(n), so a thousand appends is a
  million operations, the same cost hand-written Elixir would pay for the
  same algorithm. Under a few hundred elements it does not matter. Above that,
  build the Array with `map` or `filter` instead:

  ```gdscript
  var doubled = range(1000).map(func(i): return i * 2)
  ```

  `map`, `filter` and `reduce` go straight to `Enum.map` / `Enum.filter` /
  `Enum.reduce` under the hood, so this really is O(n), not a smaller
  constant on the same O(n²). Godot's other fast-array idiom does **not**
  carry over: `xs.resize(n)` followed by `xs[i] = v` in a loop is O(1) per
  write in Godot because its Array is contiguous, but indexed assignment here
  goes through the same per-element list cost as `append`, so `resize` will not
  rescue a loop that `append` is slow in.

- **Creating an Array or Dictionary costs ~250ns in reference mode**, which a
  plugin is in as soon as any script mutates a collection in place. A hook
  that builds ten small Dictionaries pays a few microseconds for it. A hook
  that only reads pays nothing: the boundary itself measures 1.0-1.1x.

`sdk_tools/bench/hook_bench.exs` is the benchmark, if you want to measure your
own.

## Differences from GDScript in Godot

The parts of GDScript that disagree with Elixir are preserved, not quietly
changed: `+` still concatenates strings, `5 / 2` is still `2`, and `0`, `""`
and `[]` are still falsy. What differs:

- **There is no engine.** No nodes, no scenes, no physics, no frame loop. A
  hook runs when the server calls it.

## Layout and debugging

```
my_game/
  scripts/my_game.gd    ← you write this
  gen/                  ← generated Elixir, committed
  ebin/                 ← mix bundle output
```

`gen/` is committed on purpose: it is ordinary, formatted Elixir, it is what
stack traces name, and reading its diff is how you see what a script change
actually did. `mix gamend.gdscript.compile --check` fails when it is stale.

Rebuild with `mix bundle` after every script change, since the server loads the
bundled `ebin/`, not your source.
