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

-- ...AND NOW THE TWO ROWS BELOW THE TABLE, after all.  The party menu was the
-- only door into Surf and Rock Climb, and an HM sweep found both dead from the
-- overworld: pressing A at the sea or at a rocky wall did nothing at all.
-- They are the C's own tests (`Field_TileBehaviorToScript`, field_control.c),
-- reached only when no table row matched:
--
--     PlayerAvatar_CanUseRockClimb(behavior, dir)        -> FIELD_MOVES 3
--         (ROCK_CLIMB_N_S facing north/south, _E_W facing west/east; the
--          script asks for the move and the Icicle Badge itself)
--     !surfing && CanUseSurf(next) && HasBadge(3)
--         && Party_HasMonWithMove(SURF)                  -> FIELD_MOVES 4
--
-- One door each still: the menu runs entries 11 and 12, the press 3 and 4,
-- and every one of them ends in the same `UseRockClimb` / `UseSurf`.
-- Platinum's numbering; HeartGold's field-move band is its own.
Gen4TileScripts.ROCK_CLIMB_N_S, Gen4TileScripts.ROCK_CLIMB_E_W = 0x4B, 0x4C

function Gen4TileScripts.fieldMoveRow(ow, behaviour, facing)
  local Game = package.loaded["src.core.Game"]
  local data, save = Game and Game.data, Game and Game.save
  if not (data and save) then return nil end
  if data.gen4_version and data.gen4_version.family == "hgss" then
    return Gen4TileScripts.hgssFieldMoveRow(ow, behaviour, facing, data, save)
  end
  local ns = (facing == "up" or facing == "down") and behaviour == Gen4TileScripts.ROCK_CLIMB_N_S
  local ew = (facing == "left" or facing == "right") and behaviour == Gen4TileScripts.ROCK_CLIMB_E_W
  if ns or ew then
    return { behaviour = "ROCK_CLIMB", band = "field_moves", index = 3 }
  end
  local Map = require("src.world.Map")
  local p = ow and ow.player
  if p and not p.surfing and Map.G4_SURFABLE[behaviour] then
    local F = require("src.world.Gen4FieldMoves")
    if F.partyMember(data, save, "SURF") then
      return { behaviour = "WATER", band = "field_moves", index = 4 }
    end
  end
  return nil
end

-- HEARTGOLD / SOULSILVER'S OWN ROWS (field_control.c GetInteractedMetatileScript,
-- after the table): std_field_* is SCRIPT 10000 + n in the `field_move` band.
--
--     TILE_BEHAVIOR_HEADBUTT (6)                         -> 14
--     rock climb in the facing direction (0x4B / 0x4C)   -> 3
--     not surfing: surfable ahead, the Fog Badge, a Surf user -> 4
--     surfing: TILE_BEHAVIOR_WATERFALL (0x13)            -> 5
--              TILE_BEHAVIOR_WHIRLPOOL (0x11)            -> 16
--
-- (The Waterfall and Whirlpool tests sit in the `else` of "not surfing", so
-- they only answer a surfer -- the C's order, kept.)
Gen4TileScripts.HGSS = { HEADBUTT = 0x06, WATERFALL = 0x13, WHIRLPOOL = 0x11, FOG_BADGE = 3 }

function Gen4TileScripts.hgssFieldMoveRow(ow, behaviour, facing, data, save)
  local H = Gen4TileScripts.HGSS
  local function row(name, n) return { behaviour = name, band = "field_move", index = n } end
  if behaviour == H.HEADBUTT then return row("HEADBUTT", 14) end
  local ns = (facing == "up" or facing == "down") and behaviour == Gen4TileScripts.ROCK_CLIMB_N_S
  local ew = (facing == "left" or facing == "right") and behaviour == Gen4TileScripts.ROCK_CLIMB_E_W
  if ns or ew then return row("ROCK_CLIMB", 3) end
  local p = ow and ow.player
  if p and not p.surfing then
    local Map = require("src.world.Map")
    if Map.G4_SURFABLE[behaviour] then
      local Badges = require("src.inventory.Badges")
      local entry = (Badges.list(data) or {})[H.FOG_BADGE + 1]
      local F = require("src.world.Gen4FieldMoves")
      if entry and Badges.has(save, entry) and F.partyMember(data, save, "SURF") then
        return row("WATER", 4)
      end
    end
    return Gen4TileScripts.hgssSafariRow(ow, behaviour) or Gen4TileScripts.hgssTreeRow(ow)
  end
  if behaviour == H.WATERFALL then return row("WATERFALL", 5) end
  if behaviour == H.WHIRLPOOL then return row("WHIRLPOOL", 16) end
  return Gen4TileScripts.hgssSafariRow(ow, behaviour) or Gen4TileScripts.hgssTreeRow(ow)
end

-- ...then the Safari Zone's place / remove rows (std_safari_place_object
-- 8800 / std_safari_remove_object 8801; src/world/HgssSafariPlace.lua)
function Gen4TileScripts.hgssSafariRow(ow, behaviour)
  local okS, r = pcall(function() return require("src.world.HgssSafariPlace").fieldRow(ow, behaviour) end)
  if okS then return r end
  return nil
