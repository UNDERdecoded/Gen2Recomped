# Sideload the iOS build with AltStore

Every GitHub Release ships an IPA (`gen1recomp-*-ios.ipa`). Install it on
your iPhone or iPad with [AltStore Classic](https://altstore.io/) — AltStore
re-signs the app with **your** free Apple ID so you do not need a Mac or
Xcode.

## 1. Install AltStore

Follow the official guide for your computer:

- [How to Install (Windows)](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [How to Install (macOS)](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos)

You will install **AltServer** on the computer, then use it to put AltStore
on the phone. What AltServer is and why it needs to stay running:

- [AltServer](https://faq.altstore.io/altstore-classic/altserver)

Stuck? Start here:

- [Troubleshooting Guide](https://faq.altstore.io/altstore-classic/troubleshooting-guide)

## 2. Install the game

1. Download `gen1recomp-*-ios.ipa` from
   [Releases](https://github.com/bryanthaboi/gen1recomp/releases).
2. Open **AltStore** on the phone (AltServer must be running on the same
   Wi‑Fi, or keep the phone plugged into the computer).
3. Tap **My Apps → +** (or share the IPA into AltStore) and pick the file.
4. Sign in with your Apple ID when prompted. Wait for the install to finish.
5. On first launch: Settings → **Privacy & Security → Developer Mode** (iOS
   16+), and Settings → **General → VPN & Device Management** → Trust your
   Apple ID if asked.

Then open the app, import your own legal `.gb` ROM on the Red/Blue tab, and
play.

## Refresh / 7-day limit

With a free Apple ID, sideloaded apps stop launching after **7 days**. Keep
AltServer running so AltStore can refresh them, or open AltStore and refresh
manually before they expire. Saves on the phone are kept across refreshes.

## Prefer building it yourself?

Building from source on a Mac (no AltStore) is covered in
[ios-install.md](ios-install.md).
