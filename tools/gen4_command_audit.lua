-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_command_audit.lua -- run every Gen 4 script command against the
-- REAL cache and check that it runs and writes what it promises.
--
-- WHY THIS EXISTS. Eight chapters of lowering were written by reading pret and
-- the port side by side, which catches the wrong kind of mistake. Reading finds
-- a misunderstood cartridge rule; it does not find a Lua scoping error or a
-- field spelled two ways. This found both on its first run:
--
--   * `itemKey` referenced ABOVE its `local function` line, so `g4_buffer`
--     raised "attempt to call a nil value (global 'itemKey')" every time a TM's
--     move name was wanted.
--   * `g4_pc_free_slots` answering ZERO free boxes when it could not load the
--     Boxes module -- which is not "unknown", it is "your boxes are full", the
--     one answer that locks a player out of the Great Marsh.
--
-- AND IT HAD TO BE TAUGHT TO SEE A PASS. The first run reported 25 commands as
-- "NO VAR WRITTEN" because it looked in `save.vars`; the port keeps script vars
-- in `save.gen4Vars`. A harness that cannot observe a success condemns
-- everything, which is the same class of error as one that cannot observe a
-- failure -- so it now asserts it can watch a var being written before it
-- trusts a single result.
--
--   texlua tools/gen4_command_audit.lua
--
-- Run:  texlua tools/gen4_command_audit.lua [path to a platinum data/generated]
--
-- IT FINDS ITS OWN CHECKOUT, and that is not tidiness.  This used to carry
-- three absolute paths from the machine it was written on, and the FIRST of
-- them was an overlay directory holding a stale copy of `Gen4Commands` -- so
-- the audit silently graded a module that was months out of date, reported
-- "43 checks, 0 failures", and could not run at all on anybody else's
-- checkout.  A harness that cannot observe the thing it grades is the failure
-- this file already has a canary for; this is the same fault one level up.
package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

-- Exercise every g4_ command against REAL cache data.  The point is not that
-- they return something; it is that they RUN, that the var they promise to
-- write is actually written, and -- for the ones whose value is a cartridge
-- constant -- that the number written is the cartridge's.
local KEEP = {
  ["src.script.Gen4Commands"]=true, ["src.import.Gen4Text"]=true,
  ["src.import.Gen4ScriptOps"]=true, ["src.pokemon.Boxes"]=true,
  ["src.core.GameVersion"]=true, ["src.pokemon.Contest"]=true,
}
-- src.script.Commands is the SHARED verb table Gen4Commands assigns onto, so it
-- must be a real table (Commands.meta = Commands.meta or {} needs a table, not
-- a stubbed function). Everything else can be inert.
local Shared = { meta = {} }
setmetatable(Shared, { __index = function(_, k)
  -- unknown shared verbs answer as no-ops so a g4_ command that delegates
  -- (start_battle, give_pokemon) still runs
  return function() end
end })
local inert = setmetatable({}, {
  __index=function(t,k) return rawget(t,k) or function() end end,
  __call=function() return nil end })
table.insert(package.searchers, 1, function(name)
  if KEEP[name] then return nil end
  if name == "src.script.Commands" then return function() return Shared end end
  if name:sub(1,4) ~= "src." then return nil end
  return function() return inert end
end)

-- WHERE THE CACHE IS.  Given on the command line, or the usual sibling of a
-- checkout.  Named rather than assumed: a missing cache must say so instead of
-- failing forty checks that were never run.
local D = (arg and arg[1]) or "../Gen2Recomped/platinum/data/generated"
D = D:gsub("[/\\]*$", "") .. "/"
local function load(n)
  local ok, mod = pcall(dofile, D .. n .. ".lua")
  if not ok then
    io.stderr:write(("cannot read %s%s.lua -- pass the path to a Platinum "
                     .. "data/generated as the first argument\n"):format(D, n))
    os.exit(2)
  end
  return mod
end
local data = {
  items = load("items"), pokemon = load("pokemon"), moves = load("moves"),
  maps = load("maps"), text = load("text"), gen4_menus = load("gen4_menus"),
  constants = load("constants"),
  gen4_map_headers = load("gen4_map_headers"),
}
local Gen4Commands = require("src.script.Gen4Commands")
local verbs = Shared
assert(rawget(Shared, "g4_item_pocket"), "the verb table did not receive g4_ commands")

