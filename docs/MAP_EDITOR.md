# Gen2Recomped Map Editor

Everything the map editor can do, and every control that does it.

The same text is in the editor: press **?** in the title bar. That panel and
this file are generated from one table
(`tools/map-editor/panels/Help.lua`), so they cannot disagree -- if you are
reading a key here, that is the key the code reads.

## Opening it

The map editor is a mode of the same shell the save editor runs in, so it
inherits that window's gamepad cursor, on-screen keyboard and DPI layout
rather than reimplementing them. Open it from the launcher; the title bar
reads **MAP EDITOR** and the badge reads **ME**.

Nothing in this editor writes to a ROM. Edits live in an edit store beside the
save, and an export is a separate content mod.

## Contents

* [MOVING AROUND THE MAP](#moving-around-the-map)
* [THE 3D VIEW](#the-3d-view)
* [WHAT THE MAP SHOWS](#what-the-map-shows)
* [THE TOOL DRAWER](#the-tool-drawer)
* [PAINTING TILES](#painting-tiles)
* [NPCs, TRAINERS AND TEXT](#npcs-trainers-and-text)
* [EVENTS AND FLAGS](#events-and-flags)
* [VOXELS AND HEIGHT](#voxels-and-height)
* [TYPING](#typing)
* [KEEPING AND UNDOING WORK](#keeping-and-undoing-work)
* [SHARING WHAT YOU MADE](#sharing-what-you-made)

## MOVING AROUND THE MAP

The map is always on screen -- the tools open in a drawer beside it rather than replacing it. Everything below works in the flat 2D view; the 3D view has its own section.

| control | what it does |
| --- | --- |
| `left-drag` | pan the map |
| `right-drag  /  middle-drag` | pan the map without touching the selection |
| `mouse wheel` | zoom in and out |
| `W A S D  or  arrow keys` | pan the map by one step |
| `click a cell` | select it -- every tool acts on the selection |
| `shift-click` | add that cell to the selection |
| `ctrl-click  (cmd-click)` | select every cell on the map like that one |
| `double-click a warp` | follow it to the map it leads to |
| `click the viewport` | drop the text cursor, so W A S D pan again instead of typing into the last box you used |
| `escape` | clear the selection and put down anything you are holding |

## THE 3D VIEW

The 3D button swaps the flat map for the voxel world the 3D mods draw. It is the same map and the same selection -- only the camera changes.

| control | what it does |
| --- | --- |
| `3D  /  2D` | swap between the voxel world and the flat map |
| `W A S D` | fly the camera along the ground |
| `Q  /  E` | fly down and up |
| `hold shift  /  hold alt` | fly fast  /  fly slowly, for placing the camera exactly |
| `left-drag` | orbit |
| `right-drag  /  middle-drag  /  shift-left-drag` | pan |
| `mouse wheel` | camera distance |
| `left  /  right arrow` | turn the camera |
| `up  /  down arrow` | raise and lower the camera angle |
| `F` | frame the selected cell |
| `home` | frame the whole map |
| `5` | switch between perspective and orthographic |
| `7  /  1  /  3  /  0` | top, front, side and user views |
| `G` | show or hide the grid |
| `F3  (or ctrl-D)` | show the diagnostics overlay |
| `PERSP / ORTHO, shading buttons` | the same two settings from the header |

## WHAT THE MAP SHOWS

The toggles under the map decide what is drawn over it. They change nothing in the map itself -- turning WARPS off does not remove a door, it stops drawing the marker.

| control | what it does |
| --- | --- |
| `WARPS` | show the doors, stairs and cave mouths |
| `NPCs` | show the people and items standing on the map |
| `EDITS` | show which cells you have changed |
| `GRID` | show the cell grid |
| `WORLD` | draw the neighbouring maps around this one, in place, so a seam can be judged against what is actually on the other side |
| `the region chips` | every region in the import. Johto and Kanto are separate regions because they touch only through indoor maps; Gen 1 has Kanto and its islands; a romhack has whatever it has. The view opens on the region holding your map |
| `the order they sit in` | the cartridge's own: regions run left to right by their first town-map landmark, so Johto is left of Kanto. Islands of one or two maps -- a map pack's two rooms, a pair you joined while trying something out -- go to the END, so they cannot stand between two real regions |
| `right-drag  /  middle-drag` | pan the world view |
| `clicking a map` | opens it |
| `a seam that drifts a block` | is normal. Gen 2's Kanto has loops that do not close -- Celadon to Route 14 the long way lands one block from the short way -- and the game never draws two branches at once, so it never has to agree with itself. Nothing to fix |
| `the gaps between regions` | are not geography. Inside a region every offset is the engine's own; between two regions the cartridge never places them in one space, so they are packed side by side to be looked at |
| `BACK TO MAP` | leave the world view |

## THE TOOL DRAWER

Seven tools, each opening in a drawer over one side of the map. Opening the tool that is already open closes it, and escape closes whichever is open.

| control | what it does |
| --- | --- |
| `WARPS` | doors, stairs and cave mouths; make new maps |
| `NPCs & ITEMS` | people, items, trainers and their teams |
| `SCRIPTS` | what an object does when you talk to it |
| `VOXELS` | per-cell height and shape for the 3D mods |
| `WILDS` | what lives in the grass, the water and on a hook |
| `TILES` | paint the ground itself, block by block |
| `WALKABLE` | where the player can and cannot go, and see it |

## PAINTING TILES

Open TILES and pick a block. While a block is picked the left button paints instead of selecting; the other two buttons still pan, so getting around never stops working mid-stroke.

| control | what it does |
| --- | --- |
| `click a cell` | lay the picked block there |
| `left-drag` | lay a stroke of blocks across every cell it crosses |
| `ctrl-click` | select every cell like that one, then paint the lot |
| `the big tile view` | the picked tile, drawn large in the drawer, so individual pixels can be aimed at |
| `wheel over the big tile` | zoom it, 2x to 160x, around the pointer |
| `right-drag  /  middle-drag over it` | pan the zoomed tile |
| `FIT` | put the zoom and the pan back |

## NPCs, TRAINERS AND TEXT

An NPC is a sprite, a place to stand, a way to face and something to say. A trainer is all of that plus a team and the distance at which they notice you.

| control | what it does |
| --- | --- |
| `NEW NPC` | drop a person beside the selected cell |
| `facing` | which way they stand, and which way they turn to face you -- the map and the 3D view redraw them facing that way as soon as you press it |
| `movement` | still, wandering, or a fixed path |
| `text` | what they say -- typed in the box, shown a page at a time in game, with A to advance |
| `sprite import` | a PNG of the right size and palette; the disclaimer beside the button says what will and will not load |
| `Pokemon sprites` | every species has an overworld sheet -- search the sprite list by name ("lugia", "suicune") and it is there, listed as the species with its SPRITE_MON_nnn id beside it |
| `WILD` | give the NPC a species and it becomes a wild encounter: talking to it says its TEXT, then opens the battle, and beating it removes it for good -- the same mechanism the cartridge stands Ho-Oh and Suicune on |
| `LEVEL` | what level that wild Pokemon is; it always has one |
| `TRAINER` | make them a trainer -- the party editor and the sight settings appear once they are one |
| `party editor` | up to six Pokemon, each with a level, four moves and its stats; cartridge trainers open with their real team in it |
| `sight range` | how many blocks ahead they spot the player and start the battle; the cartridge's own value is shown where there is one |

## EVENTS AND FLAGS

EVENTS in the title bar opens the map's events -- the ones you wrote and the ones the cartridge shipped, in one list.

| control | what it does |
| --- | --- |
| `the left-hand list` | every event on this map; cartridge events are selectable, viewable and editable, not just the new ones |
| `WHAT HAPPENS` | the beats the event plays, in order |
| `WHEN` | the flags that decide whether it runs, by name rather than by number |
| `TAKE OVER` | adopt a cartridge event so your edits replace it |
| `a flag's watchers` | everything on every map that reads that flag -- objects that hide, doors that open, trainers that stop appearing |

## VOXELS AND HEIGHT

Height is per cell, and can be cut finer than a cell. The grain chips decide how fine. The finest is a sculpting tool and is costly; most maps never need it.

| control | what it does |
| --- | --- |
| `16  /  8  /  4  /  2  /  1` | the grain, in pixels: a whole cell, a tile, then 4, 16 and 64 heights per tile |
| `click a square` | select it |
| `shift-click` | add it to the selection |
| `arrow keys` | pan the cell grid |
| `E` | swap between painting height and erasing it |
| `SHOW THE TILE BIG` | put the selected tile in the drawer, large, instead of the cell grid |
| `CELL GRID` | go back to the grid |
| `BUILDING / ROOF OVER n CELLS` | select a building's footprint and this raises its walls and lays a roof on the top row. The voxel path can only raise what the DRAWING says is there, and some buildings have no roof to read -- Route 23's league gate runs off the top of its own map -- so those come out flat-topped until an author says otherwise |
| `WALLS / ROOF + / ROWS` | the wall height, how far the roof sits above it, and how many rows of the selection are roof |
| `the voxel source button` | which installed mod's heights are being edited -- two mods can pin the same tile to different shapes |

## TYPING

Every text box in the editor is the same widget, so these work everywhere -- the dialogue box, the map filter, a map's name.

| control | what it does |
| --- | --- |
| `hold backspace` | keeps deleting rather than deleting one character |
| `click and drag` | select part of the text |
| `ctrl-A  /  ctrl-C  /  ctrl-X  /  ctrl-V` | select all, copy, cut, paste |
| `enter` | commit and leave the box |
| `escape` | leave the box without committing |
| `click the map` | leave the box, so the letter keys go back to panning |

## KEEPING AND UNDOING WORK

Edits live in an edit store beside the save, not in the cartridge. Nothing you do here writes to the ROM.

| control | what it does |
| --- | --- |
| `SAVE EDITS  (ctrl-S)` | write the edits; the button is lit only while there is something unsaved |
| `ctrl-Z` | undo |
| `ctrl-shift-Z` | redo |
| `RESET MAP` | put this map back as the cartridge has it -- press once to arm, again to confirm |
| `Close` | leave the editor; asks once if there are unsaved edits |
| `?` | open this help |

## SHARING WHAT YOU MADE

An export is a content mod, not a copy of the edit store. A map that borrows art from another cartridge says so, and the person installing it is told which games they need.

| control | what it does |
| --- | --- |
| `EXPORT` | write the edits out as an installable .zip map pack |
| `IMPORT` | install a map pack somebody else exported |
| `required games` | an export declares every cartridge its maps borrow from, and the import dialog says, per game, whether it is already imported or still has to be |
| `ASSETS` | the library of pieces you have cut out of maps, reusable on any map in the project |

## Where the edits go

* **Saving** writes the edit store. The game reads it on load and lays it over
  the cartridge's own maps, and it is laid over again after mods merge, so a
  map pack cannot quietly overwrite your own work.
* **Exporting** writes an installable `.zip`. Maps that borrow art from
  another cartridge are exported *by reference*, so the pack carries no ROM
  data -- which is why it declares the games it needs and why the import
  dialog checks for them.
* **Resetting** a map discards this map's edits only, and asks twice.

## If a control does nothing

Two causes account for most of it:

* **A text box still has focus.** The letter keys go to the box, not the map.
  Click the map, or press escape.
* **The build has no `tools/map-editor`.** The editor's panels are loaded
  through `pcall`, so a packaged build missing them loses the buttons rather
  than failing to start. `scripts/pack_love.sh` ships the directory; a
  hand-made payload may not.
