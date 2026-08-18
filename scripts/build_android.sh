#!/usr/bin/env bash
# Packages the LÃ–VE2D PokÃ©mon Red port into an Android APK via love-android 11.5a.
#
# Usage: scripts/build_android.sh [--version X.Y.Z] [--package-only]
#
#   --version X.Y.Z  set app.version_name / app.version_code (else left as-is)
#   --package-only   zip game.love + apply branding; skip gradle
#
# Prerequisites:
#   - mobile/android vendored love-android tree at tag 11.5a (in-repo; see mobile/ANDROID.md)
#   - Android SDK + NDK (SDK API 34, NDK 25.2.9519653)
#   - JDK 17
#
# Output (after gradle):
#   dist/android/debug/*.apk (convenience copy)
#   mobile/android/app/build/outputs/apk/embedNoRecord/debug/*.apk

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/mobile/android"
EMBED_ASSETS="$ANDROID_DIR/app/src/embed/assets"
LOVE_FILE="$EMBED_ASSETS/game.love"
DIST="$ROOT/dist/android"
APP_NAME="gen2recomp"
# Distinct from the Gen 1 port's application id so the two can sit side by
# side on one device; see mobile/ANDROID.md.
APPLICATION_ID="com.underdecodedhd.gen2recomp"
LOVE_ANDROID_VERSION="11.5a"
NDK_VERSION="25.2.9519653"
MANIFEST_BASE_URL="${MANIFEST_BASE_URL:-https://raw.githubusercontent.com/UNDERdecoded/Gen2Recomped/main}"
MANIFESTS=""
GEN2_SOURCES=""
# RomExtractorGen2:readSourceTable falls back to data/generated_gen2_<version>/
# for the tables the Python tooling produces but the ROM walk does not.
GEN2_SOURCE_TABLES="constants charmap items maps moves text text_pointers trainer_headers"

VERSION=""
PACKAGE_ONLY=false

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_packaging_tools() {
  if ! command -v python3 >/dev/null 2>&1; then
    fail "missing required tool: python3. Install it and rerun scripts/build_android.sh."
  fi
  if ! command -v zip >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
    warn "zip/unzip not found; using python3 zipfile fallback"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --package-only) PACKAGE_ONLY=true ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) fail "unknown argument: $1 (try --version X.Y.Z or --package-only)" ;;
  esac
  shift
done

VERSION_CODE=""
if [ -n "$VERSION" ]; then
  if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "invalid --version '$VERSION' (expected X.Y.Z)"
  fi
  major="${VERSION%%.*}"
  rest="${VERSION#*.}"
  minor="${rest%%.*}"
  patch="${rest##*.}"
  VERSION_CODE=$((major * 10000 + minor * 100 + patch))
fi

# --------------------------------------------------------------- preconditions
if [ ! -f "$ANDROID_DIR/settings.gradle" ] || [ ! -f "$ANDROID_DIR/gradlew" ]; then
  fail "love-android not found at mobile/android/.
  The love-android $LOVE_ANDROID_VERSION tree is vendored in this repo,  your checkout
  looks incomplete. Re-clone or 'git checkout -- mobile/android'. See mobile/ANDROID.md."
fi

if [ ! -d "$ANDROID_DIR/love/src/jni/love/src" ]; then
  fail "liblove sources missing under mobile/android/love/src/jni/love/.
  They are vendored in this repo,  your checkout looks incomplete.
  Re-clone or 'git checkout -- mobile/android'. See mobile/ANDROID.md."
fi

# ------------------------------------------------------- import metadata
# Android packages game.love itself rather than reusing scripts/build.sh's
# archive. Keep a partial source export from silently shipping an APK that can
# list a version but cannot import it. Resolve the manifest list from
# src/core/GameVersion.lua so newly added versions are included automatically.
manifest_paths() {
  python3 - "$ROOT/src/core/GameVersion.lua" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
print(" ".join(dict.fromkeys(re.findall(r'manifest\s*=\s*"([^"]+)"', src))))
PY
}

