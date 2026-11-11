"""What every emitter reads: the operations, the realtime table and the names.

The OpenAPI document says what the REST layer is; `clients/events.json` says
what the socket sends and `clients/commands.json` what it answers, since
OpenAPI describes neither; and
`clients/balaur_names.json` holds the names the Godot façade chose where they
differ from `<tag>_<operationId>`, so a game ported between engines calls the
same thing.
"""

import json
import re
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLIENTS = HERE.parent
ROOT = CLIENTS.parent
SPEC = CLIENTS / "godot" / "openapi.json"
EVENTS = CLIENTS / "events.json"
COMMANDS = CLIENTS / "commands.json"
NAMES = CLIENTS / "balaur_names.json"

METHODS = ("get", "post", "put", "patch", "delete")
ADMIN_PATHS = "/api/v1/admin"


@dataclass
class Model:
    spec: dict
    ops: list[dict]
    table: list[dict]
    commands: list[dict]
    aliases: dict[str, str]

    def name(self, op: dict) -> str:
        return function_name(op, self.aliases)

    def signals(self) -> list[str]:
        return sorted({row["signal"] for row in self.table})

    def player(self) -> "Model":
        """This model without the admin API: what a shipped game can call.

        A game never holds an admin token, so the 100-odd admin operations and
        the schemas only they reach are dead weight in its build.
        """
        paths = {
            path: item
            for path, item in self.spec["paths"].items()
            if not path.startswith(ADMIN_PATHS)
        }
        schemas = self.spec["components"]["schemas"]
        reached: set[str] = set()
        waiting = list(refs(paths))
        while waiting:
            name = waiting.pop()
            if name not in reached:
                reached.add(name)
                waiting.extend(refs(schemas[name]))
        spec = {
            **self.spec,
            "paths": paths,
            "components": {
                **self.spec["components"],
                "schemas": {name: schemas[name] for name in schemas if name in reached},
            },
        }
        return Model(spec, operations(spec), self.table, self.commands, self.aliases)


def load(document: Path = SPEC) -> Model:
    spec = json.loads(document.read_text())
    return Model(
        spec=spec,
        ops=operations(spec),
        table=json.loads(EVENTS.read_text()),
        commands=json.loads(COMMANDS.read_text()),
        aliases=json.loads(NAMES.read_text()),
    )


def snake(text: str) -> str:
    """A tag as the prefix its functions carry: `Admin – KV` is `admin_kv`."""
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def operations(spec: dict) -> list[dict]:
    """Every operation, with what a call needs to make it."""
    out = []
    for path, item in spec["paths"].items():
        for method, op in item.items():
            if method not in METHODS:
                continue
            params = op.get("parameters", [])
            body = {}
            for kind, content in op.get("requestBody", {}).get("content", {}).items():
                body = {"type": kind, "schema": content.get("schema", {})}
                break
            out.append(
                {
                    "id": op["operationId"],
                    "tag": op.get("tags", ["Other"])[0],
                    "method": method.upper(),
                    "path": path,
                    "summary": op.get("summary", "").strip(),
                    "path_params": [p["name"] for p in params if p.get("in") == "path"],
                    "query": [
                        (p["name"], bool(p.get("required")))
                        for p in params
                        if p.get("in") == "query"
                    ],
                    "body": body,
                    "binary_reply": any(
                        kind != "application/json"
                        for reply in op.get("responses", {}).values()
                        for kind in (reply.get("content") or {})
                    ),
                }
            )
    out.sort(key=lambda o: (snake(o["tag"]), o["id"]))
    return out


def function_name(op: dict, aliases: dict[str, str]) -> str:
    """`<tag>_<operationId>`, unless the Godot façade chose another name."""
    return aliases.get(op["id"], f"{snake(op['tag'])}_{op['id']}")


def refs(node) -> Iterator[str]:
    """The component named by every `$ref` under `node`."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "$ref":
                yield value.rsplit("/", 1)[-1]
            else:
                yield from refs(value)
    elif isinstance(node, list):
        for value in node:
            yield from refs(value)


def resolve(spec: dict, schema: dict) -> dict:
    """A schema with its `$ref` followed, so its fields can be read."""
    while "$ref" in schema:
        schema = spec["components"]["schemas"][schema["$ref"].rsplit("/", 1)[-1]]
    return schema


def wrap(text: str, width: int, prefix: str) -> list[str]:
    """`text` as comment lines, so a long summary does not run off the page."""
    words, lines, line = text.split(), [], prefix
    for word in words:
        candidate = f"{line} {word}" if line != prefix else f"{prefix} {word}"
        if len(candidate) > width and line != prefix:
            lines.append(line)
            line = f"{prefix} {word}"
        else:
            line = candidate
    if line != prefix:
        lines.append(line)
    return lines or [prefix]


# Operations that answer a session. `Auth` makes these calls and keeps what
# they answer; the generated method only makes the call. Not `register`: it
# answers the new account, and signs nobody in. Its code does
# (`confirm_registration`).
SESSION_OPS = {
    "device_login", "login", "refresh_token", "oauth_api_callback",
    "oauth_google_id_token", "oauth_callback_api_apple_ios", "oauth_session_status",
    "confirm_registration",
}


def body_kind(op: dict) -> str:
    """`json`, `bytes`, or empty for an operation without a body."""
    if not op["body"]:
        return ""
    return "json" if op["body"]["type"] == "application/json" else "bytes"


def body_fields(model: Model, op: dict) -> list[tuple[str, bool]]:
    if body_kind(op) != "json":
        return []
    schema = resolve(model.spec, op["body"]["schema"])
    required = list(schema.get("required", []))
    rest = [name for name in schema.get("properties", {}) if name not in required]
    return [(name, True) for name in required] + [(name, False) for name in rest]


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
