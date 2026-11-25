#!/usr/bin/env bash
set -euo pipefail

# generate_godot.sh

ROOT_DIR="$(cd "$(dirname "$0")" && pwd -P)/.."
OUT_DIR="$ROOT_DIR/clients/godot"
SPEC_FILE="$ROOT_DIR/clients/godot/openapi.json"

echo "Ensuring output directory exists: $OUT_DIR"
mkdir -p "$OUT_DIR"

echo "Running mix task to write OpenAPI JSON into clients/godot/openapi.json"
pushd "$ROOT_DIR" >/dev/null
mix openapi.spec.json --spec GamendWeb.ApiSpec --filename clients/godot/openapi.json --pretty=true
popd >/dev/null

if [ ! -f "$SPEC_FILE" ]; then
  echo "error: mix task completed but $SPEC_FILE was not created"
  exit 3
fi

mkdir -p "$OUT_DIR"

# Prune previously generated apis/models so a renamed or removed operation does
# not leave an orphan file behind. The generator only writes/overwrites the
# files for the current spec — it never deletes stale ones — so a renamed
# operationId would otherwise leave an unreferenced model class sitting there
# with a broken denormalize reference the post-processing can't fix. These dirs are 100% generated; the
# hand-maintained wrappers live in gamend_template, so clearing them is safe.
rm -rf "$OUT_DIR/apis" "$OUT_DIR/models"

# default generator output options
GEN_IMAGE=${GEN_IMAGE:-openapitools/openapi-generator-cli}
GENERATOR=${GENERATOR:-gdscript}
ADDITIONAL_PROPERTIES=${ADDITIONAL_PROPERTIES:-coreNamePrefix=Api,coreNameSuffix=Client,allowUnicodeIdentifiers=false}
# GDScript `class_name` is global: a model named `Lobby` or `Quest` would clash
# with a game's own class, so every model is `Gamend<Name>` (`GamendLobby`).
MODEL_NAME_PREFIX=${MODEL_NAME_PREFIX:-Gamend}

echo "Generating GDScript client into $OUT_DIR using Docker image $GEN_IMAGE"

# Try to make the generator run as the current host user so files written into
# the mounted volume are owned by the same uid/gid — this prevents
# permission problems later when doing in-place edits on the host (CI runners
# often create root-owned files otherwise).
DOCKER_USER_OPT=""
if command -v id >/dev/null 2>&1; then
  HOST_UID=$(id -u)
  HOST_GID=$(id -g)
  if [ -n "${HOST_UID}" ] && [ -n "${HOST_GID}" ]; then
    DOCKER_USER_OPT="-u ${HOST_UID}:${HOST_GID}"
  fi
fi

# OPENAPI_GENERATOR_JAR runs a local openapi-generator-cli jar with Java instead
# of the Docker image, for a machine where Docker is not running (or hangs).
if [ -n "${OPENAPI_GENERATOR_JAR:-}" ]; then
  java -jar "$OPENAPI_GENERATOR_JAR" generate \
    -i "$ROOT_DIR/clients/godot/openapi.json" \
    -g "$GENERATOR" \
    -o "$ROOT_DIR/clients/godot" \
    --model-name-prefix "$MODEL_NAME_PREFIX" \
    --additional-properties="$ADDITIONAL_PROPERTIES"
else
  docker run --rm $DOCKER_USER_OPT -v "$ROOT_DIR:/local" $GEN_IMAGE generate \
    -i /local/clients/godot/openapi.json \
    -g "$GENERATOR" \
    -o /local/clients/godot \
    --model-name-prefix "$MODEL_NAME_PREFIX" \
    --additional-properties="$ADDITIONAL_PROPERTIES"
fi

echo "Generation finished. See $OUT_DIR for generated files."

echo "Post-processing generated files: replacing 'Underscore' -> '_'"

# Ensure we have permission to perform in-place edits on generated files.
# When the generator ran as a different user (e.g. root inside Docker) files
# might be owned by a different uid and perl -i will fail to create temp files.
if [ -n "${HOST_UID:-}" ]; then
  chown -R "${HOST_UID}:${HOST_GID}" "$OUT_DIR" 2>/dev/null || true
fi
chmod -R u+rw "$OUT_DIR" 2>/dev/null || true

# Fix generator errors. Replace Underscore with _
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe "s/Underscore/_/g" -i

# Replace #self._bzz_client.close() with self._bzz_client.close()
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe "s/#self\._bzz_client\.close\(\)/self._bzz_client.close()/g" -i

# Replace : Object with : Dictionary
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe "s/: Object/: Dictionary/g" -i

# The enum check in a generated setter compares `str(value)` against the
# allowed values, which for an array of enum strings is the whole array's text
# (`["discord", "steam"]`): it never matches, and the setter returns without
# assigning, so `list_auth_providers` came back with no providers. Check only
# a String (`typeof`, since the setter's `value` is statically typed); an
# array's items are the server's to get right.
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe 's/if str\(value\) != "" and not \(str\(value\) in (__\w+__allowable__values)\):/if typeof(value) == TYPE_STRING and str(value) != "" and not (str(value) in $1):/g' -i

# A schema with no type (a field that is sometimes a string, sometimes a map,
# like ErrorResponse.details) comes out as `@export var x: AnyType:`, a type
# that does not exist. An exported property must be typed, so it becomes a
# plain Variant property with its setter kept.
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe 's/\@export var (\w+): AnyType:/var $1:/g' -i

