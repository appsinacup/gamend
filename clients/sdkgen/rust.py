"""The Rust emitter: `Api` over `gamend::Rest`, typed models, and the realtime names.

Writes into `rust_sdk/`, the game's half of the API only (`Model.player()`).
`src/generated/api.rs` is one method per operation, named as `GamendApi.gd`
names it; the arguments are the path's parameters as `&str`, then `body: Value`
or `bytes: Vec<u8>`, then `options: Value` for the query, and every method
answers a `Ticket<Response>` that `Client::poll()` completes. Rust has no
overloads, so where every query key is optional the plain name leaves `options`
out and `<name>_with` takes it. A required path, body or query field that is
missing refuses the call: its ticket gets an error naming the field instead of
the server getting a request it would reject.

`events.rs` is one constant per realtime signal and the table that names a
socket message, `commands.rs` one function per event a channel answers,
`models.rs` a struct per schema with its `Model` impl written out, and
`proto_schema.rs` the field table of the realtime `.proto`. `REFERENCE.md` lists
the operations by tag. Everything else is the hand-written
`clients/rust_template/`, copied over the top.
"""

import re

from model import (
    CLIENTS,
    ROOT,
    SCALARS,
    SESSION_OPS,
    Model,
    body_fields,
    body_kind,
    models_of,
    proto_messages,
    ref_name,
    wrap,
)

TEMPLATE = CLIENTS / "rust_template"
OUT = ROOT / "rust_sdk"
REGENERATE = "clients/generate_rust.sh"
GENERATED = "src/generated"

BANNER = (
    "// Written by clients/sdkgen (rust) from the OpenAPI document.\n"
    "// Do not edit; edit the generator or the spec and run\n"
    "// clients/generate_rust.sh.\n"
)

# Rust's keywords, strict and reserved. A name that is one takes a trailing
# underscore instead of `r#`: `self`, `crate` and `super` cannot be raw at all.
KEYWORDS = {
    "abstract", "as", "async", "await", "become", "box", "break", "const",
    "continue", "crate", "do", "dyn", "else", "enum", "extern", "false", "final",
    "fn", "for", "gen", "if", "impl", "in", "let", "loop", "macro", "match", "mod",
    "move", "mut", "override", "priv", "pub", "ref", "return", "self", "Self",
    "static", "struct", "super", "trait", "true", "try", "type", "typeof",
    "unsafe", "unsized", "use", "virtual", "where", "while", "yield",
}

# The names a generated method uses itself, which a path parameter must not take.
ARGUMENT_NAMES = KEYWORDS | {"body", "bytes", "options", "path"}

# Names `models.rs` uses unqualified. A schema with one of these needs a
# decision, not a silently broken build.
TAKEN_TYPES = {
    "Default", "HashMap", "Map", "Model", "Option", "Page", "String", "Value", "Vec",
}


def safe(name: str) -> str:
    """A path parameter as an argument name."""
    return f"{name}_" if name in ARGUMENT_NAMES else name


def quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def doc_text(text: str) -> str:
    """A summary fit for a doc comment: rustdoc runs a fenced block as a test."""
    return text.replace("```", "`")


def doc(text: str, prefix: str) -> list[str]:
    return wrap(doc_text(text), 96, prefix)


def parameters(op: dict, with_options: bool) -> list[str]:
    args = ["&self"] + [f"{safe(p)}: &str" for p in op["path_params"]]
    kind = body_kind(op)
    if kind == "json":
        args.append("body: Value")
    elif kind == "bytes":
        args.append("bytes: Vec<u8>")
    if op["query"] and with_options:
        args.append("options: Value")
    return args


def short_form(op: dict) -> bool:
    """Whether the plain name leaves `options` out: when no query key is
    required, leaving them all out is a call of its own."""
    return bool(op["query"]) and not any(needed for _, needed in op["query"])


