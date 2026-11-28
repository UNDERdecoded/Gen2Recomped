-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the Explorer Kit reaches the Underground, that where it
-- puts you is the cartridge's own arithmetic and not a plausible-looking
-- rewrite of it, and that the behaviour numbers hardcoded in Gen4Underground
-- still match the table they were computed from.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: Gen4Underground cannot require
-- Gen4Behaviors. Nothing under src/world requires src/import -- checked, it is
-- zero call sites across src/world, src/render and src/ui -- so the bridge range
-- and FORBIDS_EXPLORATION_KIT are literals in runtime code. Literals copied out
-- of a table drift from it silently. Section 3 re-derives all fifteen values
-- from Gen4Behaviors' own name list and fails if any moved.
--
-- Usage: texlua tools/gen4_underground_check.lua [<dataset dir>]
--   dataset dir defaults to G:/Gen2Recomped/platinum/data/generated

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local dir = (arg[1] or "G:/Gen2Recomped/platinum/data/generated"):gsub("[/\\]*$", "") .. "/"

local Gen4Behaviors  = require("src.import.Gen4Behaviors")
local Gen4Underground = require("src.world.Gen4Underground")
local GameVersion    = require("src.core.GameVersion")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local function load_(name)
  local chunk, err = loadfile(dir .. name)
  if not chunk then
    io.stderr:write(("could not load %s%s: %s\n"):format(dir, name, tostring(err)))
    os.exit(2)
  end
  return chunk()
end
local maps    = load_("maps.lua")
local layouts = load_("map_layouts.lua")
local items   = load_("items.lua")

local BLOCKED = 255
local function behAt(blocks, w, x, y) return blocks:byte((y * w + x) * 2 + 1) end

-- ---------------------------------------------------------------------------
section("1. the map exists, and is the one the header names")
-- ---------------------------------------------------------------------------
local ug = maps[Gen4Underground.MAP_ID]
ok(ug ~= nil, "maps[%q] is missing -- the Underground map is not extracted",
   Gen4Underground.MAP_ID)
if ug then
  io.write(("  UG: header %s  %sx%s  label %q  layout %s  objects %d\n"):format(
    tostring(ug.header), tostring(ug.width), tostring(ug.height),
    tostring(ug.label), tostring(ug.layout),
    (function() local n = 0 for _ in pairs(ug.objects or {}) do n = n + 1 end return n end)()))
  -- MAP_HEADER_UNDERGROUND is line 3 of generated/map_headers.txt, so index 2.
  ok(ug.header == 2, "the Underground should be header 2, dataset says %s",
     tostring(ug.header))
  ok(ug.width == 480 and ug.height == 480,
     "the Underground should be 480x480 (15x15 chunks), dataset says %sx%s",
     tostring(ug.width), tostring(ug.height))
  -- The label is what CanUseExplorerKit compares, so the refusal depends on it.
  -- (the label is the cartridge's language; Gen4Underground compares the
  -- text id, so the name is only asserted per language)
  local itemsT = load_("items.lua")
  local english = itemsT and itemsT[1] and itemsT[1].name == "Master Ball"
  local wantLabel = english and "Mystery Zone" or "Mysteriöser Ort"
  ok(ug.label == wantLabel,
     "the Underground's label is %q, expected %q -- the kit would not "
     .. "climb back out", tostring(ug.label), wantLabel)
end

-- ---------------------------------------------------------------------------
section("2. the Explorer Kit is found by the cartridge's dispatch index")
-- ---------------------------------------------------------------------------
-- ITEM_USE_FUNC_EXPLORER_KIT is row 3 of sItemUseFuncs (item_use_functions.c).
local kits, kitId = 0, nil
for id, def in pairs(items) do
  if type(def) == "table" and def.fieldUseFunc == 3 then
    kits = kits + 1
    kitId = id
  end
end
io.write(("  items with fieldUseFunc == 3: %d (id %s, %s)\n"):format(
  kits, tostring(kitId), kitId and tostring(items[kitId].name) or "-"))
ok(kits == 1, "expected exactly one item on dispatch row 3, found %d", kits)
ok(kitId == 428 and (items[kitId].name == "Explorer Kit" or items[1].name ~= "Master Ball"),
   "dispatch row 3 is %q (id %s), not the Explorer Kit (428)",
   kitId and tostring(items[kitId].name) or "nothing", tostring(kitId))
-- The control: the row number has to be doing work. If every item answered, or
-- none did, the test above would pass for the wrong reason.
local rows = {}
for _, def in pairs(items) do
  if type(def) == "table" and def.fieldUseFunc then
    rows[def.fieldUseFunc] = (rows[def.fieldUseFunc] or 0) + 1
  end
end
local distinct = 0
for _ in pairs(rows) do distinct = distinct + 1 end
io.write(("  distinct dispatch rows used by the dataset: %d\n"):format(distinct))
ok(distinct > 5,
   "only %d distinct fieldUseFunc values in the whole item table -- the field "
   .. "is not the cartridge's dispatch index and section 2 proves nothing",
   distinct)

