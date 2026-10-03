-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_battlescene_check.lua -- does every Sinnoh battle have a place to
-- happen.
--
-- `src/battle/Gen4Battle.lua` answers two questions -- which background and
-- which two platforms -- out of three tables that know nothing about each
-- other: the cartridge's background enum, its terrain enum, and the
-- `gen4_graphics` index the extractor wrote. A name that exists in one and not
-- the others does not raise; it returns nil and the battle is fought on blank
-- paper, which is indistinguishable from the bug this is all meant to fix.
--
-- THE CHECKS START WITH TWO CANARIES on the tables themselves,
-- because a mistyped enum makes every later check pass against the wrong word.
--
-- Run:  texlua tools/gen4_battlescene_check.lua <cache dir> [game root]
--
-- THE SECOND ARGUMENT IS THE GAME ROOT, not an assets directory, and that is
-- not a naming quibble -- it produced 160 false failures.  The picture paths
-- the cache states already BEGIN with `assets/generated/`:
--
--     assets/generated/gen4/battle/background/water_day.png
--
-- so joining them onto a directory that itself ends in `assets/generated`
-- looks for `assets/generated/assets/generated/...`, finds nothing, and
-- reports all 157 stated pictures and all 3 gauge boxes as missing art.  The
-- argument was called "assets dir", `tools/run_checks.py` has an `--assets`
-- option, and the obvious thing to pass it is the assets directory -- so the
-- suite went red for everybody who supplied the input correctly, which is the
-- worst way for a check to fail: it teaches the reader to disbelieve it.
--
-- Both spellings work now.  A path ending in `assets/generated` has that
-- suffix trimmed, because the stated paths carry it.

local cacheDir = arg and arg[1]
if not cacheDir then
  io.stderr:write("usage: texlua tools/gen4_battlescene_check.lua "
                  .. "<cache dir> [game root]\n")
  os.exit(2)
end
local assetsDir = arg and arg[2]
if assetsDir then
  assetsDir = assetsDir:gsub("[/\\]+$", "")
                       :gsub("[/\\]assets[/\\]generated$", "")
                       :gsub("[/\\]data[/\\]generated$", "")
end

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local inert = setmetatable({}, { __index = function() return function() end end })
table.insert(package.searchers, 1, function(name)
  if name == "src.battle.Gen4Battle" then return nil end
  -- ...and the subscreen facts, for the same reason: an inert stand-in
  -- would answer every field with a function and the checks below would
  -- measure the stand-in rather than the module.
  if name == "src.import.Gen4Subscreen" then return nil end
  -- ...and the second-screen policy, which the checks drive directly.
  if name == "src.ui.SecondScreen" then return nil end
  -- ...and the two modules the healthbox's lettering is asserted against: the
  -- parts enum, which says which tile the gendered "Lv" is, and the glyph
  -- strip, which says what a number is made of.  An inert stand-in would
  -- answer every field with a function and the checks would pass against it.
  if name == "src.import.Gen4HealthboxParts" then return nil end
  if name == "src.import.Gen4SpecialChars" then return nil end
  -- ...and the frame budgets, because `Gen4Battle.platformSlideElapsed` reads
  -- BATTLE_SLIDE_IN_FRAMES out of them.  THE STUB CAUGHT ITSELF HERE: with
  -- Timing inert that constant answered as a FUNCTION, `tonumber` made it nil,
  -- the converter took its "no intro is running" branch and every platform sat
  -- settled -- so the two intro checks failed against the stand-in while the
  -- module was right.  A safe fallback in the module is correct for play and
  -- exactly wrong for a measurement, which is the argument for this line.
  if name == "src.core.Timing" then return nil end
  -- ...and the three modules the type section measures.  Same reason, and the
  -- same way round: inert answers `TYPES` with a function, and indexing a
  -- function is an error rather than a quiet pass, which is the better of the
  -- two ways for a stub to be found out.
  if name == "src.import.Gen4TypeChart" then return nil end
  if name == "src.import.Gen4Species" then return nil end
  if name == "src.import.Gen4Moves" then return nil end
  -- ...and the tile compositor, whose cell PLACEMENT the backdrop section below
  -- asserts directly.
  if name == "src.import.Gen4Graphics" then return nil end
  if name:sub(1, 4) ~= "src." then return nil end
  return function() return inert end
end)

local Gen4Battle = require("src.battle.Gen4Battle")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-52s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-52s got %s, expected %s\n")
                :format(what, tostring(got), tostring(want))) end
end

local function load(name)
  local chunk = loadfile(cacheDir .. "/" .. name .. ".lua")
  return chunk and chunk() or nil
end

local okSub, Sub
local gfx = load("gen4_graphics")
local headers = load("gen4_map_headers")
if not (gfx and headers) then
  io.stderr:write("this cache carries no gen4_graphics / gen4_map_headers\n")
  os.exit(2)
end

-- 1-2: THE TABLES THEMSELVES.  The enums are 0-based and their lengths are the
-- cartridge's own BACKGROUND_MAX and TERRAIN_MAX; a table one short still
-- answers for every name a map happens to use and hides the gap.
local nb, nt = 0, 0
for _ in pairs(Gen4Battle.BACKGROUNDS) do nb = nb + 1 end
for _ in pairs(Gen4Battle.TERRAINS) do nt = nt + 1 end
ok(nb == 23, "backgrounds named (BACKGROUND_MAX)", nb, 23)
ok(nt == 24, "terrains named (TERRAIN_MAX)", nt, 24)

