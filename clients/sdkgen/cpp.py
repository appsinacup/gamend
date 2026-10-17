"""The C++ emitter: `Api` over `gamend::Rest`, and the realtime names.

Writes four files into `cpp_sdk/`. `include/gamend/api.hpp` and
`src/api.cpp` are one method per operation, named as `GamendApi.gd` names
it; the arguments are the path's parameters as `std::string_view`, then
`const json& params` for a body, then `const json& options` for the query,
then the callback. A required body or query field that is missing refuses
the call: its callback gets an error naming the field instead of the server
getting a request it would reject. `include/gamend/events.hpp` is one
constant per realtime signal and the table that names a socket message.
`REFERENCE.md` lists the operations by tag. Everything else is the
hand-written `clients/cpp_template/`, copied over the top.
"""

import re

from model import CLIENTS, ROOT, Model, resolve, wrap

TEMPLATE = CLIENTS / "cpp_template"
OUT = ROOT / "cpp_sdk"
REGENERATE = "clients/generate_cpp.sh"

BANNER = (
    "// Written by clients/sdkgen (cpp) from the OpenAPI document.\n"
    "// Do not edit; edit the generator or the spec and run\n"
    "// clients/generate_cpp.sh.\n"
)

# C++'s keywords, which a path parameter could otherwise collide with when it
# becomes an argument name. The document's are `id`, `key`, `provider` and
# the like today; this keeps a future `default` or `class` compiling.
RESERVED = {
    "alignas", "alignof", "and", "asm", "auto", "bool", "break", "case", "catch",
    "char", "class", "const", "constexpr", "continue", "decltype", "default",
    "delete", "do", "double", "else", "enum", "explicit", "export", "extern",
    "false", "float", "for", "friend", "goto", "if", "inline", "int", "long",
    "mutable", "namespace", "new", "noexcept", "not", "nullptr", "operator",
    "or", "private", "protected", "public", "register", "return", "short",
    "signed", "sizeof", "static", "struct", "switch", "template", "this",
    "throw", "true", "try", "typedef", "typename", "union", "unsigned", "using",
    "virtual", "void", "volatile", "while", "xor",
    # Not keywords, but the names the generated code itself uses.
    "done", "options", "params", "bytes", "path", "rest_",
}

# Operations that answer a session. `Auth` makes these calls and keeps what
# they answer; the generated method only makes the call. Not `register`: it
# answers the new account, and signs nobody in. Its code does
# (`confirm_registration`).
SESSION_OPS = {
    "device_login", "login", "refresh_token", "oauth_api_callback",
    "oauth_google_id_token", "oauth_callback_api_apple_ios", "oauth_session_status",
    "confirm_registration",
}


def safe(name: str) -> str:
    return f"{name}_" if name in RESERVED else name


def ascii_only(text: str) -> str:
    """Comment text in ASCII: MSVC reads a source file in the machine's code
    page unless told otherwise, and a game's build should not have to say."""
    for fancy, plain in {"–": "-", "—": "-", "→": "->", "…": "...", "‘": "'", "’": "'",
                         "“": '"', "”": '"'}.items():
        text = text.replace(fancy, plain)
    return text.encode("ascii", "replace").decode("ascii")


def body_kind(op: dict) -> str:
    """`json`, `bytes`, or empty for an operation without a body."""
    if not op["body"]:
        return ""
    return "json" if op["body"]["type"] == "application/json" else "bytes"


def arguments(op: dict, with_options: bool) -> list[str]:
    args = [f"std::string_view {safe(p)}" for p in op["path_params"]]
    kind = body_kind(op)
    if kind == "json":
        args.append("const json& params")
    elif kind == "bytes":
        args.append("std::string bytes")
    if op["query"] and with_options:
        args.append("const json& options")
    args.append("Callback done")
    return args


def short_form(op: dict) -> bool:
    """Whether the method also comes without `options`: when no query key is
    required, leaving them all out is a call of its own."""
    return bool(op["query"]) and not any(needed for _, needed in op["query"])