-- ---------------------------------------------------------------------------
section("3. the hardcoded behaviour numbers still match Gen4Behaviors")
-- ---------------------------------------------------------------------------
local byName = {}
for v = 0, 255 do local n = Gen4Behaviors.name(v); if n then byName[n] = v end end
ok(byName["FORBIDS_EXPLORATION_KIT"] == Gen4Underground.FORBIDS_EXPLORATION_KIT,
   "FORBIDS_EXPLORATION_KIT is 0x%02X in Gen4Behaviors, 0x%02X in Gen4Underground",
   byName["FORBIDS_EXPLORATION_KIT"] or -1,
   Gen4Underground.FORBIDS_EXPLORATION_KIT)
-- TileBehavior_IsBridge (map_tile_behavior.c) names these thirteen, in order,
-- and deliberately leaves out BRIDGE_START.
local BRIDGES = {
  "BRIDGE", "BRIDGE_OVER_CAVE", "BRIDGE_OVER_WATER", "BRIDGE_OVER_SAND",
  "BRIDGE_OVER_SNOW", "BIKE_BRIDGE_N_S", "BIKE_BRIDGE_N_S_OVER_ENCS",
  "BIKE_BRIDGE_N_S_OVER_WATER", "BIKE_BRIDGE_N_S_OVER_SAND",
  "BIKE_BRIDGE_E_W", "BIKE_BRIDGE_E_W_OVER_ENCS",
  "BIKE_BRIDGE_E_W_OVER_WATER", "BIKE_BRIDGE_E_W_OVER_SAND",
}
for i, name in ipairs(BRIDGES) do
  local v = byName[name]
  ok(v ~= nil, "Gen4Behaviors has no %s", name)
  if v then
    ok(Gen4Underground.isBridge(v),
       "%s is 0x%02X and Gen4Underground.isBridge says no", name, v)
    -- contiguous, which is the only reason a range is allowed to stand in for
    -- a thirteen-name list
    ok(v == Gen4Underground.BRIDGE_FIRST + i - 1,
       "%s is 0x%02X but the range expects 0x%02X -- the values are no longer "
       .. "contiguous and isBridge must become a set", name, v,
       Gen4Underground.BRIDGE_FIRST + i - 1)
  end