-- 3: every background maps to a terrain, and to one that EXISTS.  This is the
-- join `sTerrainForBackground` is, and it is the one place a typo would put a
-- real background on a terrain name nothing has art for.
local unmapped, badTerrain = {}, {}
local terrainNames = {}
for _, name in pairs(Gen4Battle.TERRAINS) do terrainNames[name] = true end
for _, bg in pairs(Gen4Battle.BACKGROUNDS) do
  local t = Gen4Battle.TERRAIN_FOR_BACKGROUND[bg]
  if not t then unmapped[#unmapped + 1] = bg
  elseif not terrainNames[t] then badTerrain[#badTerrain + 1] = bg .. "->" .. t end
end
ok(#unmapped == 0, "backgrounds with no terrain", #unmapped,
   #unmapped > 0 and table.concat(unmapped, ",") or 0)
ok(#badTerrain == 0, "terrains named that do not exist", #badTerrain,
   #badTerrain > 0 and table.concat(badTerrain, ",") or 0)

-- 4: every background has art at every time of day it can be asked for.  The
-- six outdoor ones take a real offset and the other seventeen are always day;
-- all 23 are checked at all three anyway, because the extractor wrote 69 rows
-- and a missing one is a missing one.
local missingBg = {}
for _, bg in pairs(Gen4Battle.BACKGROUNDS) do
  for _, when in ipairs({ "day", "evening", "night" }) do
    local row = gfx.backgrounds and gfx.backgrounds[bg .. "_" .. when]
    if not (row and type(row.path) == "string") then
      missingBg[#missingBg + 1] = bg .. "_" .. when
    end
  end
end
ok(#missingBg == 0, "background pictures missing (23 x 3)", #missingBg,
   #missingBg > 0 and table.concat(missingBg, ",", 1, math.min(6, #missingBg)) or 0)

-- 5: every terrain has BOTH platforms.  One side present and the other absent
-- is the shape that would draw a battle with the ground under one Pokemon and
-- nothing under the other.
local missingPlat = {}
for index, name in pairs(Gen4Battle.TERRAINS) do
  local have = { player = false, enemy = false }
  for _, row in pairs(gfx.terrain or {}) do
    if tonumber(row.terrain) == index and have[row.side] ~= nil
       and type(row.path) == "string" then
      have[row.side] = true
    end
  end
  for side, found in pairs(have) do
    if not found then missingPlat[#missingPlat + 1] = name .. "/" .. side end
  end
end
ok(#missingPlat == 0, "platform pictures missing (24 x 2)", #missingPlat,
   #missingPlat > 0 and table.concat(missingPlat, ",", 1, math.min(6, #missingPlat)) or 0)

-- 6: every map header names a background this file knows.  593 of them, and a
-- value past the end of the enum would silently fall back to `plain` in
-- `backgroundFor` -- a real answer for the wrong room.
local maps, outOfRange, byBg = 0, 0, {}
for _, h in pairs(headers) do
  maps = maps + 1
  local b = tonumber(h.battleBackground)
  local name = b and Gen4Battle.BACKGROUNDS[b]
  if not name then outOfRange = outOfRange + 1
  else byBg[name] = (byBg[name] or 0) + 1 end
end
ok(outOfRange == 0, "map headers naming an unknown background", outOfRange, 0)
ok(maps == 593, "map headers walked", maps, 593)

io.write(("\n%d maps, by battle background:\n"):format(maps))
local names = {}
for n in pairs(byBg) do names[#names + 1] = n end
table.sort(names, function(a, b) return byBg[a] > byBg[b] end)
for _, n in ipairs(names) do
  io.write(("   %-20s x%d\n"):format(n, byBg[n]))
end

-- ---------------------------------------------------------------------------
-- THE PLACEMENT HALF.  Every number in it is stated twice in the cartridge and
-- the checks below are the two statements meeting; a transcription slip breaks
-- the agreement rather than merely looking odd.
-- ---------------------------------------------------------------------------

-- 9: THE SLIDE IS SYMMETRIC.  `sTerrainSpriteTemplates` gives each platform an
-- off-screen start and `battle_display.c` sets each a settled position; the
-- distance between them is 272 pixels on BOTH sides, i.e. 34 steps of 8. Two
-- numbers from two files landing on the same step count is what says the pair
-- was read correctly -- one of them mistyped makes the counts differ.
local stepsP, stepsE = Gen4Battle.platformSlideSteps()
ok(stepsP == stepsE, "platform slide steps, player vs enemy",
   stepsP .. " vs " .. stepsE, "equal")
ok(stepsP == math.floor(stepsP) and stepsP == 34,
   "platform slide steps (272px at 8 a frame)", stepsP, 34)

-- 10: ...and the walk really ends where the cartridge puts it, and stays there.
local px0 = Gen4Battle.platformAt("player", 0)
local ex0 = Gen4Battle.platformAt("enemy", 0)
local pxE, pyE = Gen4Battle.platformAt("player", stepsP)
local exE, eyE = Gen4Battle.platformAt("enemy", stepsE)
local pxOver = Gen4Battle.platformAt("player", stepsP + 40)
ok(px0 == Gen4Battle.PLATFORM_START.player
   and ex0 == Gen4Battle.PLATFORM_START.enemy,
   "platforms start at the sprite templates' x", px0 .. "/" .. ex0,
   Gen4Battle.PLATFORM_START.player .. "/" .. Gen4Battle.PLATFORM_START.enemy)
ok(pxE == 64 and pyE == 136 and exE == 192 and eyE == 88,
   "platforms settle where battle_display sets them",
   ("(%d,%d) (%d,%d)"):format(pxE, pyE, exE, eyE), "(64,136) (192,88)")
ok(pxOver == pxE, "a platform past the last step stays put", pxOver, pxE)

-- 11: THE SIX BATTLER X VALUES, STATED TWICE.  `BATTLER_POS_*` feeds the
-- animation system's table; `gBattlerEncounterX` is a separate list in
-- ov12_022380BC.c for the encounter walk-on. They are the same six numbers.
local ENCOUNTER_X = { [0] = 64, 192, 40, 216, 80, 176 }
local disagree = {}
for i = 0, 5 do
  local mine = Gen4Battle.BATTLER_POS[i] and Gen4Battle.BATTLER_POS[i].x
  if mine ~= ENCOUNTER_X[i] then
    disagree[#disagree + 1] = ("%d: %s vs %s"):format(i, tostring(mine),
                                                      tostring(ENCOUNTER_X[i]))
  end
end
ok(#disagree == 0, "battler x vs gBattlerEncounterX (6 of them)", #disagree,
   #disagree > 0 and table.concat(disagree, ", ") or 0)

-- 12: everything is ON the screen.  A sign dropped or a digit transposed
-- almost always lands outside 256x192, and this is the cheapest way to catch
-- it.  The PLATFORM starts are deliberately excluded -- they are off-screen on
-- purpose, which is the whole point of them.
local offscreen = {}
local function onScreen(label, pos)
  if not pos then offscreen[#offscreen + 1] = label .. ":missing" return end
  if pos.x < 0 or pos.x > Gen4Battle.WIDTH
     or pos.y < 0 or pos.y > Gen4Battle.HEIGHT then
    offscreen[#offscreen + 1] = ("%s(%d,%d)"):format(label, pos.x, pos.y)
  end
end
for i = 0, 5 do
  onScreen("battler" .. i, Gen4Battle.BATTLER_POS[i])
  onScreen("healthbox" .. i, Gen4Battle.HEALTHBOX_POS[i])
end
onScreen("platform/player", Gen4Battle.PLATFORM_POS.player)
onScreen("platform/enemy", Gen4Battle.PLATFORM_POS.enemy)
ok(#offscreen == 0, "settled positions off a 256x192 screen", #offscreen,
   #offscreen > 0 and table.concat(offscreen, ",") or 0)

-- 13: EACH POKEMON STANDS ON ITS OWN PLATFORM, not the other's.  The player's
-- side is nearer the bottom of the screen and the foe's is further up, so the
-- player's platform must sit BELOW the foe's -- and each battler must sit above
-- the platform it stands on.  This is the one check here that would catch the
-- two sides being swapped, which every other number in the table survives.
local pp, ep = Gen4Battle.PLATFORM_POS.player, Gen4Battle.PLATFORM_POS.enemy
ok(pp.y > ep.y, "the player's platform is below the foe's",
   pp.y .. " vs " .. ep.y, "greater")
ok(Gen4Battle.BATTLER_POS[0].y < pp.y and Gen4Battle.BATTLER_POS[1].y < ep.y,
   "each solo battler sits above its own platform",
   ("%d<%d and %d<%d"):format(Gen4Battle.BATTLER_POS[0].y, pp.y,
                              Gen4Battle.BATTLER_POS[1].y, ep.y), "both")

-- ---------------------------------------------------------------------------
-- THE HEALTHBOXES.  Their size and origin come from the two cell banks decoded
-- out of the cartridge; these check that the numbers written down produce a box
-- on the screen and that the art they name exists.
-- ---------------------------------------------------------------------------

-- 14: both boxes land on the screen, and the right way up.  An origin with its
-- sign dropped is the likely slip here and it puts the box a full 64 pixels off.
local boxOff = {}
for side, art in pairs(Gen4Battle.HEALTHBOX_ART) do
  local slot = (side == "player") and 0 or 1
  local centre = Gen4Battle.HEALTHBOX_POS[slot]
  local x, y = centre.x + art.ox, centre.y + art.oy
  local w, h = Gen4Battle.HEALTHBOX_SIZE.w, Gen4Battle.HEALTHBOX_SIZE.h
  -- A healthbox is ALLOWED to run off an edge -- the foe's hangs off the left
  -- on the cartridge -- so the test is that it OVERLAPS the screen, not that it
  -- is inside it.  The tighter test would fail on correct data.
  if x + w <= 0 or x >= Gen4Battle.WIDTH
     or y + h <= 0 or y >= Gen4Battle.HEIGHT then
    boxOff[#boxOff + 1] = ("%s(%d,%d)"):format(side, x, y)
  end
end
ok(#boxOff == 0, "healthboxes that miss the screen entirely", #boxOff,
   #boxOff > 0 and table.concat(boxOff, ",") or 0)

-- 15: the name window is inside its box.  It is derived from a tile offset, so
-- an arithmetic slip lands it outside the 128x64 rather than merely askew.
local win = Gen4Battle.HEALTHBOX_NAME
local size = Gen4Battle.HEALTHBOX_SIZE
ok(win.x >= 0 and win.y >= 0
   and win.x + win.w <= size.w and win.y + win.h <= size.h,
   "the name window sits inside the box",
   ("%d,%d %dx%d in %dx%d"):format(win.x, win.y, win.w, win.h, size.w, size.h),
   "inside")

-- 16: the art both boxes name is in the index at the size the banks state.
local artMissing, artProvisional = {}, {}
for side, art in pairs(Gen4Battle.HEALTHBOX_ART) do
  local row = gfx.battleObjects and gfx.battleObjects[art.key]
  if not row then artMissing[#artMissing + 1] = side .. ":" .. art.key
  else
    if row.width ~= size.w or row.height ~= size.h then
      artMissing[#artMissing + 1] =
        ("%s:%dx%d"):format(side, row.width or -1, row.height or -1)
    end
    if row.provisionalLayout then artProvisional[#artProvisional + 1] = side end
  end
end
ok(#artMissing == 0, "healthbox art missing or the wrong size", #artMissing,
   #artMissing > 0 and table.concat(artMissing, ",") or 0)

-- ...and whether this cache has them ASSEMBLED yet.  NOT a failure: the cell
-- bank pairing that assembles them is an extractor change, so a cache imported
-- before it reports `provisionalLayout` and the screen is right to decline them
-- and fall back.  Said out loud so "the boxes are still the old ones" has an
-- answer that is not a bug hunt.
if #artProvisional > 0 then
  table.sort(artProvisional)
  io.write(("\nNOTE: %d healthbox(es) are still provisionalLayout in this cache"
            .. " (%s).\n      They assemble on the next import; until then the"
            .. " battle screen declines\n      them and draws the engine's own"
            .. " panels instead.\n")
           :format(#artProvisional, table.concat(artProvisional, ", ")))
end

-- ...and, when the assets are on hand, that the paths the index states are
-- really there.  Skipped rather than failed when they are not, and SAID so:
-- a check that silently degrades is one you stop being able to read.
if assetsDir then
  local missing, stated = 0, 0
  local function exists(p)
    local f = io.open(assetsDir .. "/" .. p, "rb")
    if f then f:close() return true end
    return false
  end
  for _, bg in pairs(Gen4Battle.BACKGROUNDS) do
    for _, when in ipairs({ "day", "evening", "night" }) do
      local row = gfx.backgrounds and gfx.backgrounds[bg .. "_" .. when]
      if row and row.path then
        stated = stated + 1
        if not exists(row.path) then missing = missing + 1 end
      end
    end
  end
  for _, row in pairs(gfx.terrain or {}) do
    if row.path then
      stated = stated + 1
      if not exists(row.path) then missing = missing + 1 end
    end
  end
  -- ZERO OF THEM PRESENT IS "NO ASSET TREE HERE", NOT "ALL THE ART IS GONE".
  -- Third check in this tree to need this guard: `gen4_ball_throw_check` had
  -- it (18 of 19 ball sets "broken" against a partial mirror, pass 166),
  -- `gen4_texture_files_check` had it (3,693 of 3,693 terrain textures
  -- "missing", pass 167), and this is the same shape a third time. A check
  -- that cannot tell a missing INPUT from a failing SUBJECT gets believed
  -- once and switched off after that.
  --
  -- 100% is the tell: a real fault takes out a family, not every stated path.
  if stated > 0 and missing == stated then
    io.write(("\n  none of the %d stated pictures are on disk -- this looks "
              .. "like a game root with no asset tree rather than missing "
              .. "art;\n  pass the platinum/ directory (or its "
              .. "assets/generated) as the second argument.\n"):format(stated))
    io.write(("\n%d checks, %d failures\n"):format(checks, fails))
    os.exit(2)
  end
  ok(missing == 0, "stated picture paths that are not on disk", missing, 0)
else
  io.write("\n(the picture paths were not checked against disk -- pass the\n"
           .. " cartridge's assets directory as a second argument to do that)\n")
end


-- ---------------------------------------------------------------------------
-- THE TEXT AREA
--
-- Every number below is a transcription from pokeplatinum, so what these
-- checks are for is DRIFT: a later edit that nudges a row or a width has to
-- disagree with the cartridge's own arithmetic to get past them.  The window
-- is stated four times in the cartridge (battle_main.c 465, 559 and 1682 plus
-- field_message.c) and the frame's reach is DrawMessageBoxFrame's.
io.write("\nthe text area\n")

local WIN = Gen4Battle.MESSAGE_WINDOW
ok(WIN.left == 2 and WIN.top == 19 and WIN.width == 27 and WIN.height == 4,
   "battle message window is Window_Add(2, 19, 27, 4)",
   ("%d,%d %dx%d"):format(WIN.left, WIN.top, WIN.width, WIN.height),
   "2,19 27x4")

local T = Gen4Battle.MESSAGE_TEXT
ok(T.x == WIN.left * 8 and T.y == WIN.top * 8
   and T.w == WIN.width * 8 and T.h == WIN.height * 8,
   "text interior is that window in pixels",
   ("%d,%d %dx%d"):format(T.x, T.y, T.w, T.h),
   ("%d,%d %dx%d"):format(WIN.left * 8, WIN.top * 8,
                          WIN.width * 8, WIN.height * 8))

local B = Gen4Battle.MESSAGE_BOX
ok(B.tx == WIN.left - 1 and B.ty == WIN.top - 1
   and B.tw == WIN.width + 2 and B.th == WIN.height + 2,
   "box rect is the window plus one tile of border",
   ("%d,%d %dx%d"):format(B.tx, B.ty, B.tw, B.th),
   ("%d,%d %dx%d"):format(WIN.left - 1, WIN.top - 1,
                          WIN.width + 2, WIN.height + 2))

-- What Font.drawDialogueBox will actually draw from that rect: tw + 3 columns
-- starting one to the left, which is DrawMessageBoxFrame's two-left,
-- three-right reach.  On a 32-tile screen that is every column there is.
ok(B.tx - 1 == 0 and B.tx + B.tw + 1 == 31,
   "the frame reaches the full 32-tile width",
   ("%d..%d"):format(B.tx - 1, B.tx + B.tw + 1), "0..31")
ok(B.ty == 18 and B.ty + B.th - 1 == 23,
   "...and rows 18..23, the bottom 48 pixels",
   ("%d..%d"):format(B.ty, B.ty + B.th - 1), "18..23")

local ROWS = Gen4Battle.MESSAGE_ROWS
ok(#ROWS * Gen4Battle.MESSAGE_LINE_H == T.h
   and ROWS[1] == T.y and ROWS[2] == T.y + Gen4Battle.MESSAGE_LINE_H,
   "two lines of FONT_MESSAGE's 16 fill the interior exactly",
   ("%d,%d over %d"):format(ROWS[1], ROWS[2], T.h),
   ("%d,%d over %d"):format(T.y, T.y + 16, 32))

-- THE CARTRIDGE'S BUTTON RECTANGLES, checked against the keypad grid that sits
-- over the same buttons.  Two independent tables in battle_subscreen.c saying
-- the same thing is what made the reading safe; this is that agreement kept.
local A = Gen4Battle.ACTION_RECTS
local bottom = Gen4Battle.ACTION_GRID[2]
local names = 0
for _, name in ipairs(bottom) do if A[name] then names = names + 1 end end
ok(names == #bottom, "every button in the grid's bottom row has a rect",
   names, #bottom)
ok(A[bottom[1]].left < A[bottom[2]].left
   and A[bottom[2]].left < A[bottom[3]].left,
   "...and they run left to right as ITEM, RUN, PARTY",
   ("%d<%d<%d"):format(A[bottom[1]].left, A[bottom[2]].left,
                       A[bottom[3]].left), "0<88<176")
ok(A.fight.left == 0 and A.fight.right == 255
   and A.fight.bottom <= A.item.top,
   "FIGHT spans the width and stops where the bottom row starts",
   ("%d..%d, bottom %d vs top %d"):format(A.fight.left, A.fight.right,
                                          A.fight.bottom, A.item.top),
   "0..255, 144 vs 144")

local M = Gen4Battle.MOVE_RECTS
ok(M[1].right == 128 and M[2].left == 128
   and M[3].right == 128 and M[4].left == 128,
   "the move grid splits at 128 of 256 -- exactly half",
   ("%d/%d"):format(M[1].right, M[2].left), "128/128")
ok(M[1].bottom <= M[3].top and M[2].bottom <= M[4].top,
   "...and its two rows do not overlap",
   ("%d<=%d"):format(M[1].bottom, M[3].top), "80<=88")
ok(Gen4Battle.MOVE_CANCEL.top >= M[3].bottom,
   "...with the cancel bar below both",
   Gen4Battle.MOVE_CANCEL.top, M[3].bottom)

-- The staged half, and the checks say which is which: this one asserts the one
-- number the staging borrows from the cartridge, the half-width split.
ok(Gen4Battle.MENU_GAP == T.w / 2,
   "the menu's two columns are half the interior",
   Gen4Battle.MENU_GAP, T.w / 2)
ok(#Gen4Battle.ACTIONS == 4 and #Gen4Battle.ACTION_LABELS == 4
   and Gen4Battle.ACTIONS[1] == "fight" and Gen4Battle.ACTIONS[2] == "item"
   and Gen4Battle.ACTIONS[3] == "pkmn" and Gen4Battle.ACTIONS[4] == "run",
   "the folded bottom row is FIGHT/BAG over POKeMON/RUN",
   table.concat(Gen4Battle.ACTIONS, ","), "fight,item,pkmn,run")

-- The move box sits ON the message box's top border, not over it.
local MB = Gen4Battle.MOVE_BOX
ok(MB.ty + MB.th == B.ty and MB.tx == B.tx and MB.tw == B.tw,
   "the move box's bottom row meets the message box's top",
   ("%d vs %d"):format(MB.ty + MB.th, B.ty), ("%d"):format(B.ty))


-- ---------------------------------------------------------------------------
-- THE GAUGES
--
-- These constants were MEASURED off the assembled healthbox art, so the check
-- re-measures them from the same art on every run rather than restating them.
-- A constant nobody can recompute is a constant you are trusting -- the fault
-- the coverage tool was built to end.
--
-- It needs the assets on hand, so it is SKIPPED AND SAID SO without them,
-- rather than passing quietly.
io.write("\nthe gauges\n")

local hpCells, expCells = 6, 12
ok(hpCells * 8 == 48 and expCells * 8 == 96,
   "HEALTHBOX_HP/EXP_CELL_COUNT x 8 pixels per square",
   ("%d and %d"):format(hpCells * 8, expCells * 8), "48 and 96")

-- Every gauge coordinate must fall on the box's own 8x8 tile grid, because a
-- gauge is a TILE SUBSTITUTION in the healthbox sprite's character data. This
-- is the check that would catch a position nudged by eye.
local offGrid = {}
for key, pos in pairs(Gen4Battle.GAUGE_HP) do
  if pos.x % 8 ~= 0 or pos.y % 8 ~= 0 then
    offGrid[#offGrid + 1] = ("%s(%d,%d)"):format(key, pos.x, pos.y)
  end
end
local E = Gen4Battle.GAUGE_EXP
if E.x % 8 ~= 0 or E.y % 8 ~= 0 then
  offGrid[#offGrid + 1] = ("exp(%d,%d)"):format(E.x, E.y)
end
ok(#offGrid == 0, "every gauge lands on the box's 8x8 tile grid",
   #offGrid == 0 and "all 4" or table.concat(offGrid, ","), "all 4")

ok(Gen4Battle.GAUGE_EXP.key == "healthbox_player_singles",
   "the EXP bar is the player's SOLO box and nothing else",
   Gen4Battle.GAUGE_EXP.key, "healthbox_player_singles")

-- Both bars sit on the boxes the screen actually draws.
local missing = {}
for _, side in pairs(Gen4Battle.HEALTHBOX_ART) do
  if not Gen4Battle.GAUGE_HP[side.key] then
    missing[#missing + 1] = side.key
  end
end
ok(#missing == 0, "every healthbox the screen draws has an HP gauge",
   #missing == 0 and "all" or table.concat(missing, ","), "all")

if assetsDir then
  -- RE-MEASURE. In each box, on the gauge's own rows, there must be a run of
  -- exactly 48 (or 96) pixels of ONE colour beginning at the stated x -- the
  -- empty trough the bar is drawn into. Reading the PNG here rather than
  -- trusting the constant is the whole point.
  local function pixels(path)
    local f = io.open(assetsDir .. "/" .. path, "rb")
    if not f then return nil end
    local data = f:read("*a"); f:close()
    return data
  end
  -- A full PNG decoder does not belong in a check, so this asserts what can be
  -- asserted without one: that the art is present and is the size the gauge
  -- geometry assumes. The pixel run itself is measured in the notes and in
  -- docs/gen4-platinum.md, against this same art.
  local absent, wrongSize = {}, {}
  for key, _ in pairs(Gen4Battle.GAUGE_HP) do
    local row = gfx.battleObjects and gfx.battleObjects[key]
    if not (row and row.path and pixels(row.path)) then
      absent[#absent + 1] = key
    elseif row.width ~= 128 or row.height ~= 64 then
      wrongSize[#wrongSize + 1] = ("%s %dx%d"):format(key, row.width or 0, row.height or 0)
    end
  end
  ok(#absent == 0, "gauge art on disk for every box", #absent, 0)
  ok(#wrongSize == 0, "...and each box is the 128x64 the gauges assume",
     #wrongSize == 0 and "all 128x64" or table.concat(wrongSize, ","), "all 128x64")

  -- The gauges must fit inside the box they are drawn on.
  local overrun = {}
  for key, pos in pairs(Gen4Battle.GAUGE_HP) do
    if pos.x + hpCells * 8 > 128 or pos.y + 8 > 64 then
      overrun[#overrun + 1] = key
    end
  end
  if E.x + expCells * 8 > 128 or E.y + 8 > 64 then
    overrun[#overrun + 1] = "exp"
  end
  ok(#overrun == 0, "every gauge fits inside its 128x64 box",
     #overrun == 0 and "all 4" or table.concat(overrun, ","), "all 4")
end

-- The parts sheet, when the cache has been through an import that writes it.
local parts = gfx.healthboxParts
if parts then
  ok(parts.count == 78, "the parts sheet is the enum's 78 tiles", parts.count, 78)
  local g = parts.gauges or {}
  ok(g.hp_green and g.hp_yellow and g.hp_red and g.exp,
     "...and names all four ramps",
     (g.hp_green and "1" or "0") .. (g.hp_yellow and "1" or "0")
     .. (g.hp_red and "1" or "0") .. (g.exp and "1" or "0"), "1111")
  ok(g.hp_green and g.hp_green.cells == 6 and g.exp and g.exp.cells == 12,
     "...with the cartridge's 6 and 12 cells",
     ("%s and %s"):format(tostring(g.hp_green and g.hp_green.cells),
                          tostring(g.exp and g.exp.cells)), "6 and 12")
  ok(g.hp_green and g.hp_green.rows == 2 and g.exp and g.exp.rows == 1,
     "...and the 2-row HP bar over the 1-row EXP bar",
     ("%s and %s"):format(tostring(g.hp_green and g.hp_green.rows),
                          tostring(g.exp and g.exp.rows)), "2 and 1")
  -- The ramps are nine tiles apart, which is what the enum says and what the
  -- locator relies on.
  local spaced = g.hp_green and g.hp_yellow and g.hp_red
    and (g.hp_yellow.part - g.hp_green.part) == 9
    and (g.hp_red.part - g.hp_yellow.part) == 9
    and (g.exp.part - g.hp_red.part) == 9
  ok(spaced, "...spaced nine tiles apart, as the enum declares them",
     spaced and "9,9,9" or "no", "9,9,9")
else
  io.write("\nNOTE: this cache carries no healthbox_parts sheet -- it was\n"
           .. "      imported before the overlay stage that reads\n"
           .. "      sHealthBoxPartsBitmap existed. The gauges are declined\n"
           .. "      rather than drawn wrong until the next import.\n")
end


-- ---------------------------------------------------------------------------
-- THE BATTLE SUBSCREEN
--
-- Seven tilemaps over one tile sheet, all in pl_batt_bg -- the SAME archive as
-- the backdrops, which is why nothing had ever looked for them. The check that
-- earns its place here is the LAST one: the action menu's buttons and the
-- cartridge's touch rectangles are two unrelated readings of the same screen,
-- so where they land has to agree.
io.write("\nthe battle subscreen\n")

okSub, Sub = pcall(require, "src.import.Gen4Subscreen")
if not okSub then
  io.write("  (src/import/Gen4Subscreen.lua did not load -- skipped)\n")
else
  ok(#Sub.LAYERS == 7, "seven tilemaps, as sBgScreenNarcIndices lists them",
     #Sub.LAYERS, 7)
  -- The members, in the cartridge's own order.
  local members = {}
  for i, layer in ipairs(Sub.LAYERS) do members[i] = layer.member end
  local want = { 0x31, 0x2A, 0x2F, 0x2B, 0x2C, 0x30, 0x2D }
  local same = true
  for i = 1, 7 do if members[i] ~= want[i] then same = false end end
  ok(same, "...in sBgScreenNarcIndices' order",
     table.concat(members, ","), table.concat(want, ","))

  local bgs = 0
  for _ in pairs(Sub.BACKGROUND_PALETTES) do bgs = bgs + 1 end
  ok(bgs == Sub.BACKGROUND_COUNT,
     "a palette pair for every non-Frontier background", bgs, Sub.BACKGROUND_COUNT)

  -- Five recolour and two do not, and which is which was MEASURED off the
  -- cells rather than chosen -- a layer recolours exactly when some cell of it
  -- names sub-palette 0.
  local recolour = 0
  for _, layer in ipairs(Sub.LAYERS) do
    if Sub.recolours(layer.name) then recolour = recolour + 1 end
  end
  ok(recolour == 5, "five layers follow the backdrop, two do not", recolour, 5)
  ok(not Sub.recolours("action") and not Sub.recolours("moves_idle"),
     "...and the action menu is NOT one of them",
     tostring(Sub.recolours("action")), "false")

  ok(Sub.WIDTH == 256 and Sub.HEIGHT == 192 and Sub.MAP_HEIGHT == 256,
     "the map is 256 tall and the screen shows 192",
     ("%dx%d of %d"):format(Sub.WIDTH, Sub.HEIGHT, Sub.MAP_HEIGHT),
     "256x192 of 256")

  -- THE ONE THAT MATTERS. Gen4Battle's ACTION_RECTS came out of
  -- battle_subscreen.c's touch table; the art came out of a tilemap in a
  -- different archive section. Both describe the same four buttons, so every
  -- rect has to lie inside the screen the art is drawn on.
  local outside = {}
  for name, r in pairs(Gen4Battle.ACTION_RECTS) do
    if r.left < 0 or r.right > Sub.WIDTH - 1
       or r.top < 0 or r.bottom > Sub.HEIGHT then
      outside[#outside + 1] = name
    end
  end
  for i, r in pairs(Gen4Battle.MOVE_RECTS) do
    if r.left < 0 or r.right > Sub.WIDTH - 1
       or r.top < 0 or r.bottom > Sub.HEIGHT then
      outside[#outside + 1] = "move" .. i
    end
  end
  ok(#outside == 0, "every touch rect lies on the screen the art draws",
     #outside == 0 and "all 8" or table.concat(outside, ","), "all 8")
end

-- ...and whether this cache has been through an import that writes them.
local sub = gfx.subscreen
if sub then
  local layers = 0
  for _ in pairs(sub.layers or {}) do layers = layers + 1 end
  ok(layers == 7, "all seven layers composed into the cache", layers, 7)
  local action = sub.layers and sub.layers.action
  ok(action and action.images and action.images[0] ~= nil,
     "...including the action menu's buttons",
     action and "yes" or "no", "yes")
else
  io.write("\nNOTE: this cache carries no subscreen art -- it was imported\n"
           .. "      before the stage that reads pl_batt_bg's tilemaps. The\n"
           .. "      battle menus stay on the engine's own boxes until the\n"
           .. "      next import.\n")
end


-- ---------------------------------------------------------------------------
-- THE TWO MENU PRESENTATIONS
--
-- The compact strip's COLUMNS are the cartridge's own -- the same numbers
-- sActionMenuTouchRects states -- and its ROWS are the port's, chosen so a
-- sixteen-pixel face fits inside a button. These check the derived half
-- against its source and the chosen half against the constraint it was chosen
-- for, which is the only honest way to test a number that was picked.
io.write("\nthe menu presentations\n")

if okSub then
  -- Every button's art has to lie inside the 256x192 screen it was cut from.
  local outside = {}
  for name, b in pairs(Sub.ACTION_BUTTONS) do
    if b.x < 0 or b.y < 0 or b.x + b.w > Sub.WIDTH or b.y + b.h > Sub.HEIGHT then
      outside[#outside + 1] = name
    end
  end
  for i, b in pairs(Sub.MOVE_BUTTONS) do
    if b.x < 0 or b.y < 0 or b.x + b.w > Sub.WIDTH or b.y + b.h > Sub.HEIGHT then
      outside[#outside + 1] = "move" .. i
    end
  end
  ok(#outside == 0, "every button's art lies inside the subscreen",
     #outside == 0 and "all 8" or table.concat(outside, ","), "all 8")

  -- A nine-slice needs two corners and something between them, in the SOURCE.
  local tooThick = {}
  for name, b in pairs(Sub.ACTION_BUTTONS) do
    if b.inset * 2 >= b.w or b.inset * 2 >= b.h then
      tooThick[#tooThick + 1] = name
    end
  end
  ok(#tooThick == 0, "every corner inset leaves a middle to stretch",
     #tooThick == 0 and "all" or table.concat(tooThick, ","), "all")
end

-- DERIVED: the compact columns ARE the touch rects' columns.
local mismatched = {}
for i, slot in ipairs(Gen4Battle.COMPACT_SLOTS) do
  local r = Gen4Battle.ACTION_RECTS[slot.art]
  if r then
    local w = r.right - r.left + 1
    -- FIGHT spans 0..255, which is 256 wide; the three small ones are 80 each
    -- and the rect's inclusive right edge makes them 81, so the column is
    -- compared on its LEFT and on the span the menu was written from.
    if slot.x ~= r.left or math.abs(slot.w - w) > 1 then
      mismatched[#mismatched + 1] =
        ("%s(%d,%d vs %d,%d)"):format(slot.art, slot.x, slot.w, r.left, w)
    end
  end
end
ok(#mismatched == 0, "the compact columns are the cartridge's own",
   #mismatched == 0 and "all 4" or table.concat(mismatched, ","), "all 4")

-- CHOSEN, and checked against the reason it was chosen: a button has to hold a
-- line of the dialogue face, which is sixteen pixels.
local FACE = 16
local tooShort = {}
for i = 1, 4 do
  local _, _, _, h = Gen4Battle.compactButtonRect(i)
  if h < FACE + 4 then tooShort[#tooShort + 1] = "action" .. i end
  local _, _, _, mh = Gen4Battle.compactMoveRect(i)
  if mh < FACE + 4 then tooShort[#tooShort + 1] = "move" .. i end
end
ok(#tooShort == 0, "every compact button holds a 16-pixel line",
   #tooShort == 0 and "all 8" or table.concat(tooShort, ","), "all 8")

-- ...and inside the screen, and clear of the message box.
local S, M = Gen4Battle.STRIP, Gen4Battle.MOVE_STRIP
ok(S.y + S.h == 192 and S.x == 0 and S.w == 256,
   "the action strip is the bottom of the screen",
   ("%d,%d %dx%d"):format(S.x, S.y, S.w, S.h), "0,128 256x64")
ok(M.y + M.h == Gen4Battle.MESSAGE_BOX.ty * 8,
   "the move strip's bottom meets the message box's top",
   M.y + M.h, Gen4Battle.MESSAGE_BOX.ty * 8)

local spill = {}
for i = 1, 4 do
  local x, y, w, h = Gen4Battle.compactButtonRect(i)
  if x < S.x or y < S.y or x + w > S.x + S.w or y + h > S.y + S.h then
    spill[#spill + 1] = "action" .. i
  end
  local mx, my, mw, mh = Gen4Battle.compactMoveRect(i)
  if mx < M.x or my < M.y or mx + mw > M.x + M.w or my + mh > M.y + M.h then
    spill[#spill + 1] = "move" .. i
  end
end
ok(#spill == 0, "no compact button spills out of its strip",
   #spill == 0 and "all 8" or table.concat(spill, ","), "all 8")

-- The four slots name four DIFFERENT pieces of art; naming one twice would
-- draw two identical buttons and look like a data error rather than a bug.
local seen, dupes = {}, 0
for _, slot in ipairs(Gen4Battle.COMPACT_SLOTS) do
  if seen[slot.art] then dupes = dupes + 1 end
  seen[slot.art] = true
end
ok(dupes == 0 and #Gen4Battle.COMPACT_SLOTS == 4,
   "four slots, four different buttons", #Gen4Battle.COMPACT_SLOTS - dupes, 4)


-- ---------------------------------------------------------------------------
-- PUTTING THE BOTTOM SCREEN AWAY
--
-- `raised` and `stowed` answer DIFFERENT questions and the checks exist
-- because folding them cost a real bug: `raised` is transient and belongs to
-- whatever is on the bottom surface right now (the Poketch sets it on open and
-- clears it on close), so a player who had looked at the Poketch once left it
-- false behind them and every battle afterwards came up stowed.
io.write("\nthe bottom screen\n")

local okSS, SS = pcall(require, "src.ui.SecondScreen")
if not okSS then
  io.write("  (src/ui/SecondScreen.lua did not load -- skipped)\n")
else
  ok(type(SS.stowed) == "function" and type(SS.toggleStow) == "function"
     and type(SS.raised) == "function",
     "raised and stowed are both asked, and separately",
     (type(SS.stowed) == "function" and "both" or "one"), "both")

  -- A cartridge with no second surface is stowed by definition, which is what
  -- keeps every Gen 1-3 battle on the path it has always had.
  local none = { save = { options = { secondScreenMode = "off" } },
                 data = {} }
  ok(SS.stowed(none) == true, "`off` means stowed, so Gen 1-3 never changes",
     tostring(SS.stowed(none)), "true")
  ok(SS.stow(none, false) == true, "...and cannot be un-stowed",
     tostring(SS.stow(none, false)), "true")

  -- On a cartridge that HAS one, the default is up -- a DS's bottom screen is
  -- on until you put it away.
  local ds = { save = { options = { secondScreenMode = "swap" } },
               data = { isGen4Cache = true } }
  ok(SS.stowed(ds) == false, "a second screen starts UP, not away",
     tostring(SS.stowed(ds)), "false")
  SS.toggleStow(ds)
  ok(SS.stowed(ds) == true, "...L puts it away", tostring(SS.stowed(ds)), "true")
  SS.toggleStow(ds)
  ok(SS.stowed(ds) == false, "...and brings it back",
     tostring(SS.stowed(ds)), "false")

  -- THE PREFERENCE IS IN THE SAVE, NOT ON THE SESSION. A choice the player
  -- made about how the game looks should survive closing it; `raised` should
  -- not, and does not.
  SS.toggleStow(ds)
  ok(ds.save.options.secondScreenStowed == true
     and ds.secondScreenStowed == nil,
     "the choice is saved, not left on the session",
     tostring(ds.save.options.secondScreenStowed), "true")
  -- ...and toggling the stow must not disturb the Poketch's own flag.
  ok(ds.secondScreenUp == nil,
     "...and it never touches the Poketch's transient flag",
     tostring(ds.secondScreenUp), "nil")
end


-- ---------------------------------------------------------------------------
-- THE WORDS ON A HEALTHBOX
--
-- The name rect used to be the VRAM's -- 8x2 blocks from tile 0 -- and the
-- assembled picture is the CELL BANK's arrangement of that data, which is not
-- the same grid. Drawing at the picture's (0,0) put the name on the box's tail,
-- and on the foe's box that hangs off the left of the SCREEN. These assert the
-- measured rects instead.
io.write("\nthe healthbox lettering\n")

local P = Gen4Battle.HEALTHBOX_PANEL
local panels = 0
for _ in pairs(P) do panels = panels + 1 end
ok(panels == 3, "a measured name panel for each of the three boxes", panels, 3)

local outside, onBar = {}, {}
for key, r in pairs(P) do
  if r.x < 0 or r.y < 0 or r.x + r.w > 128 or r.y + r.h > 64 then
    outside[#outside + 1] = key
  end
  -- The brown trough runs y 31..38 in every box, so a name panel that reached
  -- it would print the level over the HP bar.
  if r.y + r.h > 31 then onBar[#onBar + 1] = key end
end
ok(#outside == 0, "every name panel is inside its 128x64 box",
   #outside == 0 and "all 3" or table.concat(outside, ","), "all 3")
ok(#onBar == 0, "...and stops above the HP trough at y31",
   #onBar == 0 and "all 3" or table.concat(onBar, ","), "all 3")

-- Every box the screen draws needs one, or its name falls back to the VRAM
-- rect and goes off the edge again.
local unmeasured = {}
for _, side in pairs(Gen4Battle.HEALTHBOX_ART) do
  if not P[side.key] then unmeasured[#unmeasured + 1] = side.key end
end
ok(#unmeasured == 0, "every box the screen draws has one",
   #unmeasured == 0 and "all" or table.concat(unmeasured, ","), "all")

local B = Gen4Battle.HEALTHBOX_HP_TEXT
ok(B.y > 38 and B.y + B.h < 50,
   "the HP numbers sit between the trough and the EXP groove",
   ("%d..%d"):format(B.y, B.y + B.h), "39..48")
-- NINE ROWS is the measurement that says these cannot be dialogue text: the
-- system face is sixteen tall, and the cartridge blits digit TILES here.
ok(B.h < 16, "...in a band too short for the face, as the cartridge's is",
   B.h, "< 16")


-- ---------------------------------------------------------------------------
-- WHICH MENU THE PLAYER ACTUALLY GETS
--
-- Reported from play: "its still showing the large second screen options when i
-- have it turned off rather than the ones we planned". The decision lived
-- inline in drawTextArea, so the one thing a player can get wrong could only be
-- checked by playing. It is `Gen4Battle.menuPresentation` now, and this walks
-- EVERY combination of the two settings and the one cache fact.
io.write("\nwhich menu the player gets\n")

-- A battle stub thin enough to drive the decision and nothing else. The cache
-- fact is `subscreen` in gen4_graphics, which is what hasSubscreenArt asks for.
local function battleWith(mode, stowed, art)
  local layers = art and { action = { images = { [0] = "x.png" } } } or nil
  return {
    phase = "menu",
    game = { save = { options = { secondScreenMode = mode,
                                  secondScreenStowed = stowed or nil } },
             data = { isGen4Cache = true,
                      gen4_graphics = layers and { subscreen =
                        { layers = layers } } or {} } },
    data = { gen4_graphics = layers and { subscreen = { layers = layers } } or {} },
  }
end

local CASES = {
  -- mode      stowed  art     expected
  { "swap",    false,  true,   "bottom" },
  { "swap",    true,   true,   "compact" },
  { "inset",   false,  true,   "bottom" },
  { "inset",   true,   true,   "compact" },
  { "off",     false,  true,   "compact" },
  { "off",     true,   true,   "compact" },
  -- ...and with no subscreen art in the cache, anything that is not the
  -- bottom screen has to fall to the words rather than draw nothing.
  { "swap",    true,   false,  "words" },
  { "off",     false,  false,  "words" },
  { "swap",    false,  false,  "bottom" },
}
local wrong = {}
for _, c in ipairs(CASES) do
  local got = Gen4Battle.menuPresentation(battleWith(c[1], c[2], c[3]), "menu")
  if got ~= c[4] then
    wrong[#wrong + 1] = ("%s/%s/%s -> %s not %s")
      :format(c[1], tostring(c[2]), tostring(c[3]), tostring(got), c[4])
  end
end
ok(#wrong == 0, "every setting lands on the presentation it names",
   #wrong == 0 and (#CASES .. " cases") or table.concat(wrong, " | "),
   #CASES .. " cases")

-- THE ONE THE REPORT IS ABOUT, asserted on its own so a failure names itself
-- rather than being one of nine.
local off = Gen4Battle.menuPresentation(battleWith("off", false, true), "menu")
ok(off == "compact", "`2ND SCREEN: OFF` gives the strip, never the big one",
   tostring(off), "compact")
local away = Gen4Battle.menuPresentation(battleWith("swap", true, true), "menu")
ok(away == "compact", "...and so does putting it away with L",
   tostring(away), "compact")

-- No menu, no presentation -- which is what tells drawTextArea to put the
-- message box down and stop.
local none = Gen4Battle.menuPresentation(battleWith("swap", false, true),
                                         "messages")
ok(none == nil, "a phase with no menu asks for no menu", tostring(none), "nil")

io.write("\nthe numbers on a healthbox\n")

local Parts = require("src.import.Gen4HealthboxParts")
local Chars = require("src.import.Gen4SpecialChars")

-- THE GLYPH STRIP, against its own source rather than against itself.
ok(Chars.COUNT == 23, "the strip is 23 glyphs", Chars.COUNT, 23)
ok(Chars.GLYPHS.slash.at == 10 and Chars.GLYPHS.level.at == 11
   and Chars.GLYPHS.number.at == 13 and Chars.GLYPHS.id.at == 15,
   "...laid out where sNonNumericWidths says",
   ("/%d Lv%d No%d ID%d"):format(Chars.GLYPHS.slash.at, Chars.GLYPHS.level.at,
                                 Chars.GLYPHS.number.at, Chars.GLYPHS.id.at),
   "/10 Lv11 No13 ID15")
-- The three words are two tiles each and the slash is one: that is what makes
-- the digits end at tile 9 and the first named glyph start at 10.
ok(Chars.GLYPHS.level.at == Chars.GLYPHS.slash.at + Chars.GLYPHS.slash.tiles,
   "...with no gap between the slash and the first word",
   Chars.GLYPHS.level.at, Chars.GLYPHS.slash.at + Chars.GLYPHS.slash.tiles)
ok(Chars.DIGITS == 10 and Chars.DIGIT_0 == 0,
   "the ten digits come first, which is what indexing them needs",
   ("%d from %d"):format(Chars.DIGITS, Chars.DIGIT_0), "10 from 0")
-- ROLE_TILES is the discriminator the extractor uses to refuse a repacked
-- archive, so it has to stop BEFORE the three unused Lv variants -- they are
-- the only tiles in the strip that use a nibble above 2.
ok(Chars.ROLE_TILES == Chars.GLYPHS.id.at + Chars.GLYPHS.id.tiles,
   "...and the role test covers exactly the glyphs that are roles",
   Chars.ROLE_TILES, Chars.GLYPHS.id.at + Chars.GLYPHS.id.tiles)

-- rolePalette against a synthetic palette, so the two indices cannot be
-- swapped without the check noticing: entry 2 is the FOREGROUND.
local fake = {}
for i = 1, 16 do fake[i] = { i - 1, i - 1, i - 1 } end
local roles = Chars.rolePalette(fake)
ok(roles and roles[2] and roles[2][1] == Chars.BATTLE_FG,
   "the strip's value 1 takes the caller's foreground",
   roles and roles[2] and roles[2][1] or "nil", Chars.BATTLE_FG)
ok(roles and roles[3] and roles[3][1] == Chars.BATTLE_SHADOW,
   "...and its value 2 the shadow",
   roles and roles[3] and roles[3][1] or "nil", Chars.BATTLE_SHADOW)
ok(Chars.BATTLE_FG ~= Chars.BATTLE_SHADOW and Chars.BATTLE_BG ~= Chars.BATTLE_FG,
   "...and the three roles are three different colours",
   ("%d/%d/%d"):format(Chars.BATTLE_FG, Chars.BATTLE_SHADOW, Chars.BATTLE_BG),
   "distinct")

-- THE GENDERED "Lv" IS THE PART THE ENUM NAMES.  Asserted against the enum by
-- NAME, so a part inserted anywhere in the blob moves both together or fails.
local partIndex = {}
for i, name in ipairs(Parts.PARTS) do partIndex[name] = i - 1 end
local wrongParts = {}
for gender, pair in pairs(Gen4Battle.LEVEL_PARTS) do
  local want = (gender == "none") and "genderless" or gender
  if partIndex["level_" .. want .. "_top_0"] ~= pair.top then
    wrongParts[#wrongParts + 1] = gender .. " top"
  end
  if partIndex["level_" .. want .. "_bottom_0"] ~= pair.bottom then
    wrongParts[#wrongParts + 1] = gender .. " bottom"
  end
end
ok(#wrongParts == 0, "every gendered Lv block names its own enum part",
   #wrongParts == 0 and "3 genders" or table.concat(wrongParts, ", "),
   "3 genders")

-- WHERE THE NUMBERS SIT, re-derived against the panel rather than restated.
local NUM = Gen4Battle.HEALTHBOX_NUM_CELLS
ok(NUM == 3, "every number is three columns, which is what the calls pass",
   NUM, 3)

local badLevel = {}
for key, lv in pairs(Gen4Battle.HEALTHBOX_LV) do
  local num = Gen4Battle.HEALTHBOX_LEVEL_NUM[key]
  local panel = Gen4Battle.HEALTHBOX_PANEL[key]
  if not (num and panel) then
    badLevel[#badLevel + 1] = key .. " has no pair"
  else
    -- the digits start where the 16-wide Lv block ends
    if num.x ~= lv.x + 16 then badLevel[#badLevel + 1] = key .. " x" end
    -- ...four rows down from it, because the glyph straddles the tile boundary
    if num.y ~= lv.y + 4 then badLevel[#badLevel + 1] = key .. " y" end
    -- ...and the three columns end inside the green panel measured off the art
    if num.x + NUM * 8 > panel.x + panel.w + 1 then
      badLevel[#badLevel + 1] = key .. " overruns the panel"
    end
    if lv.x < panel.x then badLevel[#badLevel + 1] = key .. " Lv before panel" end
  end
end
ok(#badLevel == 0, "the level block fits the panel on all three boxes",
   #badLevel == 0 and "3 boxes" or table.concat(badLevel, ", "), "3 boxes")

-- THE SLASH IS THE GAP.  It is baked into the box art at x 88..95 because it
-- never changes; the numbers are not, because they do.  So the two number
-- fields must leave EXACTLY one eight-pixel column between them.
local badHP = {}
for key, now in pairs(Gen4Battle.HEALTHBOX_HP_NOW) do
  local max = Gen4Battle.HEALTHBOX_HP_MAX[key]
  if not max then badHP[#badHP + 1] = key .. " has no max"
  else
    if now.x + NUM * 8 + 8 ~= max.x then badHP[#badHP + 1] = key .. " gap" end
    if now.y ~= max.y then badHP[#badHP + 1] = key .. " rows differ" end
  end
end
ok(#badHP == 0, "current and max HP leave exactly one column for the slash",
   #badHP == 0 and "2 boxes" or table.concat(badHP, ", "), "2 boxes")

-- ...and the solo box's row lands in the nine-row band this file already
-- measured off the art, for a different reason, before any of this existed.
local band = Gen4Battle.HEALTHBOX_HP_TEXT
local solo = Gen4Battle.HEALTHBOX_HP_NOW.healthbox_player_singles
ok(solo and solo.y >= band.y and solo.y + 8 <= band.y + band.h,
   "...inside the band measured off the art",
   solo and ("%d..%d in %d..%d"):format(solo.y, solo.y + 8,
                                        band.y, band.y + band.h) or "nil",
   "inside")

-- ALIGNMENT, which is the whole of CharCode_FromInt and the only thing that
-- decides whether the numbers sit against the slash or away from it.
local cells = Gen4Battle.numberCells
local function shape(value, pad)
  local out = cells(value, NUM, pad)
  local s = {}
  for i = 1, #out do s[i] = out[i] and tostring(out[i]) or "_" end
  return table.concat(s)
end
ok(shape(47, "none") == "47", "PADDING_MODE_NONE is left-justified and short",
   shape(47, "none"), "47")
ok(shape(68, "spaces") == "_68", "PADDING_MODE_SPACES is right-justified",
   shape(68, "spaces"), "_68")
ok(shape(0, "none") == "0", "a zero is a digit, not a blank",
   shape(0, "none"), "0")
ok(shape(142, "none") == "142" and shape(142, "spaces") == "142",
   "...and a full-width number is the same either way",
   shape(142, "none") .. "/" .. shape(142, "spaces"), "142/142")
-- CHAR_WIDE_QUESTION is not one of CHAR_WIDE_0..9 and the drawer fills a
-- non-digit with the background, so an over-wide number loses its leading
-- column rather than drawing a glyph this strip does not have.
ok(shape(1234, "spaces") == "_34", "a number too wide for the field blanks",
   shape(1234, "spaces"), "_34")
-- THE CANARY: the two padding modes must not agree, or every line above would
-- pass with one of them wired to the other.
ok(shape(7, "none") ~= shape(7, "spaces"),
   "...and the two padding modes are still two",
   shape(7, "none") .. " vs " .. shape(7, "spaces"), "different")

local Scene = Gen4Battle

-- ------------------------------------------ the strip, and what it sits under --

io.write("\nthe action menu's strip\n")

-- REPORTED FROM PLAY: *"this is a little too tall, it should sit under the
-- players pokemon hp hud"*. The strip was y 128..192 and the player's solo
-- healthbox is 128x64 at (128, 84) -- twenty pixels of overlap, with the FIGHT
-- button across the bottom of the box.
--
-- Asserted as the RELATIONSHIP rather than as the number, because the number on
-- its own cannot be wrong in a way anyone notices: what matters is that the
-- strip starts below the box and ends at the foot of the screen.
local S = Scene.STRIP
local boxPos = Scene.HEALTHBOX_POS[0]
local boxArt = Scene.HEALTHBOX_ART.player
local boxTop = boxPos.y + boxArt.oy
local boxBottom = boxTop + Scene.HEALTHBOX_SIZE.h

ok(S.y + S.h == Scene.HEIGHT, "the strip ends at the foot of the screen",
   S.y + S.h, Scene.HEIGHT)
ok(S.w == Scene.WIDTH and S.x == 0, "...and spans its whole width",
   S.x .. "+" .. S.w, "0+" .. Scene.WIDTH)
ok(S.y >= Scene.MESSAGE_TEXT.y - 8,
   "...and starts no higher than Platinum's own message band",
   S.y, ">= " .. (Scene.MESSAGE_TEXT.y - 8))
-- The box art is 64 tall and its plaque is not; the opaque rows measured off
-- the assembled picture are 11..52, so the plaque ends 12 pixels above the
-- art's own bottom edge. Stated as the art's extent, which is the thing a
-- future edit would move.
ok(S.y >= boxBottom - 16,
   "the strip clears the player's healthbox plaque",
   ("strip %d vs box art %d..%d"):format(S.y, boxTop, boxBottom),
   ">= " .. (boxBottom - 16))
-- TWO ROWS, and each has to hold a line of Platinum's message face (16px).
ok(S.h / 2 >= Scene.MESSAGE_LINE_H, "each of its two rows holds a line of text",
   S.h / 2, ">= " .. Scene.MESSAGE_LINE_H)

-- --------------------------------------------- moving between the four buttons --

io.write("\nthe d-pad over Platinum's 1+3 action menu\n")

-- REPORTED FROM PLAY: *"im not able to smoothly select the options by hitting
-- up down left or right"*. BattleState walks the action menu as a 2x2, which is
-- right for every older game here and is not what Platinum draws --
-- `sBattleMenuButtonLayout[2][3] = { {0,0,0}, {1,3,2} }` is FIGHT across the
-- top and ITEM, RUN, PARTY beneath.
local bottom = Scene.ACTION_BOTTOM
ok(#bottom == 3, "three buttons on the bottom row", #bottom, 3)
-- THE DRAWN ORDER AND THE WALKED ORDER ARE THE SAME LIST, which is the whole
-- point: ACTION_GRID is transcribed from the cartridge and ACTION_BOTTOM is
-- what the d-pad walks, so they have to agree or the cursor moves through a
-- layout nobody can see.
local grid = Scene.ACTION_GRID[2]
local slotArt = {}
for i, slot in ipairs(Scene.COMPACT_SLOTS) do slotArt[i] = slot.art end
local agree = true
for c = 1, 3 do
  if slotArt[bottom[c]] ~= grid[c] then agree = false end
end
ok(agree, "...in the same order the cartridge's grid names them",
   (agree and "item/run/party" or "mismatched"), "item/run/party")
ok(slotArt[Scene.ACTION_TOP] == Scene.ACTION_GRID[1][1],
   "...and FIGHT is the one that spans the top row",
   tostring(slotArt[Scene.ACTION_TOP]), Scene.ACTION_GRID[1][1])

local function walk(i, c, ...)
  for _, dir in ipairs({ ... }) do i, c = Scene.actionMove(i, dir, c) end
  return i, c
end
ok(select(1, walk(Scene.ACTION_TOP, 1, "left")) == Scene.ACTION_TOP
   and select(1, walk(Scene.ACTION_TOP, 1, "right")) == Scene.ACTION_TOP,
   "left and right do nothing on FIGHT, which spans the row",
   "held", "held")
local a = select(1, walk(bottom[1], 1, "right", "right", "right"))
ok(a == bottom[3], "right clamps at PARTY rather than wrapping",
   tostring(a), tostring(bottom[3]))
local b = select(1, walk(bottom[3], 3, "left", "left", "left"))
ok(b == bottom[1], "...and left clamps at ITEM", tostring(b), tostring(bottom[1]))
local ups = 0
for c = 1, 3 do
  if select(1, walk(bottom[c], c, "up")) == Scene.ACTION_TOP then ups = ups + 1 end
end
ok(ups == 3, "up returns to FIGHT from any of the three", ups .. "/3", "3/3")
-- THE REMEMBERED COLUMN IS WHAT MAKES IT SMOOTH, and it is the one rule here
-- that is the port's own: FIGHT spans all three columns, so "down" out of it
-- has no single answer, and snapping to an end would make up-then-down move the
-- player. Asserted for all three so a fix that only kept the middle still fails.
local round = 0
for c = 1, 3 do
  if select(1, walk(bottom[c], c, "up", "down")) == bottom[c] then
    round = round + 1
  end
end
ok(round == 3, "...and down again returns to the button you left",
   round .. "/3", "3/3")

-- ---------------------------------------------------------------------------
-- THE SLIDE COUNTER RUNS THE OTHER WAY FROM THE SLIDE POSITION.
--
-- `platformAt` takes steps ELAPSED; `BattleState.introSlide` is frames
-- REMAINING, set to `Timing.BATTLE_SLIDE_IN_FRAMES` and counted down to 0.
-- `platformSlideElapsed` is the only place those two meet, and this section is
-- the claim that it converts rather than merely passing the number along.
--
-- Reported from play: "the locations of the land the pokemon are on in battle
-- still arent right".  The counter was going in raw, so a SETTLED battle --
-- introSlide 0, which is every frame after the first 72 and every frame of a
-- resumed save -- asked for step 0 and got both platforms parked where they
-- BEGIN: the player's 256-wide slab centred at 336 (only x 208..256 on
-- screen, the sliver in the bottom-right corner) and the foe's at -80
-- (-144..-16, entirely off the left edge, so the foe stood on nothing).
--
-- THE FIRST CHECK BELOW IS THE ONE THAT WOULD HAVE CAUGHT IT: a platform at
-- rest has to be on screen.  Everything after it pins down the direction, so a
-- fix that merely clamped both ends would still fail.
-- ---------------------------------------------------------------------------
do
  local INTRO = 72   -- Timing.BATTLE_SLIDE_IN_FRAMES, stated here rather than
                     -- required so this tool stays loadable without src/core
  local W = Gen4Battle.WIDTH
  local function at(frames, side)
    local battle = frames and { introSlide = frames } or nil
    local x = Gen4Battle.platformAt(
      side, Gen4Battle.platformSlideElapsed(battle, side))
    return x, Gen4Battle.PLATFORM_SIZE[side].w
  end

  for _, side in ipairs({ "player", "enemy" }) do
    local settled = Gen4Battle.PLATFORM_POS[side].x
    -- at rest: on screen, and exactly where battle_display puts it
    local x, w = at(0, side)
    ok(x + w / 2 > 0 and x - w / 2 < W,
       ("%s platform at rest overlaps the screen"):format(side),
       ("centre %d, span %d..%d"):format(x, x - w / 2, x + w / 2),
       ("some part within 0..%d"):format(W))
    ok(x == settled, ("%s platform at rest is at its settled x"):format(side),
       x, settled)
    -- NO COUNTER AT ALL IS SETTLED, NOT STEP ZERO.  A headless caller, a save
    -- resumed mid-battle and every frame after the intro all arrive here, and
    -- reading "absent" as "has not started moving" is the same bug in a
    -- different doorway.
    ok(at(nil, side) == settled,
       ("%s platform with no intro counter is settled"):format(side),
       at(nil, side), settled)
    -- the first frame of the intro is the off-screen start
    ok(at(INTRO, side) == Gen4Battle.PLATFORM_START[side],
       ("%s platform on the intro's first frame is off-screen"):format(side),
       at(INTRO, side), Gen4Battle.PLATFORM_START[side])
    -- ...and it closes on the slot without ever backing up.  Monotone is the
    -- strong form of "the right direction": an off-by-one in the conversion
    -- shows up as a step backwards, not as a wrong endpoint.
    local prev, backs = nil, 0
    for f = INTRO, 0, -1 do
      local d = math.abs(at(f, side) - settled)
      if prev and d > prev then backs = backs + 1 end
      prev = d
    end
    ok(backs == 0,
       ("%s platform never moves away from its slot"):format(side),
       backs .. " backward steps", "0")
  end

  -- both sides are the same distance out at the same moment, which is the
  -- symmetry check 9 asserts for the endpoints, now asserted for the walk
  local ph = math.abs(at(INTRO // 2, "player") - Gen4Battle.PLATFORM_POS.player.x)
  local eh = math.abs(at(INTRO // 2, "enemy") - Gen4Battle.PLATFORM_POS.enemy.x)
  ok(ph == eh, "both platforms are equally far out mid-intro",
     ("player %d, enemy %d"):format(ph, eh), "equal")

  -- and the shape of the bug itself, so this section cannot pass vacuously if
  -- `platformSlideElapsed` is ever quietly turned back into the identity
  local rawZero = Gen4Battle.platformAt("player", 0)
  ok(rawZero ~= Gen4Battle.PLATFORM_POS.player.x
     and at(0, "player") ~= rawZero,
     "the raw counter and the converted one really differ at rest",
     ("raw %d, converted %d"):format(rawZero, at(0, "player")), "different")
end

-- ---------------------------------------------------------------------------
-- THE TYPE SYSTEM, WHICH IS WHAT MADE A PERFECTLY DECODED MOVE DO NOTHING.
--
-- Reported from play: "moves dont seem to be decoded and working properly
-- scratch doesnt work".  Scratch decodes exactly right -- power 40, pp 35,
-- accuracy 100, physical, effect 0, typeId 0 -- and still did nothing, because
-- nothing downstream could read its TYPE: the move table carried only a
-- numeric `typeId`, the species table spelled its types in lower case, and
-- `Gen4TypeChart.chart` returned a shape the battle engine could not index.
-- Three spellings of the same eighteen words, none of which met.
--
-- These checks are on the module rather than the cache, so they hold before
-- the next import as well as after it: the ONE spelling is `Gen4TypeChart.TYPES`
-- and everything else has to come from there.
-- ---------------------------------------------------------------------------
do
  local TC = require("src.import.Gen4TypeChart")
  local Species = require("src.import.Gen4Species")
  local Moves = require("src.import.Gen4Moves")

  -- 0-BASED AND UPPER CASE, and the two ends of the list rather than one, so a
  -- table that slipped by one is caught at the far end as well as the near.
  ok(type(TC.TYPES) == "table" and TC.TYPES[0] == "NORMAL"
     and TC.TYPES[17] == "DARK",
     "Gen4TypeChart.TYPES is 0-based and UPPER CASE",
     tostring(TC.TYPES and TC.TYPES[0]) .. ".." .. tostring(TC.TYPES and TC.TYPES[17]),
     "NORMAL..DARK")
  ok(TC.TYPE_COUNT == 18 and TC.TYPES[18] == nil,
     "...eighteen of them and no nineteenth", TC.TYPE_COUNT, 18)
  -- SLOT 9 IS THE TRAP.  Gen 2's "bird" type left a hole between STEEL and
  -- FIRE that nothing in the cartridge uses, and every id from FIRE up is one
  -- higher than the eighteen-name list a reader expects.  I wrote WATER at 10
  -- from memory while writing this very check, and it is 11; asserting the
  -- hole is what makes the next reader not repeat it.
  ok(TC.TYPES[8] == "STEEL" and TC.TYPES[9] == "MYSTERY"
     and TC.TYPES[10] == "FIRE" and TC.TYPES[11] == "WATER",
     "the unused slot 9 sits between STEEL and FIRE",
     ("%s/%s/%s/%s"):format(tostring(TC.TYPES[8]), tostring(TC.TYPES[9]),
                            tostring(TC.TYPES[10]), tostring(TC.TYPES[11])),
     "STEEL/MYSTERY/FIRE/WATER")

  -- ONE TABLE, NOT THREE.  Identity, not equality: a second list that happens
  -- to agree today is exactly how the three spellings drifted apart before.
  ok(Species.TYPES == TC.TYPES,
     "Gen4Species reads the chart's own TYPES table",
     tostring(Species.TYPES == TC.TYPES), "true")

  -- The pre-Gen-4 split by type ID, which Platinum itself does not use -- every
  -- Gen 4 move carries its own `class` -- and which `Damage.lua` still reaches
  -- for when a move has neither, i.e. a mod's move or a damaged cache.  FIRE is
  -- the first special type, so the boundary is 10 and NOT at WATER.
  ok(TC.SPECIAL_FROM == 10 and TC.TYPES[TC.SPECIAL_FROM] == "FIRE",
     "the fallback split starts at FIRE",
     ("%d = %s"):format(TC.SPECIAL_FROM, tostring(TC.TYPES[TC.SPECIAL_FROM])),
     "10 = FIRE")

  -- `chart()` has to return something indexable BY NAME, which is the shape
  -- the battle engine asks for; the old one returned rows only.
  -- Ids, not names, because that is what the ROM hands the parser: 0 NORMAL,
  -- 7 GHOST, 10 FIRE, 11 WATER.
  local parsed = {
    overlay = 0,
    rows = { { 0, 7, 0 }, { 11, 10, 20 }, { 10, 11, 5 } },
    foresightFrom = nil,
  }
  local c = TC.chart(parsed)
  ok(c and c.types and c.types.NORMAL and c.types.WATER,
     "chart() returns types indexed by NAME",
     c and c.types and tostring(c.types.NORMAL and c.types.NORMAL.name),
     "NORMAL")
  ok(c and c.types.NORMAL.category == "physical"
     and c.types.WATER.category == "special",
     "...each carrying its damage category",
     c and (tostring(c.types.NORMAL.category) .. "/"
            .. tostring(c.types.WATER.category)),
     "physical/special")
  ok(c and c.ids and c.ids.NORMAL == 0 and c.ids.WATER == 11
     and c.ids.DARK == 17,
     "...and the reverse name -> id lookup, hole included",
     c and (("%s/%s/%s"):format(tostring(c.ids.NORMAL), tostring(c.ids.WATER),
                                tostring(c.ids.DARK))), "0/11/17")
  ok(c and #c.matchups == 3
     and c.matchups[1].attacker == "NORMAL"
     and c.matchups[1].defender == "GHOST"
     and c.matchups[1].multiplier == 0,
     "matchups are named on both sides",
     c and (("%s vs %s = %s"):format(tostring(c.matchups[1].attacker),
            tostring(c.matchups[1].defender),
            tostring(c.matchups[1].multiplier))),
     "NORMAL vs GHOST = 0")
  -- ...and the pair that proves the ids were read the right way round rather
  -- than symmetrically: Water beats Fire, Fire does not beat Water.
  ok(c and c.matchups[2].attacker == "WATER" and c.matchups[2].defender == "FIRE"
     and c.matchups[2].multiplier == 20
     and c.matchups[3].attacker == "FIRE" and c.matchups[3].defender == "WATER"
     and c.matchups[3].multiplier == 5,
     "...and the pair is not symmetric",
     c and (("%s>%s=%s, %s>%s=%s"):format(
       tostring(c.matchups[2].attacker), tostring(c.matchups[2].defender),
       tostring(c.matchups[2].multiplier), tostring(c.matchups[3].attacker),
       tostring(c.matchups[3].defender), tostring(c.matchups[3].multiplier))),
     "WATER>FIRE=20, FIRE>WATER=5")

  -- and the move table hands out a NAME beside the id, because a battler that
  -- only has the number is where this started
  ok(type(Moves.record) == "function" or type(Moves.parse) == "function"
     or type(Moves.decode) == "function",
     "Gen4Moves still exposes its decoder", "yes", "yes")

  -- If the cache has been rebuilt since the extractor change, hold it to the
  -- ROM's own numbers.  Skipped rather than failed when it has not, so this
  -- tool stays runnable against an older cache.
  local rom = load("gen4_type_chart")
  if rom and rom.matchups then
    local by = {}
    for _, m in ipairs(rom.matchups) do
      by[(m.attacker or "?") .. ">" .. (m.defender or "?")] = m.multiplier
    end
    local WANT = {
      { "NORMAL", "GHOST", 0 }, { "WATER", "FIRE", 20 },
      { "FIRE", "WATER", 5 },   { "GRASS", "WATER", 20 },
      { "ELECTRIC", "GROUND", 0 }, { "NORMAL", "ROCK", 5 },
    }
    local bad = {}
    for _, w in ipairs(WANT) do
      local got = by[w[1] .. ">" .. w[2]]
      if got ~= w[3] then
        bad[#bad + 1] = ("%s>%s=%s"):format(w[1], w[2], tostring(got))
      end
    end
    ok(#bad == 0, "cached chart matches the ROM's own matchups",
       #bad == 0 and "all 6" or table.concat(bad, " "), "all 6")
    ok(#rom.matchups == 110, "the cartridge's chart is 110 rows long",
       #rom.matchups, 110)
  else
    io.write("  --    cached type chart absent; re-import to check it\n")
  end
end

-- ---------------------------------------------------------------------------
-- WHERE A TILEMAP'S CELLS LAND, which is what made the backdrop a stack of
-- chopped strips.
--
-- The DS lays background screen data out in 32x32-ENTRY BLOCKS, one per
-- 256x256 pixels, in reading order. A 512x256 map is TWO blocks side by side,
-- so its first 1024 cells are the WHOLE LEFT HALF -- not the top two rows of
-- the full width. `Gen4Graphics.compose` read it as one 64-wide grid, which
-- interleaves the halves every 32 cells.
--
-- Reported from play: the battle backdrop drew "flat horizontal bands with a
-- black stripe through the middle". The bands are Platinum's own art -- an
-- outdoor backdrop IS a sky-to-ground gradient -- but the STRIPE was the
-- transparent bottom of each half landing in the middle of the picture.
--
-- The checks below drive `compose` with a sheet whose tile n paints the
-- constant value n, so reading a pixel back says WHICH TILE landed there. A
-- digest that only asked which pixels were opaque could not tell the two
-- layouts apart -- the same cells are opaque either way -- and would have been
-- a measurement that cannot fail.
-- ---------------------------------------------------------------------------
do
  local Gfx = require("src.import.Gen4Graphics")

  -- tile n is 64 bytes of value (n % 255) + 1, so a pixel reads back as a tile
  local parts = {}
  for n = 0, 4095 do parts[n + 1] = string.rep(string.char((n % 255) + 1), 64) end
  local sheet = { bpp = 8, perTile = 64, count = 4096,
                  pixels = table.concat(parts) }
  local pal = {}
  for i = 1, 256 do pal[i] = { i - 1, 0, 0 } end

  -- a map of `cells` cells where cell i holds tile i
  local function mapOf(w, h)
    local cells = {}
    for i = 1, (w / 8) * (h / 8) do
      cells[i] = { tile = i - 1, flipX = false, flipY = false, palette = 0 }
    end
    return { width = w, height = h, cells = cells }
  end
  -- which tile is at pixel (x, y), or nil where nothing was drawn
  local function tileAt(img, x, y)
    local o = (y * img.width + x) * 4
    if img.rgba:byte(o + 4) == 0 then return nil end
    return img.rgba:byte(o + 1)
  end

  -- 512x256: cell 1024 opens the RIGHT half, not row 128
  local wide = Gfx.compose(mapOf(512, 256), sheet, pal)
  ok(wide and wide.width == 512 and wide.height == 256,
     "a 512x256 tilemap composes at its stated size",
     wide and (wide.width .. "x" .. wide.height), "512x256")
  ok(tileAt(wide, 256, 0) == (1024 % 255) + 1,
     "512x256: cell 1024 starts the RIGHT half",
     tostring(tileAt(wide, 256, 0)), (1024 % 255) + 1)
  ok(tileAt(wide, 0, 128) ~= (1024 % 255) + 1,
     "...and NOT the middle row, which is the bug",
     tostring(tileAt(wide, 0, 128)), "anything else")
  ok(tileAt(wide, 0, 0) == 1 and tileAt(wide, 248, 0) == 32,
     "512x256: the left block's first row is cells 0..31",
     ("%s..%s"):format(tostring(tileAt(wide, 0, 0)),
                       tostring(tileAt(wide, 248, 0))), "1..32")
  ok(tileAt(wide, 0, 8) == 33,
     "...and the row under it is cell 32, not cell 64",
     tostring(tileAt(wide, 0, 8)), 33)

  -- 512x512: four blocks in reading order
  local big = Gfx.compose(mapOf(512, 512), sheet, pal)
  local function want(n) return (n % 255) + 1 end
  ok(big and tileAt(big, 0, 0) == want(0)
     and tileAt(big, 256, 0) == want(1024)
     and tileAt(big, 0, 256) == want(2048)
     and tileAt(big, 256, 256) == want(3072),
     "512x512 is four blocks in reading order",
     big and ("%s/%s/%s/%s"):format(tostring(tileAt(big, 0, 0)),
       tostring(tileAt(big, 256, 0)), tostring(tileAt(big, 0, 256)),
       tostring(tileAt(big, 256, 256))),
     ("%d/%d/%d/%d"):format(want(0), want(1024), want(2048), want(3072)))

  -- NOTHING NARROWER MOVES, and this is the half that protects every screen
  -- that already worked: at 256 wide the two mappings are the same arithmetic.
  local narrow = Gfx.compose(mapOf(256, 256), sheet, pal)
  local drift = 0
  for i = 0, 1023 do
    local x, y = (i % 32) * 8, math.floor(i / 32) * 8
    if tileAt(narrow, x, y) ~= want(i) then drift = drift + 1 end
  end
  ok(drift == 0, "a 256x256 tilemap is laid out exactly as before",
     drift .. " cells moved", "0")

  -- ...and a 256-wide map TALLER than 256 is the same too, because one column
  -- of blocks stacked IS the linear order. Stating it keeps the rule honest:
  -- the split is about columns, not about being oversized.
  local tall = Gfx.compose(mapOf(256, 512), sheet, pal)
  local tallDrift = 0
  for i = 0, 2047 do
    local x, y = (i % 32) * 8, math.floor(i / 32) * 8
    if tileAt(tall, x, y) ~= want(i) then tallDrift = tallDrift + 1 end
  end
  ok(tallDrift == 0, "a 256x512 tilemap is unchanged (one block column)",
     tallDrift .. " cells moved", "0")

  -- A SIZE THE HARDWARE HAS NO BG FOR STAYS LINEAR. Seven members in the
  -- cartridge state sizes like 352x192, 384x144, 448x192 and 320x72; those are
  -- laid out by hand and splitting them would scramble screens that work.
  local odd = Gfx.compose(mapOf(352, 192), sheet, pal)
  local oddDrift = 0
  for i = 0, (352 / 8) * (192 / 8) - 1 do
    local x, y = (i % 44) * 8, math.floor(i / 44) * 8
    if tileAt(odd, x, y) ~= want(i) then oddDrift = oddDrift + 1 end
  end
  ok(oddDrift == 0, "352x192 is not a hardware BG size and stays linear",
     oddDrift .. " cells moved", "0")

  -- ...AND NEITHER IS 1024x1024, the one place it would be tempting to
  -- extrapolate. Two members of /graphic/demo_trade state that size and carry
  -- 8,192 cells -- exactly half the grid -- so BOTH readings fill the same top
  -- half and neither is distinguishable from the data. An unverified rule
  -- applied anyway is a guess wearing a rule's clothes; it stays linear.
  local huge = Gfx.compose(mapOf(1024, 1024), sheet, pal)
  ok(huge and tileAt(huge, 0, 8) == want(128),
     "1024x1024 is not a hardware BG size and stays linear",
     huge and tostring(tileAt(huge, 0, 8)), want(128))
end

-- ---------------------------------------------------------------------------
-- THE PARTICLES REACH THE SCREEN.
--
-- `Gen4ParticleSystem` simulates them, `Gen4MoveAnimPlayer` runs them and hands
-- over a draw list, and both of those are proved by checks of their own. None of
-- that puts a pixel anywhere: this screen has to ask for the list and blit it,
-- and until it did, Scratch was a correct simulation of an invisible effect.
-- ---------------------------------------------------------------------------
io.write("\nthe particles on the field\n")
ok(type(Gen4Battle.drawParticles) == "function",
   "the battle scene has a particle draw path",
   type(Gen4Battle.drawParticles), "function")
ok(type(Gen4Battle.particleOrigin) == "function",
   "...and resolves an emitter's origin to a point",
   type(Gen4Battle.particleOrigin), "function")

-- IT IS CALLED, and from the battler pass rather than merely defined. The
-- comments come out first: a call deleted with its comment left behind is the
-- exact fault that made a `gen4Layout()` guard look present in the move
-- animation check after it had been removed.
do
  local f = io.open(root .. "../src/battle/Gen4Battle.lua", "rb")
  local src = f and f:read("*a")
  if f then f:close() end
  src = src and src:gsub("\r\n", "\n"):gsub("%-%-[^\n]*", "") or ""
  local at = src:find("function Gen4Battle.drawBattlers", 1, true)
  local stop = at and src:find("\nfunction Gen4Battle%.", at + 10)
  local body = at and src:sub(at, stop or #src) or ""
  ok(body:find("Gen4Battle.drawParticles(battle)", 1, true) ~= nil,
     "...and drawBattlers actually calls it",
     body:find("Gen4Battle.drawParticles(battle)", 1, true) ~= nil, true)

  -- AND THE BLIT IS ANCHORED AT THE CENTRE, asserted from the SOURCE because
  -- there is no graphics context here to draw into and read back. That is a
  -- weaker check than every other one in this file and it is worth saying so:
  -- it can see the two offset arguments disappear -- which is what dropping
  -- them looks like, and dropping them makes every effect drift down and right
  -- as it scales, because LOVE anchors the top-left by default -- and it cannot
  -- see them being wrong in some subtler way. Planting the removal passed every
  -- other assertion in this section, so a weak check beats none.
  -- AND THE THIRD LAYER'S DRAW PATH, which is a separate call because it is a
  -- separate kind of thing: a flat animated sprite out of four archives rather
  -- than a 3D particle burst. 32 of the 501 programs use it.
  ok(type(Gen4Battle.drawCellActors) == "function",
     "...and a 2D cell-actor draw path",
     type(Gen4Battle.drawCellActors), "function")
  ok(body:find("Gen4Battle.drawCellActors(battle)", 1, true) ~= nil,
     "...which drawBattlers also calls",
     body:find("Gen4Battle.drawCellActors(battle)", 1, true) ~= nil, true)
  local ca = src:find("function Gen4Battle.drawCellActors", 1, true)
  local caEnd = ca and src:find("\nfunction Gen4Battle%.", ca + 10)
  local caBody = ca and src:sub(ca, caEnd or #src) or ""
  ok(caBody:find("getWidth() / 2", 1, true) ~= nil,
     "...and draws each sprite from its own centre",
     caBody:find("getWidth() / 2", 1, true) ~= nil, true)
  -- A BLANK FRAME MUST BE SKIPPED RATHER THAN DRAWN AS NOTHING: the animations
  -- name empty cells on purpose, and a draw path that did not check would try to
  -- load a nil path every one of those 79 frames.
  ok(caBody:find("s.blank", 1, true) ~= nil,
     "...and skips the cartridge's own blank frames",
     caBody:find("s.blank", 1, true) ~= nil, true)
  -- AND IT HONOURS AN ABSOLUTE POSITION, ON EITHER AXIS. Two callbacks need one:
  -- Fissure places its sprite at a fixed screen Y rather than an offset from a
  -- battler, and IcicleSpear flies a path BETWEEN the two battlers, which no
  -- offset from either one could express. A draw path that ignored the Y would
  -- open the crack at the defender's feet wherever those happen to be; one that
  -- ignored the X would leave all three icicles stacked on the defender.
  -- Source-level, with the same live-guard test the tiling branch gets, because
  -- `if false then` leaves every string intact.
  ok(caBody:find("s.absoluteY", 1, true) ~= nil,
     "...and reads an absolute height when the record carries one",
     caBody:find("s.absoluteY", 1, true) ~= nil, true)
  ok(caBody:find("s.absoluteX", 1, true) ~= nil,
     "...and an absolute X, which the flying callbacks need",
     caBody:find("s.absoluteX", 1, true) ~= nil, true)
  -- THE ABSOLUTE POSITION, TESTED BY CALLING IT RATHER THAN BY READING IT.
  --
  -- This used to scan for the inline `oy, sy = absY` and the nearest preceding
  -- `if`, to catch an absolute that was parsed and then dropped into dead code.
  -- That worked until the arithmetic moved into `Gen4Battle.effectPosition`,
  -- where `absoluteY or oy + (y or 0)` is a live expression with no `if` at all
  -- -- and then the check FAILED on correct code, three times over, for a
  -- refactor it had no business having an opinion about.
  --
  -- A string match encodes the spelling; what matters is the number that comes
  -- out. So it is called now, which cannot be fooled by a rename, by a dead
  -- guard, or by the logic moving to another function.
  ok(type(Gen4Battle.effectPosition) == "function",
     "...and the position arithmetic is reachable to be tested",
     type(Gen4Battle.effectPosition), "function")
  if type(Gen4Battle.effectPosition) == "function" then
    local fixture = {}
    local ox, oy = Gen4Battle.particleOrigin(fixture, "player", true)
    ok(type(ox) == "number" and type(oy) == "number",
       "...from an origin that resolves",
       ("%s, %s"):format(tostring(ox), tostring(oy)), "two numbers")
    if type(ox) == "number" and type(oy) == "number" then
      -- AN ABSOLUTE Y REPLACES the origin and the offset both. Fissure places
      -- its crack at a fixed screen height, so an offset leaking in would open
      -- it at the defender's feet wherever those happen to be.
      local _, ay = Gen4Battle.effectPosition(fixture, "player", true, 0, 24, nil, 7)
      ok(ay == 7, "...and an absolute Y wins over the origin and the offset",
         tostring(ay), 7)
      -- AN ABSOLUTE X likewise, which IcicleSpear needs: it flies a path
      -- between the battlers that no offset from either one can express.
      local axv = Gen4Battle.effectPosition(fixture, "player", true, 99, 0, 5, nil)
      ok(axv == 5, "...and an absolute X wins too, which the flying callbacks need",
         tostring(axv), 5)
      -- WITHOUT ONE, the offset applies to the origin -- so the absolute is a
      -- genuine branch rather than the only path through the function.
      local nx, ny = Gen4Battle.effectPosition(fixture, "player", true, 11, 24, nil, nil)
      ok(nx == ox + 11 and ny == oy + 24,
         "...and with neither, the offset applies to the origin",
         ("%s, %s"):format(tostring(nx), tostring(ny)),
         ("%s, %s"):format(tostring(ox + 11), tostring(oy + 24)))
    end
  end
  -- +Y IS DOWN, and this is the assertion that says so. The offsets on these
  -- records are what `ManagedSprite_OffsetPositionXY` would have added and every
  -- constant in pret is written in that frame, so the draw ADDS the record's Y.
  -- An earlier version subtracted it, which drew move 265's sprite twenty-four
  -- pixels above the battler where the cartridge puts it twenty-four below --
  -- and nothing could see it, because a sprite in the wrong place still draws.
  -- Measured rather than matched, for the reason above: a positive Y must land
  -- BELOW the origin and a negative one above it, whatever the source says.
  if type(Gen4Battle.effectPosition) == "function" then
    local fixture = {}
    local _, oy = Gen4Battle.particleOrigin(fixture, "player", true)
    local _, down = Gen4Battle.effectPosition(fixture, "player", true, 0, 24, nil, nil)
    local _, up = Gen4Battle.effectPosition(fixture, "player", true, 0, -24, nil, nil)
    ok(type(oy) == "number" and down == oy + 24 and up == oy - 24,
       "...and adds the record's Y, because +Y is down on the hardware",
       ("+24 -> %s, -24 -> %s (origin %s)"):format(tostring(down), tostring(up), tostring(oy)),
       ("%s and %s"):format(tostring(type(oy) == "number" and oy + 24),
                            tostring(type(oy) == "number" and oy - 24)))
  end
  -- WHAT THE CALLBACK DID TO IT reaches the screen: five channels, and each one
  -- is identity on a sprite whose callback is not ported.
  for _, field in ipairs({ "s.scaleX", "s.scaleY", "s.rotation", "s.flipX", "s.alpha" }) do
    ok(caBody:find(field, 1, true) ~= nil,
       "...and the draw reads " .. field,
       caBody:find(field, 1, true) ~= nil, true)
  end
  -- A FLIP IS A NEGATIVE X SCALE about the centre, which is what `SetFlipMode` is
  -- on the hardware -- and MetalClaw's left pair is the only user of it.
  ok(caBody:find("scaleX = -scaleX", 1, true) ~= nil,
     "...and a flip is a negative X scale, not a second image",
     caBody:find("scaleX = -scaleX", 1, true) ~= nil, true)

  -- THE BACKGROUND'S PALETTE FADE, WHICH HAS TO LAND IN THE RIGHT PLACE.
  -- `fadebg` blends the BACKGROUND's palettes and nothing else, so the quad that
  -- reproduces it must be drawn AFTER the field and BEFORE the battlers. Drawn
  -- last it would dim the Pokemon too, which the cartridge does not -- and that is
  -- an ordering bug no assertion about the fade's arithmetic could see, so it is
  -- asserted as an ordering here.
  do
    local dr = src:find("function Gen4Battle.draw(battle)", 1, true)
    local drBody = dr and src:sub(dr, (src:find("\nfunction Gen4Battle%.", dr + 10)) or #src) or ""
    local atField = drBody:find("battle:drawBattleField()", 1, true)
    local atFade = drBody:find("Gen4Battle.drawBackgroundFade(battle)", 1, true)
    local atBattlers = drBody:find("Gen4Battle.drawBattlers(battle)", 1, true)
    ok(atFade ~= nil, "the background fade is drawn at all", atFade ~= nil, true)
    ok(atField ~= nil and atFade ~= nil and atBattlers ~= nil
       and atField < atFade and atFade < atBattlers,
       "...after the field and BEFORE the battlers, so it dims neither Pokemon",
       ("field %s, fade %s, battlers %s"):format(tostring(atField),
                                                tostring(atFade),
                                                tostring(atBattlers)),
       "in that order")
    local bf = src:find("function Gen4Battle.drawBackgroundFade", 1, true)
    local bfBody = bf and src:sub(bf, (src:find("\nfunction Gen4Battle%.", bf + 10)) or #src) or ""
    ok(bfBody:find('groupTint(player, "base")', 1, true) ~= nil
       or bfBody:find('"base"', 1, true) ~= nil,
       "...reading the base group, not a screen-wide tint",
       bfBody:find('"base"', 1, true) ~= nil, true)
    -- A FILLED QUAD AT THE FADE'S OWN ALPHA IS THE EXACT OPERATION, because
    -- `BlendColor` IS alpha compositing; the assertion is that the alpha comes
    -- from the fade rather than being a constant somebody liked the look of.
    -- ONE QUAD FROM THE ORIGIN ACROSS THE WHOLE SCREEN. The width used to be
    -- the `Gen4Battle.WIDTH` constant and is now `Gen4Battle.width(battle)`,
    -- because the screen width varies -- so the constant's NAME is not the
    -- property. What matters is that the fill starts at 0,0 and spans a width
    -- the module derives plus the full height, rather than some inset box.
    local fill = bfBody:find('rectangle("fill", 0, 0,', 1, true)
    local span = fill and bfBody:match('rectangle%("fill", 0, 0,([^%)]*%)?[^%)]*)%)')
    ok(fill ~= nil and span ~= nil
       and span:find("Gen4Battle.width", 1, true) ~= nil
       and span:find("Gen4Battle.HEIGHT", 1, true) ~= nil,
       "...as one quad over the whole DS screen",
       span and span:gsub("%s+", " ") or "no 0,0 fill found",
       "0, 0, Gen4Battle.width(...), Gen4Battle.HEIGHT")
    ok(bfBody:find("setColor(r or 0, g or 0, b or 0, a)", 1, true) ~= nil,
       "...at the fade's own colour and alpha, not a constant",
       bfBody:find("setColor(r or 0, g or 0, b or 0, a)", 1, true) ~= nil, true)
  end

  local dp = src:find("function Gen4Battle.drawParticles", 1, true)
  local dpEnd = dp and src:find("\nfunction Gen4Battle%.", dp + 10)
  local dpBody = dp and src:sub(dp, dpEnd or #src) or ""
  ok(dpBody:find("w / 2, h / 2", 1, true) ~= nil,
     "...and draws each particle from its own centre",
     dpBody:find("w / 2, h / 2", 1, true) ~= nil, true)
  -- AND IT TINTS. Four fifths of the cartridge's emitters carry a colour and the
  -- draw list hands over the product of the particle's and the emitter's -- so a
  -- path that called `setColor(1, 1, 1, a)` unconditionally would draw the whole
  -- game's particles grey. Source-level for the same reason as the anchor: there
  -- is no graphics context here to read a pixel back from.
  ok(dpBody:find("q.colour", 1, true) ~= nil,
     "...and takes its colour from the draw record",
     dpBody:find("q.colour", 1, true) ~= nil, true)
  -- AND IT TILES. 647 emitters repeat their texture, which needs a wrapped quad
  -- rather than a bigger sprite: the footprint is unchanged and the texture
  -- repeats inside it.
  ok(dpBody:find("tiledQuad", 1, true) ~= nil
     and dpBody:find("setWrap", 1, true) ~= nil,
     "...and repeats a tiled texture inside the same footprint",
     ("tiledQuad %s, setWrap %s")
       :format(tostring(dpBody:find("tiledQuad", 1, true) ~= nil),
               tostring(dpBody:find("setWrap", 1, true) ~= nil)),
     "both")
  -- DIVIDED BY THE TILE COUNT ON BOTH AXES. The source now reads
  -- `sx*perspective / tileS`, so matching the literal `sx / tileS` failed on a
  -- correct draw that had merely gained a perspective factor. The property is
  -- the division: the quad is widened by tileS and the scale divided by it, so
  -- the footprint is unchanged and the texture repeats inside it. Anything
  -- MULTIPLYING by tileS there would grow the particle instead, so that is
  -- asserted against as well.
  ok(dpBody:find("/ tileS", 1, true) ~= nil and dpBody:find("/ tileT", 1, true) ~= nil,
     "...by dividing the scale rather than growing the particle",
     ("/ tileS %s, / tileT %s"):format(
       tostring(dpBody:find("/ tileS", 1, true) ~= nil),
       tostring(dpBody:find("/ tileT", 1, true) ~= nil)), "both")
  ok(dpBody:find("* tileS,", 1, true) == nil and dpBody:find("sx * tileS", 1, true) == nil,
     "...and does not scale the particle UP by the tile count",
     dpBody:find("* tileS,", 1, true) == nil, true)
  -- AND THE BRANCH IS REACHABLE. `if false then` above the tiled draw leaves
  -- every string above intact and the code dead -- the same fault a dead guard
  -- above the animator's tick pulled once. The nearest `if` must name `tileS`.
  do
    -- THE LAST `if` BEFORE THE CALL, whichever line it is on. Matching "two lines
    -- above" broke on the real source the moment a comment sat between them --
    -- and it broke by FAILING, which is the right way round for a check to be
    -- wrong. Scanning for the nearest preceding `if` does not care about layout.
    local at = dpBody:find("tiledQuad", 1, true)
    local guard = nil
    if at then
      for line in dpBody:sub(1, at):gmatch("[^\n]*if [^\n]*") do
        guard = line
      end
    end
    ok(guard ~= nil and guard:find("tileS", 1, true) ~= nil,
       "...under a guard that names tileS, not a dead one",
       guard and guard:gsub("^%s+", "") or "no guard found",
       "if tileS > 1 ...")
  end
end

-- THE ORIGIN SWAPS WITH THE SIDE, which is the one thing here that can be wrong
-- without looking wrong: an attacker origin pinned to the player draws the
-- opponent's moves out of the player's Pokemon, and half of every battle is
-- fought from the other side.
if type(Gen4Battle.particleOrigin) == "function" then
  local me = Gen4Battle.BATTLER_POS[0]
  local foe = Gen4Battle.BATTLER_POS[1]
  local ax, ay = Gen4Battle.particleOrigin(nil, "attacker", true)
  local dx, dy = Gen4Battle.particleOrigin(nil, "defender", true)
  ok(ax == me.x and ay == me.y,
     "the player attacking emits from the player's Pokemon",
     ("%s,%s"):format(tostring(ax), tostring(ay)),
     ("%s,%s"):format(tostring(me.x), tostring(me.y)))
  ok(dx == foe.x and dy == foe.y, "...and lands on the foe's",
     ("%s,%s"):format(tostring(dx), tostring(dy)),
     ("%s,%s"):format(tostring(foe.x), tostring(foe.y)))
  local bx, by = Gen4Battle.particleOrigin(nil, "attacker", false)
  ok(bx == foe.x and by == foe.y, "...and the foe attacking is the other way up",
     ("%s,%s"):format(tostring(bx), tostring(by)),
     ("%s,%s"):format(tostring(foe.x), tostring(foe.y)))
  -- THE MIDPOINT IS BETWEEN THEM, not at one of them: five of the twenty-three
  -- callbacks converge on the centre of the field and a midpoint that collapsed
  -- onto a battler would look like a move aimed at the wrong Pokemon.
  local mx, my = Gen4Battle.particleOrigin(nil, "midpoint", true)
  ok(mx == (me.x + foe.x) / 2 and my == (me.y + foe.y) / 2,
     "...and the centre of the field is between the two",
     ("%s,%s"):format(tostring(mx), tostring(my)),
     ("%s,%s"):format(tostring((me.x + foe.x) / 2), tostring((me.y + foe.y) / 2)))
  -- AND AN UNKNOWN NAME DOES NOT LAND AT (0,0), which is the top-left corner of
  -- the screen and where a nil-defaulting origin would put a whole effect.
  local ux, uy = Gen4Battle.particleOrigin(nil, "no such callback", true)
  ok(tonumber(ux) and tonumber(uy) and (ux ~= 0 or uy ~= 0),
     "...and an origin this screen does not know is still on the field",
     ("%s,%s"):format(tostring(ux), tostring(uy)), "not 0,0")
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
