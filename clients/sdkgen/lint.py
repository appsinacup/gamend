"""Whether every SDK reaches everything the server offers.

    python3 clients/sdkgen lint               # what this checkout can read
    python3 clients/sdkgen lint --generated   # and openapi-generator's output (CI)

Four surfaces, from the same files the generators read: the OpenAPI document's
operations and schemas, the events the socket sends (`clients/events.json`) and
the events it answers (`clients/commands.json`). The C++ and Balaur SDKs are
checked through what their emitters write, the Godot and JavaScript clients
through their hand-written halves. What openapi-generator writes is not in the
repository, so `--generated` reads it where it lies on disk.

Exits 1 and names what is missing. A new operation, schema or event fails here
until each SDK has it.
"""

import re
from collections.abc import Callable, Iterable
from pathlib import Path

import balaur
import cpp
from model import CLIENTS, Model

GODOT = CLIENTS / "gamend_template"
GODOT_OUT = CLIENTS / "godot"
JS_OUT = CLIENTS / "javascript" / "src"

SDKS = ("JavaScript", "Godot", "C++", "Balaur")
FACADE_CALL = re.compile(r'_call_api\(\s*\w+\.new\(_config\),\s*"(\w+)"')


class Report:
    def __init__(self) -> None:
        self.cells: dict[str, dict[str, str]] = {}
        self.problems: list[str] = []

    def label(self, surface: str, sdk: str, text: str) -> None:
        self.cells.setdefault(surface, {})[sdk] = text

    def need(
        self, surface: str, sdk: str, wanted: Iterable[str], have: Callable[[str], bool]
    ) -> None:
        """Every one of `wanted` must satisfy `have`."""
        items = list(wanted)
        missing = [item for item in items if not have(item)]
        self.label(surface, sdk, f"{len(items) - len(missing)}/{len(items)}")
        if missing:
            self.problems.append(f"{sdk} {surface}: missing {', '.join(sorted(missing))}")

    def print(self) -> None:
        width = max(len(surface) for surface in self.cells) + 2
        print("".ljust(width) + "".join(sdk.ljust(12) for sdk in SDKS))
        for surface, cells in self.cells.items():
            print(surface.ljust(width) + "".join(cells.get(sdk, "-").ljust(12) for sdk in SDKS))
        for problem in self.problems:
            print(f"\n{problem}")


def text_of(paths: Iterable[Path]) -> str:
    return "\n".join(path.read_text() for path in paths)


def camel(name: str) -> str:
    return re.sub(r"_(\w)", lambda m: m.group(1).upper(), name)


def operations(report: Report, model: Model, generated: bool) -> None:
    surface = f"operations ({len(model.ops)})"
    ids = [op["id"] for op in model.ops]

    if generated and JS_OUT.is_dir():
        api = text_of(sorted((JS_OUT / "api").glob("*.js")))
        report.need(surface, "JavaScript", ids, lambda i: f" {camel(i)}(" in api)
    else:
        report.label(surface, "JavaScript", "generated")

    # What a game calls is the façade, written by hand, so it is what can lag.
    called = set(FACADE_CALL.findall((GODOT / "GamendApi.gd").read_text()))
    report.need(surface, "Godot", ids, lambda i: i in called)
    stale = called - set(ids)
    if stale:
        report.problems.append(
            f"Godot {surface}: GamendApi.gd calls what the API lacks: {', '.join(sorted(stale))}"
        )
    if generated and (GODOT_OUT / "apis").is_dir():
        apis = text_of(sorted((GODOT_OUT / "apis").glob("*.gd")))
        missing = [i for i in ids if f"func {i}(" not in apis]
        if missing:
            report.problems.append(f"Godot {surface}: not generated: {', '.join(missing)}")

    header = cpp.emit(model)["include/gamend/api.hpp"]
    report.need(surface, "C++", [model.name(op) for op in model.ops], lambda n: f" {n}(" in header)

    written = balaur.emit(model)
    report.need(
        surface,
        "Balaur",
        [f"{file}.bs::{name}" for file, ops in balaur.by_file(model).items() for name, _ in ops],
        lambda item: f"pub fn {item.split('::')[1]}(" in written[item.split("::")[0]],
    )