# Gen2 versions declared in GameVersion.lua, so a newly added cart is covered
# without touching this script.
gen2_version_ids() {
  python3 - "$ROOT/src/core/GameVersion.lua" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
ids = [i for i, gen in re.findall(r'id\s*=\s*"([^"]+)"[^}]*?generation\s*=\s*(\d+)', src, re.S)
       if gen == "2"]
print(" ".join(dict.fromkeys(ids)))
PY
}

# The Gen2 extractor cannot run off the ROM alone: without these the APK lists
# Gold/Silver and then dies partway through the import.
ensure_gen2_sources() {
  GEN2_SOURCES=""
  local version table rel
  for version in $(gen2_version_ids); do
    for table in $GEN2_SOURCE_TABLES; do
      rel="data/generated_gen2_$version/$table.lua"
      [ -s "$ROOT/$rel" ] || fail "$rel is missing or empty.
  Regenerate the Gen2 source tables before packaging:
    powershell -ExecutionPolicy Bypass -File scripts/setup_gen2_symbols.ps1
  (see mobile/ANDROID.md, \"Gold/Silver mobile prep checklist\")"
      GEN2_SOURCES="$GEN2_SOURCES $rel"
    done
  done
  say "gen2 source tables:$(printf ' %s' $(gen2_version_ids))"
}

manifest_is_valid() {
  local path="$1"
  python3 - "$path" <<'PY'
import json, pathlib, sys

try:
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, ValueError):
    raise SystemExit(1)

sha = manifest.get("romSha1")
raise SystemExit(0 if isinstance(sha, str) and len(sha) == 40 else 1)
PY
}

ensure_manifests() {
  MANIFESTS="$(manifest_paths)"
  [ -n "$MANIFESTS" ] \
    || fail "could not read any manifest path out of src/core/GameVersion.lua"
  local rel staged
  for rel in $MANIFESTS; do
    if manifest_is_valid "$ROOT/$rel"; then continue; fi
    warn "$rel is missing or invalid; recovering it before packaging"
    staged="$(mktemp)"
    if git -C "$ROOT" show "HEAD:$rel" > "$staged" 2>/dev/null \
        && manifest_is_valid "$staged"; then
      mkdir -p "$ROOT/$(dirname "$rel")"
      mv "$staged" "$ROOT/$rel"
      say "restored $rel from this checkout's Git data"
      continue
    fi

    if command -v curl >/dev/null 2>&1 \
        && curl --fail --location --retry 2 --connect-timeout 15 \
            --output "$staged" "$MANIFEST_BASE_URL/$rel" \
        && manifest_is_valid "$staged"; then
      mkdir -p "$ROOT/$(dirname "$rel")"
      mv "$staged" "$ROOT/$rel"
      say "downloaded $rel from the project repository"
      continue
    fi

    rm -f "$staged"
    fail "$rel is unavailable: Git recovery failed and $MANIFEST_BASE_URL/$rel could not be downloaded"
  done
  say "import manifests: $MANIFESTS"
}

archive_list() {
  local archive="$1"
  if command -v unzip >/dev/null 2>&1; then
    unzip -Z1 "$archive"
    return
  fi
  python3 - "$archive" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "r") as zf:
    for name in zf.namelist():
        print(name)
PY
}

archive_read_entry() {
  local archive="$1"
  local entry="$2"
  if command -v unzip >/dev/null 2>&1; then
    unzip -p "$archive" "$entry"
    return
  fi
  python3 - "$archive" "$entry" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "r") as zf:
    sys.stdout.buffer.write(zf.read(sys.argv[2]))
PY
}

