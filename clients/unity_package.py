#!/usr/bin/env python3
"""Finish a Unity package directory: stamp its version and give every asset a .meta.

    python3 clients/unity_package.py unity_sdk --version 1.1.1302
    python3 clients/unity_package.py clients/unity_template --check

Unity ignores an asset without a .meta inside an immutable package (one from a
git URL, a tarball or a registry), so every file and folder needs one. The
hand-written ones in clients/unity_template/ are committed; the C# SDK's files
are copied in by generate_unity.sh and get theirs here, with a GUID made from
the path, so the same file keeps the same GUID from one release to the next.

A component's GUID is what a scene stores to find its script: never change the
.meta of a MonoBehaviour such as GamendBehaviour.cs, and move it with its file.

Fails on a .meta whose asset is gone, on two assets sharing a GUID, and on a
package.json the Package Manager would refuse. With --check, also on a missing
.meta, and writes nothing.
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

PACKAGE = "org.gamend.sdk"

FOOTER = "  userData: \n  assetBundleName: \n  assetBundleVariant: \n"

IMPORTERS = {
    ".cs": (
        "MonoImporter:\n"
        "  externalObjects: {}\n"
        "  serializedVersion: 2\n"
        "  defaultReferences: []\n"
        "  executionOrder: 0\n"
        "  icon: {instanceID: 0}\n"
    ),
    ".asmdef": "AssemblyDefinitionImporter:\n  externalObjects: {}\n",
    ".md": "TextScriptImporter:\n  externalObjects: {}\n",
    ".json": "TextScriptImporter:\n  externalObjects: {}\n",
    ".txt": "TextScriptImporter:\n  externalObjects: {}\n",
    # A browser library: in WebGL players only, never in the editor.
    ".jslib": (
        "PluginImporter:\n"
        "  externalObjects: {}\n"
        "  serializedVersion: 2\n"
        "  iconMap: {}\n"
        "  executionOrder: {}\n"
        "  defineConstraints: []\n"
        "  isPreloaded: 0\n"
        "  isOverridable: 0\n"
        "  isExplicitlyReferenced: 0\n"
        "  validateReferences: 1\n"
        "  platformData:\n"
        "  - first:\n"
        "      Any: \n"
        "    second:\n"
        "      enabled: 0\n"
        "      settings: {}\n"
        "  - first:\n"
        "      Editor: Editor\n"
        "    second:\n"
        "      enabled: 0\n"
        "      settings:\n"
        "        DefaultValueInitialized: true\n"
        "  - first:\n"
        "      WebGL: WebGL\n"
        "    second:\n"
        "      enabled: 1\n"
        "      settings: {}\n"
    ),
}

DEFAULT = "DefaultImporter:\n  externalObjects: {}\n"
FOLDER = "folderAsset: yes\n" + DEFAULT
MANIFEST = "PackageManifestImporter:\n  externalObjects: {}\n"

GUID = re.compile(r"^guid: ([0-9a-f]{32})$", re.MULTILINE)
SEMVER = re.compile(r"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$")
UNITY = re.compile(r"^\d{4}\.\d+$")


def hidden(path):
    """Unity skips dotfiles. A name ending in `~` (Samples~) is skipped too, but
    its contents are copied out when a sample is imported, so they keep theirs."""
    return path.name.startswith(".")


def assets(root):
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(hidden(part) for part in map(Path, relative.parts)):
            continue
        if path.suffix == ".meta" or path.name.endswith("~"):
            continue
        yield path


def meta_for(root, path):
    relative = path.relative_to(root).as_posix()
    guid = hashlib.md5(f"{PACKAGE}/{relative}".encode()).hexdigest()
    if path.is_dir():
        body = FOLDER
    elif relative == "package.json":
        body = MANIFEST
    else:
        body = IMPORTERS.get(path.suffix, DEFAULT)
    return f"fileFormatVersion: 2\nguid: {guid}\n{body}{FOOTER}"


def stamp(root, version):
    if not SEMVER.match(version):
        sys.exit(f"error: {version!r} is not a version Unity reads (major.minor.patch)")
    manifest = root / "package.json"
    data = json.loads(manifest.read_text())
    data["version"] = version
    manifest.write_text(json.dumps(data, indent=2) + "\n")


def manifest_errors(root):
    data = json.loads((root / "package.json").read_text())
    errors = []
    if data.get("name") != PACKAGE:
        errors.append(f"package.json names {data.get('name')!r}, not {PACKAGE}")
    if not SEMVER.match(str(data.get("version", ""))):
        errors.append(f"package.json's version {data.get('version')!r} is not major.minor.patch")
    if not UNITY.match(str(data.get("unity", ""))):
        errors.append(f"package.json's unity {data.get('unity')!r} is not a Unity version like 2021.3")
    for sample in data.get("samples", []):
        if not (root / sample["path"]).is_dir():
            errors.append(f"package.json's sample {sample['path']} is not a folder")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.version:
        stamp(root, args.version)
    errors = manifest_errors(root)

    wrote = 0
    for path in assets(root):
        meta = path.with_name(path.name + ".meta")
        if meta.exists():
            continue
        if args.check:
            errors.append(f"{meta.relative_to(root)} is missing")
        else:
            meta.write_text(meta_for(root, path))
            wrote += 1

    owners = {}
    for meta in sorted(root.rglob("*.meta")):
        asset = meta.with_name(meta.name[: -len(".meta")])
        relative = meta.relative_to(root)
        if not asset.exists():
            errors.append(f"{relative} has no asset beside it")
            continue
        found = GUID.search(meta.read_text())
        if not found:
            errors.append(f"{relative} has no guid")
            continue
        guid = found.group(1)
        if guid in owners:
            errors.append(f"{relative} has the guid of {owners[guid]}")
        owners[guid] = relative

    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if errors:
        sys.exit(1)
    if not args.check:
        print(f"wrote {wrote} .meta files in {args.root}")


if __name__ == "__main__":
    main()
