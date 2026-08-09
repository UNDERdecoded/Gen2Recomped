# Android (love-android 11.5a)

`mobile/android/` is a **vendored copy** of
[love2d/love-android](https://github.com/love2d/love-android) at tag
**11.5a** (matches `conf.lua` `t.version = "11.5"`), tracked directly in
this repo,  no git submodules involved. Nested `love` sources live at
`mobile/android/love/src/jni/love` (also vendored). Build outputs
(`app/build/`, `love/build/`, `.gradle/`, `local.properties`) stay
gitignored.

## Refreshing the vendored tree

To pick up a newer love-android release, replace the tree and re-vendor:

```bash
rm -rf mobile/android
git clone --depth 1 --branch <new-tag> --recurse-submodules --shallow-submodules \
  https://github.com/love2d/love-android.git mobile/android
rm -rf mobile/android/.git mobile/android/love/src/jni/love/.git \
       mobile/android/.gitmodules
```

`scripts/build_android.sh` re-applies project branding on every run
(`gradle.properties` app id / name / portrait, plus permission trims), so a
refresh is safe,  just rebuild.

## Build

```bash
# Build the APK
scripts/build_android.sh

# Build the APK, setting app.version_name/app.version_code to match a release
scripts/build_android.sh --version 0.2.5

# Zip game.love + branding only (no Android SDK required)
scripts/build_android.sh --package-only
```

`scripts/build_android.sh` now checks host tools up front. `python3` is
required; `zip`/`unzip` are preferred but optional (the script falls back to
Python's `zipfile` when they are missing). Required for packaging:

- `python3`

Preferred (faster native path):

- `zip`
- `unzip`

Or via `scripts/build.sh android [--version X.Y.Z]`.

### On Windows

`build_android.sh` is bash, and its gradle half assumes a Linux JDK. Use the
PowerShell front end instead — it runs the packaging half through Git Bash or
WSL (which only needs `python3`), then drives `gradlew.bat` with a Windows
JDK 17:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1
powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1 -Version 0.2.11
powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1 -PackageOnly
```

It shadow-builds out of a space-free directory on the repo's drive
(`<drive>:\gen2recomp-android-shadow`) because ndk-build is GNU make
underneath and cannot cope with spaces in the project path, and it parks
`GRADLE_USER_HOME` on the same drive so a small system drive is not asked to
host the NDK output.

The embedded `game.love` deliberately excludes `data/generated/`,
`assets/generated/`, and any ROM. It contains the first-boot Lua importer,
all ROM import manifests referenced by `src/core/GameVersion.lua`, and the
`data/generated_gen2_<version>/` source tables the Gen2 extractor cannot
derive from the cart alone. The build fails rather than shipping an APK that
lists Gold/Silver but is missing any of them.

ROM / mod / save import on Android uses `love.system.pickFile([kind])` →
`GameActivity.showFilePicker` (Storage Access Framework), which copies the
chosen file under the app save directory as `picked_rom.gb`,
`picked_mod.zip`, or `picked_save.sav`. `RomImporter` imports pending files
from that folder on Choose / refocus; see `docs/launcher.md`. The APK payload
itself remains data-free (no embedded ROM or generated cache).

ROM routing is SHA-1 based (not filename based): the importer accepts
canonical 1 MiB carts (Red/Blue/Yellow) and 2 MiB carts (Gold/Silver), then
selects the target version from `src/core/GameVersion.lua` by ROM hash.

Gold/Silver import and play through the same in-app path as Red/Blue/Yellow:
drop in the cart, the importer runs `RomExtractorGen2`, and the game boots.

Android does not have a separate ROM extractor implementation: it uses the
same Lua importer path as desktop (`src/import/RomImporter.lua`, which
dispatches to `src/import/RomExtractor.lua` for Gen1 and
`src/import/RomExtractorGen2.lua` for Gen2) against whichever manifest
matches the cart. First import on a phone takes several minutes.

### Gold/Silver mobile prep checklist

Before cutting an Android build that should import Gold/Silver:

```powershell
# 1) Refresh embedded Gen2 symbol maps and regenerate manifests
powershell -ExecutionPolicy Bypass -File scripts/setup_gen2_symbols.ps1

# 2) Verify Gen2 scaffold extraction quality
python tools/verify_rom_data.py --manifest tools/rom_manifest_gold.json --version gold
python tools/verify_rom_data.py --manifest tools/rom_manifest_silver.json --version silver

# 3) Package Android payload (all manifests from GameVersion.lua are embedded)
scripts/build_android.sh --package-only
```

### Step bridge (Pokéwalker mod)

`love.system.syncHealthSteps()` → `GameActivity.syncHealthSteps` (same
JNI route as the picker: `common/android.cpp` →
`modules/system/System.cpp` → `wrap_System.cpp`). The Java side does a
one-shot read of the hardware `TYPE_STEP_COUNTER` sensor (cumulative
since boot, counted by the OS whether or not any app runs), anchors the
reading in `SharedPreferences` so a walk is never credited twice
(a reading below the anchor means the phone rebooted → re-anchor without
crediting), and stages the delta as `steps_pending.json` in the save
identity dir — the same contract as the iOS `GRHealthBridge`. Nothing in
the base game calls it; the consumer is the
[Pokéwalker mod](https://github.com/mresnick67/Gen1ReComp-Pokewalker),
installed as a mod `.zip` at runtime (its SYNC STEPS option defaults
off).

Android 10+ gates the sensor behind the `ACTIVITY_RECOGNITION` runtime
permission (declared in `app/src/main/AndroidManifest.xml`; keep it out
of the build script's permission trim). The first
`syncHealthSteps()` call shows the system prompt; on grant the sensor
read runs immediately (`onRequestPermissionsResult`,
`STEP_PERMISSION_REQUEST_CODE`).

### Network transport (mod index / mod updates)

`love.system.httpDownload(url, absPath [, userAgent [, accept]])` ->
`GameActivity.httpDownload` (same JNI route as the picker and the step
bridge: `common/android.cpp` -> `modules/system/System.cpp` ->
`wrap_System.cpp`). Android ships no `curl`, which is what the desktop
builds fetch the mod index, mod release lists and mod zips with, so the
"Find mods" tab used to fail with "curl is not available on this
platform" (#597). The Java side is a blocking `HttpsURLConnection` GET
(https only, redirects followed by hand, body renamed into place only
once complete) and runs on LOVE's Lua thread, never the UI thread.
`src/core/HostShell.lua` picks the transport: curl when present,
otherwise this bridge; an APK older than the bridge simply reports no
transport, exactly as a missing curl does.

### SDK / NDK

love-android 11.5a expects:

- **JDK 17**
- Android SDK with **API 34**
- NDK **25.2.9519653** (Apple Silicon host supported)

Set `ANDROID_SDK_ROOT` (or `ANDROID_HOME`), or let the script write
`local.properties` when it finds `~/Library/Android/sdk`.

The build script also reads `mobile/android/local.properties` when
`ANDROID_SDK_ROOT` / `ANDROID_HOME` are unset, so an explicit
`sdk.dir=...` value is honored. Windows-style paths are accepted there
and normalized for bash-based builds.

Gradle flavor used: **`embedNoRecord`** (game fused into the APK, no microphone).
Build task: `assembleEmbedNoRecordDebug`.

The APK lands under `app/build/outputs/apk/embedNoRecord/debug/`.
`scripts/build_android.sh` also copies it to `dist/android/debug/`.

### Payload path

`app/src/embed/assets/game.love` - zip of `main.lua`, `conf.lua`, `src/`,
`data/`, `assets/`, and all version manifests listed in
`src/core/GameVersion.lua` (currently Red/Blue/Yellow/Gold/Silver).
The Android packer verifies every listed manifest before packaging; if a
partial source export omitted one, it restores that file from this checkout's
Git data and then falls back to the project's GitHub copy. Generated game data,
scripts, tests, and mobile build sources are excluded.

## Branding (applied by the build script)

| Setting | Value |
| --- | --- |
| `app.application_id` | `com.underdecodedhd.gen2recomp` |
| `app.name` | gen2recomp |
| `app.orientation` | `fullUser`. This is only the manifest default: SDL requests FULL_SENSOR at window creation (resizable window, no `SDL_HINT_ORIENTATIONS`), and `GameActivity.setOrientationBis` remaps that to FULL_USER so the device's rotation lock is honoured. |
| `app.version_name` / `app.version_code` | set from `--version X.Y.Z` (code = major*10000 + minor*100 + patch); left as-is if `--version` is omitted |
| Permissions | RECORD_AUDIO / WRITE_EXTERNAL_STORAGE stripped; VIBRATE + BLUETOOTH + INTERNET (link play, mod index) + ACTIVITY_RECOGNITION (step bridge) kept |

## Releases

`.github/workflows/release.yml` builds the APK with `--version` set to the
release version and publishes it alongside the macOS/Windows/Linux builds as
`PokemonRed-<version>-android.apk`.

## Signing

Signed with the default Android keystore (no setup required).

## Installing alongside gen1recomp

Android identifies an app by its `applicationId` alone and will not replace an
installed package with an APK signed by a different key, so builds that reused
gen1recomp's `com.theboisclub.pokemonred` failed with "App not installed"
(`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) on any device that already had
gen1recomp. Under `com.underdecodedhd.gen2recomp` the two install side by side
and keep separate data: the save directory is `getExternalFilesDir()`-based and
therefore package-scoped, so the shared `t.identity` in `conf.lua` cannot
collide.

A gen2recomp build predating this change is still installed under the old id
and hits the same error. Export saves from it first (START → SAVE → EXPORT),
uninstall it, then install the new APK — uninstalling removes that package's
external files directory, which holds `save.lua` and the ROM-derived cache.
