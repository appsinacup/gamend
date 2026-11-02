"""The Balaur emitter: Balaur Script over the engine's `gamend::rest`.

The Godot client goes through openapi-generator, which has no Balaur Script
target, so this writes one `.bs` module per tag. A script links one with
`use addons::gamend::lobbies;` and calls `lobbies::create_lobby(..)`; a
module inside the addon links its neighbours by name (`use core;`). A
function is named for its operation without the tag. The realtime events
are one file per channel under `events/` (`use addons::gamend::events::lobby;`,
`lobby::MEMBER_JOINED`) and `events.bs`, the table and the decoder.
`README.md` is the reference, by tag. Everything else in the addon is the
hand-written `clients/balaur_template/`, copied over the top.
"""

import json
import re

from model import CLIENTS, ROOT, Model, resolve, snake, wrap

TEMPLATE = CLIENTS / "balaur_template"
OUT = ROOT / "balaur_addons" / "addons" / "gamend"
REGENERATE = "clients/generate_balaur.sh"
# Every file in OUT is this emitter's or the template's, so a file neither
# writes any more (a tag renamed, the old `.rn` modules) is removed.
OWNS_OUT = True

# A tag whose file would read as something else.
FILE_NAMES = {"push": "push_tokens"}
# What a tag's file must not take: the template's files.
TAKEN = {"auth", "client", "core", "events", "log_sink", "logs", "prefs", "presence", "version"}

BANNER = (
    "// Written by clients/sdkgen (balaur) from the OpenAPI document.\n"
    "// Do not edit; edit the generator or the spec and run\n"
    "// clients/generate_balaur.sh.\n"
)

# Balaur Script's keywords and built-in types, which a path parameter or a
# body field could otherwise collide with when it becomes an argument name.
RESERVED = {
    "as", "async", "await", "break", "const", "continue", "else", "extern",
    "false", "fn", "for", "if", "impl", "in", "let", "loop", "mut", "nil",
    "pub", "return", "self", "struct", "true", "use", "while",
    "int", "float", "bool", "str", "any", "Node",
}


def safe(name: str) -> str:
    return f"{name}_" if name in RESERVED else name


def path_expression(op: dict, with_query: bool) -> str:
    """The path as a Balaur Script string: `{id}` interpolates `id`, which
    is the OpenAPI spelling already, and `{query}` the query string."""
    filled = re.sub(r"\{([^}]+)\}", lambda m: "{" + safe(m.group(1)) + "}", op["path"])
    tail = "{query}" if with_query else ""
    return json.dumps(filled + tail)


def file_of(op: dict) -> str:
    """The file a tag's operations go in: `Admin – KV` is `admin_kv`."""
    tag = snake(op["tag"])
    return FILE_NAMES.get(tag, tag)


def short_name(op: dict, file: str) -> str:
    """The operation without what its file already says:
    `matchmaking_join` in `matchmaking` is `join`, and `admin_list_lobbies`
    in `admin_lobbies` is `list_lobbies`."""
    name = op["id"]
    prefixes = [f"{file}_"] + (["admin_"] if file.startswith("admin_") else [])
    for prefix in prefixes:
        if name.startswith(prefix) and len(name) > len(prefix):
            name = name[len(prefix):]
            break
    return safe(name)


