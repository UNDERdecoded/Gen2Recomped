# Packaging: iOS, MSIX ("UWP") and AppImage

Three targets people ask about most, and where each already stood.

| Target | Script | Runs on | Status |
| --- | --- | --- | --- |
| iOS (.app / .ipa) | `scripts/build_ios.sh` | macOS only | already shipped |
| AppImage (x86_64) | `scripts/build.sh linux` | macOS **or Linux** | already shipped; now builds on Linux too |
| MSIX / "UWP" | `scripts/build_msix.ps1` | Windows | new |

`scripts/build.sh` is the front door for mac / win / linux / android / ios;
`build_msix.ps1` stands alone because it is the only Windows-native step.

---

## iOS

This has been in the repo for a while — `scripts/build_ios.sh` is ~700 lines
and the release workflow already builds it, so there is nothing to add.

```sh
scripts/build.sh ios              # debug .app
scripts/build.sh ios --release    # release config
scripts/build.sh ios --release --ipa
```

Output lands in `dist/ios/<Config>-<sdk>/`, with the full Xcode tree under
`mobile/ios/build/Build/Products/`.

**macOS + Xcode only.** There is no cross-compile: Apple's toolchain does not
run anywhere else, and no CI runner outside macOS can produce an `.ipa`.

Installing without the App Store is covered in `docs/ios-install.md` and
`docs/ios-sideload.md` (AltStore / SideStore / Feather). The unsigned `.ipa`
is what those sideloaders re-sign with your own free developer certificate.

---

## AppImage

```sh
scripts/build.sh linux
```

Produces both:

- `dist/linux/gen2recomp-x86_64.AppImage` — the double-clickable file
- `dist/linux/gen2recomp-linux.zip` — same binary, zipped (the release
  pipeline names this one)

### What the build actually does

An AppImage is not fusable the way `love.exe` is. `cat love.exe game.love >
game.exe` works because Windows LÖVE reads the archive appended to its own
`.exe`; an AppImage is a small runtime ELF with a **squashfs appended**, and at
launch the runtime mounts that squashfs and runs `bin/love` from inside it.
Bytes appended to the outer file are never read — you would ship vanilla LÖVE's
"no game" screen.

So the build unpacks the squashfs, drops `game.love` in, uncomments the
`FUSE_PATH` hook in `AppRun` (LÖVE's official AppImage ships it commented out
for exactly this), repacks with matching compression (gzip, 128K blocks — the
bundled runtime cannot read anything else) and glues runtime + squashfs back
together.

### Requirements

`squashfs-tools`, for `unsquashfs` and `mksquashfs`:

```sh
brew install squashfs                 # macOS
sudo apt install squashfs-tools       # Debian / Ubuntu / WSL
sudo dnf install squashfs-tools       # Fedora
sudo pacman -S squashfs-tools         # Arch
```

This step used to be macOS-only: it patched `AppRun` with `sed -i ''`, and
that empty backup suffix is mandatory on BSD sed but is swallowed as the
*script argument* by GNU sed. It now writes the patched file out and moves it
back, so Linux and WSL work.

x86_64 only. An arm64 AppImage would need an arm64 LÖVE AppImage upstream to
unpack, and LÖVE 11.5 does not publish one.

---

## MSIX ("UWP")

### What this is, and what it is not

There is no real UWP target here. LÖVE has no UWP backend — the only community
fork of one is years behind upstream and does not build against 11.5 — so
"make it a UWP app" is not a switch anyone can flip.

MSIX with the Desktop Bridge gets you everything people actually want from
UWP, though: a signed, versioned, single-file installer; clean
install/uninstall through Windows' package manager; per-user install with no
admin prompt; a proper Start menu entry and tile; and eligibility for the
Microsoft Store. The app inside stays the ordinary win64 build, declared
`runFullTrust` — which it must be, because ROM import and save slots need real
filesystem access that a sandboxed UWP app would not have.

### Build it

```powershell
# from the repo root, in PowerShell
scripts\build_msix.ps1 -MakeCert
```

Output: `dist\msix\Gen2Recomped-<version>.msix`, plus a `.cer` next to it when
`-MakeCert` is used.

It repackages an existing Windows build — no LÖVE rebuild. By default it picks
the newest `*windowsEXE*` folder in the repo (the one you already have) or
whatever is under `dist\win\`. Point it somewhere specific with `-Source`.

### Requirements

`MakeAppx.exe` and `SignTool.exe` from the Windows SDK. The script finds them
under `Windows Kits\10\bin` on its own; if they are missing:

```powershell
winget install --id Microsoft.WindowsSDK.10.0.22621
```

The "Windows SDK Signing Tools for Desktop Apps" component alone is enough —
you do not need the whole SDK or Visual Studio.

### Installing your own package

```powershell
# once, elevated: trust the self-signed cert
Import-Certificate -FilePath dist\msix\Gen2Recomped-0.7.0.0.cer `
  -CertStoreLocation Cert:\LocalMachine\TrustedPeople

# then, normal shell
Add-AppxPackage dist\msix\Gen2Recomped-0.7.0.0.msix
```

Uninstall from Settings → Apps like any other, or
`Remove-AppxPackage TheBoisClub.Gen2Recomped_...`.

### Two things that will bite you

**The Publisher string must match the certificate Subject exactly.** Character
for character, including spaces. Mismatch gives `0x800B0100` — "no signature
was present in the subject" — which does not sound like a name mismatch at all.
`-MakeCert` keeps them in step for you; a real cert means passing `-Publisher`
to match what your CA issued.

**The version must be four numeric parts, and the fourth must be 0 for the
Store.** `0.7.0b` is not a valid MSIX version. The script strips non-numerics
and pads, and tells you what it settled on — but set `-Version` yourself if you
care which number lands where.

### For the Microsoft Store

Do **not** use `-MakeCert`. Reserve the name in Partner Center first, then take
the three identity values from your app's identity page verbatim:

```powershell
scripts\build_msix.ps1 `
  -PackageName "12345YourPublisher.Gen2Recomped" `
  -Publisher "CN=ABCD1234-..." `
  -PublisherDisplayName "Your Publisher Name"
```

Store submissions are signed by Microsoft, so upload the package unsigned.

Worth knowing before you spend the effort: the Store's certification policy
covers what the *package* does, and this one ships no ROM and no copyrighted
game data — it imports from a cartridge dump the player supplies. That is the
same posture as any emulator front-end, and Microsoft's stance on those has
moved around. Sideloading the MSIX has none of that friction.

---

## Not covered

- **arm64 Windows / Linux** — upstream LÖVE 11.5 publishes no arm64 binaries
  to fuse. Building LÖVE itself for arm64 is the prerequisite, not a packaging
  change.
- **Flatpak / Snap** — neither exists here. Flatpak would be the closer fit for
  a Linux store listing; AppImage covers "one file, runs anywhere" already.
- **macOS App Store** — the `.app` is Developer ID signed and notarized for
  distribution outside the Store (see `scripts/build.sh mac`), which is a
  different entitlement set from a Store build.