def fields_line(label: str, fields: list[tuple[str, bool]]) -> list[str]:
    if not fields:
        return []
    listed = ", ".join(f"`{name}`{' (required)' if needed else ''}" for name, needed in fields)
    return ["    ///", *wrap(f"`{label}`: {listed}.", 96, "    ///")]


def docs_of(model: Model, op: dict, name: str) -> list[str]:
    out = doc(op["summary"] or name, "    ///")
    out += ["    ///", f"    /// `{op['method']} {op['path']}`"]
    out += fields_line("body", body_fields(model, op))
    out += fields_line("options", op["query"])
    if body_kind(op) == "bytes":
        out += ["    ///", "    /// `bytes` go as `application/octet-stream`; `Rest::send` with"]
        out.append("    /// `Body::raw_as` sends another content type.")
    if op["binary_reply"]:
        out += ["    ///", "    /// The reply is raw bytes, in `Response::bytes`."]
    if op["id"] in SESSION_OPS:
        out += ["    ///", "    /// Answers a session without keeping it: `Client::auth()` signs in."]
    return out


def path_expression(op: dict) -> str:
    """The expression that builds the path, each parameter escaped."""
    parts = re.split(r"\{([^}]+)\}", op["path"])
    template, arguments = parts[0], []
    for i in range(1, len(parts), 2):
        template += "{}" + parts[i + 1]
        arguments.append(f"escape({safe(parts[i])})")
    if op["query"]:
        allowed = ", ".join(quote(q) for q, _ in op["query"])
        template += "{}"
        arguments.append(f"query(&options, &[{allowed}])")
    if not arguments:
        return quote(template)
    return f"format!({quote(template)}, {', '.join(arguments)})"


def refusal(condition: str, name: str, field: str) -> list[str]:
    return [
        f"        if {condition} {{",
        f"            return self.rest.refuse({quote(name)}, {quote(field)});",
        "        }",
    ]


def method(model: Model, op: dict, name: str) -> str:
    short = short_form(op)
    full = f"{name}_with" if short else name
    out = docs_of(model, op, name)
    out.append(f"    pub fn {full}({', '.join(parameters(op, True))}) -> Ticket<Response> {{")
    for param in op["path_params"]:
        out += refusal(f"{safe(param)}.is_empty()", name, param)
    for field, needed in body_fields(model, op):
        if needed:
            out += refusal(f"!given(&body, {quote(field)})", name, field)
    for field, needed in op["query"]:
        if needed:
            out += refusal(f"!given(&options, {quote(field)})", name, field)
    kind = body_kind(op)
    body = {"json": "Body::of(body)", "bytes": "Body::raw(bytes)", "": "Body::none()"}[kind]
    out.append(f"        let path = {path_expression(op)};")
    out.append(f"        self.rest.send({quote(op['method'])}, path, {body})")
    out.append("    }")
    if short:
        forwarded = [safe(p) for p in op["path_params"]]
        if kind == "json":
            forwarded.append("body")
        elif kind == "bytes":
            forwarded.append("bytes")
        forwarded.append("Value::Null")
        out.append("")
        out += doc(op["summary"] or name, "    ///")
        out += ["    ///", f"    /// `{name}_with` takes the query."]
        out.append(f"    pub fn {name}({', '.join(parameters(op, False))}) -> Ticket<Response> {{")
        out.append(f"        self.{full}({', '.join(forwarded)})")
        out.append("    }")
    return "\n".join(out)


def names(model: Model) -> list[tuple[dict, str]]:
    seen: dict[str, str] = {}
    out = []
    for op in model.ops:
        name = model.name(op)
        if name in KEYWORDS:
            raise SystemExit(f"{name}: {op['id']} is named after a Rust keyword")
        taken = [name, f"{name}_with"] if short_form(op) else [name]
        for word in taken:
            if word in seen:
                raise SystemExit(f"{word}: {op['id']} and {seen[word]} want the same name")
            seen[word] = op["id"]
        out.append((op, name))
    return out