end

-- ...and after every metatile script, the forest itself: a facing tile in a
-- land-0xD0 matrix cell (GetInteractedHeadbuttTreeScript ->
-- FieldSystem_FacingModelIsHeadbuttTree; src/world/HgssHeadbuttTrees.lua)
function Gen4TileScripts.hgssTreeRow(ow)
  local okT, isTree = pcall(function() return require("src.world.HgssHeadbuttTrees").facingTree(ow) end)
  if okT and isTree then return { behaviour = "HEADBUTT_TREE", band = "field_move", index = 14 } end
  return nil
end

-- BLACK / WHITE'S TABLE (Black ov21 0x021D3CE8, overlay offset 0x4BDE8:
-- thirteen `{ IsBehavior_X, u16 flags, u16 script }` rows the field walks
-- when A is pressed at a tile). Black / White's bytes are not Platinum's --
-- the Pokemon Center's PC is 0xD6 -- so the named table above never matched
-- and every Unova PC, bookshelf and shelf answered nothing ("the Pokemon
-- Center is missing the PC storage system"). The script ids are shared
-- scripts: 10090 is the PC (band bw_10090, member 868), 2500.. the
-- furniture; 0xFFFF is "nothing".
Gen4TileScripts.BW = {
  [0xD6] = 10090, [0xD8] = 10520, [0xD9] = 2500, [0xDA] = 2501, [0xDB] = 2502,
  [0xDC] = 2503, [0xDD] = 2504, [0xDE] = 2504, [0xDF] = 2505, [0xE0] = 2506,
  [0xE1] = 2507, [0xE2] = 10400,
}

-- a shared script id -> its band and 0-based entry: the band whose first id
-- (its key, `bw_<first>`) is the nearest at or below it
function Gen4TileScripts.bwBand(data, id)
  local VM = require("src.script.Gen4ScriptVM")
  local pool = VM.store(data)
  local best, bestFirst
  for key, band in pairs(pool and pool.bands or {}) do
    local first = tonumber(tostring(key):match("^bw_(%d+)$"))
    if first and first <= id and (not bestFirst or first > bestFirst)
       and band.entries and id - first < #band.entries then
      best, bestFirst = key, first
    end
  end
  if best then return best, id - bestFirst end
  return nil
end

-- The row for a behaviour byte, or nil.  `facing` is the player's, in this
-- engine's words ("up" is DIR_NORTH).
function Gen4TileScripts.rowFor(behaviour, facing)
  local info = require("src.core.GameVersion").info()
  if info and info.family == "bw" then
    local id = Gen4TileScripts.BW[behaviour]
    if not id then return nil end
    local Game = package.loaded["src.core.Game"]
    local band, n = Gen4TileScripts.bwBand(Game and Game.data, id)
    if not band then return nil end
    return { behaviour = ("BW_%02X"):format(behaviour), band = band, index = n }
  end
  local row = index()[behaviour]
  if not row then return nil end
  if row.facing and row.facing ~= facing then return nil end
  if require("src.core.GameVersion").info().family == "hgss" then
    -- pokeheartgold constants/std_script.h: HGSS reorganized these bands.
    local band, n = row.band, row.index
    -- Waterfall is one of HGSS's own field-move rows (hgssFieldMoveRow: band
    -- `field_move` 5, and only while surfing)
    if row.behaviour == "WATERFALL" then return nil end
    if row.behaviour == "PC" then n = 10
    elseif row.behaviour == "BIKE_PARKING" then n = 20
    elseif band == "bg_events" then band = "bookshelves"
    elseif row.behaviour == "TV" then band = "tv" end
    return { behaviour = row.behaviour, band = band, index = n, facing = row.facing }
  end
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
