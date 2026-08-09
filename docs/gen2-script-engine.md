# Gen2 script engine — ROM ground truth

Everything here was decoded from `Pokemon - Gold Version (USA, Europe)` with
`tools/rom_manifest_gold.json`; Silver shares the engine.  This file exists so
the numbers do not have to be re-derived every time the Gen2 event work is
picked back up.

## Ledge hops

`DoPlayerMovement.TryJump` (`04:41F3`):

```
ld a, [$D20B]     ; wPlayerTileCollision -- the tile the player STANDS ON
and $F0
cp $A0            ; ledge classes are $A0-$AF
ld a, e / and $07 ; low three bits index .ledge_table
ld hl, $421E      ; .ledge_table
add hl, de
ld a, [$CF2F]     ; wFacingDirection
and [hl]
jr z, .no
```

`.ledge_table` (`04:421E`, 8 bytes): `01 02 04 08 09 0A 05 06`, with
`bit 0 = down, 1 = up, 2 = left, 3 = right`:

| class | mask | hop |
| --- | --- | --- |
| `$A0` | `$01` | down |
| `$A1` | `$02` | up |
| `$A2` | `$04` | left |
| `$A3` | `$08` | right |
| `$A4` | `$09` | down + right |
| `$A5` | `$0A` | up + right |
| `$A6` | `$05` | down + left |
| `$A7` | `$06` | up + left |

`$A8`-`$AF` mirror `$A0`-`$A7`.

The critical difference from Gen1: **the hop is keyed off the tile the player
is standing on, not the tile in front.**  `CollisionPermissionTable`
(`3E:74BE`) gives every class in `$A0`-`$AF` permission `$00`, i.e. ordinary
walkable land, so the ledge lip is a tile you step onto first and hop off
second.  Gen1's `field.ledges` rows (standing tile + ledge tile in front) do
not describe this at all, which is why no Gen2 ledge was hoppable until
`field.ledgeHops` was added.

The hop itself is `STEP_LEDGE` and moves the player two cells.

Port: `RomExtractorGen2:gen2LedgeHops()` writes `field.ledgeHops`;
`OverworldState:gen2LedgeAllows` / `:checkLedgeHop` consume it.

## Map events block (`<Map>_MapEvents`)

```
db 0, 0                       ; filler
db warpCount;  warpCount  x 5 bytes  (y, x, warpId, mapGroup, mapNumber)
db coordCount; coordCount x 8 bytes  (scene, y, x, ?, dw script, dw 0)
db bgCount;    bgCount    x 5 bytes  (y, x, type, dw pointer)
db objCount;   objCount   x 13 bytes (see below)
```

The coord-event script pointer sits at **offset 5** of the row; offsets 4 and 6
both produce garbage.  `y`/`x` carry the usual `+4` border bias.

bg_event types seen in Gold: `0` (621), `1` (31), `3` (9), `4` (8), `5` (1),
`6` (4), `7` (87, hidden item).  All of them are 5 bytes — hidden items do
*not* widen the row.

object_event row:

```
[1] sprite  [2] y  [3] x  [4] movement  [5] radius  [6] hour  [7] timeOfDay
[8] palette << 4 | kind   [9] sightRange   [10..11] script   [12..13] eventFlag
```

`kind`: `0` script, `1` itemball (the "script" is `db item, qty`), `2` trainer.
A trainer's pointer is a 12 byte header — `dw event; db class; db id;
dw seenText; dw beatenText; dw winText; dw afterScript` — and the trainer's own
script starts at header + 12.

## Map scripts block (`<Map>_MapScripts`)

```
db sceneCount
sceneCount x (dw scriptAddr, dw 0000)
db callbackCount
callbackCount x (db type, dw scriptAddr)
```

`<Map>_MapAttributes` byte 6 is the script bank, bytes 7..8 point at
`<Map>_MapScripts`, bytes 9..10 at `<Map>_MapEvents`.

## Script command table

`ScriptCommandTable` (`25:6BE4`) has **162 entries, `$00`-`$A1`**.  The names
below come straight out of the ROM symbol table; the argument specs were
cross-checked by counting `GetScriptByte` calls in each handler and then
validated by disassembling every reachable map script (2680 scripts walked,
~96% decode cleanly end to end).

`tools/gen2_script_disasm.py` holds the machine-readable table (`CMDS`) and is
the validation harness: run it and it reports desyncs, the command that
preceded each one, and an instruction trail.  Arg spec letters:

* `b` one byte
* `w` two byte little-endian value
* `p` two byte script pointer in the current bank
* `f` three byte far pointer (`dba`: bank, then address)
* `m` three byte money value

Terminators (execution stops or transfers): `sjump`, `farsjump`, `memjump`,
`jumpstd`, `jumptext`, `jumptextfaceplayer`, `stopandsjump`, `endcallback`,
`end`, `reloadend`, `endall`, `halloffame`, `credits`.

## Object visibility

`CheckObjectFlag` (`09:44A5`): an object's event flag word being **set** means
the object is **hidden**; `$FFFF` means always visible.  `InitializeEventsScript`
(`40:4368`) runs 108 `setevent`s at new game, so 156 objects start hidden and
stay hidden until some later script issues the matching `clearevent` — which is
exactly what the script interpreter is for.
