# Updater

**This file is the mechanism. `docs/auto-update.md` is the per-platform story**
— what each shell can actually do about an update, how that was measured, and
what the Switch, Xbox and Android were doing wrong. Read that one for "why
doesn't X update"; read this one for how Boot and Check work.

A fused build (`love.filesystem.isFused()` true) ships a bundled `game.love`
baked into the executable, but that bundled copy is only ever the *fallback*.
On every launch, before anything else runs, `Boot.run` (`src/update/Boot.lua`)
looks in the save directory's `updates/` folder for a downloaded
`Gen2Recomped-X.Y.Z.love` payload that is both strictly newer than the bundled
engine version and runnable on this shell. If one qualifies, it is mounted
over `/` (so its files win over the fused source for every subsequent
`require`) and chainloaded in place: the payload's `main.lua` and `love.load`
run as if they had shipped in the executable. A dev/source checkout is never
fused, so `Boot.run` no-ops there and the working tree always runs itself.

The pieces are deliberately layered so the risky part is small. `Boot.select`
is a pure function (no `love.*` calls) that, given probed candidates and the
bundled `engine`/`shell`, decides what to run and what stale payloads to
delete. `Boot.probePayload` mounts one archive at an isolated mountpoint and
reads its `src/core/Version.lua` with `loadstring` (never `require`, so it is
never cached as a module) to learn its `engine` and `minShell`. `Boot.run`
orchestrates the crash guard, enumeration, selection, and the mount +
chainload, with full rollback on any failure. Checking for and fetching a
new payload is a separate, slower path: `src/update/Check.lua` is a thin
main-thread state machine the launcher screen polls, while the curl calls,
JSON parsing, and sha256 verification run on a background `love.thread`
(`src/update/check_worker.lua`) so a hung network call never blocks a frame.

## Version.lua fields

`src/core/Version.lua` carries three fields the updater reads directly (the
existing `modApi`, `linkProtocol`, `saveFormat`, and `cache` fields are
untouched):

- `engine` - the semver release, e.g. `"1.4.0"`. The repo default is the
  `"0.0.0-dev"` placeholder; CI stamps the real `X.Y.Z` into the packed
  `game.love` only, never the working tree. A `"0.0.0-dev"` engine always
  reports itself up to date (it never chases a release, and it never counts
  as a valid payload to chainload).
- `shell` - the native-shell contract this build's fused executable
  implements.
- `minShell` - the lowest shell contract required to *run* this payload.

Bump `minShell` only when a payload needs something the currently-shipped
native shell cannot provide, for example a LOVE version bump, a new required
system binary, or a change to `love.run` itself (see Known limitations
below). An older shell refuses to chainload a payload whose `minShell`
exceeds the shell it provides; `Boot.select` keeps that payload in `updates/`
rather than deleting it, in case a future shell upgrade can run it, and
`Check`'s worker reports `needs_full` so the player is pointed at a full
installer instead. Do not bump `minShell` for an ordinary Lua/data release;
that is exactly the case the updater exists to avoid a reinstall for.

## Release assets

Each tagged release `vX.Y.Z` carries the existing per-platform archives
(`Gen2Recomped-X.Y.Z-macos.zip`, `-windows.zip`, `-linux.zip`,
`-android.apk`, `-switch.zip`, `-xbox-uwp.zip`, `-windows.msix`, `-ios.ipa`,
`-rg34xxsp-stockos64-mod.zip`, `-linux-arm64.AppImage`) plus two assets the
updater itself consumes:

- `Gen2Recomped-X.Y.Z.love` - the payload. The folder, the prefix, the
  extension and the pattern that recognises one all live in
  **`src/update/Payload.lua`**, which is the only place they exist: they used
  to be seven string literals across `Boot.lua`, `Check.lua` and
  `check_worker.lua`, so the downloader and the boot shell each had their own
  idea of where a payload goes. `Boot.isPayloadName` and
  `Check.parseRelease`'s `payloadName` both come from it, and
  `tools/auto_update_check.lua` fails if either spells it again.
- `sha256sums.txt` - `shasum -a 256` output (`<hex>  <filename>`, bare
  filenames) covering at least the `.love` payload. `Check.parseSums`
  tolerates a leading `*` binary marker and a `./` prefix but expects the
  filename otherwise to match the asset name exactly.

A release missing either asset is treated as "no in-place update available":
`Check` reports `needs_full` and sends the player to `Check.releaseUrl()`
(`https://github.com/UNDERdecoded/Gen2Recomped/releases/latest`).

## Save-directory layout

Under the save directory — identity `Gen2Recomp` on desktop and console,
`pokemon-love2d` on Android and iOS, which `conf.lua` decides and
`src/core/SaveIdentity.lua` migrates:

```
updates/Gen2Recomped-<X.Y.Z>.love  downloaded payload(s)
updates/pending.txt                crash-guard marker
```

`pending.txt` holds the filename of the payload currently being chainloaded.
`Boot.run`'s `chainload` writes it immediately before mounting, and removes it
on both a successful handoff and a clean rollback. If it is still present the
*next* time `Boot.run` starts, the previous boot died mid-handoff, so that
named payload is distrusted: it and the marker are deleted before candidates
are enumerated. Boot may still fall back to an older valid payload, or to the
bundled game, in that case.