# Other fixes
# Fix the placeholder polling default: BEE_DEFAULT_POLLING_INTERVAL_MS is emitted
# as 333 but should be 16ms. Scoped to that const so unrelated "333" values
# anywhere else in the generated code are never corrupted.
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe "s/(BEE_DEFAULT_POLLING_INTERVAL_MS\s*:=\s*)333/\${1}16/g" -i
# Replace @export var data: Dictionary with var data
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe "s/\@export var data: Dictionary/var data/g" -i
# Replace from_dict.has("ends_at") with from_dict.has("ends_at") && from_dict.get("ends_at", "")
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe 's/from_dict\.has\("ends_at"\)/from_dict.has("ends_at") && from_dict.get("ends_at", "")/g' -i
# Replace from_dict.has("starts_at") with from_dict.has("starts_at") && from_dict.get("starts_at", "")
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe 's/from_dict\.has\("starts_at"\)/from_dict.has("starts_at") && from_dict.get("starts_at", "")/g' -i
# headers_for_godot, body_serialized
# with 
# headers_for_godot, "" if body_serialized == "null" else body_serialized
find "$OUT_DIR" -type f -iname "*.gd" -print0 | xargs -0 -r perl -0777 -pe 's/headers_for_godot, body_serialized/headers_for_godot, "" if body_serialized == "null" else body_serialized/g' -i

echo "Post-processing complete."

# If APP_VERSION is set (CI), stamp it into the gamend_template so the
# generated Godot addon contains explicit version metadata that consumers can
# read at runtime.
if [ -n "${APP_VERSION:-}" ]; then
  echo "Adding version metadata to gamend_template: ${APP_VERSION}"
  TEMPLATE_VERSION_FILE="$ROOT_DIR/clients/gamend_template/GamendVersion.gd"
  cat > "$TEMPLATE_VERSION_FILE" <<EOF
# Auto-generated version information. Do not edit -- CI will overwrite.
const GAMEND_VERSION = "${APP_VERSION}"
EOF
fi

# A nested inline model is declared PascalCase but referenced as
# `<Parent>_<snake>` (`GamendAdminCreateQuestRequest_objectives_inner` for
# `GamendAdminCreateQuestRequestObjectivesInner`). Join it back when that class
# exists. Every response is a named schema, whose `$ref` already comes out as
# the class name, so only what the document still leaves inline takes this:
# request body items.
python3 - "$OUT_DIR" <<'PYEOF'
import os, re, glob, sys
out_dir = sys.argv[1]
models = [os.path.splitext(os.path.basename(f))[0] for f in glob.glob(os.path.join(out_dir, "models/*.gd"))]
known = set(models)
def join_suffix(m):
    candidate = m.group(1) + "".join(w.capitalize() for w in m.group(2).split("_"))
    return candidate if candidate in known else m.group(0)
suffixed = re.compile(r'\b([A-Z][A-Za-z0-9]*)_([a-z0-9]+(?:_[a-z0-9]+)*)\b')
for f in glob.glob(os.path.join(out_dir, "**/*.gd"), recursive=True):
    src = open(f).read()
    out = suffixed.sub(join_suffix, src)
    if out != src:
        open(f, "w").write(out)
PYEOF

# Generic fix: JSON null must never reach a typed model property or a nested
# denormalize call. The API serializes absent values as null (progress: null,
# claimed_at: null, reset_interval_days: null...), and the generated
# `if from_dict.has("key"):` guard happily assigns that Nil into a typed
# String/int property — a runtime error in Godot. Treat null exactly like
# absent: the property keeps its default.
python3 - "$OUT_DIR" <<'PYEOF'
import glob, re, sys, os
out_dir = sys.argv[1]
pattern = re.compile(r'if from_dict\.has\((".*?")\):')
for f in glob.glob(os.path.join(out_dir, "models/*.gd")):
    src = open(f).read()
    out = pattern.sub(r'if from_dict.get(\1) != null:', src)
    if out != src:
        open(f, "w").write(out)
PYEOF

# Copy the main client pieces (apis, core, model) to a separate godot_api folder
# This keeps the API surface separated for distribution or packaging.
DEST_API_DIR="$ROOT_DIR/clients/gamend"
mkdir -p "$DEST_API_DIR"

for sub in apis core models; do
  SRC="$OUT_DIR/$sub"
  DST="$DEST_API_DIR/$sub"

  if [ -d "$SRC" ]; then
    echo "Copying $sub to $DST"
    rm -rf "$DST"
    mkdir -p "$(dirname "$DST")"
    cp -R "$SRC" "$DST"
  else
    echo "Skip copying $sub - not present in $OUT_DIR"
  fi
done

# Copy gamend_template to gamend if present (rename template folder to final folder)
SRC_TMPL="$OUT_DIR/../gamend_template"
DST_GAMEND="$DEST_API_DIR"

cp -R "$SRC_TMPL/." "$DST_GAMEND"

ROOT_ADDONS="$ROOT_DIR/godot_addons"

mkdir -p "$ROOT_ADDONS/addons"

rm -rf "$ROOT_ADDONS/addons/gamend"
mv "$DST_GAMEND" "$ROOT_ADDONS/addons/gamend"

echo "gamend_template -> gamend copy complete."

# Godot's editor saves scripts with exactly one trailing newline; the
# generator emits two. Normalize so a file Godot ever re-saves in the game
# repo does not flap forever against `mix game.sync_data --check`.
find "$ROOT_ADDONS/addons/gamend" -name '*.gd' -exec perl -0777 -pi -e 's/\n+\z/\n/' {} +

echo "Trailing-newline normalization complete."