archive_update_entry_from_file() {
  local archive="$1"
  local entry="$2"
  local src_file="$3"
  if command -v zip >/dev/null 2>&1; then
    local stage
    stage="$(mktemp -d)"
    mkdir -p "$stage/$(dirname "$entry")"
    cp "$src_file" "$stage/$entry"
    (cd "$stage" && zip -q "$archive" "$entry")
    rm -rf "$stage"
    return
  fi
  python3 - "$archive" "$entry" "$src_file" <<'PY'
import pathlib, sys, tempfile, zipfile
archive, entry, src = sys.argv[1], sys.argv[2], sys.argv[3]
data = pathlib.Path(src).read_bytes()
archive_path = pathlib.Path(archive)
tmp_fd, tmp_name = tempfile.mkstemp(suffix=".zip", dir=str(archive_path.parent))
pathlib.Path(tmp_name).unlink(missing_ok=True)

with zipfile.ZipFile(archive_path, "r") as src_zip, \
   zipfile.ZipFile(tmp_name, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as dst_zip:
  for info in src_zip.infolist():
    if info.filename == entry:
      continue
    dst_zip.writestr(info, src_zip.read(info.filename))
  dst_zip.writestr(entry, data)

pathlib.Path(tmp_name).replace(archive_path)
PY
}

pack_love_archive() {
  local archive="$1"
  local root="$2"
  local manifests="$3"

  if command -v zip >/dev/null 2>&1; then
    # shellcheck disable=SC2086  # manifests is a deliberate word list
    # NO mods/ here, deliberately.  Adding it shipped eleven bundled mods to
    # Android for the first time -- the launcher enables a bundled mod by
    # default, so the app booted, loaded a mod set that had never run on that
    # platform, and died about a second in with no Lua error reaching the
    # handler.  0.7.5 shipped no mods and boots; this restores that exactly.
    # Re-add only after the bundled mods are known to load on device, one at
    # a time (see mobile/ANDROID.md).
    (cd "$root" && zip -q -9 -r "$archive" \
      main.lua conf.lua src data assets tools/save-editor \
      $manifests \
      -x '*.DS_Store' -x '*/.git/*' -x '*/.DS_Store' \
      -x 'data/generated/*' -x 'assets/generated/*')
    return
  fi

  python3 - "$root" "$archive" "$manifests" <<'PY'
import fnmatch
import os
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1]).resolve()
archive = pathlib.Path(sys.argv[2])
manifest_words = [w for w in sys.argv[3].split() if w]
# mods/ intentionally absent -- see the note on the zip path above.
includes = ["main.lua", "conf.lua", "src", "data", "assets",
            "tools/save-editor", *manifest_words]
excludes = ["*.DS_Store", "*/.DS_Store", "*/.git/*", "data/generated/*", "assets/generated/*"]

def excluded(rel: str) -> bool:
    rel = rel.replace("\\", "/")
    return any(fnmatch.fnmatch(rel, pat) for pat in excludes)

paths = []
for item in includes:
    path = (root / item).resolve()
    if not path.exists():
        continue
    if path.is_file():
        rel = path.relative_to(root).as_posix()
        if not excluded(rel):
            paths.append(rel)
        continue
    for base, dirs, files in os.walk(path):
        base_path = pathlib.Path(base)
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in files:
            rel = (base_path / name).relative_to(root).as_posix()
            if not excluded(rel):
                paths.append(rel)

paths = sorted(dict.fromkeys(paths))
archive.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for rel in paths:
        zf.write(root / rel, rel)
PY
}