def write_api(model: Model) -> str:
    by_tag: dict[str, list[str]] = {}
    for op, name in names(model):
        by_tag.setdefault(op["tag"], []).append(method(model, op, name))
    sections = "\n\n".join(
        f"    // {tag}\n\n" + "\n\n".join(methods) for tag, methods in by_tag.items()
    )
    return (
        BANNER
        + "//\n"
        "// Every Gamend operation a game can call, one method each, named as the\n"
        "// Godot SDK names it. A method takes the path's own parameters, then `body`\n"
        "// for the request body and `options` for the query where the operation has\n"
        "// them, and answers a ticket that `Client::poll()` completes.\n"
        "\n"
        "use serde_json::Value;\n"
        "\n"
        "use crate::query::{escape, given, query};\n"
        "use crate::response::Response;\n"
        "use crate::rest::{Body, Rest};\n"
        "use crate::ticket::Ticket;\n"
        "\n"
        "/// Every REST operation a game can call, one method each.\n"
        "///\n"
        '/// `client.api().lobbies_quick_join(json!({"title": "duel", "max_users": 2}))`\n'
        "/// answers a `Ticket<Response>` that `Client::poll()` completes.\n"
        "#[derive(Clone)]\n"
        "pub struct Api {\n"
        "    rest: Rest,\n"
        "}\n"
        "\n"
        "impl Api {\n"
        "    pub(crate) fn new(rest: Rest) -> Self {\n"
        "        Self { rest }\n"
        "    }\n"
        "\n"
        f"{sections}\n"
        "}\n"
    )


def write_events(model: Model) -> str:
    constants = "\n".join(
        f"pub const {signal.upper()}: &str = {quote(signal)};" for signal in model.signals()
    )
    rows = "\n".join(
        f"    Row {{ channel: {quote(row['channel'])}, event: {quote(row['event'])}, "
        f"signal: {quote(row['signal'])} }},"
        for row in model.table
    )
    return (
        BANNER
        + "//\n"
        "// The realtime events, one constant each, and the table that names a socket\n"
        "// message. OpenAPI does not describe the socket, so this comes from\n"
        "// `clients/events.json`. An event the table does not name is `MESSAGE`.\n"
        "\n"
        f"{constants}\n"
        'pub const MESSAGE: &str = "message";\n'
        "\n"
        "/// One row of the table: the channel a topic belongs to, the event the server\n"
        "/// sends on it, and the signal this SDK calls it.\n"
        "#[derive(Clone, Copy, Debug, PartialEq, Eq)]\n"
        "pub struct Row {\n"
        "    pub channel: &'static str,\n"
        "    pub event: &'static str,\n"
        "    pub signal: &'static str,\n"
        "}\n"
        "\n"
        "pub const TABLE: &[Row] = &[\n"
        f"{rows}\n"
        "];\n"
        "\n"
        "/// The channel a topic names: `lobby:12` is `lobby`, `lobbies` is itself.\n"
        "pub fn channel_of(topic: &str) -> &str {\n"
        "    topic.split_once(':').map_or(topic, |(channel, _)| channel)\n"
        "}\n"
        "\n"
        "/// The signal a message on `topic` named `event` is, or `MESSAGE`.\n"
        "pub fn signal_of(topic: &str, event: &str) -> &'static str {\n"
        "    let channel = channel_of(topic);\n"
        "    TABLE\n"
        "        .iter()\n"
        "        .find(|row| row.channel == channel && row.event == event)\n"
        "        .map_or(MESSAGE, |row| row.signal)\n"
        "}\n"
    )