## Update flow

1. **Boot** (every launch, fused builds only): crash-guard check, enumerate
   and probe every `updates/*.love`, pick the highest engine that is
   strictly newer than the bundled one and whose `minShell` this shell
   satisfies, delete stale payloads, chainload the winner (or run the
   bundled game if none qualifies).
2. **Check** (launcher screen): `Check.start()` kicks off an async check
   against the GitHub releases API; safe to call every frame, it is a no-op
   once a check is in flight or has reached a terminal state. `Check.state()`
   reports one of the nine statuses in `Check.STATUS` — `idle | checking |
   uptodate | available | downloading | ready | needs_full | notify | error` —
   plus the latest version, download progress and an `advice` enum. Only the
   five `Check.STATUS` marks `true` are drawn by the launcher banner, and
   `tools/auto_update_check.lua` asserts the banner's own branches agree with
   that table: a state posted and not drawn is invisible to the player, which
   is what `notify` was added to stop.
3. **Download + verify**: on `available`, `Check.download()` tells the
   worker to fetch the payload, polling the growing `.part` file for
   progress. On completion the worker re-fetches `sha256sums.txt`, verifies
   the payload's sha256, and probes it with `Boot.probePayload` to gate its
   `minShell` against this shell's `shell`. A verified, runnable payload is
   renamed into place and reported as `ready`; anything else reports
   `error` or `needs_full` and leaves `updates/` clean.
4. **Restart to apply**: a `ready` payload just sits in `updates/` until the
   player relaunches; the next launch's Boot step (1) is what actually
   mounts and runs it. There is no in-session hot-swap.

## Verifying a hand-placed payload

On a console the player copies the payload into `updates/` themselves, because
neither host can fetch (see `docs/auto-update.md`). That copy used to be
mounted unexamined, while every other arrival route refused a bad hash. If the
release's own `sha256sums.txt` is copied into `updates/` **beside** the
payload, `Boot.run` hashes the archive with `love.data.hash("sha256", …)` and
compares it against the row for that exact filename:

| verdict | when | result |
|---|---|---|
| `verified` | listed, hash matches | mounted |
| `mismatch` | listed, hash differs | refused; both hashes printed; file kept |
| `unlisted` | manifest present (or empty) and does not name the payload | refused |
| `unverified` | no manifest in `updates/` | mounted, with a loud line |

The decision and its wording are in `src/update/Sideload.lua` (zero `love.*`
calls, so it is driven from a plain-Lua test); the hashing and the mount stay in
`src/update/Boot.lua`. `Payload.SUMS` / `Payload.sumsRel()` /
`Payload.parseSums()` own the manifest name and its format — `Check.parseSums`
delegates there, and `tools/auto_update_check.lua` fails on a second spelling in
either language.

A refused payload is dropped from the candidate list but **not** deleted: the
player placed it by hand, so copying it again is the fix and the file is the
evidence. (A payload that fails handoff is still deleted — that one failed
deterministically.)

## Known limitations

- **`love.run` persists across handoff.** By the time `chainload` runs, the
  bundled `love.run` has already returned its stepper to LOVE; redefining the
  global `love.run` from the payload's `main.lua` does not affect the loop
  already driving the frame. A payload that must change `love.run` itself
  needs a `minShell` bump so an older shell refuses to chainload it rather
  than running with half its intended behavior.
- **Android downloads through the host bridge.** (This bullet used to deny
  that Android had any in-app transport at all. That stopped being true a
  release and a half ago and the bullet outlived it, which is the failure mode
  `docs/auto-update.md` exists to record;
  `tools/auto_update_check.lua` now asserts the old claim cannot come back.)
  `HostShell.transport()` resolves `curl` on desktop and
  `love.system.httpDownload` — a JNI call into GameActivity that our vendored
  liblove exports — on Android. The bridge deals in whole files and blocks the
  calling thread, and it must be called from the main thread (a JNI call from
  a `love.thread` is a native abort), so `Check.lua` services the worker's
  request from `drain()` and answers a payload-sized one **a frame late**, so
  the "Downloading update" banner is on screen before the thread stalls. There
  is no progress fill on that path: the bridge takes no `Range` header, so
  there is nothing to poll.
- **Two hosts can host a payload and cannot fetch one.** On NX and inside a
  packaged app container there is no HTTPS client reachable from Lua, so the
  capability resolves `notify-only`: the banner says what the real update path
  is (the native OTA launcher on Switch, a newer package on Xbox) and a payload
  placed in `updates/` by hand still chainloads. The full measurement, and why
  the old "the payload is fused into the NRO" argument was answering the wrong
  question, is in `docs/auto-update.md`.
- **Dev/source runs never self-update.** `Boot.run` returns immediately when
  `love.filesystem.isFused()` is false, and a working tree's `engine` is the
  `"0.0.0-dev"` placeholder that always reports up to date, so a source
  checkout is always "the game" itself; updating it means pulling the repo.