def fields_line(label: str, fields: list[tuple[str, bool]]) -> list[str]:
    if not fields:
        return []
    listed = ", ".join(f"`{name}`{' (required)' if needed else ''}" for name, needed in fields)
    return wrap(f"`{label}`: {listed}.", 96, "  ///")


def body_fields(model: Model, op: dict) -> list[tuple[str, bool]]:
    if body_kind(op) != "json":
        return []
    schema = resolve(model.spec, op["body"]["schema"])
    required = list(schema.get("required", []))
    rest = [name for name in schema.get("properties", {}) if name not in required]
    return [(name, True) for name in required] + [(name, False) for name in rest]


def declaration(model: Model, op: dict, name: str) -> str:
    out = wrap(ascii_only(op["summary"]), 96, "  ///")
    out.append(f"  /// `{op['method']} {op['path']}`")
    out += fields_line("params", body_fields(model, op))
    out += fields_line("options", op["query"])
    if body_kind(op) == "bytes":
        out.append("  /// `bytes` go as `application/octet-stream`; `rest().send` with")
        out.append("  /// `Body::raw` sends another content type.")
    if op["binary_reply"]:
        out.append("  /// The reply is raw bytes, in `Response::text`.")
    if op["id"] in SESSION_OPS:
        out.append("  /// Answers a session without keeping it: `Client::auth()` signs in.")
    out.append(f"  void {name}({', '.join(arguments(op, True))});")
    if short_form(op):
        out.append(f"  void {name}({', '.join(arguments(op, False))});")
    return "\n".join(out)


def path_lines(op: dict) -> list[str]:
    """The statements that build `path`, each parameter escaped."""
    parts = re.split(r"\{([^}]+)\}", op["path"])
    lines = [f'  std::string path = "{parts[0]}";']
    for i in range(1, len(parts), 2):
        lines.append(f"  path += detail::escape({safe(parts[i])});")
        if parts[i + 1]:
            lines.append(f'  path += "{parts[i + 1]}";')
    return lines


def definition(model: Model, op: dict, name: str) -> str:
    out = [f"void Api::{name}({', '.join(arguments(op, True))}) {{"]
    for field, _ in [f for f in body_fields(model, op) if f[1]]:
        out.append(f'  if (!detail::given(params, "{field}")) {{')
        out.append(f'    return rest_.refuse("{name}", "{field}", std::move(done));')
        out.append("  }")
    for field in [q for q, needed in op["query"] if needed]:
        out.append(f'  if (!detail::given(options, "{field}")) {{')
        out.append(f'    return rest_.refuse("{name}", "{field}", std::move(done));')
        out.append("  }")
    out += path_lines(op)
    if op["query"]:
        allowed = ", ".join(f'"{q}"' for q, _ in op["query"])
        out.append(f"  path += detail::query(options, {{{allowed}}});")
    kind = body_kind(op)
    body = {
        "json": "Body::of(params)",
        "bytes": "Body::raw(std::move(bytes))",
        "": "Body::none()",
    }[kind]
    out.append(f'  rest_.send("{op["method"]}", std::move(path), {body}, std::move(done));')
    out.append("}")
    if short_form(op):
        forwarded = [safe(p) for p in op["path_params"]]
        if kind == "json":
            forwarded.append("params")
        elif kind == "bytes":
            forwarded.append("std::move(bytes)")
        forwarded += ["json::object()", "std::move(done)"]
        out.append("")
        out.append(f"void Api::{name}({', '.join(arguments(op, False))}) {{")
        out.append(f"  {name}({', '.join(forwarded)});")
        out.append("}")
    return "\n".join(out)


def names(model: Model) -> list[tuple[dict, str]]:
    seen: dict[str, str] = {}
    out = []
    for op in model.ops:
        name = model.name(op)
        if name in seen:
            raise SystemExit(f"{name}: {op['id']} and {seen[name]} want the same name")
        if name in RESERVED:
            raise SystemExit(f"{name}: {op['id']} is named after a C++ keyword")
        seen[name] = op["id"]
        out.append((op, name))
    return out


