"""The TypeScript declarations of the JavaScript package.

Writes `clients/javascript/dist/index.d.ts`. The package stays the plain
JavaScript openapi-generator writes, so nothing that already imports it
changes; this describes it. Every operation is its two methods as generated
(`getLobby(id)` and `getLobbyWithHttpInfo(id)`, required parameters first, the
rest in `opts`), every schema a class, and `clients/events.json` a union of
event names per channel. `clients/gamend_client.d.ts` is the hand-written half.

`lint --generated` compares the signatures here with the generated JavaScript.
"""

import json
import re

from model import CLIENTS, Model, ref_name

OUT = CLIENTS / "javascript" / "dist"
TEMPLATE = None
REGENERATE = "python3 clients/sdkgen ts"
HAND_WRITTEN = CLIENTS / "gamend_client.d.ts"

BANNER = (
    "// Written by clients/sdkgen (ts) from the OpenAPI document and\n"
    "// clients/gamend_client.d.ts. Do not edit.\n"
)

IDENTIFIER = re.compile(r"^[A-Za-z_$][A-Za-z0-9_$]*$")


def camel(name: str) -> str:
    return re.sub(r"_(\w)", lambda m: m.group(1).upper(), name)


def api_class(tag: str) -> str:
    """The class openapi-generator writes for a tag: `Admin – KV` is `AdminKVApi`."""
    words = [word for word in re.split(r"[^A-Za-z0-9]+", tag) if word]
    return "".join(word[0].upper() + word[1:] for word in words) + "Api"


def comment(text: str, indent: str) -> list[str]:
    text = " ".join(text.split()).replace("*/", "* /")
    return [f"{indent}/** {text} */"] if text else []


def property_key(name: str) -> str:
    return name if IDENTIFIER.match(name) else json.dumps(name)


def is_map(schema: dict) -> bool:
    """A schema that is only a map: openapi-generator writes no class for it."""
    return not schema.get("properties") and "additionalProperties" in schema


def members(schema: dict) -> list[tuple[str, str, dict]]:
    """Each property as its key, `?` when optional, and its schema."""
    required = set(schema.get("required", []))
    return [
        (name, "" if name in required else "?", value)
        for name, value in schema.get("properties", {}).items()
    ]


def ts_type(schema: dict) -> str:
    ref = ref_name(schema)
    if ref:
        text = ref
    else:
        kind = schema.get("type")
        if kind == "array":
            inner = ts_type(schema.get("items", {}))
            text = f"({inner})[]" if " | " in inner else f"{inner}[]"
        elif schema.get("properties"):
            fields = "; ".join(
                f"{property_key(name)}{optional}: {ts_type(value)}"
                for name, optional, value in members(schema)
            )
            text = f"{{ {fields} }}"
        elif kind == "object" or "additionalProperties" in schema:
            values = schema.get("additionalProperties")
            inner = ts_type(values) if isinstance(values, dict) and values else "any"
            text = f"Record<string, {inner}>"
        elif kind == "string" and "enum" in schema:
            text = " | ".join(json.dumps(value) for value in schema["enum"])
        elif kind == "string":
            # The generated code turns these into Date objects as it reads them.
            text = {"date-time": "Date", "date": "Date", "binary": "Blob"}.get(
                schema.get("format"), "string"
            )
        elif kind in ("integer", "number"):
            text = "number"
        elif kind == "boolean":
            text = "boolean"
        else:
            return "any"
    return f"{text} | null" if schema.get("nullable") else text


def enum_name(prop: str) -> str:
    return "".join(word[:1].upper() + word[1:] for word in prop.split("_")) + "Enum"


def write_model(name: str, schema: dict) -> str:
    out = comment(schema.get("description") or "", "")
    if is_map(schema):
        out.append(f"export type {name} = {ts_type(schema)};")
        return "\n".join(out)
    out.append(f"export class {name} {{")
    out.append("  constructor(...required: any[]);")
    out.append(f"  static constructFromObject(data: unknown, obj?: {name}): {name};")
    out.append("  static validateJSON(data: unknown): boolean;")
    for prop, _, value in members(schema):
        if value.get("type") == "string" and "enum" in value:
            entries = "; ".join(f"readonly {json.dumps(v)}: {json.dumps(v)}" for v in value["enum"])
            out.append(f"  static readonly {enum_name(prop)}: {{ {entries} }};")
    for prop, optional, value in members(schema):
        out += comment(value.get("description") or "", "  ")
        out.append(f"  {property_key(prop)}{optional}: {ts_type(value)};")
    out.append("}")
    return "\n".join(out)