local VAR = 0x4000
local function newCtx()
  local save = {
    gen4Vars = {}, flags = {}, party = {
      { species = 387, level = 20, isEgg = false, item = 298,
        moves = { {id=33,pp=35}, {id=45,pp=40} }, evs = { hp=4, attack=6 },
        ribbons = {}, friendship = nil },
      { species = 390, level = 18, isEgg = true, moves = {} },
    },
    pokedex = { seen = {[1]=true,[4]=true}, owned = {[1]=true} },
    hallOfFame = { {}, {} }, money = 5000, inventory = {}, boxes = nil,
    poketch = nil, onBike = false,
  }
  local ow = { map = { def = data.maps["C01"], id = "C01" },
               previousMapId = "T01", entities = {} }
  return { save = save, game = { data = data, stringBuffers = {} },
           overworld = ow, lastBattleResult = "caught" }
end

-- HARNESS CANARY. The first run reported 25 "NO VAR WRITTEN" because it looked
-- in save.vars; the port keeps script vars in save.gen4Vars. A harness that
-- cannot observe a success reports every pass as a failure, which is the same
-- error as one that cannot observe a failure. Prove it can see one.
do
  local probe = { gen4Vars = {} }
  local Gen4 = require("src.script.Gen4Commands")
  Gen4.setVar(probe, 0x4000, 7)
  assert(probe.gen4Vars[0x4000] == 7, "harness cannot observe a var write")
end