def emit_function(model: Model, op: dict, file: str, name: str) -> str:
    """One operation as a function over `gamend::rest`. Path parameters are
    `any`, so an id passes as a number or a string; the body and the query
    are maps."""
    args = [f"{safe(p)}: any" for p in op["path_params"]]
    required_body: list[str] = []
    if op["body"]:
        args.append("params: any")
        required_body = list(resolve(model.spec, op["body"]["schema"]).get("required", []))
    if op["query"]:
        args.append("options: any")
    called = json.dumps(f"gamend::{file}::{name}")
    out = wrap(op["summary"], 76, "///")
    out.append(f"/// `{op['method']} {op['path']}`")
    out.append(f"pub fn {name}({', '.join(args)}) -> any {{")
    # A left-out id is nil, and a path built on it asks for something else.
    for param in op["path_params"]:
        out.append(f"    if {safe(param)} == nil {{")
        out.append(f"        return core::missing({called}, {json.dumps(param)});")
        out.append("    }")
    for field in required_body:
        out.append(f"    if !core::given(params, {json.dumps(field)}) {{")
        out.append(f"        return core::missing({called}, {json.dumps(field)});")
        out.append("    }")
    if op["query"]:
        for field in [q for q, needed in op["query"] if needed]:
            out.append(f"    if !core::given(options, {json.dumps(field)}) {{")
            out.append(f"        return core::missing({called}, {json.dumps(field)});")
            out.append("    }")
        allowed = ", ".join(json.dumps(q) for q, _ in op["query"])
        out.append(f"    let query = core::query(options, [{allowed}]);")
    path = path_expression(op, bool(op["query"]))
    # A left-out body is nil, so a call with none writes none.
    body = ", params" if op["body"] else ""
    out.append(f'    gamend::rest("{op["method"]}", {path}{body})')
    out.append("}")
    return "\n".join(out)


def by_file(model: Model) -> dict[str, list[tuple[str, dict]]]:
    """Each file's operations, with the name each takes in it."""
    files: dict[str, list[tuple[str, dict]]] = {}
    for op in model.ops:
        file = file_of(op)
        if file in TAKEN:
            raise SystemExit(f"tag {op['tag']!r} would be gamend::{file}; add it to FILE_NAMES")
        name = short_name(op, file)
        taken = [n for n, _ in files.get(file, [])]
        if name in taken:
            raise SystemExit(f"gamend::{file}::{name} is wanted twice; {op['id']} is the second")
        files.setdefault(file, []).append((name, op))
    return files


def write_tags(model: Model) -> dict[str, str]:
    out = {}
    for file, ops in by_file(model).items():
        tag = ops[0][1]["tag"]
        chunks = [
            # The chunks are joined by one blank line; the banner's own end is not a second.
            BANNER.rstrip("\n"),
            f"// {tag}: one function per operation, `{file}::<name>` once a\n"
            f"// script says `use addons::gamend::{file};`.\n"
            "//\n"
            "// A call takes the path's own parameters, then `params` for the request\n"
            "// body and `options` for the query where the operation has them; either\n"
            "// may be left out when the call has nothing to put in it. It answers the\n"
            "// id `gamend::rest` answers, to await with `task::wait`. With a path\n"
            "// parameter or a required field left out it sends nothing, logs which,\n"
            "// and answers nil.\n"
            "\nuse core;",
        ]
        chunks += [emit_function(model, op, file, name) for name, op in ops]
        out[f"{file}.bs"] = "\n\n".join(chunks) + "\n"
    return out


def channels_of(model: Model) -> dict[str, dict[str, str]]:
    """Each channel's events, as the constant name and the signal."""
    channels: dict[str, set[str]] = {}
    for row in model.table:
        channels.setdefault(row["channel"], set()).add(row["signal"])
    named: dict[str, dict[str, str]] = {}
    for channel in sorted(channels):
        names: dict[str, str] = {}
        for signal in sorted(channels[channel]):
            name = signal.removeprefix(f"{channel}_").upper()
            if name in names:
                raise SystemExit(f"events::{channel}::{name} is both {names[name]} and {signal}")
            names[name] = signal
        named[channel] = names
    return named


