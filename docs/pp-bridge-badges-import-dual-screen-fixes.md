# PP, elevations, badges, importing and dual screens

Summary PP denominators now include each move slot's PP-Up count in the
Gen1/2, Emerald and FireRed layouts. The shared maximum matches the existing
battle formula: base + floor(base / 5) × upgrades, capped at three upgrades.
Healing uses that same maximum. Double-battle command prompts read the current
chooser through menuBattler instead of always naming the first player battler.

Gen3 trainer sight requires matching object elevations before checking the
line of sight. Zero remains the ROM wildcard. A trainer on the cycling-road
deck cannot spot a surfing player underneath even when intervening bridge
cells allow both elevations. Surf initiation requires shore elevation 3;
both the party-menu check and direct field route reject upper decks/cliffs.

Platinum badges are canonical flags plus the native badges record, not bag
items. Save validation migrates legacy inventory badges without quarantining
them. Reads also accept the native badges record, recovering visibility for
existing saves whose bag copy was removed. Serialization/validation and native
givebadge/checkbadge checks cover the eight Sinnoh badges.

Android picker copies run off the activity thread into a .part file. The
recognized filename is published only after a complete close. A completion
flag wakes Lua and clears that basename's previous failed-import skip. Opening
a fresh picker clears only its bridge-owned inbox destination, preventing a
previous pick from being consumed while the new one is being copied. Descriptor
streams retain their ParcelFileDescriptor through AutoCloseInputStream.

Java tests compile the production copying/publication methods and exercise
16 MiB files in default/custom directories, visibility during an unfinished
copy, provider failure and retry. Lua tests exercise completion acknowledgements.
These address concrete import races and UI-thread copying; the reported Razr
Android 16 crash has no supplied log and has not been reproduced on hardware.

Gen4 Options → 2ND SCREEN now offers TOP/BOTTOM and SIDE BY SIDE inside one
window, alongside the existing swap, corner, physical-device and off modes.
The main renderer uses its own half-window viewport at the actual display DPI.
The bottom surface is rendered independently, fitted without stretching, and
mouse/touch coordinates map to native DS pixels. Controls are drawn after both
screens. Changing back to an existing mode restores the full main viewport.

Checks: pp_bridge_badges_check.lua, android_picker_publication_check.py,
android_picker_retry_check.lua, gen4_dual_window_check.lua, and the existing
item/save/display/mobile suites. Local LOVE previews verified both layouts
with extracted Platinum watch art. Physical Android verification is pending.
No ROM reimport is required by these fixes.

Follow-up: the Razr tester reports the same old-build failure for Gen2, Gen3
and Gen4; another user reports Android 13 working. These observations point
to a shared device/platform path, but do not establish the native crash cause.

Imports now persist their source, selected data folder and last stage in
`rom-import.pending` beside settings. Verification records reading and hashing;
the Gen3 constants stage also records the image/table operation before it
runs. A new launcher session displays the interrupted stage and waits for an
explicit Import retry. A stale picker-completion flag cannot bypass this
recovery state. Handled failures retain the same recovery state; successful
cache completion clears it. Folder selection and save/mod picker handling
remain available while an import is interrupted.

The background worker checks that the selected cache folder can be written
and read before clearing an existing cache. Custom-folder writes now check
both write and close results, including delayed disk-full/flush failures.
A worker that exits without a result reports an error instead of leaving the
launcher waiting forever. Completion messages arriving during the running-state
check are drained before reporting a stopped worker.

Validation: `tools/android_import_recovery_check.lua` passes 32 checks covering
durable recovery, fresh-launcher behavior, manual retry, stale picker flags,
thread completion races, write/close failures and preflight-before-cleanup.
The Java picker publication checks and existing picker retry checks also pass.
Native desktop LOVE workers passed eight selected-stage imports: Emerald and
FireRed constants, Gold moves, and Platinum constants, each through default
and custom folders with the resulting Lua tables parsed successfully. These
are stage probes, not full imports or physical Android 16 verification. The
reported constants-stage crash was not reproduced locally. Test the updated
APK on the affected device before claiming that its native crash is resolved.
