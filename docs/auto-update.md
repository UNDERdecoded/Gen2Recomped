# Auto-update, per platform

This is the companion to `docs/updater.md`, which describes the mechanism.
This file records what each platform can actually do about an update, how that
was measured, and what used to be wrong.

Read `docs/updater.md` with one correction: its "Known limitations" section
still says "Android has no in-app download transport yet", and its asset names
are still spelled `gen1recomp-X.Y.Z.love`. Neither is true now; the payload
name is `Gen2Recomped-X.Y.Z.love` and Android downloads through the host
bridge. The authority for the name is `src/update/Payload.lua`.

## The two capabilities, and why they are separate

Self-update is the conjunction of two facts that have nothing to do with each
other, and for two years they were answered by one OS table:

* **Can this shell host a payload?** `Platform.canHostPayload()`
  (`src/core/Platform.lua`). Measured, not listed: it writes a byte into the
  save directory's `updates/` folder, reads it back, and requires
  `love.filesystem.mount`/`unmount` to exist. `Boot.run` never writes inside
  the application package and never replaces the executable — it mounts a
  `.love` out of the **save directory** over `/` and chainloads it — so the
  only question is whether that directory takes a write.
* **Can this shell fetch one?** `HostShell.transport()`
  (`src/core/HostShell.lua`). Returns `"curl"` (a curl we actually ran
  `--version` on, through `HostShell.popen`), `"bridge"`
  (`love.system.httpDownload`, the GameActivity JNI call our Android liblove
  exports, #597), or `nil` plus a sentence saying why.

`Check.capability()` (`src/update/Check.lua`) combines them into one of four
modes and **prints one line per launch** saying which it took:

```
update: capability host=Android fused=true host-payload=true transport=bridge -> self-update
update: capability host=NX fused=true host-payload=true transport=none -> notify-only (no HTTPS client on NX: this host cannot spawn curl and exports no download bridge)
```

That line is the point. The bug this replaced was not a crash; it was three
different silent refusals that all looked identical from the outside.

## What was wrong, platform by platform

### Android — a policy refusal, not a failure

`src/update/check_worker.lua`'s `doCheck` ended with

```lua
if resolveTransport() == "bridge" then
  post({ status = "needs_full", latest = rel.version })
  return
end
```

Android is the only platform whose transport is the bridge, so that branch
**was** the Android update path. Every Android release reported `needs_full`,
the launcher banner drew "A new version needs a fresh download" with an "Open
releases" button, and the tap called `love.system.openURL(Check.releaseUrl())`
— the player was sent to the GitHub releases page by hand on every version of
Android, which is exactly what was reported. Nothing was broken and nothing
logged anything, because nothing had failed.

Its two stated reasons were both out of date. `launchDownload` was curl-only,
which is now fixed: `doDownload` has a bridge branch. And the freeze it worried
about was costed at "a ~6 MB transfer" — the measured payload for v0.8.3 is
**20,368,165 bytes**, read off the release asset. The freeze is real, so it is
now announced rather than avoided: a bridge request carrying `big = true` is
answered **one drain late**, so the first frame posts `downloading`, the
launcher draws the banner, and the transfer blocks on the following frame with
"Downloading update" on screen. There is no progress bar fill, because the
bridge deals in whole files and takes no `Range` header, so there is nothing to
poll.

Nothing about Android 12 versus Android 16 was involved. `targetSdk` is 34 and
has not moved; the save directory is `t.externalstorage`'s app-specific
external folder, which needs no runtime permission on any API level; and
`INTERNET` is in the manifest. The one real per-device difference was that a
device whose ROM happens to ship `/system/bin/curl` resolved the **curl**
transport and behaved differently from one that does not. `HostShell.popen`
now refuses outright on a host that is not one of the three desktops, so every
Android device takes the same bridge path.

### Switch — the stated blocker is not the blocker

The old gate read:

```lua
local NOTIFY_ONLY_OS = { Horizon = true, NX = true, Switch = true }
```

with a comment arguing that "on the Switch the payload is fused into the NRO
... so those builds CHECK and REPORT but never download".

Both halves were wrong. `Boot.run` does not touch the NRO; it mounts a `.love`
from the save directory, which on the Switch is
`sdmc:/switch/gen2recomp/pokemon-love2d/` and is where the launcher already
writes saves, options and the entire ROM cache. **A payload copied into
`updates/` there by hand boots today** — that is not a new feature, it is what
the refusal was hiding.

And "CHECK and REPORT" was not happening either: with no transport the worker
posted `status = "error"`, and the launcher banner renders only `available`,
`downloading`, `ready` and `needs_full` — so the Switch showed the player
nothing at all, not even a notice.

What the Switch genuinely cannot do is fetch. `io.popen` cannot start a child
process there (and does not return `nil` — it **raises**), `switch-curl` is a
library linked into the OTA launcher rather than a binary on the console, and
`love-nx` exports no download bridge. LÖVE's only socket library is plain
LuaSocket with no TLS, and GitHub is HTTPS-only. So: `notify-only`, and the
reason is printed.

The Switch is not left without updates, because it already had a better path
than the LÖVE updater: `ports/switch/ota-launcher` is a native NRO (the hbmenu
entry `gen2recomp.nro`) that checks GitHub, verifies SHA-256 from
`sha256sums.txt`, and replaces **both** `Gen2Recomped-game.nro` and
`gen2recomp.nro` via a one-shot `ota-bootstrap.nro`. Its README already said
"The LÖVE self-updater stays disabled on NX" — it was right, for a reason the
gate beside it did not give.

### …and that better path was asking a repository that does not exist

The Switch's real update bug was not in Lua at all. `ota_protocol.h` had

```c
#define OTA_RELEASES_API \
  "https://api.github.com/repos/UNDERdecodedHD/Gen2Recomped/releases/latest"
```

and `src/main.c` built its checksum URL from the same owner, spelled out a
second time. Measured on 2026-10-04:

| slug | HTTP |
|---|---|
| `UNDERdecodedHD/Gen2Recomped` | **404** |
| `UNDERdecoded/Gen2Recomped` (`Check.REPO`) | **200** |

**`UNDERdecodedHD` is the author name** — the NACP author, the MSIX publisher,
the intro credit — and is correct everywhere it appears as a name. The GitHub
owner is `UNDERdecoded`. The two were conflated in the one place where the
difference costs a feature, so the launcher's quiet check 404ed on every boot,
took its "up to date or offline" branch, showed nothing, and the console had no
working in-app update path at all. `src/update/Check.lua` carried the correct
slug *and a comment describing this exact mistake* — "an updater that points at
the wrong repo fails exactly like an updater with no network" — two directories
away.

Both URLs now derive from one `OTA_REPO_SLUG`, and the check asserts it equals
`Check.REPO`: the cross-language half of the recurring bug, which nothing in
the tree had been comparing. The launcher's own host suite
(`make host-test`, 34 cases) builds and passes on the change, and `main.c`
syntax-checks clean for the host branch.

The README's dangling pointer to `src/update/SwitchOta.lua` — a file that has
never existed in this tree — is corrected to the C files that really hold the
wire format, in both the README and the header comment that carried the same
reference.

### Xbox (UWP) — a gate that could not fire

`canSelfUpdate()` consulted `love._os`, which reports **"Windows"** inside a
UWP container, so `NOTIFY_ONLY_OS` never matched Xbox. The comment said the
console packagers set `_G.POKEPORT_NOTIFY_ONLY_UPDATES` "from their own
bootstrap". That identifier occurs **exactly once in the repository** — the
read in `Check.lua`. `ports/uwp/app/main.cpp`, `ports/uwp/CMakeLists.txt`,
`scripts/build_xbox_uwp.sh`, `scripts/xbox-uwp/stage_release.ps1` and
`scripts/build_msix.ps1` set nothing. So the notify-only branch for Xbox was
dead code and `canSelfUpdate()` returned **true** there; what actually stopped
Xbox was the absence of a transport, reported as `error`, drawn as nothing.

**And it is detectable after all.** The old comment's premise —
"`love._os` cannot tell a UWP package apart from a desktop Windows build (both
report \"Windows\")" — is true of `love._os` and false of the shell. A process
with package identity is handed its writable folder *under that identity*:

```
desktop LOVE on Windows   C:\Users\<u>\AppData\Roaming\LOVE\<identity>
UWP / MSIX container      C:\Users\<u>\AppData\Local\Packages\
                            <PackageFamilyName>\LocalState\...
```

so `Platform.isPackagedContainer()` reads `love.filesystem.getSaveDirectory()`
and looks for the `Packages` component. An MSIX-packaged *desktop* build
(`scripts/build_msix.ps1`) matches too, and that is correct rather than a false
positive: an MSIX build is also updated by installing a newer package, which is
the only thing this answer is used for. The one way to be wrong is a user
folder with a literal `Packages` component, and the cost of that is a different
sentence in the banner.

Like the Switch, Xbox **can** host a payload: `ports/uwp/app/main.cpp` passes
`--fused` with the package-relative `gen2recomp.love`, so `isFused()` is true,
and the save directory is the package's writable `LocalState`. A payload placed
in `LocalState/.../updates/` (via the Xbox Device Portal's file browser) is
mounted and chainloaded on the next launch. What it cannot do is fetch:
`internetClient` is declared in `Package.appxmanifest.in`, but a UWP container
cannot `CreateProcess` curl and the UWP LÖVE backend exports no
`love.system.httpDownload`. So: `notify-only`, with the reason printed.

`POKEPORT_NOTIFY_ONLY_UPDATES` survives as an override and is now read from the
**environment** as well as the global, so a packager can actually set it. In
that mode the check still runs (that is the one case where "CHECK and REPORT"
was ever possible) and only the download is refused.

### Desktop — unchanged, and verified end to end

macOS, Windows and Linux resolve curl and self-update exactly as before. The
release side was verified against the live v0.8.3 release rather than assumed:

| fact | measured value |
|---|---|
| release tag | `v0.8.3` |
| payload asset | `Gen2Recomped-0.8.3.love`, 20,368,165 bytes |
| its sha256 | `96fd6080…1d9e11d`, matching the line in `sha256sums.txt` |
| payload's `Version.engine` | `0.8.3` |
| payload's `minShell` | `1` (this shell provides `1`, so the gate passes) |
| sums format | `sha256sum` output, two spaces, bare filenames, and the sums file is outside the `Gen2Recomped-*` glob so it never lists itself |

No `.github/workflows/` change was needed: `release.yml` already stages
`Gen2Recomped-${v}.love` from the shared `game.love` and writes
`sha256sums.txt` over it.

## One fact for where a payload lives

The recurring fault in this tree is the same thing spelled differently in two
places that never meet, and the updater had it badly. Before this pass, the
folder and the asset name were **seven string literals in three files**:
`Boot.lua` had `"updates"`, `"updates/pending.txt"` and the pattern
`"^Gen2Recomped%-.+%.love$"`; `Check.parseRelease` built
`"Gen2Recomped-" .. version .. ".love"`; and `check_worker.lua` spelled
`"updates/"` four more times plus `"updates/dl.bat"`. The downloader wrote the
payload and the boot shell went looking for it, and neither asked the other
where it was.

`src/update/Payload.lua` is now the only place those exist — zero requires, no
`love.*` calls, so it loads on the main thread, inside the worker thread and
under plain Lua. `tools/auto_update_check.lua` strips comments from every file
in `src/update` and **fails if any of those literals reappears**. The same pass
removed a second spelling of the repository slug: `check_worker.lua` had the
`api.github.com` URL written out, so moving the repo in `Check.REPO` would have
moved the "Open releases" button and left the API call pointing at the old one.

## Failures are visible now

An update path that gives up quietly is indistinguishable from one that is not
there, and that was most of this bug. Four new announcements, following the
`chip audio: music path = ...` precedent:

* `update: capability host=… -> <mode> (<reason>)` — once per launch, from
  `Check.start()`, so a host that never draws an Update button still says what
  it can do. It used to be reachable only from `Check.download()`.
* `update: transport = curl | bridge | none (<why>)` — once, from the worker.
* `update: <status> latest=<v> -- <error>` — once per distinct terminal state.
  The banner draws four of the eight states and nothing for `uptodate`,
  `error` or `idle`.
* `update: payload <name> needs shell 2, this build provides 1 …` — from
  `Boot.run`, for every candidate it declined. An older payload and a payload
  whose `minShell` is too high used to look identical from outside (nothing
  happened) and are completely different inside: the second one needs a full
  reinstall and no amount of re-downloading will fix it. `Boot.run` also says
  so when it is skipped on an unfused build **while payloads are sitting in
  `updates/`**, which is the "I copied the .love across and nothing happened"
  case and the first thing to check on a console.

`Check.download()`'s refusal also moved **ahead** of the `cmdCh` guard — behind
it, on a host with no worker thread, the refusal never ran at all — and now
leaves `status = "needs_full"`, a state the banner actually draws, instead of
returning silently.

## The banner, and the two things it used to get wrong

The launcher's update banner (`src/import/RomImporter.lua`) kept its own list
of which states were worth drawing — four of them — and `error` was not on it.
So the leg a transport-less host ended on rendered **nothing**, and that is the
whole reason NX and UWP looked like builds with no updater rather than builds
with a disabled one. Two changes:

* `Check.STATUS` marks which of the nine statuses are drawable, and the banner
  derives its set from that table instead of listing them. There is a new
  drawable status, **`notify`**, which `Check.start()` leaves on a host that
  cannot check at all.
* Every snapshot carries an **`advice`** enum — `download | ota | package |
  releases` — decided in `Check.capability()` so the launcher only picks the
  wording:

| advice | the row reads | button |
|---|---|---|
| `download` | "Update vX.Y.Z available" | **Update** |
| `releases` | "A new version needs a fresh download", or "Cannot check for updates on this build" | **Open releases** |
| `ota` | "Update from the OTA launcher (gen2recomp.nro)" | none |
| `package` | "Install the newer package to update" | none |

The two console advices draw **no button on purpose**: neither host has a
browser for `love.system.openURL` to open, and a dead button is worse than no
button because the player taps it and concludes the updater is broken. The
releases tap is also `pcall`'d now — it was a bare call, reachable on a host
whose `openURL` is a stub, which would have taken the launcher down on a tap.

`tools/auto_update_check.lua` asserts both joins in both directions: every
status `Check.STATUS` marks drawable must have a branch in the banner and vice
versa, and every value `Check.advice()` can return must be mentioned there, so
a fifth advice cannot be added in one file and ignored in the other.

## The check

`tools/auto_update_check.lua`, 218 assertions, no cartridge and no cache
required. It grades nine things, each so that it can fail:

1. **One fact.** `Payload.rel()`'s folder must equal the folder `Boot.run`
   enumerates and its basename must satisfy `Boot`'s own `isPayloadName`; the
   `.part` and `.done` names must not. The comment-stripped scan of
   `src/update` must find no second spelling. When `.github/workflows/release.yml`
   is in the tree, the asset name is checked against the line that stages it.
2. **The capability rule**, driven through ten stub hosts (desktop with and
   without curl, Android, NX, UWP, a UWP container reporting "Windows", a
   read-only save directory, an unfused checkout, an explicit suppression).
   `io.popen` is replaced for the duration and **counted**, so "the Switch must
   not reach `io.popen` at all" is an observation rather than a claim about a
   comment. Every case also asserts that the branch logged itself, and that the
   state a refusal leaves is one the banner draws.
3. **The deferred bridge transfer**, driven for real with in-memory channels: a
   `big` request must not transfer on the drain that first sees it, must leave
   `downloading` on that drain, must transfer on the next one, and must hand
   the bridge an **absolute** path (a save-directory-relative path was one of
   the three things that used to abort the Android process).
4. **The semver comparison**, including `0.10.0` vs `0.9.9` (a string compare
   would report every release past `.9` as older) and the `0.0.0-dev`
   placeholder, which must not parse.
5. **The sums parsing** in the exact format `release.yml` produces, plus the
   `*` and `./` variants, a CRLF body, and two negatives.
6. **The `minShell` refusal**: `>` not `>=` (a `>=` refuses a payload this
   shell can run), and a payload that is too new must be **kept**, not deleted,
   because a later native build may run it.
7. **The two Check↔banner joins**, in both directions, plus which advices are
   allowed to draw a button and that the releases tap goes through `pcall`.
8. **The cross-language repository slug.** `OTA_REPO_SLUG` in
   `ports/switch/ota-launcher/include/ota_protocol.h` must equal `Check.REPO`,
   both of the launcher's URLs must derive from it, `src/main.c` must not spell
   an owner out, and the dead `src/update/SwitchOta.lua` pointer must not come
   back in the header or the README. Plus `docs/updater.md`: no `gen1recomp-`
   payload name, the real name present, the "Android has no in-app download
   transport" claim absent, and a pointer to this file — because a doc that
   contradicts the doc beside it is how this project keeps losing facts.

9. **That the run was a whole run.** Four of the files above are committed
   repo files, so a missing one is a broken tree and fails by name; and a floor
   on the assertion count catches a reduction from any other cause.

Twenty-eight faults were planted across three rounds, each verified to have
landed by md5 and each confirmed to fail with a message that names it; the
control was re-run on md5-verified-identical files afterwards. The Switch
launcher's own host suite (`make host-test`, 34 cases) was built and run on the
C change, and `main.c` syntax-checked for the host branch.

### A reduced run used to look exactly like a whole one

Four blocks opened with `if not read(path) then io.write("(… not present —
skipped)") else … end`. Run in a tree without `ports/`, the check lost **ten
assertions** — including the cross-language slug assertion, the one thing
standing between the Switch's 404 and its return — printed a parenthetical
nobody greps for, and reported a plain **`PASS`**. The suite line was
indistinguishable from a full run. Worse, that is how every run reported before
this round was made: the `release.yml` cross-check had *never once executed*,
because this working tree had no `.github/`.

**And `PASS*` was never available for it.** `tools/run_checks.py` sets that
marker (its lines 255–259) from `reduced`, which it populates at line 247 only
when an *optional argument slot declared in the check's own `Run:` line* was not
supplied. It never reads the check's output, and this check declares no argument
slots, so `reduced` is permanently empty here. A check cannot ask to be marked
reduced — it can only fail.

So all four fail by name. `git ls-files` confirms every one is tracked and
`git check-ignore` that none is ignored, which is what makes absence a fault
rather than a condition:

| file | why its absence is a fault |
|---|---|
| `ports/switch/ota-launcher/include/ota_protocol.h` | carries `OTA_REPO_SLUG` |
| `.github/workflows/release.yml` | names the release asset; without it the check compares `Payload.lua` with itself |
| `docs/updater.md` | the four claims that had already gone stale once |
| `src/import/RomImporter.lua` | the Check↔banner joins |

**Plus a floor on the assertion count**, because `required()` only covers the
four absences somebody thought of. A pattern that stops matching removes
assertions with no file missing at all, and a planted fault proved it: breaking
the banner dispatch-head pattern dropped the run from 218 to 178 with **no**
"missing from the tree" line, and the floor is what failed it. `PASS*` would not
have caught that either, since no argument was absent. The floor is pinned at
the count of everything that runs *before* it — not at the number the verdict
line prints, which would fail on a clean tree (shape 2a) — and it may only rise.

### Three of those plants found faults in the check, and they are one fault

Each time, an **absence or membership assertion over prose was satisfied by a
second occurrence of the same text that was not the thing under test**:

| the assertion | what satisfied it instead |
|---|---|
| the banner draws `notify` | a *second* `upStatus == "notify"` inside the branch body, left behind when the branch head was deleted |
| the releases tap is `pcall`'d | an unrelated `pcall(love.system.openURL, …)` 2,300 lines away |
| the dead `SwitchOta.lua` pointer is gone | the comment *explaining* that it was removed |

All three passed a planted fault. The repairs are the same shape: anchor on the
form the thing under test actually takes and that prose about it does not — the
dispatch's `if`/`elseif` heads rather than any mention; `pcall(…, self.Check.releaseUrl`
rather than the function name; the full path rather than the bare filename —
and, where the prose was the problem, reword the prose. A vocabulary or absence
scan with two sources for one token grades neither.


## The consoles, re-asked: what gen1recomp does, and what is left

Cedric's question was *"investigate other methods of ensuring that switch and
xbox can update if they can't already — check how gen1recomp is currently doing
it and maybe copy their implementation of it for those consoles."*
`gen1recomp` is the predecessor project (`bryanthaboi/gen1recomp`, HTTP 200,
public) and its branding is still in this tree, so the expectation that it had
solved something was reasonable. It has not.

### The licence answer first, because it decides what "copy" can mean

`LICENSE.MD` in that repository is **GPLv3 with Section 7 additional terms**
(Copyright 2026 BOIS CLUB GAMES, LLC). Term 1 requires attribution in the
README, the in-app credits *and* any launcher. Term 2 carves the launcher out
of the GPL entirely and makes it proprietary, "not to be copied, modified,
redistributed, or used in any fork … in whole or in part", naming
`src/import/LauncherView.lua`, `src/import/OnlinePanel.lua`,
`src/mods/LauncherMods.lua` and the launcher UI code inside
`src/import/RomImporter.lua`.

Gen2Recomped is source-available with no redistribution, which is not a licence
GPLv3 code can be folded into: taking GPL source obliges the combined work to
be distributable under the GPL, and this project is not. **So nothing was
vendored. Every line below is written here, and only the approach was read.**
That is the honest answer even where the two designs converge, which they do:
both verify SHA-256 against the release's own `sha256sums.txt`, because that is
the file GitHub publishes.

### What gen1recomp actually does on Switch — the same thing we do

Read as code, not as docs: `ports/switch/ota-launcher/src/ota_net.c` there is
libnx + `switch-curl`, with

```c
#define OTA_CA_BUNDLE "romfs:/cacert.pem"
curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
curl_easy_setopt(curl, CURLOPT_CAINFO, OTA_CA_BUNDLE);
```

— a CA bundle baked into the NRO's romfs. **Our launcher's `ota_net.c` is the
same three lines and the same `cacert.pem`**, fetched from `https://curl.se/ca/`
by the launcher `Makefile`'s `sync-romfs` target and linked against
`switch-mbedtls`. The transport, the trust store and the verification are
already identical. The asset it pulls is the whole SD zip; the payload lands in
`<install>/updates/`; SHA-256 is looked up in the release's `sha256sums.txt` and
a missing sum is a reject on both sides; and both replace **both** NROs through
a one-shot bootstrap so the NACP versions stay in step.

The one genuine difference is a *negative*: gen1recomp's host test asserts
`!ota_is_ota_asset_name("gen1recomp-1.5.0.love")` — "reject love payload". Its
launcher deliberately refuses a bare `.love`. So the route that looked strongest
going in is the route the predecessor explicitly closed, for the reason given
below.

### What gen1recomp does on Xbox — nothing

`ports/uwp/app/main.cpp` there is a 29-line SDL WinRT shim with no HTTP of any
kind, `ports/uwp/CMakeLists.txt` links no HTTP library, and
`src/core/Platform.lua` answers

```lua
networkValidated = not nx and not uwp,
canFetchRemote   = (not nx and not uwp) or nativeHttp,
```

with its own comment: *"The UWP LOVE backend does not export that bridge yet,
so this still resolves false on Xbox."* `Check.lua` there offers Xbox the label
**"Open Xbox install guide"** pointing at the releases page. That is notify-only
with a button, which is strictly less than what this port already does — and
its detection is weaker than ours: it keys on `love.system.getOS() == "UWP"`,
which depends entirely on the LÖVE backend it bundles (there is no patch for it
in `ports/uwp/third_party/love/patches/`, which holds only two file-picker
patches), where `Platform.isPackagedContainer()` here reads the `Packages`
component out of the actual save path and cannot be wrong about it.

gen1recomp does have one thing this tree does not: `native/tls_dial/`, a .NET
Native-AOT DLL (`gen1tls`) wrapping `SslStream`, FFI-loaded by mods that need
outbound TLS. Its own README scopes it to **desktop** — "Windows: Schannel …
Linux / macOS: same project … Ship `gen1tls.dll` next to the fused
executable" — and it is for multiworld clients, not the updater. It is not a
console answer and was not treated as one.

### The four routes, each with the measurement that chose or rejected it

**Route 1 — have the Switch OTA launcher fetch the `.love` payload as well.
Rejected, and it was the favourite going in.** The premise was that the
launcher has working HTTPS, SHA-256 verification and write access to the same
`updates/` folder `Boot.run` reads, so pointing it at the payload too would be
nearly free. It would also be pointless and actively harmful. Measured against
the live release (HTTP 200, 2026-10-04): `Gen2Recomped-0.8.3-switch.zip` is
**26,773,008 bytes** and contains the **fused** `Gen2Recomped-game.nro` — the
`.love` is *inside* the NRO. Replacing that NRO, which the launcher already
does atomically, already replaces the engine Lua. Fetching a bare `.love` in
addition would put a second copy of the same code in `updates/`, and
`Boot.run` **prepend**-mounts `updates/*.love` over `/`, so a payload left
behind from an earlier OTA would silently shadow a freshly installed NRO: the
console would report the new version in its NACP and run the old Lua. That is
this port's recurring bug — the same thing in two places that never meet —
manufactured on purpose. gen1recomp's `reject love payload` test is the same
conclusion reached earlier.

**Route 2 — a CA bundle plus luasec/TLS reachable from LÖVE. Rejected, and
half of it already exists.** The CA-bundle half is done, in the NRO, on both
projects. The LÖVE half has no vendored code to reach for: `luasec`, `ssl.lua`,
`ssl.so` and `ssl.dll` are **absent from both trees** (searched by name across
each repository). Building luasec for love-nx would mean an mbedTLS-backed
LuaSec against a LÖVE that neither project builds from source for NX, and for
UWP the problem is worse — see route 3. Neither project has attempted it and
nothing in `love-nx` exports a socket with TLS; `src/link/Net.lua:69` is plain
LuaSocket.

**Route 3 — UWP's own HTTP stack behind a small bridge, the shape of Android's
JNI bridge. Rejected on a file listing.** The bridge Android uses is
`love.system.httpDownload`, a function registered on the `love.system` Lua table
from inside liblove. `ports/uwp/third_party/love/` contains exactly
`README.md`, `bin/love.dll`, `bin/lua51.dll`, `lib/liblove.lib`,
`lib/lovestatic.lib`, `lib/lua51.lib` and `patches/` — **prebuilt binaries and
no LÖVE sources**. There is nowhere in this tree to add the function, and
`ports/uwp/app/main.cpp` runs *after* LÖVE's module registration, so the app
shell cannot inject it either. A WinRT `Windows.Web.Http` DLL loaded through
LuaJIT FFI is the one remaining shape, and it needs the UWP MSVC toolchain, a
signed package and an actual Xbox to tell whether `ffi.load` survives the app
container at all — none of which is testable from here, and a transport nobody
can run is worse than an honest refusal. **So Xbox ends up where it was for
fetching: notify-only, `advice = "package"`, no button, "Install the newer
package to update".** The asset that sentence refers to is real and was
measured: `Gen2Recomped-0.8.3-xbox-uwp.zip`, 29,699,297 bytes, sha256
`46cf7762…dbafc333` in that release's `sha256sums.txt`.

**Route 4 — the sideload flow, made honest. Implemented.** This is the route
with something actually wrong behind it.

## The hand-placed payload was the one arrival nobody checked

Every other way a payload can reach a player is verified. `check_worker.lua`
re-fetches the release manifest and refuses a payload whose sha256 does not
match **before it ever lands**. `ports/switch/ota-launcher` refuses a zip whose
sum is missing or wrong — `ota_verify_sha256`'s own comment is "missing sum is
ALWAYS reject". And the hand-placed copy — the *only* update path the two
consoles have outside the native launcher, the one `docs/auto-update.md` tells
players to use — went straight into `love.filesystem.mount` with no integrity
question asked at all.

The failure that buys is not theoretical. A truncated Xbox Device Portal
upload, a microSD copy pulled before the write flushed, or a file grabbed while
a browser was still writing it **mounts as the game**: the zip's central
directory is intact enough to open, `src/core/Version.lua` reads fine because it
sits near the front, `Boot.select` picks it because it advertises a newer
engine, and the damage surfaces minutes later as a missing module or a corrupt
asset with nothing anywhere pointing at the payload.

`src/update/Sideload.lua` is the fix, and it is opt-in **by the presence of the
manifest**, which is the design decision worth recording. When the player drops
the release's own `sha256sums.txt` into the payload folder beside the payload,
the boot shell hashes the archive and refuses a mismatch. When they do not, it
mounts and says loudly that nothing was checked and how to have it checked.
Making it mandatory would break the documented flow for everyone already using
it, and hashing 20 MB on every boot to answer a question nobody asked is work
for nothing. Measured against the live release: that manifest is **1,171
bytes**, twelve rows, and the payload's row is
`96fd608027b41973fe7bd4f650826e11b7234add0ef93049aaf7567ac1d9e11d
Gen2Recomped-0.8.3.love` — so the file the player is being asked for exists,
and it does list the payload.

Four verdicts, and the sentence for each lives beside the decision so what the
player is told is gradeable without a LÖVE runtime:

| verdict | when | result |
|---|---|---|
| `verified` | listed, hash matches | mount, one line |
| `mismatch` | listed, hash differs | **refuse**, and print both hashes |
| `unlisted` | a manifest is present and does not name this payload | **refuse** |
| `unverified` | no manifest in the folder | mount, and say how to verify |

`unlisted` refuses on purpose and so does an **empty** manifest. A player who
went to the trouble of placing the file, and whose file does not cover the
payload next to it, has mixed two releases — exactly the state a silent accept
would hide — and an empty file is a failed copy of the manifest far more often
than it is a decision not to verify. A `sumsText ~= ""` guard would have thrown
that distinction away.

A refused payload is **dropped from the candidate list, not deleted**. The
player put it there by hand and copying it again is the fix, so destroying the
evidence would take the diagnosis with it. (A payload that fails *handoff* is
still deleted, as before: that one failed deterministically and would re-fail
every boot.)

### And the chainload line had been reporting the wrong version

```lua
print(("update: chainloading %s (engine %s)"):format(chosen, Version.engine))
```

`Version.engine` is the **bundled** version — the one being replaced. The one
line that was supposed to say what the player is about to run named the thing
they were moving off, so a payload advertising the wrong version was
indistinguishable in the log from one advertising the right one. It reads

```
update: chainloading Gen2Recomped-0.8.4.love (engine 0.8.4 over bundled 0.8.3, verified)
```

now: both versions and the integrity verdict, in the line that already existed.

### One parser and one spelling of the manifest name

`sha256sums.txt` was spelled in `src/update/Check.lua` and the sums-line parser
lived there too. The sideload verifier runs from `Boot.run` on the first line of
`love.load`, before `Check` is loaded at all, so a second parser was the next
instance of the recurring bug waiting to happen. `Payload.SUMS`,
`Payload.sumsRel()` and `Payload.parseSums()` are the single owners now;
`Check.parseSums` delegates and stays the name the tests drive. The check fails
if any other file in `src/update` spells the name as a literal, if `Check.lua`
grows the `(%x+)%s+` pattern back, if `release.yml` stops publishing the file,
or if the C side's `OTA_SUMS_URL_FMT` stops ending in it — the cross-language
half, which nothing had been comparing.

### The check: 218 → 261, and two of sixteen plants passed

`tools/auto_update_check.lua` section 7 is 43 new assertions, still with no
cartridge and no cache. The hashes it compares are the **live v0.8.3 release's
own**, read from that release's `sha256sums.txt`; a parser graded only against
invented input is a parser graded against itself.

Sixteen faults were planted, each verified landed by md5 and each restored to
an md5-identical file afterwards. **Fourteen bit with a message that named
them.** The two that passed are both findings about the check:

* **A fifth verdict constant with no `VERDICTS` row passed**, because the join
  walked a hand-written list of the four constants it already knew. It could
  only ever confirm what it had been told. The constant set is **discovered**
  now — every `UPPER_CASE` string field on the module is a verdict by
  construction and must have a row — and the replanted fifth verdict fails by
  name.
* **A plant that made `Sideload.lua` touch `love.*` took the whole run down
  with no verdict line**, which is worse than a failure: `texlua
  tools/auto_update_check.lua` exiting non-zero with no `FAIL:` reads as a
  broken checker rather than a broken module. The purity scan moved to the top
  of the section, ahead of every call into the module, and every call into
  `mayMount` goes through `pcall`. Replanted, it now prints three failures
  including the raise itself, and still prints a verdict.

The assertion floor moved from 217 to **260** (the count before the floor
assertion itself; the verdict line prints 261 — shape 2a).

### Suite

**PASS=72, REPORT=4, NOSPEC=41**, no FAIL / SKIP / ERROR / PASS\*, against the
reference cache. `auto_update_check` contributes **261 checks, 0 failed** and
reads no cache. Nothing in this pass touches `src/world`, `src/script`,
`src/render`, the extractors or `src/import`: the only files changed are
`src/update/{Payload,Check,Boot}.lua`, the new `src/update/Sideload.lua` and
`tools/auto_update_check.lua`, so Gold, Silver, Crystal, Prism, Polished
Crystal and Emerald are untouched by construction. The one behaviour change
visible to them is the boot shell's extra log line when a payload is sitting in
the payload folder, which only a fused build reaches.

### Still needs hardware or a rebuild

* **The OTA launcher still has the 404 slug baked into the committed `.nro`.**
  The source is fixed and the asset and the checksum row it needs are both live
  (`Gen2Recomped-0.8.3-switch.zip`, 26,773,008 bytes, sha256 `7d7dff3e…21e06146`
  listed in `sha256sums.txt`), so the only thing between the Switch and a
  working in-console update is a launcher rebuild reaching an SD card.
* **Xbox cannot fetch and that is now argued rather than assumed.** It hosts,
  it chainloads, and with a manifest beside the payload it verifies. It does not
  download, and nothing in this tree can make it without LÖVE sources for UWP.

## Play-test items

116. **Android, any version.** Launcher on a build older than the latest
     release: the banner must say "Update v*X.Y.Z* available" with an
     **Update** button, not "A new version needs a fresh download" with "Open
     releases". That single difference is the whole report.
117. **Android.** Tap Update. The banner must change to "Downloading update"
     **before** the screen stops responding, and the log must carry
     `update: fetching … through the host bridge (20368165 bytes)`. The
     progress bar stays empty — expected, the bridge gives no progress.
118. **Android.** When it finishes, the banner must offer "Restart to update";
     restart and the title bar must report the new version. The log must carry
     `update: chainloading Gen2Recomped-X.Y.Z.love`.
119. **Android, aeroplane mode.** Tap Update with no network: the state must
     become an error that is logged (`update: error … the host download bridge
     refused the transfer`) and `updates/` must be left with no `.part` file.
120. **Switch.** Boot the fused game NRO and read the log: exactly one
     `update: capability host=NX … -> notify-only (no HTTPS client on NX …)`
     line, and no ten-second stall waiting for a network it cannot reach. The
     launcher banner must read "Update from the OTA launcher (gen2recomp.nro)"
     with **no button**, not "A new version needs a fresh download".
121. **Switch.** Copy a newer `Gen2Recomped-X.Y.Z.love` into
     `sdmc:/switch/gen2recomp/pokemon-love2d/updates/` by hand and launch the
     game NRO. It must chainload it and report the new version. If it does not,
     the log says why (`not a fused build`, or the `minShell` sentence) — that
     is the one claim in this pass that could not be tested without hardware.
122. **Switch, and this is the one that matters most on that platform.**
     Rebuild and launch `gen2recomp.nro` (the OTA launcher). It must now
     *find* the release — before this pass its releases API was
     `UNDERdecodedHD/Gen2Recomped`, which answers HTTP 404, so it reported "up
     to date or offline" on every boot and never offered anything. Expect the
     branded update screen when a newer release exists, the three-step
     download/verify/install, and both NROs replaced. Saves under
     `pokemon-love2d/` must be untouched.
123. **Xbox (Dev Mode).** Read the log for
     `update: capability host=Windows … -> notify-only`. It must **not** say
     `self-update`; before this pass it did, because `love._os` is "Windows" in
     a UWP container. The banner must read "Install the newer package to
     update" with **no button** — which also confirms
     `Platform.isPackagedContainer()` recognised the `LocalState` save path.
124. **Xbox.** Drop a newer payload into the package's
     `LocalState/…/updates/` via the Device Portal and relaunch: it must
     chainload. Same caveat as 121 — untested without hardware.
125. **Desktop (Windows, macOS, Linux).** One full update cycle must behave
     exactly as it did before: `update: transport = curl`, an Update button, a
     filling progress bar, "Restart to update", new version after restart.
126. **Desktop with curl removed from PATH.** The banner must offer "Open
     releases" and the log must say
     `curl is not installed or not on PATH on <OS>` rather than falling silent.
127. **Any platform, source checkout.** `POKEPORT_DEV=1` or a plain
     `love .` run must print no capability line at all (the launcher's
     `updaterAllowed()` gate still requires a fused build) and must not reach
     the network.
128. **Gen 1 / 2 / 3 regression sweep.** Import and boot Gold, Crystal, Prism,
     Polished Crystal and Emerald. Nothing in this pass touches `src/world`,
     `src/script`, `src/import` or `src/render`; the only behaviour change
     outside `src/update` is that `HostShell.popen` returns `nil` immediately
     on a host that is not macOS, Windows or Linux, so the desktop ROM picker,
     the mod index and the bundled save editor must all still work.
129. **Windows MSIX build.** It has curl, so it must still report
     `self-update` and behave exactly like the plain Windows build; the
     packaged-container detection must not change anything for it. (It would
     only ever see "Install the newer package to update" if curl went missing,
     which is the right sentence for an MSIX install anyway.)
130. **Any platform, the banner's releases button.** Tap "Open releases" on a
     desktop with no curl: the page must open and the launcher must survive —
     that call is now `pcall`'d, where it was a bare call reachable on hosts
     whose `openURL` is a stub.

131. **Switch or Xbox, a verified sideload.** Copy `Gen2Recomped-X.Y.Z.love`
     **and** that release's `sha256sums.txt` into the payload folder
     (`sdmc:/switch/gen2recomp/pokemon-love2d/updates/` on the Switch, the
     equivalent under `LocalState` on Xbox). The log must read
     `update: sideload Gen2Recomped-X.Y.Z.love sha256 verified against
     sha256sums.txt`, then `update: chainloading … (engine X.Y.Z over bundled
     <old>, verified)` — **both versions in the one line**, where it used to
     print the bundled version twice.
132. **The same, with a deliberately corrupt payload.** Truncate the `.love`
     (lop a few hundred KB off the end) with the correct `sha256sums.txt` still
     beside it. The payload must be **refused**, the line must name both the
     expected and the actual hash, the bundled game must boot, and the file
     must **still be there afterwards** — it is kept on purpose so a second
     copy attempt is possible.
133. **A manifest from the wrong release.** Correct payload, but a
     `sha256sums.txt` from a different version. Expect `REFUSED — … does not
     list this payload, so the two came from different releases`, not a
     checksum mismatch: the two diagnoses are different problems.
134. **No manifest at all — the existing manual flow, which must not have
     regressed.** Payload only. It must still boot, and must print
     `is UNVERIFIED — no sha256sums.txt in updates/` with the instruction to
     copy one in. This is the case every console player uses today.
135. **An empty `sha256sums.txt`** (`touch` it, or a copy that failed). Must
     refuse as `unlisted`, not sail through as "no manifest".
136. **Desktop and Android, unchanged.** One full update cycle each. The
     downloaded payload is verified by the worker before it lands and arrives
     with no manifest in the folder, so the boot line will say `UNVERIFIED` —
     that is correct and expected, and the download-side check is the one that
     already refused a bad hash. Nothing about the desktop or Android flow may
     have changed.
137. **A rebuilt OTA launcher on a real Switch.** It must find v0.8.3 (or
     later), verify `Gen2Recomped-X.Y.Z-switch.zip` against `sha256sums.txt`,
     replace both NROs and come back on the new version. This is the item that
     has been blocked on a rebuild since the slug fix, and it is the whole
     Switch update story.
138. **Xbox, the banner.** Still `notify-only`, `Install the newer package to
     update`, **no button** — and the capability line must say `host=Windows
     … -> notify-only`, which is also the confirmation that
     `isPackagedContainer()` recognised the `LocalState` save path.