def write_events(model: Model) -> dict[str, str]:
    """`events/<channel>.bs`, one constant per event, and `events.bs`."""
    out = {}
    for channel, names in channels_of(model).items():
        body = "\n".join(f'pub const {name}: str = "{signal}";' for name, signal in names.items())
        out[f"events/{channel}.bs"] = (
            BANNER
            + f"\n// What arrives on `{channel}` topics, as `events::decode` names it:\n"
            + f"// `use addons::gamend::events::{channel};`, then `{channel}::<NAME>`.\n\n"
            + body + "\n"
        )
    rows = ",\n".join(
        f'        ["{row["channel"]}", "{row["event"]}", "{row["signal"]}"]' for row in model.table
    )
    out["events.bs"] = (
        BANNER
        + "\n// The realtime events: the table, and the decoder that names a raw socket\n"
        "// message. OpenAPI does not describe the socket, so this comes from\n"
        "// `clients/events.json`. An event the table does not name still\n"
        "// arrives, as `message`.\n\n"
        "/// Every row of the table: the channel a topic belongs to, the event the\n"
        "/// server sends, and what this client calls it.\n"
        f"pub fn table() -> [[str]] {{\n    [\n{rows},\n    ]\n}}\n\n"
        "/// The channel a topic names: `lobby:12` is `lobby`, `lobbies` is itself.\n"
        "pub fn channel_of(topic: str) -> str {\n"
        '    topic.split(":")[0]\n'
        "}\n\n"
        "/// A socket message as this client names it: `kind` (one of the\n"
        "/// channels' constants, or `message`), `topic`, `event`, and the\n"
        "/// server's `payload` as it came.\n"
        "pub fn decode(topic: str, event: str, payload: any) -> any {\n"
        "    let channel = channel_of(topic);\n"
        '    let named = "message";\n'
        "    for row in table() {\n"
        "        if row[0] == channel && row[1] == event {\n"
        "            named = row[2];\n"
        "            break;\n"
        "        }\n"
        "    }\n"
        '    { "kind": named, "topic": topic, "event": event, "payload": payload }\n'
        "}\n"
    )
    return out


def write_readme(model: Model) -> str:
    files = by_file(model)
    lines = [
        "# The Gamend SDK for Balaur",
        "",
        "Written by `clients/sdkgen` (balaur), in Balaur Script. Copy this",
        "directory into a project as `addons/gamend/`. A script links a module",
        "with `use addons::gamend::<module>;`, beside the engine's own",
        "`gamend::login` and `gamend::rest`:",
        "",
        "```rust",
        "use addons::gamend::lobbies;",
        "use addons::gamend::events::lobby;",
        "",
        'let reply = await task::wait(lobbies::quick_join({ "title": "duel", "max_users": 2 }));',
        'if e["kind"].as_str() == lobby::MEMBER_JOINED { }',
        "```",
        "",
        f"{len(model.ops)} operations in {len(files)} modules, and "
        f"{len(model.signals())} realtime events.",
        "",
        "Beside the generated modules and `events.bs`, written by hand:",
        "",
        "| Module | For |",
        "| --- | --- |",
        "| `gamend::client` | `configure`, the socket, hooks and the key-value cache |",
        "| `gamend::auth` | Sign-in through a provider, and the kept session |",
        "| `gamend::presence` | The user cache |",
        "| `gamend::prefs` | The player's prefs on this device |",
        "| `gamend::logs` | This run's log, shipped in batches; put `log_sink.bs` on a node that lives as long as the game |",
        "| `gamend::core` | The query string, the required-field check and the reply helpers |",
        "| `editor/gamend.bs` | The Gamend dock in the Balaur editor: the server, the session, and what the calls answered |",
        "",
    ]
    for file in sorted(files):
        ops = files[file]
        lines += [
            f"## {file}",
            "",
            f"{ops[0][1]['tag']}.",
            "",
            "| Function | Call | What it does |",
            "| --- | --- | --- |",
        ]
        for name, op in ops:
            args = list(op["path_params"])
            if op["body"]:
                args.append("params")
            if op["query"]:
                args.append("options")
            summary = op["summary"].replace("|", "\\|")
            lines.append(f"| `{name}({', '.join(args)})` | `{op['method']} {op['path']}` | {summary} |")
        lines.append("")
    return "\n".join(lines)


def emit(model: Model) -> dict[str, str]:
    return {
        **write_tags(model),
        **write_events(model),
        "README.md": write_readme(model),
    }


def summary(model: Model) -> str:
    return f"wrote {len(model.ops)} operations and {len(model.signals())} events"