def write_header(model: Model) -> str:
    by_tag: dict[str, list[str]] = {}
    for op, name in names(model):
        by_tag.setdefault(op["tag"], []).append(declaration(model, op, name))
    sections = "\n\n".join(
        f"  // --- {ascii_only(tag)} " + "-" * max(3, 72 - len(tag)) + "\n\n" + "\n\n".join(decls)
        for tag, decls in by_tag.items()
    )
    return (
        BANNER
        + "//\n"
        "// Every Gamend operation, one method each, named as the Godot SDK names\n"
        "// it. A method takes the path's own parameters, then `params` for the\n"
        "// request body and `options` for the query where the operation has them,\n"
        "// then the callback, which runs in `Client::poll()`:\n"
        "//\n"
        '//     client.api().lobbies_quick_join({{"title", "duel"}, {"max_users", 2}},\n'
        "//       [](const gamend::Response& r) { if (r.ok()) use(r.data()); });\n"
        "#pragma once\n"
        "\n"
        "#include <string>\n"
        "#include <string_view>\n"
        "\n"
        '#include "gamend/json.hpp"\n'
        '#include "gamend/response.hpp"\n'
        "\n"
        "namespace gamend {\n"
        "\n"
        "class Rest;\n"
        "\n"
        "class Api {\n"
        " public:\n"
        "  explicit Api(Rest& rest) : rest_(rest) {}\n"
        "\n"
        f"{sections}\n"
        "\n"
        " private:\n"
        "  Rest& rest_;\n"
        "};\n"
        "\n"
        "}  // namespace gamend\n"
    )


def write_source(model: Model) -> str:
    bodies = "\n\n".join(definition(model, op, name) for op, name in names(model))
    return (
        BANNER
        + '#include "gamend/api.hpp"\n'
        "\n"
        "#include <utility>\n"
        "\n"
        '#include "gamend/rest.hpp"\n'
        '#include "query.hpp"\n'
        "\n"
        "namespace gamend {\n"
        "\n"
        f"{bodies}\n"
        "\n"
        "}  // namespace gamend\n"
    )


def write_events(model: Model) -> str:
    constants = "\n".join(
        f'inline constexpr std::string_view {signal.upper()} = "{signal}";'
        for signal in model.signals()
    )
    rows = "\n".join(
        f'    {{"{row["channel"]}", "{row["event"]}", "{row["signal"]}"}},'
        for row in model.table
    )
    return (
        BANNER
        + "//\n"
        "// The realtime events, one constant each, and the table that names a\n"
        "// socket message. OpenAPI does not describe the socket, so this comes\n"
        "// from `clients/events.json`. An event the table does not name is\n"
        "// `MESSAGE`.\n"
        "#pragma once\n"
        "\n"
        "#include <cstddef>\n"
        "#include <string_view>\n"
        "\n"
        "namespace gamend::events {\n"
        "\n"
        f"{constants}\n"
        'inline constexpr std::string_view MESSAGE = "message";\n'
        "\n"
        "/// One row of the table: the channel a topic belongs to, the event the\n"
        "/// server sends on it, and the signal this SDK calls it.\n"
        "struct Row {\n"
        "  std::string_view channel;\n"
        "  std::string_view event;\n"
        "  std::string_view signal;\n"
        "};\n"
        "\n"
        "inline constexpr Row TABLE[] = {\n"
        f"{rows}\n"
        "};\n"
        "\n"
        "/// The channel a topic names: `lobby:12` is `lobby`, `lobbies` is itself.\n"
        "constexpr std::string_view channel_of(std::string_view topic) {\n"
        "  std::size_t colon = topic.find(':');\n"
        "  return colon == std::string_view::npos ? topic : topic.substr(0, colon);\n"
        "}\n"
        "\n"
        "/// The signal a message on `topic` named `event` is, or `MESSAGE`.\n"
        "constexpr std::string_view signal_of(std::string_view topic, std::string_view event) {\n"
        "  std::string_view channel = channel_of(topic);\n"
        "  for (const Row& row : TABLE) {\n"
        "    if (row.channel == channel && row.event == event) return row.signal;\n"
        "  }\n"
        "  return MESSAGE;\n"
        "}\n"
        "\n"
        "}  // namespace gamend::events\n"
    )


