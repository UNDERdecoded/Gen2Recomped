# Native GSC Fly/Dig presentation

The shared controller previously replaced a first charge with Gen1's
`TELEPORT` or `SLIDE_DOWN_ANIM`. Its genuine GSC interpreter accepted
`env.flying`, but actual move admission never bound either native battler.
`SHOW_MON` and the two battler-row OBJ effects could therefore treat an absent
Fly/Dig target as present. A cleared picture box also had no persistent native
owner between moves.

## Result

GSC charge moves retain their own native ROM animation row with parameter 1;
the release uses parameter 0. Existing damage, accuracy, PP, charge flags,
charge-required hooks and random draws retain their native owners. Gen1/GBA
charge selection is unchanged.

`Gen2VanishPresentation` observes the actual native `invulnerable`/`hiddenAs`
state and the admitted row's genuine interpreter. The first takeoff/burrow
starts visible; only completion of that animation latches the cleared box.
Each new VM receives its own snapshot of both battlers through the native
`isUnderground(side, mon)` reader. A retained runner keeps its original flags.
The release holds an already-cleared box until its actual BG `SHOW_MON`
produces `picSize`, or until normal completion/fallback releases it.

Cancelled/missing/disabled animations, replacement, switch and faint retire
only their own picture relationship. Native picture-state readers and the existing native drawer share the same
visibility. Reads never step an interpreter, spend PP
or consume RNG. The latch has at most one record per active side and does not
allocate work per draw.

This upstream adaptation uses the existing native updateQueue owner. That
source tree has no semantic checkpoint service; none is invented here. The
fork has an additional checked integration with its existing checkpoint graph.

## Reference and verification

The timing follows the frozen Gen1Recomp reference
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, especially
`src/ui/gen2/BattleState.lua` (`isUnderground`, `startAnim`, `revealVanished`)
and its documented GSC `BattleCommand_Charge` / `CheckFlyDigStatus` behavior.
Existing Gen1Recomp/Cedric rights and interpreter provenance remain intact;
see `compat/gen1-gsc/` and `LICENSE-ROXAS2712.md`. Original contributions are
offered to Cedric / UNDERdecoded under the latter permission, including
visible credit; earlier grants and other authors' terms remain effective.

The ROM-free `gen2_vanish_presentation` suite drives the actual shared native
controller, queue, command VM and BG/object pools for Gold, Silver and Crystal,
legacy and original source-native schemas, both attacking sides, both charge
moves and an ordinary visible charge. It also covers missing/disabled data,
cancel/replacement/switch/faint/missed release, retained runners, PP/RNG reads
and non-GSC isolation. `gen2_vanish_checkpoint` drives the actual public
semantic capture/restore and the restored second turn.

A separate local actual-Crystal-ROM check runs both Fly/Dig halves through the
same controller with ROM-free test battlers. Actual ROM timings on both sides:
Fly charge 66 VM frames, Dig charge 179; release SHOW_MON at frame 34 and
completion at frame 67. A hidden-target Growl runs 170 VM frames with complete
command/object/OAM/BG state equal to the frozen reference receiving the same
flags. No ROM bytes, mod changes, saves or machine paths are committed.

These are engine CPU/ROM-data checks. They do not qualify unchanged VASC,
visible OS windows, GPU output, Windows, performance or a packaged release.
The upstream adaptation uses its existing native queue; its source tree has
no semantic checkpoint service, so that fork-only service is neither invented
nor claimed there.
