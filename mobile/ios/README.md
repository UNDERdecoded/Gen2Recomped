# iOS build (LÖVE 12.0)

> **TV / CAST (AirPlay, HDMI) -- needs a NEW IPA.** Two native pieces, both
> wired in by `patch_love_src.py`; a Lua-only update cannot deliver them.
>
> - `native/GRSceneGuard.m` fixes the **white TV screen** under AirPlay
>   mirroring. SDL 3.4.10 (the SDL3 in love-apple-dependencies `a552263`) is
>   scene-based, and its `SDLUIKitSceneDelegate` treated the TV's
>   external-display scene as the main one: a white launch window
>   (`Launch Screen.xib`) on the TV, `main` scheduled a second time, and the
>   TV scene's resign/background callbacks pausing the game. Upstream SDL
>   fixed it after 3.4.10 (libsdl-org/SDL `6f34ce4d`, "Don't re-launch the
>   application for external display scenes on iOS"); the guard applies the
>   same rule at run time by wrapping those delegate methods from a
>   constructor. Drop it once the pinned SDL carries `6f34ce4d` (harmless
>   until then: the checks are identical).
> - `native/GRCastBridge.swift` is the iOS end of the Android second-display
>   file protocol (`second_display/host.txt`, `mode.txt`, `frame.bin`; see
>   `src/render/SecondScreen.lua`). Lua starts it with
>   `love.system.castHostStart()`; an older IPA has no such function, so the
>   TV / CAST row stays hidden there even if a stale `host.txt` exists.
>   MIRROR (the default) creates nothing, so iOS mirrors the phone. BOTTOM /
>   TOP put one window on the TV's scene showing `frame.bin` (letterboxed,
>   size reported to Lua capped at 640x360); no taps are routed from a TV.
>
> Checked on Windows only (`tools/second_display_cast_check.lua` section 6,
> `tools/second_display_protocol_check.py` tier 3, `patch_love_src.py` run
> against a scratch copy of the pinned LÖVE source). **No Swift/Objective-C
> compiler has seen these files.** On a device with the new IPA, test:
>
> 1. Build: `GRCastBridge.swift` and `GRSceneGuard.m` compile; the log shows
>    `GRSceneGuard: installed on SDLUIKitSceneDelegate`.
> 2. AirPlay **screen mirroring** to an Apple TV, and to an AirPlay smart TV
>    (Samsung/LG/Roku): the TV shows the phone's picture, not white, both when
>    mirroring is started before launch and mid-game; the phone keeps running
>    (no pause, no second game boot).
> 3. OPTIONS > TV / CAST and launcher Settings > TV / CAST appear on iOS.
>    MIRROR: TV mirrors. BOTTOM (Gen 4/5 game): DS bottom screen on the TV,
>    top screen on the phone. TOP: game picture on the TV, bottom screen on
>    the phone with working taps. Launcher in BOTTOM: launcher panel on TV.
> 4. Switching BOTTOM/TOP -> MIRROR mid-game: the window leaves the TV and
>    mirroring resumes (if the TV stays black, iOS did not resume mirroring
>    when our window was hidden -- report it).
> 5. Unplug / stop AirPlay mid-game in each mode, then reconnect: no crash,
>    the game returns to the single-screen layout, and the chosen mode comes
>    back with the TV. Also a Lightning/USB-C HDMI adapter if available.

> **Native ROM/mod/save import.** The iOS build ships a Swift
> document-picker bridge (`native/GRPickerBridge.swift` + `GRBootstrap.m`)
> that `patch_love_src.py` wires into the LÖVE tree on every build:
>
> - `love.system.pickFile("rom"|"mod"|"sav")` and `love.system.createFile`
>   are exposed to Lua on iOS (same contract as love-android's SAF picker:
>   picks land in the save dir as `picked_rom.gb` / `picked_mod.zip` /
>   `picked_save.sav`; exports signal via `export_done.flag`).
> - The Info.plist overlay enables `UIFileSharingEnabled` +
>   `LSSupportsOpeningDocumentsInPlace`, and `GRBootstrap.m` sweeps
>   `.gb/.gbc/.zip/.sav` files dropped in Documents (Files app / Finder)
>   into the LÖVE save dir on every activation — drop a ROM, open the app,
>   and it imports with no taps.
> - `src/import/RomImporter.lua` treats iOS as a mobile platform and polls
>   for picker results (iOS pickers are in-process modals, so Android's
>   refocus rescan never fires).
>
> The note below about a missing "UIDocumentPicker handoff" is
> resolved by this bridge.

