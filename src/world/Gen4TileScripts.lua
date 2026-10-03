-- WHAT A SINNOH TILE DOES WHEN YOU PRESS A AT IT.
--
-- `Field_TileBehaviorToScript` (pokeplatinum src/overlay005/field_control.c)
-- is a table, and it is the only thing that makes nine kinds of scenery
-- interactive: the PC, four bookshelves, the trash can, three mart shelves,
-- the town map on the wall, the bike-parking sign and the television.  None of
-- them is an object event and none of them is a bg event -- there is nothing
-- in the map data to find.  The behaviour byte under the tile IS the whole
-- record, and the script it names does the rest.
--
-- This port had no Gen 4 arm for any of it.  `OverworldState:tryPcTile` knows
-- about Gen 2's collision class $93 and Gen 3's PC metatile and stops there,
-- so every one of these tiles in Sinnoh answered a press with nothing.
--
-- MEASURED over the extracted cache: **3,527 tiles across 289 layouts**, the
-- PC alone on 66 maps.  Counted per layout and multiplied by the maps that use
-- it, because a Pokemon Centre's interior is one layout behind many headers.
--
--     BIKE_PARKING       2274 tiles across  85 maps
--     MART_SHELF_1        408 tiles across  43 maps
--     TV                  314 tiles across  76 maps
--     BOOKSHELF_1         228 tiles across  42 maps
--     PC                  130 tiles across  66 maps
--     TOWN_MAP             66 tiles across  32 maps
--     TRASH_CAN            45 tiles across  31 maps
--     SMALL_BOOKSHELF_1    44 tiles across  14 maps
--     BOOKSHELF_2          18 tiles across   3 maps
--
-- THE SAME FAULT GEN 3 ALREADY HAD AND ALREADY FIXED.  The note at this
-- port's Gen 3 PC branch says it plainly -- "what it opens is the CARTRIDGE'S
-- OWN SCRIPT, not this port's PC menu ... it left the boxes unreachable from
-- every Poke Centre in the region" -- and Gen 4 was still calling `openPC`,
-- which jumps straight to the storage grid and never asks the cartridge
-- anything.  Everything the PC script does on the way -- naming the box PC
-- after Bebe once you have met her, the player's own PC, the professor's dex
-- rating, the Hall of Fame row, COMPARE POKeMON, the boot-up animation and
-- its sound -- is in `CommonScript_PC`, and none of it ran.
local Gen4Behaviors = require("src.import.Gen4Behaviors")
local Logger = require("src.core.Logger")

local Gen4TileScripts = {}

-- THE CARTRIDGE'S TABLE, IN ITS ORDER, BY NAME.
--
-- Behaviour NAMES rather than numbers: `Gen4Behaviors.PACKED` is the
-- cartridge's own 256-entry name table and is already the one place that says
-- which byte is which, so a number written here would be a second spelling of
-- something that is already written down.
--
-- The band index is the cartridge's `SCRIPT_ID(BAND, n)` operand -- 0-based --
-- and `entries` in the cache is a Lua array, so the lookup adds one.  That
-- off-by-one is the whole reason `index` is stored raw and converted in one
-- place instead of being pre-adjusted here.
--
-- `facing` is the cartridge's own guard: the PC and the TV only answer a
-- player facing NORTH, because both are drawn on the wall behind the tile and
-- you cannot read a screen from the side.
Gen4TileScripts.TABLE = {
  { behaviour = "PC",                band = "common_scripts", index = 18, facing = "up" },
  { behaviour = "SMALL_BOOKSHELF_1", band = "bg_events",      index = 0 },
  { behaviour = "SMALL_BOOKSHELF_2", band = "bg_events",      index = 1 },
  { behaviour = "BOOKSHELF_1",       band = "bg_events",      index = 2 },
  { behaviour = "BOOKSHELF_2",       band = "bg_events",      index = 3 },
  { behaviour = "TRASH_CAN",         band = "bg_events",      index = 4 },
  { behaviour = "MART_SHELF_1",      band = "bg_events",      index = 5 },
  { behaviour = "MART_SHELF_2",      band = "bg_events",      index = 6 },
  { behaviour = "MART_SHELF_3",      band = "bg_events",      index = 7 },
  { behaviour = "WATERFALL",         band = "field_moves",    index = 6 },
  { behaviour = "TOWN_MAP",          band = "bg_events",      index = 8 },
  { behaviour = "BIKE_PARKING",      band = "common_scripts", index = 30 },
  { behaviour = "TV",                band = "tv_broadcast",   index = 0, facing = "up" },
}

-- ROCK CLIMB AND SURF ARE DELIBERATELY NOT HERE, and that is a scope line
-- rather than an omission.  The two rows below the table in the C are not
-- equality tests on a behaviour byte:
--
--     if (PlayerAvatar_CanUseRockClimb(behavior, playerDir))      -> FIELD_MOVES 3
--     if (!surfing && CanUseSurf(...) && HasBadge(3)
--         && Party_HasMonWithMove(SURF))                          -> FIELD_MOVES 4
--
-- Each is a derivation of its own -- a direction rule, a badge, a party scan --
-- and this port reaches Gen 4's field moves through the party menu
-- (`Gen4FieldMoves.partyMember`) rather than through the overworld press.
-- Adding half a rule here would give Sinnoh two ways into Surf that can
-- disagree, which is the shape of fault this port keeps finding.  Waterfall IS
-- here because `TileBehavior_IsWaterfall` is a plain equality with no guard at
-- all, and nothing in this port answers a press at one today.

-- behaviour value -> row, built once from the names.
local byValue
local function index()
  if byValue then return byValue end
  byValue = {}
  for _, row in ipairs(Gen4TileScripts.TABLE) do
    local values = Gen4Behaviors.matching("^" .. row.behaviour .. "$")
    local v = values and values[1]
    if v then
      byValue[v] = row
    else
      -- A name that is not in the cartridge's table is a typo here, not a
      -- cartridge change, and it would otherwise be a row that silently never
      -- matches anything.
      Logger.warn("gen4 tile scripts: no behaviour named %q", tostring(row.behaviour))
    end
  end
  return byValue
end

Gen4TileScripts.byValue = index

-- The row for a behaviour byte, or nil.  `facing` is the player's, in this
-- engine's words ("up" is DIR_NORTH).
function Gen4TileScripts.rowFor(behaviour, facing)
  local row = index()[behaviour]
  if not row then return nil end
  if row.facing and row.facing ~= facing then return nil end
  return row
end

-- ONE SPELLING OF "RUN COMMON SCRIPT N", because there are now fourteen
-- callers of it and there used to be one, written inline at the honey tree.
--
-- `pool.bands[band].entries` is the band's label list in the cartridge's own
-- order, so entry n+1 is `SCRIPT_ID(band, n)`.  Returns the compiled rows, or
-- nil with the reason logged once -- a cache imported before a band existed
-- has no entries for it, and that is a stale cache rather than a fault here.
function Gen4TileScripts.compile(data, band, cartridgeIndex)
  local VM = require("src.script.Gen4ScriptVM")
  local pool = VM.store(data)
  local entry = pool and pool.bands and pool.bands[band]
  local label = entry and entry.entries and entry.entries[cartridgeIndex + 1]
  if not label then return nil, ("no %s entry %d in this cache"):format(
    tostring(band), cartridgeIndex) end
  local rows = VM.compile(data, label)
  if not rows then return nil, ("%s did not compile"):format(tostring(label)) end
  return rows, label
end

return Gen4TileScripts
