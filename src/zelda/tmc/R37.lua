-- Round 37: one entry of R27B.MODULES for this round's modules (the R26 /
-- R27B interface: spawnEnemy / handles / update / spawnObject /
-- spawnManager / roomInit / frame / draw / playerFrame), the BG hook that
-- Priority.compose calls once per priority, and the room tile types for a
-- room without a tileset.
--
--   PathBg37    VERTICAL_ / HORIZONTAL_MINISH_PATH_BACKGROUND_MANAGER $02 /
--               $08, MINISH_RAFTERS_BACKGROUND_MANAGER $09 (the parallax BGs)
--   Rain37      RAINFALL_MANAGER $1C + the WATER_DROP enemy $19 and its
--               WATER_DROP_OBJECT shadow
--   Objects37   GIANT_BOOK_LADDER, HOUSE_DOOR_INT, LILYPAD_SMALL, PINWHEEL,
--               HOUSE_SIGN / HYRULE_TOWN_TILESET / MINISH_VILLAGE managers
--   Armos37     ARMOS_INTERIOR_MANAGER $27 + FLAME $2A type 4
--
-- CARTRIDGE BEHAVIOUR (room tile types): LoadRoomGfx loads the area's
-- gAreaTiles (metatiles + the two tile-type lists) apart from the room's
-- tileset (graphics + palettes); the collision / act tiles come from the
-- tile types.  Room $47:02 (an unused test room, the pressure plate's only
-- room) names tileset 1 of AREA_47's one-entry gAreaTileSets_45: the
-- cartridge reads the next word ($8008D160, not a valid address) as the
-- tileset, so its picture is undefined, but its types (and its clone
-- tiles) are the area's.  The port drew nothing and had no collision; now
-- the types are read as the cartridge does (the picture stays black).
local R = {}

R.MODULES = {
  "src.zelda.tmc.PathBg37",
  "src.zelda.tmc.Rain37",
  "src.zelda.tmc.Objects37",
  "src.zelda.tmc.Armos37",
  "src.zelda.tmc.Objects38", -- round 38: TREE_HIDING_PORTAL $9C
  "src.zelda.tmc.Objects39", -- round 39: MISC_MANAGER types 7 / $A / $D, darkness tile entities
  "src.zelda.tmc.Natives40", -- round 40: the last six script natives (Castor statue, town Minish, NPC4E)
  "src.zelda.tmc.Story54", -- round 54: Lake Hylia's Flippers-quest Minish (forestMinish.c sub_08060270 / sub_080601D4)
  "src.zelda.tmc.Entrance55", -- round 55: MINISH_SIZED_ENTRANCE_MANAGER $21 (Hyrule Town's Minish holes)
  "src.zelda.tmc.Story55", -- round 55: HUGE_BOOK $88 (Dr. Left's rafters, macroBook.c), townMinish sub_0806AF70 / AF78
  "src.zelda.tmc.Mask58", -- round 58: MASK $5C (mask.c) + the Mayor's room code (his masks)
  "src.zelda.tmc.Story58", -- round 58: MayorHagen_MakeInteractable (his interact box across the desk)
  "src.zelda.tmc.Trapdoor61", -- round 61: TRAPDOOR $86 (Librari's trap door, trapdoor.c)
  "src.zelda.tmc.Board61", -- round 61: BOARD $80 (board.c: Init's tile; supports from Dungeon:checkFall)
  "src.zelda.tmc.PortalToD62", -- round 62: the Temple of Droplets' portal (PT_TOD: PortalEnterUpdate -> gUnk_0813AB58)
}

R.ROM_RANGES = {}

local loaded
local function mods()
  if loaded then return loaded end
  loaded = {}
  for _, name in ipairs(R.MODULES) do
    local ok, m = pcall(require, name)
    if ok then
      if type(m) == "table" then
        loaded[#loaded + 1] = m
        for k, v in pairs(m.ROM_RANGES or {}) do R.ROM_RANGES[k] = v end
      end
    elseif not tostring(m):find("module '" .. name .. "' not found", 1, true) then
      error(m, 0)
    end
  end
  return loaded
end
R.mods = mods

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

-- the area's tile types (gAreaTiles: bottom types at +$8000, top at +$9000)
function R.areaTypes(assets, area)
  assets._types37 = assets._types37 or {}
  local c = assets._types37[area]
  if c then return c end
  local info = assets:area(area)
  local tiles = info and info.tiles and assets.store:read(info.tiles)
  if not tiles then return nil end
  c = {}
  for layer = 0, 1 do
    local t = {}
    local base = 0x8000 + layer * 0x1000
    for i = 0, 0x7FF do t[i] = u16(tiles, base + i * 2) end
    c[layer == 0 and "bottom" or "top"] = t
  end
  assets._types37[area] = c
  return c
end

function R.spawnEnemy(E, dat, def)
  for _, m in ipairs(mods()) do
    if m.spawnEnemy then local x = m.spawnEnemy(E, dat, def) if x ~= nil then return x end end
  end
  return nil
end

function R.handles(e)
  if e.r37 ~= nil then return e.r37 ~= false end
  for _, m in ipairs(mods()) do
    if m.handles and m.handles(e) then e.r37 = m return true end
  end
  e.r37 = false
  return false
end
function R.update(E, e)
  local m = e.r37
  if m then return m.update(E, e) end
end

function R.spawnObject(d, e)
  for _, m in ipairs(mods()) do
    if m.spawnObject then local x = m.spawnObject(d, e) if x ~= nil then return x end end
  end
  return nil
end

function R.spawnManager(d, m, dat)
  for _, mm in ipairs(mods()) do
    if mm.spawnManager then local x = mm.spawnManager(d, m, dat) if x ~= nil then return x end end
  end
  return nil
end

function R.roomInit(f)
  for _, m in ipairs(mods()) do if m.roomInit then m.roomInit(f) end end
end

function R.frame(f, input)
  for _, m in ipairs(mods()) do
    if m.frame and m.frame(f, input) then return true end
  end
  return false
end

function R.draw(f, font)
  for _, m in ipairs(mods()) do if m.draw then m.draw(f, font) end end
end

function R.playerFrame(p, input)
  for _, m in ipairs(mods()) do
    if m.playerFrame and m.playerFrame(p, input) then return true end
  end
  return false
end

-- Priority.compose: after the room's BG layers of priority p, before the
-- OBJs of that priority (BG over BG by number, OBJ over BG)
function R.bgPass(f, r, p, camX, camY)
  if r ~= f.room then return end
  for _, m in ipairs(mods()) do if m.bgPass then m.bgPass(f, r, p, camX, camY) end end
end

mods()
return R