macOS + Xcode only. Fetches the **LÖVE 12.0** source tree and matching Apple
dependencies from the official [LÖVE source](https://github.com/love2d/love)
and [Apple dependencies](https://github.com/love2d/love-apple-dependencies)
repositories. `conf.lua` declares LÖVE 12.0 on iOS and 11.5 elsewhere.

Pin file: [`LOVE_VERSION`](./LOVE_VERSION) → `12.0`.

## Quick start (simulator)

```bash
# Fetch LÖVE 12.0 iOS sources and dependencies (once) + build for Simulator
scripts/build_ios.sh --fetch
```

The embedded `game.love` contains no ROM or generated game data. The current
first-boot importer has desktop file pickers only, so a production iOS release
still needs a UIDocumentPicker handoff that passes the selected ROM to LÖVE.

`game.love` includes all ROM import manifests referenced by
`src/core/GameVersion.lua` (currently Red/Blue/Yellow/Gold/Silver). The iOS
packer validates each listed manifest and restores missing files from this
checkout's Git data (or the project repository as a fallback) before
packaging.

Default output: an unsigned Simulator `.app` under `mobile/ios/build/`
(no Apple Developer account required). A convenience copy also lands under
`dist/ios/<Config>-<sdk>/`.

Install on a booted simulator (example):

```bash
xcrun simctl install booted mobile/ios/build/Build/Products/Debug-iphonesimulator/PokemonRed.app
xcrun simctl launch booted com.theboisclub.pokemonred
```

Or open `mobile/ios/love-src/platform/xcode/love.xcodeproj` in Xcode,
select the `love-ios` target, and Run on a Simulator after
`scripts/build_ios.sh --package-only` (or a full build) has placed `game.love`.

## Device / Release

```bash
scripts/build_ios.sh --device            # Debug, physical device SDK
scripts/build_ios.sh --device --release  # Release configuration
```

Device builds need a signing identity and provisioning profile configured in
Xcode (or via `DEVELOPMENT_TEAM` / `CODE_SIGN_IDENTITY` env vars). This repo
does **not** store certificates, profiles, or App Store Connect secrets.

Manual out-of-band steps:

1. Apple Developer account + App ID for `com.theboisclub.pokemonred`
2. Development or Distribution certificate + provisioning profile
3. In Xcode: open `love.xcodeproj` → target `love-ios` → Signing & Capabilities
   → select your Team (or set `DEVELOPMENT_TEAM=XXXXXXXXXX` when invoking
   `scripts/build_ios.sh --device`)
4. Archive / export an `.ipa` from Xcode Organizer for TestFlight / Ad Hoc

## Layout

| Path | Role |
|------|------|
| `LOVE_VERSION` | Engine pin (`12.0`) |
| `overlays/love-ios.plist` | Portrait-only Info.plist + display name **Pokemon Red** (copied over the upstream plist every build) |
| `love-src/` | Downloaded LÖVE 12.0 source tree (**gitignored**, do not commit) |
| `cache/` | Temporary source and dependency checkout data (**gitignored**) |
| `build/` | `xcodebuild` derived data (**gitignored**) |

Game payload lands at:

`love-src/platform/xcode/ios/resources/game.love`

and is fused into the built `.app` (LÖVE auto-runs any bundled `*.love`).

## Apple libraries dependency

`scripts/build_ios.sh --fetch` retrieves the matching iOS libraries and the
SDL3 framework from
[love-apple-dependencies](https://github.com/love2d/love-apple-dependencies).
Re-run it if either dependency directory is absent.

## App identity

| Field | Value |
|-------|--------|
| Display name | Pokemon Red |
| `PRODUCT_NAME` | PokemonRed |
| Bundle ID | `com.theboisclub.pokemonred` |
| Orientations | Portrait only (`UIInterfaceOrientationPortrait`) |

Overrides are applied by the build script (`xcodebuild` settings + plist overlay)
so refreshing `love-src/` does not lose branding.

## Flags (`scripts/build_ios.sh`)

| Flag | Meaning |
|------|---------|
| *(default)* | Simulator, Debug, no signing |
| `--fetch` | Fetch the LÖVE 12.0 source tree and Apple dependencies if `love-src/` is missing |
| `--device` | Build against `iphoneos` instead of `iphonesimulator` |
| `--release` | `Release` configuration instead of `Debug` |
| `--package-only` | Zip `game.love` + apply plist overlay; skip `xcodebuild` |

Also: `scripts/build.sh ios` delegates here (`--release` is forwarded).

## Preconditions

- macOS (Darwin) with Xcode + `xcodebuild` on `PATH`
- iOS platform installed in Xcode (Settings → Platforms). `xcodebuild -showsdks`
  should list `iphonesimulator` / `iphoneos`. A partial install can fail IB/xib
  compiles with `iOS … Platform Not Installed` even when the SDK name appears.
- `love-src/` present (`--fetch`)
- iOS libraries under `love-src/platform/xcode/ios/libraries/` and SDL3 under `love-src/platform/xcode/shared/Frameworks/`