def write_reference(model: Model) -> str:
    lines = [
        "# Gamend C++ SDK reference",
        "",
        "Written by `clients/sdkgen` (cpp) from the OpenAPI document. "
        f"{len(model.ops)} operations on `client.api()`, and "
        f"{len(model.signals())} realtime signals in `gamend::events`.",
        "",
        "Arguments are the path's parameters, then `params` (the request body),",
        "then `options` (the query), then the callback. `include/gamend/api.hpp`",
        "lists each operation's fields.",
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
                args.append("params" if kind == "json" else "bytes")
            if op["query"]:
                args.append("options")
            args.append("done")
            summary = op["summary"].replace("|", "\\|")
            lines.append(
                f"| `{name}({', '.join(args)})` | `{op['method']} {op['path']}` | {summary} |"
            )
        lines.append("")
    return "\n".join(lines)


# C++'s own keywords, for a struct field named after one (`operator`).
KEYWORDS = RESERVED - {"done", "options", "params", "bytes", "path", "rest_"}


def field_name(name: str) -> str:
    name = re.sub(r"[^A-Za-z0-9_]", "_", name)
    if name[:1].isdigit():
        name = "_" + name
    return f"{name}_" if name in KEYWORDS else name


def ref_name(schema: dict) -> str | None:
    """The component a property names, directly or as a nullable `allOf`."""
    if "$ref" in schema:
        return schema["$ref"].rsplit("/", 1)[-1]
    parts = schema.get("allOf") or []
    if len(parts) == 1 and "$ref" in parts[0]:
        return parts[0]["$ref"].rsplit("/", 1)[-1]
    return None


def is_envelope(schema: dict) -> bool:
    """`{data}` and `{data, meta}`: read through `Response::as` and `page`."""
    props = set(schema.get("properties", {}))
    return "data" in props and props <= {"data", "meta"}


def models_of(model: Model) -> list[tuple[str, dict]]:
    """The components worth a struct, each after those it contains."""
    schemas = model.spec["components"]["schemas"]
    kept = {name: s for name, s in schemas.items() if not is_envelope(s)}
    order: list[str] = []
    seen: set[str] = set()

    def visit(name: str) -> None:
        if name in seen or name not in kept:
            return
        seen.add(name)
        schema = kept[name]
        inners = [schema.get("additionalProperties") or {}]
        for prop in schema.get("properties", {}).values():
            inners += [prop, prop.get("items", {}), prop.get("additionalProperties") or {}]
        for inner in inners:
            ref = ref_name(inner) if isinstance(inner, dict) else None
            if ref:
                visit(ref)
        order.append(name)

    for name in sorted(kept):
        visit(name)
    return [(name, kept[name]) for name in order]


def field_type(schema: dict) -> str:
    ref = ref_name(schema)
    nullable = bool(schema.get("nullable"))
    if ref:
        base = f"models::{ref}"
    else:
        kind = schema.get("type")
        if kind == "array":
            return f"std::vector<{field_type(schema.get('items', {}))}>"
        values = schema.get("additionalProperties")
        if kind == "object" and isinstance(values, dict) and not schema.get("properties"):
            return f"std::map<std::string, {field_type(values)}>"
        base = {
            "string": "std::string",
            "integer": "std::int64_t",
            "number": "double",
            "boolean": "bool",
        }.get(kind, "json")
        if base == "json":
            return "json"
    return f"std::optional<{base}>" if nullable else base


def default_of(kind: str) -> str:
    return {"std::int64_t": " = 0", "double": " = 0", "bool": " = false"}.get(kind, "")


def write_models_header(model: Model) -> str:
    structs = []
    codecs = []
    for name, schema in models_of(model):
        lines = wrap(ascii_only(schema.get("description") or schema.get("title") or name), 96, "///")
        if not schema.get("properties"):
            # A map (currency -> balance): the map itself, read by its codec.
            lines.append(f"using {name} = {field_type(schema).replace('models::', '')};")
            structs.append("\n".join(lines))
            continue
        lines.append(f"struct {name} {{")
        for prop, spec in schema.get("properties", {}).items():
            doc = spec.get("description")
            if doc:
                lines += wrap(ascii_only(doc), 94, "  ///")
            kind = field_type(spec).replace("models::", "")
            lines.append(f"  {kind} {field_name(prop)}{default_of(kind)};")
        lines.append("};")
        structs.append("\n".join(lines))
        codecs.append(
            "template <>\n"
            f"struct Codec<models::{name}> {{\n"
            f"  static bool read(const json& j, models::{name}& out);\n"
            f"  static json write(const models::{name}& v);\n"
            "};"
        )
    return (
        BANNER
        + "//\n"
        "// A struct for every schema the API answers with, read from a reply with\n"
        "// `Response::as`:\n"
        "//\n"
        "//     if (auto lobby = r.as<gamend::models::Lobby>()) show(lobby->title);\n"
        "//     if (auto page = r.page<gamend::models::Lobby>()) list(page->data);\n"
        "//\n"
        "// A field the reply leaves out keeps its default; a nullable one is a\n"
        "// `std::optional`; a free-form map stays `json`.\n"
        "#pragma once\n"
        "\n"
        "#include <cstdint>\n"
        "#include <map>\n"
        "#include <optional>\n"
        "#include <string>\n"
        "#include <vector>\n"
        "\n"
        '#include "gamend/codec.hpp"\n'
        '#include "gamend/json.hpp"\n'
        "\n"
        "namespace gamend {\n"
        "namespace models {\n"
        "\n"
        + "\n\n".join(structs)
        + "\n\n"
        "/// A page of a list: the items, and where they sit in the whole.\n"
        "template <class T>\n"
        "struct Page {\n"
        "  std::vector<T> data;\n"
        "  PageMeta meta;\n"
        "};\n"
        "\n"
        "}  // namespace models\n"
        "\n"
        + "\n\n".join(codecs)
        + "\n\n"
        "template <class T>\n"
        "struct Codec<models::Page<T>> {\n"
        "  static bool read(const json& j, models::Page<T>& out) {\n"
        "    if (!j.is_object()) return false;\n"
        "    detail::read_field(j, \"data\", out.data);\n"
        "    detail::read_field(j, \"meta\", out.meta);\n"
        "    return true;\n"
        "  }\n"
        "  static json write(const models::Page<T>& v) {\n"
        "    return json{{\"data\", Codec<std::vector<T>>::write(v.data)},\n"
        "                {\"meta\", Codec<models::PageMeta>::write(v.meta)}};\n"
        "  }\n"
        "};\n"
        "\n"
        "}  // namespace gamend\n"
    )


def write_models_source(model: Model) -> str:
    bodies = []
    for name, schema in models_of(model):
        props = schema.get("properties", {})
        if not props:
            continue
        read = [f"bool Codec<models::{name}>::read(const json& j, models::{name}& out) {{",
                "  if (!j.is_object()) return false;"]
        read += [f'  detail::read_field(j, "{prop}", out.{field_name(prop)});' for prop in props]
        read += ["  return true;", "}"]
        write = [f"json Codec<models::{name}>::write(const models::{name}& v) {{",
                 "  json j = json::object();"]
        for prop, spec in props.items():
            kind = field_type(spec)
            write.append(f'  j["{prop}"] = Codec<{kind}>::write(v.{field_name(prop)});')
        write += ["  return j;", "}"]
        bodies.append("\n".join(read) + "\n\n" + "\n".join(write))
    return (
        BANNER
        + '#include "gamend/models.hpp"\n'
        "\n"
        "namespace gamend {\n"
        "\n"
        + "\n\n".join(bodies)
        + "\n\n}  // namespace gamend\n"
    )


PROTO = ROOT / "proto" / "gamend_realtime.proto"

SCALARS = {
    "bool": "Bool", "int32": "Int32", "int64": "Int64", "uint32": "Uint32",
    "uint64": "Uint64", "sint32": "Sint32", "sint64": "Sint64", "string": "String",
    "bytes": "Bytes",
}

FIELD = re.compile(
    r"^(optional\s+|repeated\s+)?(map<\s*(\w+)\s*,\s*(\w+)\s*>|\w+)\s+(\w+)\s*=\s*(\d+)\s*;"
)


def proto_messages() -> list[tuple[str, list[dict]]]:
    """The messages of the realtime `.proto`, each with its fields.

    Enough of the language for this file: proto3 scalars, messages, `optional`,
    `repeated`, `map<string, V>` and `oneof`, whose members are optional.
    """
    text = re.sub(r"//[^\n]*", "", PROTO.read_text())
    messages = []
    for match in re.finditer(r"message\s+(\w+)\s*\{", text):
        depth, at = 1, match.end()
        while depth:
            depth += {"{": 1, "}": -1}.get(text[at], 0)
            at += 1
        body = text[match.end():at - 1]
        fields = []
        in_oneof = False
        for line in (part.strip() for part in body.split("\n")):
            if line.startswith("oneof "):
                in_oneof = True
                continue
            if line == "}":
                in_oneof = False
                continue
            field = FIELD.match(line)
            if not field:
                continue
            label, kind, key, value, name, number = field.groups()
            if kind.startswith("map<"):
                if key != "string":
                    raise SystemExit(f"{match.group(1)}.{name}: only map<string, V> is read")
                fields.append({"name": name, "number": int(number), "label": "Map", "type": value})
            else:
                label = (label or "").strip()
                fields.append({
                    "name": name,
                    "number": int(number),
                    "label": "Repeated" if label == "repeated"
                    else "Optional" if label == "optional" or in_oneof else "Singular",
                    "type": kind,
                })
        messages.append((match.group(1), fields))
    return messages


def write_proto_schema(model: Model) -> str:
    messages = proto_messages()
    index = {name: i for i, (name, _) in enumerate(messages)}
    tables = []
    for name, fields in messages:
        rows = []
        for f in sorted(fields, key=lambda f: f["number"]):
            kind = f["type"]
            if kind in SCALARS:
                type_, message = SCALARS[kind], -1
            elif kind in index:
                type_, message = "Message", index[kind]
            else:
                raise SystemExit(f"{name}.{f['name']}: unknown type {kind}")
            rows.append(
                f'    {{{f["number"]}, "{f["name"]}", Label::{f["label"]}, Type::{type_}, {message}}},'
            )
        tables.append(f"constexpr Field k{name}[] = {{\n" + "\n".join(rows) + "\n};")
    entries = ",\n".join(
        f'    {{"{name}", k{name}, sizeof(k{name}) / sizeof(Field)}}' for name, _ in messages
    )
    return (
        BANNER
        + "//\n"
        "// Every message of proto/gamend_realtime.proto as a field table, which\n"
        "// src/proto.cpp decodes the wire format against.\n"
        '#include "proto.hpp"\n'
        "\n"
        "namespace gamend::detail::proto {\n"
        "namespace {\n"
        "\n"
        + "\n\n".join(tables)
        + "\n\n}  // namespace\n"
        "\n"
        f"const Message kMessages[] = {{\n{entries},\n}};\n"
        "\n"
        "const std::size_t kMessageCount = sizeof(kMessages) / sizeof(Message);\n"
        "\n"
        "}  // namespace gamend::detail::proto\n"
    )


def emit(model: Model) -> dict[str, str]:
    return {
        "include/gamend/api.hpp": write_header(model),
        "src/api.cpp": write_source(model),
        "include/gamend/events.hpp": write_events(model),
        "include/gamend/models.hpp": write_models_header(model),
        "src/models.cpp": write_models_source(model),
        "src/proto_schema.cpp": write_proto_schema(model),
        "REFERENCE.md": write_reference(model),
    }


def summary(model: Model) -> str:
    return f"wrote {len(model.ops)} operations and {len(model.signals())} events"
