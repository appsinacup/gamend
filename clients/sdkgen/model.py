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


def load() -> Model:
    spec = json.loads(SPEC.read_text())
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