local results, failures = {}, 0
local function try(name, args, expectVar)
  local ctx = newCtx()
  local fn = rawget(verbs, name)
  if type(fn) ~= "function" then
    results[#results+1] = ("%-34s MISSING"):format(name); failures = failures + 1
    return
  end
  local ok, err = pcall(fn, ctx, (table.unpack or unpack)(args))
  if not ok then
    results[#results+1] = ("%-34s RAISED  %s"):format(name, tostring(err))
    failures = failures + 1
    return
  end
  local note = ""
  if expectVar then
    local v = ctx.save.gen4Vars and ctx.save.gen4Vars[expectVar]
    if v == nil then
      results[#results+1] = ("%-34s NO VAR WRITTEN"):format(name)
      failures = failures + 1
      return
    end
    note = ("var=%s"):format(tostring(v))
  end
  -- buffers, for the g4_buffer kinds
  local b = ctx.game.stringBuffers[1]
  if b ~= nil and b ~= "" then note = note .. (" buf=%q"):format(tostring(b):sub(1,28)) end
  results[#results+1] = ("%-34s ok      %s"):format(name, note)
end

-- ...AND WHAT IT WROTE, not merely that it wrote.
--
-- `try` above answers "did a var appear", which is the question that let the
-- yes/no menu ship inverted for the whole Gen 4 effort: `showyesnomenu` DID
-- write its destination, every time, with the wrong number.  `MENU_YES` is 0
-- and `MENU_NO` is 1 (include/constants/menu.h) -- a menu numbers its rows
-- from the top -- and the port wrote the intuitive 1 for yes, so all 511
-- yes/no questions in Sinnoh read backwards.  Reported from play on Rowan's
-- "do you truly love Pokemon?": yes was heard as no, and he asked again.
--
-- Several of the expectations below were already written down AS COMMENTS and
-- never asserted, which is its own small lesson: a value worth writing in the
-- margin is a value worth failing on.
local function expect(name, args, destVar, want, why)
  local ctx = newCtx()
  local fn = rawget(verbs, name)
  if type(fn) ~= "function" then
    results[#results+1] = ("%-34s MISSING"):format(name); failures = failures + 1
    return
  end
  if type(args) == "function" then args = args(ctx) end
  local ok, err = pcall(fn, ctx, (table.unpack or unpack)(args))
  if not ok then
    results[#results+1] = ("%-34s RAISED  %s"):format(name, tostring(err))
    failures = failures + 1
    return
  end
  local got = ctx.save.gen4Vars and ctx.save.gen4Vars[destVar]
  if got ~= want then
    results[#results+1] = ("%-34s WRONG VALUE  got %s, want %s  (%s)")
      :format(name, tostring(got), tostring(want), tostring(why))
    failures = failures + 1
    return
  end
  results[#results+1] = ("%-34s ok      var=%s  (%s)"):format(name, tostring(got), tostring(why))
end

-- THE YES/NO MENU, BOTH WAYS.  The cartridge tests its destination against 0
-- for the yes branch and 1 for the no branch -- 496 of the 511 sites do it on
-- the very next instruction -- so both values have to be right, and asserting
-- only one of them would pass with them swapped.
expect("g4_from_yesno", function(ctx) ctx.lastCheck = true;  return { VAR } end,
       VAR, 0, "MENU_YES is 0 -- a menu numbers its rows from the top")
expect("g4_from_yesno", function(ctx) ctx.lastCheck = false; return { VAR } end,
       VAR, 1, "MENU_NO is 1")

-- destination-writing commands: (args..., destVar) per the lowering
expect("g4_item_pocket",     {413, VAR}, VAR, 3, "TM86 is in pocket 3")
expect("g4_item_is_plate",   {298, VAR}, VAR, 1, "Flame Plate starts the plate run")
expect("g4_game_version",    {VAR}, VAR, 12, "VERSION_PLATINUM, counted off versions.h")
expect("g4_selected_party_slot", {VAR}, VAR, 0xFF,
       "PARTY_SLOT_NONE -- cancelled, not the lead")

-- THE BATTLE RESULT IS A BITMASK, and the whole point of asserting it is that
-- its compound values are built from the three bits rather than counted off.
-- The fixture context sets lastBattleResult = "caught".
expect("g4_get_battle_result", {VAR}, VAR, 4,
       "BATTLE_RESULT_CAPTURED_MON is 1<<2 -- not 5, which is CAPTURED|WIN")
try("g4_party_count",        {VAR}, VAR)
try("g4_party_non_eggs",     {VAR}, VAR)
try("g4_day_of_week",        {VAR}, VAR)
try("g4_dex_seen_count",     {VAR}, VAR)
try("g4_overworld_weather",  {VAR}, VAR)
try("g4_mon_move",           {VAR, 0, 0}, VAR)
try("g4_mon_move_count",     {VAR, 0}, VAR)
try("g4_find_slot_with_move",{VAR, 33}, VAR)
try("g4_pc_free_slots",      {VAR}, VAR)
try("g4_did_not_capture",    {VAR}, VAR)
try("g4_party_has_held_item",{298, VAR}, VAR)
try("g4_league_victories",   {VAR}, VAR)
try("g4_mon_ev_total",       {VAR, 0}, VAR)
try("g4_get_mon_ribbon",     {VAR, 0, 5}, VAR)
try("g4_mon_friendship",     {VAR, 0}, VAR)
try("g4_mon_types",          {VAR, VAR+1, 0}, VAR)
try("g4_mon_has_move",       {VAR, 33, 0}, VAR)
try("g4_first_non_egg",      {VAR}, VAR)
try("g4_party_has_species",  {VAR, 387}, VAR)
try("g4_party_has_species2", {387, VAR}, VAR)
try("g4_destroy_obstacle_anim", {0, VAR}, VAR)
-- state setters (no var)
try("g4_set_blackout_warp",  {9})
try("g4_enable_poketch",     {})
try("g4_register_poketch_app", {3})
try("g4_player_state",       {1})
try("g4_player_bike",        {1})
try("g4_give_pokedex",       {})
try("g4_set_species_seen",   {387})
try("g4_set_mon_ribbon",     {0, 5})
-- buffers
try("g4_buffer", {0, "pocket", 3})
try("g4_buffer", {0, "itemPlural", 1})
try("g4_buffer", {0, "poketchApp", 1})
try("g4_buffer", {0, "tmhmMove", 413})
try("g4_buffer", {0, "speciesArticle", 387})
try("g4_buffer", {0, "bank:393", 1})
try("g4_buffer", {0, "bank:386", 1})
try("g4_buffer", {0, "bank:626", 1})
try("g4_buffer_map_name", {0, 3})
try("g4_buffer_counterpart_starter_article", {0})

table.sort(results)
for _, r in ipairs(results) do print(r) end
print(("\n%d checks, %d failures"):format(#results, failures))