def command(row: dict) -> str:
    """One command as a function: to the caller's channel, or a named one's."""
    on_user = row["channel"] == "user"
    args = ["realtime: &Realtime"]
    if not on_user:
        args.append("id: &str")
    fields = [(key, True) for key in row["required"]] + [(key, False) for key in row["optional"]]
    if fields:
        args.append("params: Value")
    where = "the user channel" if on_user else f"`{row['channel']}:<id>`"
    lines = wrap(f"`{row['event']}` on {where}.", 96, "///")
    if fields:
        listed = ", ".join(f"`{key}`{' (required)' if needed else ''}" for key, needed in fields)
        lines += ["///", *wrap(f"`params`: {listed}.", 96, "///")]
    topic = "realtime.user_topic()" if on_user else f'format!("{row["channel"]}:{{id}}")'
    payload = "params" if fields else "json!({})"
    name = row["name"]
    if name in KEYWORDS:
        raise SystemExit(f"commands.json: {name} is a Rust keyword")
    return "\n".join(
        lines
        + [
            f"pub fn {name}({', '.join(args)}) -> Ticket<Reply> {{",
            f"    realtime.push(&{topic}, {quote(row['event'])}, {payload})",
            "}",
        ]
    )


def write_commands(model: Model) -> str:
    seen = [row["name"] for row in model.commands]
    if len(set(seen)) != len(seen):
        raise SystemExit("commands.json: two commands want the same function name")
    uses_json = any(
        not row["required"] and not row["optional"] for row in model.commands
    )
    imports = "use serde_json::{json, Value};\n" if uses_json else "use serde_json::Value;\n"
    body = "\n\n".join(command(row) for row in model.commands)
    return (
        BANNER
        + "//\n"
        "// Every event a channel answers, one function each, from\n"
        "// `clients/commands.json`. Each is a `Realtime::push` with its topic and event\n"
        "// filled in, and answers the same way.\n"
        "\n"
        f"{imports}"
        "\n"
        "use crate::realtime::{Realtime, Reply};\n"
        "use crate::ticket::Ticket;\n"
        "\n"
        f"{body}\n"
    )


def field_name(name: str) -> str:
    name = re.sub(r"[^A-Za-z0-9_]", "_", name)
    if name[:1].isdigit():
        name = "_" + name
    return f"{name}_" if name in KEYWORDS else name


class Types:
    """How the schemas read in Rust, once it is known which of them have a type."""

    def __init__(self, model: Model) -> None:
        self.models = models_of(model)
        self.names = {name for name, _ in self.models}
        for name in self.names:
            if name in TAKEN_TYPES or name in KEYWORDS:
                raise SystemExit(f"{name}: a schema with this name clashes in the Rust models")
        self.check_no_cycle()

    def of(self, schema: dict) -> str:
        """The Rust type of a property, an item or a whole schema."""
        ref = ref_name(schema)
        if ref:
            if ref not in self.names:
                return "Value"
            base = ref
        else:
            kind = schema.get("type")
            if kind == "array":
                return f"Vec<{self.of(schema.get('items', {}))}>"
            values = schema.get("additionalProperties")
            if kind == "object" and isinstance(values, dict) and not schema.get("properties"):
                return f"HashMap<String, {self.of(values)}>"
            base = {
                "string": "String",
                "integer": "i64",
                "number": "f64",
                "boolean": "bool",
            }.get(kind, "Value")
            if base == "Value":
                return base
        return f"Option<{base}>" if schema.get("nullable") else base

    def check_no_cycle(self) -> None:
        """A struct holding itself by value has no size. The emitter would need
        a `Box` for it, so a schema that does has to say so here first."""
        inside = {
            name: [ref_name(p) for p in schema.get("properties", {}).values() if ref_name(p)]
            for name, schema in self.models
        }

        def walk(name: str, path: list[str]) -> None:
            if name in path:
                raise SystemExit(f"{' -> '.join(path + [name])}: a struct holds itself by value")
            for inner in inside.get(name, []):
                walk(inner, path + [name])

        for name in inside:
            walk(name, [])


