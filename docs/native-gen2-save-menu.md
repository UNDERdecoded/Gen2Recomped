# Native Gen2 START and save dialogue

Gen2 START has its own native `Gen2StartMenu` class. Its public
`src.ui.gen2.StartMenu` spelling identifies the actual field-menu owner.
It uses the cartridge row IDs, scrolling list, descriptions and quit prompts,
retains the same START instance below native submenus, and remembers the
cursor in the save. Gen1 keeps its existing generic menu path. The START
controller and reusable typewriter are adapted from the read-only reference
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`; existing rights remain applicable.

START opens `Gen2SaveMenu`, an actual state over the native text
printer and save pipeline. The public `src.ui.gen2.SaveMenu` spelling names
this same owner. Screen registry overrides retain authority over the native
`Gen2SaveMenu` entry.

An existing active save slot requires a second overwrite answer. B/NO cannot
write. The timed saving message uses MID text cadence without held-button
acceleration; the write follows sixteen post-text logic frames. The saved
message follows another thirty-two frames and retains a thirty-frame tail,
waiting for its returned save sound with a bounded host failure escape.
Completion and writing are each guarded against duplicate calls.

The default operation calls `Game:writeSave`, retaining save-write vetoes,
live overworld capture, metadata capture, mod notifications and the
existing safe serializer. Explicit alternate snapshots use `SaveData.save`;
an injected writer receives the selected snapshot. Failed or throwing writes
cannot produce a successful completion message. Slot detection uses the
same active-slot lookup as native saving; an indeterminate lookup asks for
overwrite confirmation. The panel counts native badge and owned-Dex records.

ROM-free integration tests exercise Gold/Silver/Crystal through actual stack,
text printer, START input, screen resolution and the native Game writer,
including refusal, overwrite, fixed timing, duplicate suppression, writer
failure and a real save-hook veto. Gen1 retains its existing dialogue path.
This upstream branch has ROM-free coverage only. Real-cartridge save/reload,
unchanged-mod menu presentation, exact reference raster/typewriter helper
coverage and full story/save/link parity remain unverified. Supplying native
START does not assert that other PC/menu owner contracts are complete.
This state does not change save-format or link-protocol numbers.

Original contributions by Roxas2712; existing upstream and third-party rights
and credits remain applicable. See NOTICE.md and LICENSE-ROXAS2712.md.
