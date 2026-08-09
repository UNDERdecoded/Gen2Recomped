# iOS build (LÖVE 12.0)

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
