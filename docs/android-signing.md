# Android signing

Android identifies an app by its package name **and its signing certificate**.
An update signed by a different certificate is not an update — it's a different
app claiming the same package name, and the installer refuses it with:

> App not installed. The package appears to be invalid.

which reads like a corrupt download and isn't.

## What was wrong

`mobile/android/app/build.gradle` declares no `signingConfigs`, and the build
runs `assembleEmbedNoRecordDebug`. Gradle therefore signs with the debug
keystore at `~/.android/debug.keystore`.

That file doesn't exist on a hosted CI runner, so **Gradle generates a new one
on every run**. Every release was signed by a different key. No release could
upgrade any other release, in either direction, and none of them could upgrade
a locally-built APK either.

Note what the problem is *not*: it isn't that the builds are debug builds. A
debug-signed APK upgrades another debug-signed APK perfectly well — as long as
it's the **same** debug key. The instability was the whole bug.

## The fix: one committed debug keystore

`mobile/android/debug.keystore` is checked into the repo, and CI copies it to
`~/.android/debug.keystore` before Gradle runs. Builds stay exactly as they
were locally: debug variant, no secrets to configure, sideload as before — the
signature just stops changing.

### Which keystore to commit — this decides whether users must uninstall

**Commit the debug keystore that signed the APK your users already have.**
If the installed base came from APKs you built on your own machine, that is
your existing `~/.android/debug.keystore` — and committing it means those
users upgrade in place, with no uninstall and no lost saves.

On Windows it lives at:

```
%USERPROFILE%\.android\debug.keystore
```

Check that it matches what people are running, before you rely on it:

```powershell
# the key in your keystore
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -storepass android | Select-String "SHA256:"

# the key that signed an APK you actually distributed
apksigner verify --print-certs Gen2Recomped-0.7.5-android.apk | Select-String "SHA-256"
```

Same digest → copy that file to `mobile/android/debug.keystore`, commit, and
nobody has to uninstall.

Different digest, or the file is gone → use the keystore shipped in this repo
(or generate one) and accept the one-time uninstall described below. There is
no way to migrate an installed app to a different signing key; Android has no
mechanism for it, by design.

**Releases built by CI before this fix cannot be rescued either way.** Each of
those got a fresh random key at build time and that key no longer exists
anywhere. Anyone who installed 0.7.6, 0.7.7 or 0.7.8 from GitHub has to
uninstall once regardless of which keystore you commit.

### What is in a debug keystore

Nothing secret. It uses the standard Android debug credentials, which are
public and identical in every Android SDK install:

| Field | Value |
| --- | --- |
| store password | `android` |
| key alias | `androiddebugkey` |
| key password | `android` |
| subject | `CN=Android Debug, O=Android, C=US` |

`.gitignore` blocks `*.jks` and `*.keystore` generally and negates this one
file, so a real release keystore still can't be committed by accident.

**The trade, stated plainly:** anyone can sign an APK with the standard debug
key, so anyone could build a package that installs *over* yours on a device
that already has it. That's true of every debug-signed app, and it's the same
exposure your local builds always had. It's a fine trade for sideloaded
distribution from GitHub Releases. It is not acceptable for the Play Store,
which rejects debug-signed uploads outright.

### If you outgrow it

Generate a real release key and stop using the debug one:

```bash
keytool -genkeypair -v \
  -keystore gen2recomped-release.jks \
  -alias gen2recomped \
  -keyalg RSA -keysize 4096 \
  -validity 10000 \
  -dname "CN=Gen2Recomped, O=UNDERdecoded"
```

Keep it out of the repo, store it as repo secrets, and sign with `apksigner`
after the build. Switching to it costs every user another uninstall, so it's
worth doing before the audience grows rather than after.

## What users have to do once

Only those whose installed APK was signed by a key you no longer have — see
the digest check above. In practice that is everyone who installed a CI-built
release (0.7.6 onward), and nobody who installed one of your local builds, if
you commit your own debug keystore.

For those who do need it: **uninstall the old app first**, one time. After
that, upgrades work normally.

**Warn them about saves.** The Android save directory is inside the app's
external-files folder (see `conf.lua`), and Android deletes that on uninstall
— saves, options and the imported ROM cache all go with it. Before
uninstalling, they should:

1. Open the launcher, pick the game's tab → **SAVE FILES → Export save**.
2. Copy the exported `.sav` off the device (USB, or a file manager).
3. Uninstall, install the new APK, re-import the ROM, then **Import save**.

Say this in the release notes for the first fixed release. It is a one-time
cost, and it is the last time it will be necessary.

## Checking an APK by hand

```bash
apksigner verify --print-certs Gen2Recomped-0.7.9-android.apk
```

Two APKs can upgrade each other if and only if their printed SHA-256 digests
match. The committed keystore's digest is stable, so every release from here
prints the same one.

The CI log prints the keystore's file hash (`debug keystore: <sha256>`) on
every run — if that line ever changes, the next release will not install over
the last.