def operation_of(model: Model, op: dict) -> dict:
    return model.spec["paths"][op["path"]][op["method"].lower()]


def body_key(raw: dict) -> str | None:
    """The `opts` key the generated method reads its body from."""
    body = raw.get("requestBody")
    if not body:
        return None
    schema = next(iter(body["content"].values()))["schema"]
    name = ref_name(schema) or schema.get("title")
    if name:
        return name[0].lower() + name[1:]
    return "requestBody" if schema.get("properties") or "additionalProperties" in schema else "body"


def body_schema(raw: dict) -> dict:
    return next(iter(raw["requestBody"]["content"].values()))["schema"]


def positional(raw: dict) -> list[dict]:
    return [p for p in raw.get("parameters", []) if p.get("required")]


def opts_entries(raw: dict) -> list[tuple[str, str, str]]:
    """What the method reads from `opts`: key, type, description."""
    entries = [
        (camel(p["name"]), ts_type(p.get("schema", {})), p.get("description") or "")
        for p in raw.get("parameters", [])
        if not p.get("required")
    ]
    key = body_key(raw)
    if key:
        entries.append((key, ts_type(body_schema(raw)), ""))
    return entries


def signature(model: Model, op: dict) -> list[str]:
    """The generated method's parameter names, in order."""
    raw = operation_of(model, op)
    names = [camel(p["name"]) for p in positional(raw)]
    return names + ["opts"] if opts_entries(raw) else names


def result_type(raw: dict) -> str:
    for status in sorted(raw.get("responses", {})):
        if not status.startswith("2"):
            continue
        content = raw["responses"][status].get("content") or {}
        if "application/json" in content:
            return ts_type(content["application/json"]["schema"])
        if content:
            return "any"
        return "null"
    return "any"


def write_method(model: Model, op: dict) -> list[str]:
    raw = operation_of(model, op)
    args = [f"{camel(p['name'])}: {ts_type(p.get('schema', {}))}" for p in positional(raw)]
    entries = opts_entries(raw)
    if entries:
        fields = "; ".join(f"{key}?: {kind}" for key, kind, _ in entries)
        args.append(f"opts?: {{ {fields} }}")
    joined = ", ".join(args)
    name = camel(op["id"])
    result = result_type(raw)
    return [
        *comment(op["summary"], "  "),
        f"  {name}({joined}): Promise<{result}>;",
        f"  {name}WithHttpInfo({joined}): Promise<{{ data: {result}; response: any }}>;",
    ]


def write_apis(model: Model) -> list[str]:
    by_class: dict[str, list[dict]] = {}
    for op in model.ops:
        by_class.setdefault(api_class(op["tag"]), []).append(op)
    out = []
    for name in sorted(by_class):
        lines = [f"export class {name} {{", "  constructor(apiClient?: ApiClient);"]
        lines.append("  apiClient: ApiClient;")
        for op in by_class[name]:
            lines += write_method(model, op)
        lines.append("}")
        out.append("\n".join(lines))
    return out


def write_events(model: Model) -> list[str]:
    by_channel: dict[str, list[str]] = {}
    for row in model.table:
        names = by_channel.setdefault(row["channel"], [])
        if row["event"] not in names:
            names.append(row["event"])
    return [
        f"export type {channel.capitalize()}ChannelEvent =\n  "
        + "\n  | ".join(json.dumps(event) for event in names)
        + ";"
        for channel, names in sorted(by_channel.items())
    ]


def emit(model: Model) -> dict[str, str]:
    schemas = model.spec["components"]["schemas"]
    chunks = [
        BANNER.rstrip("\n"),
        HAND_WRITTEN.read_text().rstrip("\n"),
        *write_events(model),
        *[write_model(name, schema) for name, schema in sorted(schemas.items())],
        *write_apis(model),
    ]
    return {"index.d.ts": "\n\n".join(chunks) + "\n"}


def summary(model: Model) -> str:
    return (
        f"wrote {len(model.ops)} operations and "
        f"{len(model.spec['components']['schemas'])} schemas as TypeScript"
    )