def struct_of(types: Types, name: str, schema: dict) -> str:
    lines = doc(schema.get("description") or schema.get("title") or name, "///")
    props = schema.get("properties", {})
    if not props:
        # A map (currency -> balance): the map itself, read by its own impl.
        lines.append(f"pub type {name} = {types.of(schema)};")
        return "\n".join(lines)
    lines += ["#[derive(Clone, Debug, Default, PartialEq)]", f"pub struct {name} {{"]
    seen: dict[str, str] = {}
    for prop, spec in props.items():
        word = field_name(prop)
        if word in seen:
            raise SystemExit(f"{name}: {prop} and {seen[word]} want the same field")
        seen[word] = prop
        if spec.get("description"):
            lines += doc(spec["description"], "    ///")
        lines.append(f"    pub {word}: {types.of(spec)},")
    lines.append("}")
    lines += [
        "",
        f"impl Model for {name} {{",
        "    fn read(value: &Value) -> Self {",
        "        let mut out = Self::default();",
    ]
    lines += [
        f"        read_field(value, {quote(prop)}, &mut out.{field_name(prop)});" for prop in props
    ]
    lines += [
        "        out",
        "    }",
        "",
        "    fn write(&self) -> Value {",
        "        let mut out = Map::new();",
    ]
    lines += [
        f"        out.insert({quote(prop)}.to_string(), self.{field_name(prop)}.write());"
        for prop in props
    ]
    lines += [
        "        Value::Object(out)",
        "    }",
        "",
        "    fn accepts(value: &Value) -> bool {",
        "        value.is_object()",
        "    }",
        "}",
    ]
    return "\n".join(lines)


def write_models(model: Model) -> str:
    types = Types(model)
    structs = [struct_of(types, name, schema) for name, schema in types.models]
    uses_map = any("HashMap<" in text for text in structs)
    imports = "use std::collections::HashMap;\n\n" if uses_map else ""
    return (
        BANNER
        + "//\n"
        "// A struct for every schema the API answers with, read from a reply with\n"
        "// `Response::as_model`:\n"
        "//\n"
        "//     let lobby = reply.as_model::<models::Lobby>();\n"
        "//     let page = reply.page::<models::Lobby>();\n"
        "//\n"
        "// A field the reply leaves out or mistypes keeps its default; a nullable one\n"
        "// is an `Option`; a map is a `HashMap`; a free-form object stays a `Value`.\n"
        "// The impls are written out rather than derived, so a game pays for no serde\n"
        "// derive and a read never fails halfway.\n"
        "\n"
        f"{imports}"
        "use serde_json::{Map, Value};\n"
        "\n"
        "use crate::model::{read_field, Model};\n"
        "\n"
        + "\n\n".join(structs)
        + "\n\n"
        "/// A page of a list: the items, and where they sit in the whole.\n"
        "#[derive(Clone, Debug, PartialEq)]\n"
        "pub struct Page<T> {\n"
        "    pub data: Vec<T>,\n"
        "    pub meta: PageMeta,\n"
        "}\n"
        "\n"
        "impl<T> Default for Page<T> {\n"
        "    fn default() -> Self {\n"
        "        Self { data: Vec::new(), meta: PageMeta::default() }\n"
        "    }\n"
        "}\n"
        "\n"
        "impl<T: Model> Model for Page<T> {\n"
        "    fn read(value: &Value) -> Self {\n"
        "        let mut out = Self::default();\n"
        '        read_field(value, "data", &mut out.data);\n'
        '        read_field(value, "meta", &mut out.meta);\n'
        "        out\n"
        "    }\n"
        "\n"
        "    fn write(&self) -> Value {\n"
        "        let mut out = Map::new();\n"
        '        out.insert("data".to_string(), self.data.write());\n'
        '        out.insert("meta".to_string(), self.meta.write());\n'
        "        Value::Object(out)\n"
        "    }\n"
        "\n"
        "    fn accepts(value: &Value) -> bool {\n"
        "        value.is_object()\n"
        "    }\n"
        "}\n"
    )


