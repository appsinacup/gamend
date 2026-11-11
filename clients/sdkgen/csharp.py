"""The C# emitter: `Api` over `Gamend.Rest`, typed models, and the realtime names.

Writes into `csharp_sdk/`, the game's half of the API only (`Model.player()`).
`src/Gamend/Generated/Api.g.cs` is one method per operation, named as
`GamendApi.gd` names it in PascalCase; the arguments are the path's parameters
as `string`, then `JObject body` or `byte[] bytes`, then `JObject options` for
the query, and every method answers a `Task<Response>` that `Client.Poll()`
completes. A required path, body or query field that is missing refuses the
call: its task gets an error naming the field instead of the server getting a
request it would reject. `Events.g.cs` is one constant per realtime signal and
the table that names a socket message, `Commands.g.cs` one method per event a
channel answers, `Models.g.cs` a class per schema and `Codec.g.cs` their
readers and writers, written out so that nothing reaches for reflection, which
IL2CPP strips. `ProtoSchema.g.cs` is the field table of the realtime `.proto`.
`REFERENCE.md` lists the operations by tag. Everything else is the hand-written
`clients/csharp_template/`, copied over the top.
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

TEMPLATE = CLIENTS / "csharp_template"
OUT = ROOT / "csharp_sdk"
REGENERATE = "clients/generate_csharp.sh"
GENERATED = "src/Gamend/Generated"

BANNER = (
    "// Written by clients/sdkgen (csharp) from the OpenAPI document.\n"
    "// Do not edit; edit the generator or the spec and run\n"
    "// clients/generate_csharp.sh.\n"
)

# C#'s keywords, which a path parameter could otherwise collide with when it
# becomes an argument name, plus the names the generated methods use themselves.
KEYWORDS = {
    "abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char",
    "checked", "class", "const", "continue", "decimal", "default", "delegate",
    "do", "double", "else", "enum", "event", "explicit", "extern", "false",
    "finally", "fixed", "float", "for", "foreach", "goto", "if", "implicit",
    "in", "int", "interface", "internal", "is", "lock", "long", "namespace",
    "new", "null", "object", "operator", "out", "override", "params", "private",
    "protected", "public", "readonly", "ref", "return", "sbyte", "sealed",
    "short", "sizeof", "stackalloc", "static", "string", "struct", "switch",
    "this", "throw", "true", "try", "typeof", "uint", "ulong", "unchecked",
    "unsafe", "ushort", "using", "virtual", "void", "volatile", "while",
}
ARGUMENT_NAMES = KEYWORDS | {"body", "bytes", "options", "path"}

# What a model property would hide or clash with on every class.
OBJECT_MEMBERS = {
    "Equals", "Finalize", "GetHashCode", "GetType", "MemberwiseClone",
    "ReferenceEquals", "ToString",
}

# Names `Models.g.cs` and `Codec.g.cs` use unqualified. A schema with one of
# these needs a decision, not a silently broken build.
TAKEN_TYPES = {
    "Codec", "Dictionary", "Func", "JObject", "JToken", "JValue", "List",
    "Page", "Reader", "Type", "Writer",
}

EVENTS_MEMBERS = {"ChannelOf", "Events", "Message", "Row", "SignalOf", "Table"}


def pascal(name: str) -> str:
    """`lobbies_quick_join` as `LobbiesQuickJoin`."""
    parts = [part for part in re.split(r"[^A-Za-z0-9]+", name) if part]
    out = "".join(part[:1].upper() + part[1:] for part in parts)
    return f"_{out}" if out[:1].isdigit() else out


def argument(name: str) -> str:
    """`user_id` as the argument `userId`, clear of keywords."""
    word = pascal(name)
    word = word[:1].lower() + word[1:]
    return f"{word}_" if word in ARGUMENT_NAMES else word


def member(name: str, enclosing: str) -> str:
    """A field as a property of `enclosing`, which C# forbids it to equal."""
    word = pascal(name)
    return f"{word}_" if word == enclosing or word in OBJECT_MEMBERS else word


def quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def xml(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def summary_lines(text: str, indent: str) -> list[str]:
    prefix = f"{indent}///"
    return [
        f"{prefix} <summary>",
        *wrap(xml(text), 96, prefix),
        f"{prefix} </summary>",
    ]


def remarks_lines(lines: list[str], indent: str) -> list[str]:
    if not lines:
        return []
    prefix = f"{indent}///"
    out = [f"{prefix} <remarks>"]
    for line in lines:
        out += wrap(xml(line), 96, prefix)
    return out + [f"{prefix} </remarks>"]


def parameters(op: dict, with_options: bool) -> list[str]:
    args = [f"string {argument(p)}" for p in op["path_params"]]
    kind = body_kind(op)
    if kind == "json":
        args.append("JObject body")
    elif kind == "bytes":
        args.append("byte[] bytes")
    if op["query"] and with_options:
        args.append("JObject options")
    return args


def short_form(op: dict) -> bool:
    """Whether the method also comes without `options`: when no query key is
    required, leaving them all out is a call of its own."""
    return bool(op["query"]) and not any(needed for _, needed in op["query"])


def fields_line(label: str, fields: list[tuple[str, bool]]) -> list[str]:
    if not fields:
        return []
    listed = ", ".join(f"{name}{' (required)' if needed else ''}" for name, needed in fields)
    return [f"{label}: {listed}."]


def remarks_of(model: Model, op: dict) -> list[str]:
    out = [f"{op['method']} {op['path']}"]
    out += fields_line("body", body_fields(model, op))
    out += fields_line("options", op["query"])
    if body_kind(op) == "bytes":
        out.append("bytes go as application/octet-stream; Rest.Send with Body.Raw sends another type.")
    if op["binary_reply"]:
        out.append("The reply is raw bytes, in Response.Bytes.")
    if op["id"] in SESSION_OPS:
        out.append("Answers a session without keeping it: Client.Auth signs in.")
    return out


def path_expression(op: dict) -> str:
    """The expression that builds the path, each parameter escaped."""
    parts = re.split(r"\{([^}]+)\}", op["path"])
    pieces = [quote(parts[0])] if parts[0] else []
    for i in range(1, len(parts), 2):
        pieces.append(f"Query.Escape({argument(parts[i])})")
        if parts[i + 1]:
            pieces.append(quote(parts[i + 1]))
    return " + ".join(pieces)


def method(model: Model, op: dict, name: str) -> str:
    out = summary_lines(op["summary"] or name, "        ")
    out += remarks_lines(remarks_of(model, op), "        ")
    out.append(f"        public Task<Response> {name}({', '.join(parameters(op, True))})")
    out.append("        {")
    for param in op["path_params"]:
        out.append(f"            if (string.IsNullOrEmpty({argument(param)})) "
                   f"return _rest.Refuse({quote(name)}, {quote(param)});")
    for field, _ in [f for f in body_fields(model, op) if f[1]]:
        out.append(f"            if (!Query.Given(body, {quote(field)})) "
                   f"return _rest.Refuse({quote(name)}, {quote(field)});")
    for field in [q for q, needed in op["query"] if needed]:
        out.append(f"            if (!Query.Given(options, {quote(field)})) "
                   f"return _rest.Refuse({quote(name)}, {quote(field)});")
    out.append(f"            var path = {path_expression(op)};")
    if op["query"]:
        allowed = ", ".join(quote(q) for q, _ in op["query"])
        out.append(f"            path += Query.Build(options, {allowed});")
    kind = body_kind(op)
    body = {"json": "Body.Of(body)", "bytes": "Body.Raw(bytes)", "": "Body.None"}[kind]
    out.append(f"            return _rest.Send({quote(op['method'])}, path, {body});")
    out.append("        }")
    if short_form(op):
        forwarded = [argument(p) for p in op["path_params"]]
        if kind == "json":
            forwarded.append("body")
        elif kind == "bytes":
            forwarded.append("bytes")
        forwarded.append("null")
        out.append("")
        out += summary_lines(op["summary"] or name, "        ")
        out.append(f"        public Task<Response> {name}({', '.join(parameters(op, False))})")
        out.append("        {")
        out.append(f"            return {name}({', '.join(forwarded)});")
        out.append("        }")
    return "\n".join(out)


def names(model: Model) -> list[tuple[dict, str]]:
    seen: dict[str, str] = {}
    out = []
    for op in model.ops:
        name = member(model.name(op), "Api")
        if name in seen:
            raise SystemExit(f"{name}: {op['id']} and {seen[name]} want the same name")
        seen[name] = op["id"]
        out.append((op, name))
    return out


def write_api(model: Model) -> str:
    by_tag: dict[str, list[str]] = {}
    for op, name in names(model):
        by_tag.setdefault(op["tag"], []).append(method(model, op, name))
    sections = "\n\n".join(
        f"        // {tag}\n\n" + "\n\n".join(methods) for tag, methods in by_tag.items()
    )
    return (
        BANNER
        + "//\n"
        "// Every Gamend operation a game can call, one method each, named as the\n"
        "// Godot SDK names it. A method takes the path's own parameters, then `body`\n"
        "// for the request body and `options` for the query where the operation has\n"
        "// them, and answers a task that `Client.Poll()` completes:\n"
        "//\n"
        "//     var body = new JObject { [\"title\"] = \"duel\", [\"max_users\"] = 2 };\n"
        "//     var reply = await client.Api.LobbiesQuickJoin(body);\n"
        "//     if (reply.Ok) Use(reply.Data);\n"
        "using System.Threading.Tasks;\n"
        "using Newtonsoft.Json.Linq;\n"
        "\n"
        "namespace Gamend\n"
        "{\n"
        "    /// <summary>Every REST operation, one method each.</summary>\n"
        "    public sealed class Api\n"
        "    {\n"
        "        private readonly Rest _rest;\n"
        "\n"
        "        internal Api(Rest rest)\n"
        "        {\n"
        "            _rest = rest;\n"
        "        }\n"
        "\n"
        f"{sections}\n"
        "    }\n"
        "}\n"
    )


def write_events(model: Model) -> str:
    seen: dict[str, str] = {}
    for signal in model.signals():
        name = pascal(signal)
        if name in EVENTS_MEMBERS or name in seen:
            raise SystemExit(f"{signal}: its constant {name} is taken in Events")
        seen[name] = signal
    constants = "\n".join(
        f"        public const string {name} = {quote(signal)};" for name, signal in seen.items()
    )
    rows = "\n".join(
        f"            new Row({quote(row['channel'])}, {quote(row['event'])}, {quote(row['signal'])}),"
        for row in model.table
    )
    return (
        BANNER
        + "//\n"
        "// The realtime events, one constant each, and the table that names a socket\n"
        "// message. OpenAPI does not describe the socket, so this comes from\n"
        "// `clients/events.json`. An event the table does not name is `Message`.\n"
        "namespace Gamend\n"
        "{\n"
        "    /// <summary>The realtime signals, and how a socket message maps to one.</summary>\n"
        "    public static class Events\n"
        "    {\n"
        f"{constants}\n"
        '        public const string Message = "message";\n'
        "\n"
        "        /// <summary>One row of the table: the channel a topic belongs to, the event the\n"
        "        /// server sends on it, and the signal this SDK calls it.</summary>\n"
        "        public sealed class Row\n"
        "        {\n"
        "            public string Channel { get; }\n"
        "            public string Event { get; }\n"
        "            public string Signal { get; }\n"
        "\n"
        "            internal Row(string channel, string eventName, string signal)\n"
        "            {\n"
        "                Channel = channel;\n"
        "                Event = eventName;\n"
        "                Signal = signal;\n"
        "            }\n"
        "        }\n"
        "\n"
        "        public static readonly Row[] Table =\n"
        "        {\n"
        f"{rows}\n"
        "        };\n"
        "\n"
        "        /// <summary>The channel a topic names: `lobby:12` is `lobby`, `lobbies` is itself.</summary>\n"
        "        public static string ChannelOf(string topic)\n"
        "        {\n"
        "            var colon = topic.IndexOf(':');\n"
        "            return colon < 0 ? topic : topic.Substring(0, colon);\n"
        "        }\n"
        "\n"
        "        /// <summary>The signal a message on `topic` named `eventName` is, or `Message`.</summary>\n"
        "        public static string SignalOf(string topic, string eventName)\n"
        "        {\n"
        "            var channel = ChannelOf(topic);\n"
        "            foreach (var row in Table)\n"
        "            {\n"
        "                if (row.Channel == channel && row.Event == eventName) return row.Signal;\n"
        "            }\n"
        "            return Message;\n"
        "        }\n"
        "    }\n"
        "}\n"
    )


def command(row: dict) -> str:
    """One command as a method: to the caller's channel, or a named one's."""
    on_user = row["channel"] == "user"
    args = ["Realtime realtime"]
    if not on_user:
        args.append("string id")
    fields = [(key, True) for key in row["required"]] + [(key, False) for key in row["optional"]]
    if fields:
        args.append("JObject parameters")
    where = "the user channel" if on_user else f"{row['channel']}:<id>"
    doc = summary_lines(f"{row['event']} on {where}.", "        ")
    if fields:
        listed = ", ".join(f"{key}{' (required)' if needed else ''}" for key, needed in fields)
        doc += remarks_lines([f"parameters: {listed}."], "        ")
    topic = "realtime.UserTopic" if on_user else f'{quote(row["channel"] + ":")} + id'
    payload = "parameters" if fields else "new JObject()"
    name = member(row["name"], "Commands")
    return "\n".join(
        doc
        + [
            f"        public static Task<Reply> {name}({', '.join(args)})",
            "        {",
            f"            return realtime.Push({topic}, {quote(row['event'])}, {payload});",
            "        }",
        ]
    )


def write_commands(model: Model) -> str:
    names_seen = [member(row["name"], "Commands") for row in model.commands]
    if len(set(names_seen)) != len(names_seen):
        raise SystemExit("commands.json: two commands want the same method name")
    body = "\n\n".join(command(row) for row in model.commands)
    return (
        BANNER
        + "//\n"
        "// Every event a channel answers, one method each, from\n"
        "// `clients/commands.json`. Each is a `Realtime.Push` with its topic and event\n"
        "// filled in, and answers the same way:\n"
        "//\n"
        '//     var reply = await Commands.ResultsList(client.Realtime, new JObject { ["kind"] = "match" });\n'
        "using System.Threading.Tasks;\n"
        "using Newtonsoft.Json.Linq;\n"
        "\n"
        "namespace Gamend\n"
        "{\n"
        "    /// <summary>Every event a channel answers, one method each.</summary>\n"
        "    public static class Commands\n"
        "    {\n"
        f"{body}\n"
        "    }\n"
        "}\n"
    )


def write_reference(model: Model) -> str:
    lines = [
        "# Gamend C# SDK reference",
        "",
        "Written by `clients/sdkgen` (csharp) from the OpenAPI document. "
        f"{len(model.ops)} operations on `client.Api`, and "
        f"{len(model.signals())} realtime signals in `Gamend.Events`.",
        "",
        "Arguments are the path's parameters, then `body` (the request body), then",
        "`options` (the query). `src/Gamend/Generated/Api.g.cs` lists each operation's",
        "fields.",
        "",
    ]
    by_tag: dict[str, list[tuple[dict, str]]] = {}
    for op, name in names(model):
        by_tag.setdefault(op["tag"], []).append((op, name))
    for tag in sorted(by_tag):
        lines += [f"## {tag}", "", "| Method | Call | What it does |", "| --- | --- | --- |"]
        for op, name in by_tag[tag]:
            args = [argument(p) for p in op["path_params"]]
            kind = body_kind(op)
            if kind:
                args.append("body" if kind == "json" else "bytes")
            if op["query"]:
                args.append("options")
            text = op["summary"].replace("|", "\\|")
            lines.append(f"| `{name}({', '.join(args)})` | `{op['method']} {op['path']}` | {text} |")
        lines.append("")
    return "\n".join(lines)


class Types:
    """How the schemas read in C#, once it is known which of them have a class."""

    def __init__(self, model: Model) -> None:
        self.models = models_of(model)
        for name, _ in self.models:
            if name in TAKEN_TYPES or name in KEYWORDS:
                raise SystemExit(f"{name}: a schema with this name clashes in the C# models")
        self.classes = {name for name, schema in self.models if self.has_class(schema)}

    @staticmethod
    def map_values(schema: dict) -> dict | None:
        values = schema.get("additionalProperties")
        if schema.get("type") == "object" and isinstance(values, dict) and not schema.get("properties"):
            return values
        return None

    def has_class(self, schema: dict) -> bool:
        return bool(schema.get("properties")) or self.map_values(schema) is not None

    def of(self, schema: dict) -> str:
        """The C# type of a property or an item."""
        ref = ref_name(schema)
        if ref:
            return ref if ref in self.classes else "JToken"
        kind = schema.get("type")
        if kind == "array":
            return f"List<{self.of(schema.get('items', {}))}>"
        values = self.map_values(schema)
        if values is not None:
            return f"Dictionary<string, {self.of(values)}>"
        base = {"string": "string", "integer": "long", "number": "double", "boolean": "bool"}.get(kind)
        if base is None:
            return "JToken"
        return f"{base}?" if schema.get("nullable") and base != "string" else base

    def initial(self, schema: dict) -> str:
        """What a property starts as: `" = new X()"`, or nothing for null."""
        kind = self.of(schema)
        if kind == "string" and not schema.get("nullable"):
            return ' = "";'
        if kind == "JToken":
            return " = JValue.CreateNull();"
        if kind.startswith(("List<", "Dictionary<")):
            return f" = new {kind}();"
        if kind in self.classes and not schema.get("nullable"):
            return f" = new {kind}();"
        return ""

    def reader(self, schema: dict) -> str:
        """An expression that is the `Reader<T>` of `self.of(schema)`."""
        ref = ref_name(schema)
        if ref:
            return f"Read{ref}" if ref in self.classes else "ReadToken"
        kind = schema.get("type")
        if kind == "array":
            items = schema.get("items", {})
            return f"ListOf<{self.of(items)}>({self.reader(items)})"
        values = self.map_values(schema)
        if values is not None:
            return f"MapOf<{self.of(values)}>({self.reader(values)})"
        plain = {
            "string": ("string", "ReadString"),
            "integer": ("long", "ReadLong"),
            "number": ("double", "ReadDouble"),
            "boolean": ("bool", "ReadBool"),
        }.get(kind)
        if plain is None:
            return "ReadToken"
        base, read = plain
        return f"Maybe<{base}>({read})" if schema.get("nullable") and base != "string" else read

    def writer(self, schema: dict) -> str:
        """An expression that is the `Writer<T>` of `self.of(schema)`."""
        ref = ref_name(schema)
        if ref:
            return f"Write{ref}" if ref in self.classes else "WriteToken"
        kind = schema.get("type")
        if kind == "array":
            items = schema.get("items", {})
            return f"ListWriter<{self.of(items)}>({self.writer(items)})"
        values = self.map_values(schema)
        if values is not None:
            return f"MapWriter<{self.of(values)}>({self.writer(values)})"
        plain = {
            "string": ("string", "WriteString"),
            "integer": ("long", "WriteLong"),
            "number": ("double", "WriteDouble"),
            "boolean": ("bool", "WriteBool"),
        }.get(kind)
        if plain is None:
            return "WriteToken"
        base, write = plain
        return f"MaybeWriter<{base}>({write})" if schema.get("nullable") and base != "string" else write

    def properties(self, name: str, schema: dict) -> list[tuple[str, str, dict]]:
        """A class's (wire name, member, schema), no two members alike."""
        out, seen = [], {}
        for prop, spec in schema.get("properties", {}).items():
            word = member(prop, name)
            if word in seen:
                raise SystemExit(f"{name}: {prop} and {seen[word]} want the same property")
            seen[word] = prop
            out.append((prop, word, spec))
        return out


def write_models(model: Model) -> str:
    types = Types(model)
    classes = []
    for name, schema in types.models:
        if not types.has_class(schema):
            continue
        doc = summary_lines(schema.get("description") or schema.get("title") or name, "    ")
        values = types.map_values(schema)
        if values is not None:
            # A map (currency -> balance): the dictionary itself, read by its codec.
            classes.append("\n".join(doc + [
                f"    public sealed class {name} : Dictionary<string, {types.of(values)}>",
                "    {",
                "    }",
            ]))
            continue
        lines = doc + [f"    public sealed class {name}", "    {"]
        for prop, word, spec in types.properties(name, schema):
            if spec.get("description"):
                lines += summary_lines(spec["description"], "        ")
            lines.append(f"        public {types.of(spec)} {word} {{ get; set; }}{types.initial(spec)}")
        lines += ["    }"]
        classes.append("\n".join(lines))
    return (
        BANNER
        + "//\n"
        "// A class for every schema the API answers with, read from a reply with\n"
        "// `Response.As`:\n"
        "//\n"
        "//     var lobby = reply.As<Models.Lobby>();\n"
        "//     var page = reply.Page<Models.Lobby>();\n"
        "//\n"
        "// A field the reply leaves out keeps its default; a nullable one is null; a\n"
        "// free-form map stays `JToken`.\n"
        "using System.Collections.Generic;\n"
        "using Newtonsoft.Json.Linq;\n"
        "\n"
        "namespace Gamend.Models\n"
        "{\n"
        + "\n\n".join(classes)
        + "\n\n"
        "    /// <summary>A page of a list: the items, and where they sit in the whole.</summary>\n"
        "    public sealed class Page<T>\n"
        "    {\n"
        "        public List<T> Data { get; set; } = new List<T>();\n"
        "        public PageMeta Meta { get; set; } = new PageMeta();\n"
        "    }\n"
        "}\n"
    )


def codec_of(types: Types, name: str, schema: dict) -> str:
    values = types.map_values(schema)
    if values is not None:
        return "\n".join([
            f"        public static bool Read{name}(JToken j, out {name} value)",
            "        {",
            "            value = null;",
            "            var o = j as JObject;",
            "            if (o == null) return false;",
            f"            value = new {name}();",
            f"            Fill<{types.of(values)}>(o, value, {types.reader(values)});",
            "            return true;",
            "        }",
            "",
            f"        public static JToken Write{name}({name} v)",
            "        {",
            f"            return MapWriter<{types.of(values)}>({types.writer(values)})(v);",
            "        }",
        ])
    props = types.properties(name, schema)
    read = [
        f"        public static bool Read{name}(JToken j, out {name} value)",
        "        {",
        "            value = null;",
        "            var o = j as JObject;",
        "            if (o == null) return false;",
        f"            var v = new {name}();",
    ]
    read += [
        f"            v.{word} = Field<{types.of(spec)}>(o, {quote(prop)}, {types.reader(spec)}, v.{word});"
        for prop, word, spec in props
    ]
    read += ["            value = v;", "            return true;", "        }"]
    write = [
        f"        public static JToken Write{name}({name} v)",
        "        {",
        "            if (v == null) return JValue.CreateNull();",
        "            var j = new JObject();",
    ]
    write += [
        f"            j[{quote(prop)}] = {types.writer(spec)}(v.{word});"
        for prop, word, spec in props
    ]
    write += ["            return j;", "        }"]
    return "\n".join(read + [""] + write)


SCALAR_READERS = [
    ("string", "ReadString"), ("long", "ReadLong"), ("double", "ReadDouble"),
    ("bool", "ReadBool"), ("JToken", "ReadToken"),
]


def reader_entry(kind: str, read: str) -> str:
    """One row of the table `Response.As` looks a type up in. A lambda per row
    names the type outright, so IL2CPP keeps everything the row reads."""
    boxed = "(object)v" if kind in {"long", "double", "bool", "long?", "double?", "bool?"} else "v"
    return (
        f"            [typeof({kind})] = j => {{ {kind} v; "
        f"return {read}(j, out v) ? {boxed} : null; }},"
    )


def write_codec(model: Model) -> str:
    types = Types(model)
    bodies = []
    table: dict[str, str] = {}
    for kind, read in SCALAR_READERS:
        table[kind] = read
        table[f"List<{kind}>"] = f"ListOf<{kind}>({read})"
        table[f"Dictionary<string, {kind}>"] = f"MapOf<{kind}>({read})"
    for kind, read in (("long", "ReadLong"), ("double", "ReadDouble"), ("bool", "ReadBool")):
        table[f"{kind}?"] = f"Maybe<{kind}>({read})"
    for name, schema in types.models:
        if not types.has_class(schema):
            continue
        bodies.append(codec_of(types, name, schema))
        table[name] = f"Read{name}"
        table[f"List<{name}>"] = f"ListOf<{name}>(Read{name})"
        values = types.map_values(schema)
        if values is not None:
            table[f"Dictionary<string, {types.of(values)}>"] = (
                f"MapOf<{types.of(values)}>({types.reader(values)})"
            )
    entries = "\n".join(reader_entry(kind, read) for kind, read in table.items())
    return (
        BANNER
        + "//\n"
        "// The reader and the writer of every model, written out field by field: no\n"
        "// reflection, nothing for IL2CPP to strip. Reads are lenient and never throw:\n"
        "// a field that is missing or of the wrong type keeps its default.\n"
        "using System;\n"
        "using System.Collections.Generic;\n"
        "using Newtonsoft.Json.Linq;\n"
        "\n"
        "namespace Gamend.Models\n"
        "{\n"
        "    public static partial class Codec\n"
        "    {\n"
        + "\n\n".join(bodies)
        + "\n\n"
        "        /// <summary>What `Response.As` and `Response.Page` look a type up in.</summary>\n"
        "        internal static readonly Dictionary<Type, Func<JToken, object>> Readers =\n"
        "            new Dictionary<Type, Func<JToken, object>>\n"
        "        {\n"
        f"{entries}\n"
        "        };\n"
        "    }\n"
        "}\n"
    )


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
                f"            new Field({f['number']}, {quote(f['name'])}, "
                f"Label.{f['label']}, FieldType.{type_}, {message}),"
            )
        tables.append(
            f"        private static readonly Field[] Fields{name} =\n        {{\n"
            + "\n".join(rows)
            + "\n        };"
        )
    entries = "\n".join(f"            new Message({quote(name)}, Fields{name})," for name, _ in messages)
    return (
        BANNER
        + "//\n"
        "// Every message of proto/gamend_realtime.proto as a field table, which\n"
        "// Proto.cs decodes the wire format against.\n"
        "namespace Gamend\n"
        "{\n"
        "    internal static partial class Proto\n"
        "    {\n"
        + "\n\n".join(tables)
        + "\n\n"
        "        internal static readonly Message[] Messages =\n"
        "        {\n"
        f"{entries}\n"
        "        };\n"
        "    }\n"
        "}\n"
    )


def emit(model: Model) -> dict[str, str]:
    player = model.player()
    return {
        f"{GENERATED}/Api.g.cs": write_api(player),
        f"{GENERATED}/Events.g.cs": write_events(player),
        f"{GENERATED}/Commands.g.cs": write_commands(player),
        f"{GENERATED}/Models.g.cs": write_models(player),
        f"{GENERATED}/Codec.g.cs": write_codec(player),
        f"{GENERATED}/ProtoSchema.g.cs": write_proto_schema(player),
        "REFERENCE.md": write_reference(player),
    }


def summary(model: Model) -> str:
    player = model.player()
    return (
        f"wrote {len(player.ops)} operations, {len(player.signals())} events "
        f"and {len(player.commands)} commands"
    )
