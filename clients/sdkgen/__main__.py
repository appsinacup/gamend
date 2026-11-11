"""Write an SDK from the OpenAPI document and the realtime table.

    python3 clients/sdkgen balaur            # regenerate balaur_addons/addons/gamend
    python3 clients/sdkgen balaur --check    # fail when the addon is stale (CI)
    python3 clients/sdkgen cpp               # write cpp_sdk/ (not committed)
    python3 clients/sdkgen csharp            # write csharp_sdk/ (not committed)
    python3 clients/sdkgen rust              # write rust_sdk/ (not committed)
    python3 clients/sdkgen ts                # write the npm package's .d.ts
    python3 clients/sdkgen lint              # fail when an SDK lacks something

One model (`model.py`: the operations, the events, the names) and one
emitter per target. openapi-generator serves the targets it knows well
(Godot, JavaScript); these are the ones it serves badly or not at all. Each
target has a `generate_<target>.sh` that refreshes the document first.
"""

import argparse
import sys
from pathlib import Path

import balaur
import cpp
import csharp
import lint
import output
import rust
import ts
from model import SPEC, load

TARGETS = {"balaur": balaur, "cpp": cpp, "csharp": csharp, "rust": rust, "ts": ts}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=[*sorted(TARGETS), "lint"])
    parser.add_argument("--out", type=Path)
    parser.add_argument(
        "--spec",
        type=Path,
        default=SPEC,
        help="the OpenAPI document, when it is not clients/godot/openapi.json",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when the written files are not what this would write",
    )
    parser.add_argument(
        "--generated",
        action="store_true",
        help="lint: also read what openapi-generator wrote on this disk",
    )
    args = parser.parse_args()

    model = load(args.spec)
    if args.target == "lint":
        return lint.run(model, args.generated)

    target = TARGETS[args.target]
    out = args.out or target.OUT
    files = target.emit(model)

    owns = getattr(target, "OWNS_OUT", False)
    if args.check:
        return output.check(out, files, target.TEMPLATE, target.REGENERATE, owns)
    output.write(out, files, target.TEMPLATE, owns)
    print(f"{target.summary(model)} to {output.relative(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