def schemas(report: Report, model: Model, generated: bool) -> None:
    every = model.spec["components"]["schemas"]
    surface = f"schemas ({len(every)})"

    # openapi-generator writes no class for a schema that is only a map
    # (currency -> balance): whatever uses it holds a plain map.
    classes = [
        name
        for name, schema in every.items()
        if schema.get("properties") or "additionalProperties" not in schema
    ]

    if generated and JS_OUT.is_dir():
        report.need(surface, "JavaScript", classes, lambda s: (JS_OUT / "model" / f"{s}.js").exists())
    else:
        report.label(surface, "JavaScript", "generated")

    # A generated model is `Gamend<Schema>`, and two scripts cannot share a
    # `class_name`: the clash fails the addon's compile, not the generator.
    written = set(
        re.findall(r"^class_name (\w+)", text_of(sorted(GODOT.glob("*.gd"))), re.MULTILINE)
    )
    clashing = sorted(s for s in every if f"Gamend{s}" in written)
    if clashing:
        report.problems.append(
            f"Godot {surface}: a hand-written class has the model's name: {', '.join(clashing)}"
        )
    if generated and (GODOT_OUT / "models").is_dir():
        report.need(surface, "Godot", classes, lambda s: (GODOT_OUT / "models" / f"Gamend{s}.gd").exists())
    else:
        report.label(surface, "Godot", "generated")

    # `{data}` and `{data, meta}` get no struct: `Response::as` and `page` read them.
    models = cpp.emit(model)["include/gamend/models.hpp"]
    report.need(
        surface,
        "C++",
        every,
        lambda s: cpp.is_envelope(every[s]) or f"struct {s} {{" in models or f"using {s} =" in models,
    )
    report.label(surface, "Balaur", "untyped")


def server_events(report: Report, model: Model) -> None:
    surface = f"server events ({len(model.table)})"

    # A JSON frame reaches `channel.on` as it came; only protobuf needs a decoder.
    decoders = (CLIENTS / "gamend_proto.js").read_text()
    binary = [row["event"] for row in model.table if row["message"]]
    report.need(
        surface,
        "JavaScript",
        binary,
        lambda e: re.search(rf"^\s*['\"]?{re.escape(e)}['\"]?\s*:", decoders, re.MULTILINE),
    )

    routing = text_of(GODOT / name for name in ("GamendApi.gd", "GamendWebRTC.gd", "GamendSignalingClient.gd"))
    report.need(surface, "Godot", [row["event"] for row in model.table], lambda e: f'"{e}"' in routing)

    events = cpp.emit(model)["include/gamend/events.hpp"]
    report.need(
        surface,
        "C++",
        [row["event"] for row in model.table],
        lambda e: f', "{e}", ' in events,
    )

    table = balaur.emit(model)["events.bs"]
    report.need(
        surface,
        "Balaur",
        [row["event"] for row in model.table],
        lambda e: f', "{e}", ' in table,
    )


def commands(report: Report, model: Model) -> None:
    surface = f"socket commands ({len(model.commands)})"
    events = [row["event"] for row in model.commands]

    js = text_of(CLIENTS / name for name in ("realtime.js", "webrtc.js"))
    report.need(surface, "JavaScript", events, lambda e: f"'{e}'" in js)

    godot = text_of(sorted(GODOT.glob("*.gd")))
    report.need(surface, "Godot", events, lambda e: f'"{e}"' in godot)

    header = cpp.emit(model)["include/gamend/commands.hpp"]
    report.need(surface, "C++", events, lambda e: f'"{e}"' in header)

    written = balaur.emit(model)["commands.bs"]
    report.need(surface, "Balaur", events, lambda e: f'"{e}"' in written)


def run(model: Model, generated: bool) -> int:
    report = Report()
    operations(report, model, generated)
    schemas(report, model, generated)
    server_events(report, model)
    commands(report, model)
    report.print()
    return 1 if report.problems else 0