# --------------------------------------------------------------- branding
# love-android 11.5+ reads app id / name / orientation from gradle.properties.
# Manifest still gets permission trims. Re-applied every build so refreshing
# the vendored love-android tree does not lose project settings.
apply_android_branding() {
  local props="$ANDROID_DIR/gradle.properties"
  local manifest="$ANDROID_DIR/app/src/main/AndroidManifest.xml"
  [ -f "$props" ] || fail "missing $props"
  [ -f "$manifest" ] || fail "missing $manifest"

  say "applying Android branding (gradle.properties + permission trim)"

  python3 - "$props" "$APPLICATION_ID" "$APP_NAME" "$VERSION" "$VERSION_CODE" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
app_id, name, version, version_code = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
text = path.read_text()

def set_prop(text, key, value):
    pat = re.compile(rf"(?m)^{re.escape(key)}=.*$")
    line = f"{key}={value}"
    if pat.search(text):
        return pat.sub(line, text)
    return text.rstrip() + "\n" + line + "\n"

# Prefer plain app.name; clear byte-array form so it cannot win.
text = re.sub(r"(?m)^app\.name_byte_array=.*\n?", "", text)
text = set_prop(text, "app.name", name)
text = set_prop(text, "app.application_id", app_id)
text = set_prop(text, "app.orientation", "fullUser")
if version:
    text = set_prop(text, "app.version_name", version)
    text = set_prop(text, "app.version_code", version_code)
path.write_text(text)
PY

  python3 - "$manifest" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()

# Drop mic / legacy storage, not needed by this game.
# Keep VIBRATE (love.system.vibrate), BLUETOOTH (optional gamepads) and
# INTERNET: link play is not offline-only any more, and stripping INTERNET
# made every LAN host and every relay connect fail with EPERM (issue #287).
# Orientation / label come from gradle.properties placeholders.
for perm in (
    "android.permission.RECORD_AUDIO",
    "android.permission.WRITE_EXTERNAL_STORAGE",
):
    text = re.sub(
        rf'\s*<uses-permission android:name="{re.escape(perm)}"[^/]*/>\s*',
        "\n",
        text,
    )
text = re.sub(r'\s*android:usesCleartextTraffic="true"', "", text)
path.write_text(text)
PY
}

# --------------------------------------------------------------- game.love
pack_game_love() {
  say "packing game.love for love-android embed flavor"
  ensure_manifests
  ensure_gen2_sources
  mkdir -p "$EMBED_ASSETS"
  rm -f "$LOVE_FILE"
  # tools/save-editor ships with the app: the launcher's Edit button on a save
  # row opens it in-process, so it must be inside the archive (see build.sh).
  # Deliberately NO fused mods: a mod inside game.love sits in the read-only
  # APK, so the mod manager's Delete can't remove it and it reappears every
  # launch.  Pokewalker ships as an importable .zip instead, which gives it
  # a real install/upgrade/delete lifecycle.
  pack_love_archive "$LOVE_FILE" "$ROOT" "$MANIFESTS"
  local archive_entries
  archive_entries="$(archive_list "$LOVE_FILE")"
  if grep -Eq '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/' <<< "$archive_entries"; then
    fail "game.love unexpectedly contains generated ROM data"
  fi
  grep -qx 'tools/save-editor/App.lua' <<< "$archive_entries" \
    || fail "game.love is missing the save editor (Edit on a save row would crash)"
  local required
  for required in $MANIFESTS; do
    grep -qx "$required" <<< "$archive_entries" \
      || fail "game.love is missing $required"
  done
  for required in $GEN2_SOURCES; do
    grep -qx "$required" <<< "$archive_entries" \
      || fail "game.love is missing $required (Gold/Silver import would fail)"
  done
  for required in \
    src/import/RomExtractorGen2.lua \
    src/import/Gen2ScriptOps.lua \
    src/script/Gen2ScriptVM.lua \
    src/script/Gen2Commands.lua \
    src/ui/Gen2Intro.lua \
    src/ui/PokegearMenu.lua; do
    grep -qx "$required" <<< "$archive_entries" \
      || fail "game.love is missing $required (Gold/Silver would not run)"
  done
  say "game.love: $(du -h "$LOVE_FILE" | cut -f1) -> $LOVE_FILE"

  # This script packs its own game.love (it does not reuse build.sh's), so it
  # stamps the release version the same way: patch a copy of Version.lua
  # (engine set to $VERSION) under a throwaway staging dir and replace the
  # entry inside the archive in place -- never the source tree. VERSION is
  # already validated as X.Y.Z above; when it is empty the packaged game keeps
  # the "0.0.0-dev" default. The stamp is read back out and the build fails if
  # it did not take.
  if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    say "stamping engine version $VERSION into game.love"
    local stamp_dir
    stamp_dir="$(mktemp -d)"
    mkdir -p "$stamp_dir/src/core"
    sed -E "s/(engine[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1$VERSION\2/" \
      "$ROOT/src/core/Version.lua" > "$stamp_dir/src/core/Version.lua"
    archive_update_entry_from_file "$LOVE_FILE" "src/core/Version.lua" \
      "$stamp_dir/src/core/Version.lua"
    local version_re
    version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
    archive_read_entry "$LOVE_FILE" src/core/Version.lua \
      | grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
      || fail "version stamp failed: game.love does not report engine $VERSION"
    rm -rf "$stamp_dir"
    say "stamped engine version: $VERSION"
  else
    say "no X.Y.Z --version,  shipping default engine (no stamp)"
  fi
}