def write_proto_schema() -> str:
    messages = proto_messages()
    index = {name: i for i, (name, _) in enumerate(messages)}
    tables = []
    for name, fields in messages:
        rows = []
        for f in sorted(fields, key=lambda f: f["number"]):
            kind = f["type"]
            if kind in SCALARS:
                type_, message = SCALARS[kind], "None"
            elif kind in index:
                type_, message = "Message", f"Some({index[kind]})"
            else:
                raise SystemExit(f"{name}.{f['name']}: unknown type {kind}")
            rows.append(
                f"    Field {{ number: {f['number']}, name: {quote(f['name'])}, "
                f"label: Label::{f['label']}, kind: Kind::{type_}, message: {message} }},"
            )
        tables.append(
            f"const {name.upper()}: &[Field] = &[\n" + "\n".join(rows) + "\n];"
        )
    entries = "\n".join(
        f"    Message {{ name: {quote(name)}, fields: {name.upper()} }}," for name, _ in messages
    )
    return (
        BANNER
        + "//\n"
        "// Every message of proto/gamend_realtime.proto as a field table, which\n"
        "// src/proto.rs decodes the wire format against.\n"
        "\n"
        "use crate::proto::{Field, Kind, Label, Message};\n"
        "\n"
        + "\n\n".join(tables)
        + "\n\n"
        "pub(crate) const MESSAGES: &[Message] = &[\n"
        f"{entries}\n"
        "];\n"
    )


def write_mod() -> str:
    return (
        BANNER
        + "\n"
        "pub mod api;\n"
        "pub mod commands;\n"
        "pub mod events;\n"
        "pub mod models;\n"
        "pub(crate) mod proto_schema;\n"
    )


def write_reference(model: Model) -> str:
    lines = [
        "# Gamend Rust SDK reference",
        "",
        "Written by `clients/sdkgen` (rust) from the OpenAPI document. "
        f"{len(model.ops)} operations on `client.api()`, and "
        f"{len(model.signals())} realtime signals in `gamend::events`.",
        "",
        "Arguments are the path's parameters, then `body` (the request body), then",
        "`options` (the query). Where every query key is optional, the plain name",
        "leaves `options` out and `<name>_with` takes it. `src/generated/api.rs` lists",
        "each operation's fields.",
        "",
    ]
    by_tag: dict[str, list[tuple[dict, str]]] = {}
    for op, name in names(model):
        by_tag.setdefault(op["tag"], []).append((op, name))
    for tag in sorted(by_tag):
        lines += [f"## {tag}", "", "| Method | Call | What it does |", "| --- | --- | --- |"]
        for op, name in by_tag[tag]:
            args = [safe(p) for p in op["path_params"]]
            kind = body_kind(op)
            if kind:
                args.append("body" if kind == "json" else "bytes")
            if op["query"] and not short_form(op):
                args.append("options")
            text = op["summary"].replace("|", "\\|")
            lines.append(f"| `{name}({', '.join(args)})` | `{op['method']} {op['path']}` | {text} |")
        lines.append("")
    return "\n".join(lines)


def emit(model: Model) -> dict[str, str]:
    player = model.player()
    return {
        f"{GENERATED}/mod.rs": write_mod(),
        f"{GENERATED}/api.rs": write_api(player),
        f"{GENERATED}/events.rs": write_events(player),
        f"{GENERATED}/commands.rs": write_commands(player),
        f"{GENERATED}/models.rs": write_models(player),
        f"{GENERATED}/proto_schema.rs": write_proto_schema(),
        "REFERENCE.md": write_reference(player),
    }


def summary(model: Model) -> str:
    player = model.player()
    return (
        f"wrote {len(player.ops)} operations, {len(player.signals())} events "
        f"and {len(player.commands)} commands"
    )
