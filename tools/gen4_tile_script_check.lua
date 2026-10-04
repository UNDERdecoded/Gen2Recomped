-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- NINE KINDS OF SINNOH SCENERY THAT ANSWERED NOTHING.
--
-- `Field_TileBehaviorToScript` (pokeplatinum src/overlay005/field_control.c) is
-- a plain table from a tile's BEHAVIOUR BYTE to a script id, and it is the only
-- thing that makes the PC, four bookshelves, the trash can, three mart shelves,
-- the wall map, the bike-parking sign and the television interactive.  None of
-- them is an object event and none is a bg event: there is nothing in the map
-- data to find, so a port that only looks at objects and bg events finds
-- nothing and the press does nothing.
--
-- This port had a Gen 2 arm (collision class $93) and a Gen 3 arm (the PC
-- metatile) in `tryPcTile` and no Gen 4 arm anywhere.
--
-- WHAT THAT COST, measured against the extracted cache: 3,527 tiles across 289
-- layouts, the PC on 66 maps -- and `CommonScript_PC` with it, which is where
-- the box PC's name after meeting Bebe, the player's own PC, the professor's
-- dex rating, the Hall of Fame row and COMPARE POKeMON all live.
--
-- It is also the fault Gen 3 already had and already fixed; the note at this
-- port's Gen 3 PC branch says "what it opens is the CARTRIDGE'S OWN SCRIPT,
-- not this port's PC menu".  Gen 4 was still calling `openPC`.
--
-- Run:  texlua tools/gen4_tile_script_check.lua [game root or data/generated] [pokeplatinum dir]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local fails, checks, reports = 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = { getWidth = function() return 256 end, getHeight = function() return 192 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local given = (arg and arg[1]) or nil
local D
if given then
  given = given:gsub("[/\\]*$", "")
  if slurp(given .. "/maps.lua") then D = given .. "/"
  elseif slurp(given .. "/data/generated/maps.lua") then D = given .. "/data/generated/" end
end
local PP = arg and arg[2]

local Behaviors = require("src.import.Gen4Behaviors")
local TS = require("src.world.Gen4TileScripts")
local VM = require("src.script.Gen4ScriptVM")

-- ---------------------------------------------------------------------------
section("1. the table, and that every name in it is a real behaviour")
-- ---------------------------------------------------------------------------
ok(type(TS.TABLE) == "table" and #TS.TABLE == 13,
   "Gen4TileScripts.TABLE has %d rows, not the 13 equality cases in "
   .. "Field_TileBehaviorToScript", TS.TABLE and #TS.TABLE or -1)

-- EVERY NAME RESOLVES.  A row whose behaviour name is not in the cartridge's
-- own table would never match anything and would look exactly like a tile
-- nobody presses.
local values = {}
for _, row in ipairs(TS.TABLE) do
  local m = Behaviors.matching("^" .. row.behaviour .. "$")
  ok(m and m[1] ~= nil, "%s is not a behaviour name in Gen4Behaviors",
     row.behaviour)
  if m and m[1] then
    ok(values[m[1]] == nil,
       "%s and %s are the same behaviour value 0x%02X, so one of them can "
       .. "never fire", tostring(values[m[1]]), row.behaviour, m[1])
    values[m[1]] = row.behaviour
  end
end

-- ...AND THE LOOKUP FINDS THEM.  The table existing is not the same as the
-- index being built from it.
for _, row in ipairs(TS.TABLE) do
  local v = Behaviors.matching("^" .. row.behaviour .. "$")[1]
  if v then
    local got = TS.rowFor(v, row.facing or "up")
    ok(got ~= nil and got.behaviour == row.behaviour,
       "rowFor(0x%02X) did not answer %s", v, row.behaviour)
  end
end

-- A behaviour with no row answers nil, which is the C's 0xffff and what lets
-- the press fall through to everything after it.
ok(TS.rowFor(0x02, "up") == nil,
   "TALL_GRASS answered a tile script; every behaviour would start one")
ok(TS.rowFor(nil, "up") == nil, "a nil behaviour answered a tile script")

-- ---------------------------------------------------------------------------
section("2. the two facing guards, which are the cartridge's own")
-- ---------------------------------------------------------------------------
-- `TileBehavior_IsPC(behavior) && playerDir == DIR_NORTH` and the same for the
-- TV.  Both are drawn on the wall behind the tile, so neither answers from the
-- side -- and a port that dropped the guard would let you use a PC edge-on.
local function valueOf(name) return Behaviors.matching("^" .. name .. "$")[1] end
for _, name in ipairs({ "PC", "TV" }) do
  local v = valueOf(name)
  ok(TS.rowFor(v, "up") ~= nil, "%s does not answer a player facing up", name)
  for _, dir in ipairs({ "down", "left", "right" }) do
    ok(TS.rowFor(v, dir) == nil,
       "%s answered a player facing %s; the cartridge requires DIR_NORTH",
       name, dir)
  end
end
-- ...and a row with no facing answers from any direction, or every bookshelf
-- in Sinnoh would need approaching from one side.
do
  local v = valueOf("BOOKSHELF_1")
  for _, dir in ipairs({ "up", "down", "left", "right" }) do
    ok(TS.rowFor(v, dir) ~= nil,
       "BOOKSHELF_1 refused a player facing %s, but has no facing guard", dir)
  end
end

-- ---------------------------------------------------------------------------
section("3. the band indices really are the cartridge's, 0-based")
-- ---------------------------------------------------------------------------
if not D then
  report("no Platinum cache given; sections 3 and 5 were not run")
else
  local data = { map_scripts = dofile(D .. "map_scripts.lua") }
  local pool = VM.store(data)
  ok(pool ~= nil, "%smap_scripts.lua is not a RomExtractorGen4 pool", D)
  if pool then
    -- THE OFF-BY-ONE IS THE WHOLE RISK HERE.  `SCRIPT_ID(band, n)` is 0-based
    -- and `entries` is a Lua array, so entry n+1 is script n.  The honey tree
    -- is the control: `honey_tree.c` says COMMON_SCRIPTS 8 and this port has
    -- been reaching it at `entries[9]` since it was written, so if the
    -- convention were off by one the honey trees would already be wrong.
    local common = pool.bands and pool.bands.common_scripts
    ok(common and common.entries and common.entries[9] ~= nil,
       "common_scripts entry 9 (the honey tree, COMMON_SCRIPTS 8) is missing, "
       .. "so the index convention cannot be confirmed")
    -- ...AND THE +1 IS ASSERTED THROUGH `compile`, not just read off the
    -- array here.  Checking `entries[index + 1]` in this file only proves the
    -- slot exists; it would pass just as happily if `compile` looked up
    -- `entries[index]` and started the WRONG SCRIPT -- a bookshelf answering
    -- with the trash can's line, silently, forever.
    do
      local common = pool.bands.common_scripts
      local _, label = TS.compile(data, "common_scripts", 8)
      ok(label ~= nil and label == common.entries[9],
         "compile(common_scripts, 8) resolved %s, but SCRIPT_ID(band, n) is "
         .. "0-based and entry n+1 is script n -- the honey tree is at "
         .. "entries[9] and has been since it was written",
         tostring(label))
      local _, pcLabel = TS.compile(data, "common_scripts", 18)
      ok(pcLabel ~= nil and pcLabel == common.entries[19],
         "compile(common_scripts, 18) resolved %s rather than the PC script "
         .. "at entries[19]", tostring(pcLabel))
      ok(label ~= pcLabel,
         "the honey tree and the PC resolved to the same label (%s), so the "
         .. "index is being ignored", tostring(label))
    end
    for _, row in ipairs(TS.TABLE) do
      local band = pool.bands and pool.bands[row.band]
      ok(band ~= nil, "%s names band %q, which this cache does not have",
         row.behaviour, row.band)
      if band then
        ok(band.entries and band.entries[row.index + 1] ~= nil,
           "%s wants %s entry %d (array slot %d) and the band has %d entries",
           row.behaviour, row.band, row.index, row.index + 1,
           band.entries and #band.entries or 0)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
section("4. the dispatch is wired, in the cartridge's slot")
-- ---------------------------------------------------------------------------
do
  local src = slurp("src/world/OverworldController.lua") or ""
  ok(#src > 0, "src/world/OverworldController.lua did not open")
  local code = src:gsub("%-%-[^\r\n]*", "")
  ok(code:find("function OverworldState:tryGen4TileScript", 1, true) ~= nil,
     "OverworldState:tryGen4TileScript does not exist")
  ok(code:find("self:tryGen4TileScript(fx, fy)", 1, true) ~= nil,
     "interact() never calls tryGen4TileScript, so the table is built and "
     .. "never consulted")
  -- AFTER the bg events and BEFORE the field moves, which is where
  -- Field_TileBehaviorToScript sits in Field_Interact.
  local signAt = code:find('interacted(self, fx, fy, "sign"', 1, true)
  local tileAt = code:find("self:tryGen4TileScript(fx, fy)", 1, true)
  local moveAt = code:find("self:tryFieldMoveOW(fx, fy)", 1, true)
  ok(signAt and tileAt and signAt < tileAt,
     "the Gen 4 tile dispatch runs before the bg events; the cartridge "
     .. "consults the behaviour only after FieldEvent_GetInteractedBgEventScript")
  ok(tileAt and moveAt and tileAt < moveAt,
     "the Gen 4 tile dispatch runs after the field moves")
  -- ONE SPELLING of "run script n of band b": the honey tree had the only copy
  -- and there are fourteen callers now.
  ok(code:find("Gen4TileScripts').compile(Game.data,'common_scripts',8)", 1, true) ~= nil
     or code:find('Gen4TileScripts").compile(Game.data, "common_scripts", 8)', 1, true) ~= nil,
     "the honey tree no longer goes through Gen4TileScripts.compile, so the "
     .. "band lookup has two spellings again")
  -- ...and openPC's Gen 4 arm runs the script rather than jumping to the grid
  local pcArm = code:match("function OverworldState:openPC%(onDone%).-\nend")
  ok(pcArm ~= nil, "could not find OverworldState:openPC")
  if pcArm then
    ok(pcArm:find('"common_scripts", 18', 1, true) ~= nil,
       "openPC's Gen 4 arm no longer runs CommonScript_PC, so that call site "
       .. "and the tile dispatch are two PC flows that can disagree")
  end
end

-- ---------------------------------------------------------------------------
section("5. every script the table names is lowered end to end")
-- ---------------------------------------------------------------------------
-- A dispatch into a band full of unlowered commands would be a press that
-- starts a script and then warns its way through it.  This is the assertion
-- that the nine interactions actually WORK, not merely that they start.
if not PP or not slurp(PP .. "/asm/macros/scrcmd.inc") then
  io.write("   (no pokeplatinum dir given -- section 5 skipped)\n")
else
  local inc = slurp(PP .. "/asm/macros/scrcmd.inc")
  local macroConst = {}
  for name, body in inc:gmatch("%.macro%s+(%S+)(.-)%.endm") do
    local c = body:match("%.short%s+([A-Za-z][A-Za-z0-9_]*)")
    if c then macroConst[name] = c end
  end
  local enum = slurp(PP .. "/include/data/scripts/scrcmd.h") or ""
  local constIndex, n = {}, 0
  for c in enum:gmatch("ScriptCommand%(%s*([A-Za-z0-9_]+)%s*,") do
    constIndex[c] = n; n = n + 1
  end
  ok(n == 840, "%d commands in pokeplatinum's enum, expected 840", n)
  local opsSrc = slurp("src/import/Gen4ScriptOps.lua") or ""
  local opName = {}
  for id, nm in opsSrc:gmatch('%[(0x[0-9A-Fa-f]+)%]%s*=%s*{%s*"([^"]+)"') do
    opName[tonumber(id)] = nm
  end
  local Bands = require("src.import.Gen4ScriptBands")
  local fileOf = {}
  for _, b in ipairs(Bands.BANDS) do fileOf[b[2]] = b[3] end
  local wanted, worst = {}, {}
  for _, row in ipairs(TS.TABLE) do wanted[row.band] = true end
  for band in pairs(wanted) do
    local body = slurp(PP .. "/res/field/scripts/" .. tostring(fileOf[band]) .. ".s")
    ok(body ~= nil, "could not read the source for band %q", band)
    if body then
      local uses, holes, seen = 0, 0, {}
      for line in body:gmatch("[^\r\n]+") do
        local mac = line:match("^%s*([A-Za-z_][A-Za-z0-9_]*)")
        if mac and macroConst[mac] then
          uses = uses + 1
          local i = constIndex[macroConst[mac]]
          local nm = i and opName[i]
          if nm and not VM.lowered(nm) then
            holes = holes + 1
            if not seen[nm] then seen[nm] = true end
          end
        end
      end
      local list = {}
      for k in pairs(seen) do list[#list + 1] = k end
      table.sort(list)
      io.write(("   %-16s %4d uses, %3d unlowered  %s\n")
               :format(band, uses, holes, table.concat(list, ", ")))
      worst[band] = holes
    end
  end
  -- THE CANARY FOR THE METHOD, AND IT NAMES NOTHING.
  --
  -- It used to assert `VM.lowered("opensealcapsuleeditor") == false`, and pass
  -- 176 lowered `opensealcapsuleeditor`. That is the second time a canary has
  -- picked, as its example of an unlowered command, something somebody was
  -- about to fix -- `gen4_save_check` named `checkishalloffamecorrupted` and
  -- pass 173 lowered it. **A canary whose subject is a to-do item has a
  -- half-life.**
  --
  -- Derived instead, over the whole opcode table: the detector has to say yes
  -- to something and no to something. One that answers uniformly -- the inert
  -- stub answering nil for everything, or a table that lost its `lowered`
  -- predicate -- fails whichever way it leans, and no individual name can go
  -- stale underneath it.
  do
    local yes, no, total = 0, 0, 0
    for _, nm in pairs(opName) do
      if type(nm) == "string" then
        total = total + 1
        local answer = VM.lowered(nm)
        if answer == true then yes = yes + 1
        elseif answer == false then no = no + 1 end
      end
    end
    ok(total >= 800,
       "the opcode table named %d command(s), so this canary is asking about "
       .. "almost nothing", total)
    ok(yes + no == total,
       "the detector gave neither true nor false for %d of %d command(s) -- "
       .. "nil is what the command audit's inert stub answers, and it is not "
       .. "`false`", total - (yes + no), total)
    ok(yes > 0 and no > 0,
       "the detector says yes to %d and no to %d of %d commands; it has to do "
       .. "both or the counts above mean nothing", yes, no, total)
  end
  -- bg_events, field_moves and tv_broadcast are the three bands the table
  -- reaches that are NOT common_scripts, and the first two are at zero.
  ok((worst.field_moves or 1) == 0,
     "field_moves has %d unlowered use(s); the waterfall row starts a script "
     .. "that cannot finish", worst.field_moves or -1)
  ok((worst.tv_broadcast or 1) == 0,
     "tv_broadcast has %d unlowered use(s); the TV row starts a script that "
     .. "cannot finish", worst.tv_broadcast or -1)
  -- bg_events has exactly one: `openregionmap`, which needs a Sinnoh region
  -- map this port has not extracted. A ceiling, so the other eight bg_event
  -- scripts cannot quietly regress behind it.
  ok((worst.bg_events or 99) <= 1,
     "bg_events has %d unlowered use(s), up from the one (`openregionmap`, "
     .. "the wall map) that is argued", worst.bg_events or -1)
end

-- ---------------------------------------------------------------------------
section("6. the PC's own six commands")
-- ---------------------------------------------------------------------------
local Shared = { meta = {} }
setmetatable(Shared, { __index = function() return function() end end })
local inert = setmetatable({}, {
  __index = function(t, k) return rawget(t, k) or function() end end,
  __call = function() return nil end })
local KEEP = {
  ["src.script.Gen4Commands"] = true, ["src.script.Gen4ScriptVM"] = true,
  ["src.import.Gen4ScriptOps"] = true, ["src.core.Logger"] = true,
}
table.insert(package.searchers, 1, function(name)
  if KEEP[name] then return nil end
  if name == "src.script.Commands" then return function() return Shared end end
  if name:sub(1, 4) ~= "src." then return nil end
  return function() return inert end
end)
local Gen4Commands = require("src.script.Gen4Commands")
local setVar, getVar = Gen4Commands.setVar, Gen4Commands.getVar
do  -- harness canary first
  local probe = { gen4Vars = {} }
  setVar(probe, 0x4000, 7)
  assert(probe.gen4Vars[0x4000] == 7, "harness cannot observe a var write")
end

for _, name in ipairs({ "loadpcanimation", "playpcbootupanimation",
                        "playpcshutdownanimation",
                        "savetvsegmentpokemonstoragebulletin",
                        "checkishalloffamecorrupted",
                        "openpchalloffamescreen" }) do
  ok(VM.lowered(name) == true, "%s is not lowered", name)
end

-- THE HALL OF FAME IS NOT CORRUPT, and answering that it is would tell the
-- player their records are damaged when they are not.
do
  local ctx = { save = { gen4Vars = {} }, game = {} }
  local fn = rawget(Shared, "g4_hall_of_fame_corrupted")
  ok(type(fn) == "function", "g4_hall_of_fame_corrupted has no handler")
  if type(fn) == "function" then
    fn(ctx, 0x4000)
    ok(getVar(ctx.save, 0x4000) == 0,
       "a healthy save answered %s for \"is the Hall of Fame corrupted\"; "
       .. "anything but 0 sends the script to the \"data is corrupted\" message",
       tostring(getVar(ctx.save, 0x4000)))
    -- an ABSENT list is a player who has not won yet, not a damaged one
    local empty = { save = { gen4Vars = {} }, game = {} }
    fn(empty, 0x4000)
    ok(getVar(empty.save, 0x4000) == 0,
       "a save with no hallOfFame list was reported corrupted")
  end
end

-- ONE ROW FOR BOTH TV SEGMENTS.  Two spellings of "this engine has no TV
-- broadcast system" is the fault this port keeps finding.
do
  ok(type(rawget(Shared, "g4_save_tv_segment")) == "function",
     "g4_save_tv_segment has no handler")
  ok(rawget(Shared, "g4_save_tv_hidden_item") == nil,
     "the single-purpose TV row is back; both segments lower to "
     .. "g4_save_tv_segment now")
  local vmSrc = slurp("src/script/Gen4ScriptVM.lua") or ""
  local code = vmSrc:gsub("%-%-[^\r\n]*", "")
  local rows = 0
  for _ in code:gmatch("g4_save_tv_segment") do rows = rows + 1 end
  ok(rows == 2, "%d lowering(s) emit g4_save_tv_segment, expected the two "
     .. "TV segment commands", rows)
end

-- THE PROP ANIMATIONS SHARE THE DOOR'S ROW, for the same reason: one absence,
-- stated once.
do
  local vmSrc = slurp("src/script/Gen4ScriptVM.lua") or ""
  local code = vmSrc:gsub("%-%-[^\r\n]*", "")
  for _, name in ipairs({ "loadpcanimation", "playpcbootupanimation",
                          "playpcshutdownanimation" }) do
    local line = code:match("L%." .. name .. "[^\n]*")
    ok(line ~= nil and line:find("g4_noop", 1, true) ~= nil,
       "%s no longer lowers to the named no-op row", name)
  end
  ok(code:find('"prop animations"', 1, true) ~= nil,
     "the prop-animation rows no longer name what is absent, so the log says "
     .. "an opcode number instead of a feature")
end

io.write(("\n%d checks, %d failed, %d reported\n"):format(checks, fails, reports))
os.exit(fails == 0 and 0 or 1)