# --------------------------------------------------------------- SDK check
require_android_sdk() {
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  local props="$ANDROID_DIR/local.properties"

  normalize_sdk_path() {
    local p="$1"
    p="${p%$'\r'}"
    p="${p%$'\n'}"
    # Convert Windows backslashes to forward slashes for bash tools.
    p="${p//\\//}"
    # Convert drive-letter form (C:/...) into WSL mount style (/mnt/c/...).
    if printf '%s' "$p" | grep -Eq '^[A-Za-z]:/'; then
      local drive rest
      drive="$(printf '%s' "$p" | cut -c1 | tr 'A-Z' 'a-z')"
      rest="${p:2}"
      p="/mnt/$drive$rest"
    fi
    printf '%s' "$p"
  }

  if [ -z "$sdk" ] && [ -f "$props" ]; then
    local raw
    raw="$(sed -n 's/^sdk\.dir=//p' "$props" | head -n 1)"
    if [ -n "$raw" ]; then
      sdk="$(normalize_sdk_path "$raw")"
    fi
  fi

  if [ -z "$sdk" ]; then
    for candidate in \
      "$HOME/Library/Android/sdk" \
      "$HOME/Android/Sdk" \
      /usr/local/lib/android/sdk; do
      if [ -d "$candidate" ]; then
        sdk="$candidate"
        break
      fi
    done
  fi

  if [ -z "$sdk" ] || [ ! -d "$sdk" ]; then
    fail "Android SDK not found.
  Install Android Studio (or command-line tools), then either:
    export ANDROID_SDK_ROOT=\$HOME/Library/Android/sdk
  or create mobile/android/local.properties with:
    sdk.dir=/path/to/Android/sdk
  love-android $LOVE_ANDROID_VERSION expects SDK API 34 and NDK $NDK_VERSION
  (see mobile/ANDROID.md)."
  fi

  export ANDROID_SDK_ROOT="$sdk"
  export ANDROID_HOME="$sdk"

  # Always rewrite so a leftover Docker sdk.dir=/opt/android-sdk cannot stick.
  printf 'sdk.dir=%s\n' "$sdk" > "$props"

  if ! command -v java >/dev/null 2>&1; then
    local java_candidate java_bin java_exe
    for java_candidate in \
      "/mnt/c/Program Files/Android/Android Studio/jbr" \
      "/mnt/c/Program Files/Common Files/Oracle/Java/javapath"; do
      java_bin="$java_candidate/bin"
      if [ -x "$java_bin/java.exe" ]; then
        java_exe="$java_bin/java.exe"
        break
      fi
      if [ -x "$java_candidate/java.exe" ]; then
        java_exe="$java_candidate/java.exe"
        break
      fi
    done

    if [ -n "${java_exe:-}" ]; then
      local shim_root shim_bin shim_java
      shim_root="$ROOT/.cache/java-shim"
      shim_bin="$shim_root/bin"
      shim_java="$shim_bin/java"
      mkdir -p "$shim_bin"
      cat > "$shim_java" <<EOF
#!/usr/bin/env bash
exec "$java_exe" "\$@"
EOF
      chmod +x "$shim_java"
      export JAVA_HOME="$shim_root"
      export PATH="$shim_bin:$PATH"
    fi
  fi

  if ! command -v java >/dev/null 2>&1; then
    fail "java not found. Install JDK 17 (Android Studio's bundled JDK is fine)."
  fi

  if [ ! -d "$sdk/ndk/$NDK_VERSION" ]; then
    warn "NDK $NDK_VERSION not found under $sdk/ndk/"
    warn "Install via SDK Manager (Show Package Details â†’ NDK $NDK_VERSION)."
  fi
}