end
ok(Gen4Underground.BRIDGE_LAST == Gen4Underground.BRIDGE_FIRST + #BRIDGES - 1,
   "the bridge range covers %d values, the cartridge names %d",
   Gen4Underground.BRIDGE_LAST - Gen4Underground.BRIDGE_FIRST + 1, #BRIDGES)
-- BRIDGE_START has its own predicate on the cartridge and must NOT be caught.
local startV = byName["BRIDGE_START"]
ok(startV ~= nil and not Gen4Underground.isBridge(startV),
   "BRIDGE_START 0x%02X is being treated as a bridge; TileBehavior_IsBridge "
   .. "excludes it (TileBehavior_IsBridgeStart is the other predicate)",
   startV or -1)

-- ---------------------------------------------------------------------------
section("4. where you come out, over every walkable cell of the main matrix")
-- ---------------------------------------------------------------------------
-- The first draft of this measurement indexed the shared 960x960 region grid
-- with map-local coordinates and reported 293 blocked arrivals that were nothing
-- but a wrong origin. This one walks the region grid itself, which is the space
-- the cartridge's own x/z live in.
local main = layouts[0]
ok(main ~= nil and main.width == 960 and main.height == 960,
   "layout 0 should be the 960x960 region grid")
if main and ug then
  local ugB = ug.blocks or (layouts[ug.layout] or {}).blocks
  local walkable, refused, oob, blockedDest, good = 0, 0, 0, 0, 0
  local entries, minx, maxx, minz, maxz = {}, 1e9, -1, 1e9, -1
  for z = 0, main.height - 1 do
    for x = 0, main.width - 1 do
      if behAt(main.blocks, main.width, x, z) ~= BLOCKED then
        walkable = walkable + 1
        local dx, dz = Gen4Underground.descendCell(x, z)
        if not dx then refused = refused + 1
        elseif dx >= ug.width or dz >= ug.height then oob = oob + 1
        else
          if behAt(ugB, ug.width, dx, dz) == BLOCKED then
            blockedDest = blockedDest + 1
          else good = good + 1 end
          entries[dz * 1000 + dx] = true
          if dx < minx then minx = dx end
          if dx > maxx then maxx = dx end
          if dz < minz then minz = dz end
          if dz > maxz then maxz = dz end
        end
      end
    end
  end
  local n = 0
  for _ in pairs(entries) do n = n + 1 end
  io.write(("  walkable main-matrix cells %d -> %d entry points, x %d..%d z %d..%d\n")
           :format(walkable, n, minx, maxx, minz, maxz))
  io.write(("  refused %d, outside the Underground %d, onto blocked ground %d\n")
           :format(refused, oob, blockedDest))
  ok(walkable > 50000, "only %d walkable cells on the main matrix", walkable)
  ok(refused == 0,
     "%d walkable cells hit the GF_ASSERTs -- the west/north margins are wrong",
     refused)
  ok(oob == 0, "%d arrivals land outside the 480x480 Underground", oob)
  ok(blockedDest == 0,
     "%d arrivals land on a cell the Underground calls blocked", blockedDest)
  ok(n > 100, "only %d distinct entry points; Sinnoh should have about 170", n)

  -- THE CONTROL. Every number above would also come out clean from a formula
  -- that simply landed everyone on one known-good cell, so break the halving
  -- and confirm the checks above can fail at all.
  local bad = 0
  for z = 0, main.height - 1, 7 do
    for x = 0, main.width - 1, 7 do
      if behAt(main.blocks, main.width, x, z) ~= BLOCKED then
        -- the same arithmetic WITHOUT the fold: 960-space into a 480 map
        local mx = math.floor(x / 32) - 1
        local mz = math.floor(z / 32) - 6
        if mx >= 0 and mz >= 0 then
          local dx = (mx + 1) * 32 + ((mx % 2 == 0) and 8 or 23)
          local dz = (mz + 3) * 32 + ((mz % 2 == 0) and 8 or 23)
          if dx >= ug.width or dz >= ug.height then bad = bad + 1 end
        end
      end
    end
  end
  io.write(("  control -- the same arithmetic with the 2:1 fold removed: "
            .. "%d arrivals fall outside the map\n"):format(bad))
  ok(bad > 0,
     "removing the fold changed nothing, so section 4 is not measuring the "
     .. "mapping and its zeros mean nothing")
end

-- ---------------------------------------------------------------------------
section("5. the guards, each one planted")
-- ---------------------------------------------------------------------------
GameVersion.set("platinum")
ok(GameVersion.isGen4(), "GameVersion.set(\"platinum\") did not give a Gen 4")

-- A main-matrix cell known to be walkable and to descend cleanly.
local okx, okz
if main then
  for z = 200, 500 do
    for x = 100, 500 do
      if behAt(main.blocks, main.width, x, z) ~= BLOCKED
         and Gen4Underground.descendCell(x, z) then
        okx, okz = x, z break
      end
    end
    if okx then break end
  end
end
ok(okx ~= nil, "could not find a walkable main-matrix cell to test with")

local function fakeOw(opts)
  opts = opts or {}
  local def = {
    layout = opts.layout == nil and 0 or opts.layout,
    label = opts.label or "Jubilife City",
    originX = 0, originY = 0, width = 960, height = 960,
  }
  return {
    map = {
      id = opts.id or "C01", def = def,
      blockAt = function(_, _, _) return opts.behaviour or 0 end,
    },
    player = { cellX = opts.x or okx, cellY = opts.y or okz,
               facing = "down", surfing = opts.surfing },
    cast = opts.cast,
  }
end
local Game = { data = { maps = maps }, save = { player = { name = "TEST" } } }

-- Both returns captured: canUse answers `true` alone on success, so
-- select(2, ...) is EMPTY there and tostring() raises rather than printing
-- nil -- which is how the first run of this file died in its own message.
local can, canWhy = Gen4Underground.canUse(Game, fakeOw())
ok(can == true, "the control case refused: %s", tostring(canWhy))

local cases = {
  { "already underground",  { label = "Mystery Zone" } },
  { "not on the main matrix", { layout = 7 } },
  { "surfing",              { surfing = true } },
  { "on a bridge",          { behaviour = Gen4Underground.BRIDGE_FIRST } },
  { "the ground refuses",   { behaviour = Gen4Underground.FORBIDS_EXPLORATION_KIT } },
  { "nowhere to dig",       { behaviour = 255 } },
}
for _, case in ipairs(cases) do
  local want, opts = case[1], case[2]
  local got, why = Gen4Underground.canUse(Game, fakeOw(opts))
  ok(got == false and why == want,
     "guard %q did not bite: canUse returned %s / %s", want, tostring(got),
     tostring(why))
end
-- someone standing on the spot
do
  local ow = fakeOw()
  ow.cast = { ow.player, { cellX = ow.player.cellX, cellY = ow.player.cellY } }
  local got, why = Gen4Underground.canUse(Game, ow)
  ok(got == false and why == "someone is standing there",
     "the occupied-cell guard did not bite: %s / %s", tostring(got), tostring(why))
end
-- and the last bridge value, so the range's far end is covered too
ok(select(1, Gen4Underground.canUse(Game, fakeOw({
     behaviour = Gen4Underground.BRIDGE_LAST }))) == false,
   "the top of the bridge range is not refused")
-- BRIDGE_START must NOT refuse
ok(Gen4Underground.canUse(Game, fakeOw({ behaviour = 0x70 })) == true,
   "BRIDGE_START 0x70 is being refused; the cartridge's IsBridge excludes it")

-- Gen 1/2/3 can never take this path.
GameVersion.set("crystal")
ok(Gen4Underground.canUse(Game, fakeOw()) == false,
   "canUse answered yes for a non-Gen-4 cartridge")
GameVersion.set("platinum")

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
