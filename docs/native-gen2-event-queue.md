# Native Gen2 typed event admission

This change adapts the real upstream shared controller, on top of the native
model boundary, rather than substituting a fork battle controller.
`push`, `pushAll`, `pushFront` and the actual `advanceQueue` boundary share the
existing queue. Supported kinds are message, item, weather, stage, run, money,
win-text, move, damage, heal, status and text-pause. Unsupported kinds are
explicit errors, rather than silently discarded combat events.

Native producers emit observable messages/move announcements. Typing, VM,
HP/status snapshots and sound completion remain owned by native presentation;
HP/status snapshots never rewrite combat HP/status or spend PP. A queue
observer runs at actual admission and sees the settled decision phase when an
empty Gen2 queue returns. Gen2 resolving/moves spellings and older stored
messages/moveSelect spellings reach the same update/draw/link owners.

The move entry points run this upstream version's actual Gen2AnimPlayer. Its
parameter is installed in that VM's vars; its clock remains native. This
change does not fabricate the newer runner/OAM observation API around that
older VM, and does not claim the fork's later object renderer/animation parity.

Still outside this incremental change: send/faint/identity/Transform/experience,
learning/catch/trainer/picker event consumers, the pure model constructor/turn
protocol, checkpoint integration absent from this upstream base, unchanged
client acceptance and Windows/macOS GPU/package qualification.

Native queue and HP stepping retain the Gen1Recomp/upstream provenance noted
in their source files. Original native-owner integration contributions are
by Roxas2712; see the offered contribution licence:
https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md
Existing third-party rights and notices remain effective.