# --------------------------------------------------------------- gradle
run_gradle() {
  local task="assembleEmbedNoRecordDebug"
  local build_dir="$ANDROID_DIR"

  # ndk-build is GNU make underneath and cannot cope with spaces anywhere in
  # the project path ("Your APP_BUILD_SCRIPT points to an unknown file").
  # When this checkout lives at a spaced path (e.g. "~/xCode Projects/..."),
  # shadow the android tree to a space-free location and build there; the
  # shadow persists across runs so gradle/ndk builds stay incremental.
  case "$ANDROID_DIR" in
    *" "*)
      build_dir="${TMPDIR:-/tmp}/Gen2Recomped-android-shadow"
      say "path contains spaces (ndk-build cannot handle them);"
      say "shadow-building in: $build_dir"
      mkdir -p "$build_dir"
      rsync -a --delete \
        --exclude=".gradle" --exclude="app/build" --exclude="love/build" \
        --exclude="local.properties" \
        "$ANDROID_DIR/" "$build_dir/"
      if [ -f "$ANDROID_DIR/local.properties" ]; then
        cp "$ANDROID_DIR/local.properties" "$build_dir/local.properties"
      fi
      ;;
  esac

  say "building APK ($task)"
  if [ -f "$build_dir/gradlew" ]; then
    # Windows checkouts can carry CRLF into gradlew and break under bash
    # with '/bin/sh^M: bad interpreter'. Normalize just before execution.
    sed -i 's/\r$//' "$build_dir/gradlew"
    # ...and they record no exec bit either, which a Linux CI runner turns
    # into './gradlew: Permission denied'.  chmod for anyone who runs the
    # wrapper by hand later; the invocation below does not rely on it.
    chmod +x "$build_dir/gradlew" 2>/dev/null || true
  fi
  if ! (
    cd "$build_dir"
    # `sh ./gradlew`, not `./gradlew`: the wrapper is a POSIX sh script (that
    # is its own shebang), so this is the identical execution and it cannot be
    # defeated by a missing mode bit at all.  The chmod above is best-effort
    # -- it is silenced because it legitimately fails on mounts that carry no
    # permission bits (Windows shares, some WSL setups) -- so the build must
    # not depend on it having worked.
    sh ./gradlew --no-daemon "$task"
  ); then
    fail "gradle $task failed.
  Packaging already wrote: $LOVE_FILE
  Common causes: missing SDK/NDK $NDK_VERSION, or JDK â‰  17. See mobile/ANDROID.md.
  You can still iterate on the .love payload with: scripts/build_android.sh --package-only"
  fi

  local out_dir="$build_dir/app/build/outputs/apk/embedNoRecord/debug"
  if [ -d "$out_dir" ]; then
    say "APK output:"
    find "$out_dir" -name '*.apk' -exec ls -lh {} \;

    local dist_dir="$DIST/debug"
    rm -rf "$dist_dir"
    mkdir -p "$dist_dir"
    find "$out_dir" -name '*.apk' -exec cp {} "$dist_dir/" \;
    say "copied to $dist_dir/"
  else
    warn "gradle finished but no APK dir at $out_dir,  check gradle logs above"
  fi
}

# --------------------------------------------------------------- main
require_packaging_tools
apply_android_branding
pack_game_love

if $PACKAGE_ONLY; then
  say "package-only: skipping gradle (game.love + branding ready under mobile/android/)"
  exit 0
fi

require_android_sdk
run_gradle
say "done"
