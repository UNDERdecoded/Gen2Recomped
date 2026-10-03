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
-- EVERY MODULE A COMMAND READS DATA OUT OF HAS TO BE REAL, and the stub below
-- is why.  `inert` answers any field with `function() end`, so a module left
-- off this list does not fail loudly -- it hands back a function where a table
-- was wanted, or nil where a value was.  Both happened in one pass:
--
--   * `Gen4TrainerMessages.SCRIPT_TYPES` came back as a FUNCTION, and
--     `g4_trainer_message_types` raised "attempt to index a function value" --
--     loud, and fixed in a minute.
--   * `VsSeeker.rematchFor` came back as a no-op returning nil, so
--     `g4_get_rematch_trainer_id` answered 0 and the case asserting
--     "TRAINER_NONE for a trainer with no rematch armed" PASSED -- against the
--     stub, having never entered the module it was grading.  A green result
--     from a measurement that could not fail is worse than the red one above
--     it, and it is the fault this file was written to catch one level up.
local KEEP = {
  ["src.script.Gen4Commands"]=true, ["src.import.Gen4Text"]=true,
  ["src.import.Gen4ScriptOps"]=true, ["src.pokemon.Boxes"]=true,
  ["src.core.GameVersion"]=true, ["src.pokemon.Contest"]=true,
  ["src.import.Gen4TrainerMessages"]=true, ["src.world.VsSeeker"]=true,
  ["src.import.Gen4ScriptOps"]=true, ["src.core.Music"]=true,
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
-- Two more destinations, for the one command that writes THREE of them. Three
-- separate slots rather than three calls to the same one: a handler that wrote
-- its first answer three times would pass any single-destination test.
local VAR2, VAR3 = 0x4001, 0x4002
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

-- SOME COMMANDS WRITE STATE RATHER THAN A VAR, and until this existed they
-- could only be checked for "did not raise" -- which is the shape of
-- assertion this file was written to stop. `probe(ctx)` returns whatever the
-- command was supposed to have changed.
local function expectState(name, args, probe, want, why)
  local ctx = newCtx()
  local fn = rawget(verbs, name)
  if type(fn) ~= "function" then
    results[#results+1] = ("%-34s MISSING"):format(name); failures = failures + 1
    return
  end
  if type(args) == "function" then args = args(ctx) end
  local ran, err = pcall(fn, ctx, (table.unpack or unpack)(args))
  if not ran then
    results[#results+1] = ("%-34s RAISED  %s"):format(name, tostring(err))
    failures = failures + 1
    return
  end
  local okProbe, got = pcall(probe, ctx)
  if not okProbe then
    results[#results+1] = ("%-34s PROBE RAISED  %s"):format(name, tostring(got))
    failures = failures + 1
    return
  end
  if got ~= want then
    results[#results+1] = ("%-34s WRONG STATE  got %s, want %s  (%s)")
      :format(name, tostring(got), tostring(want), tostring(why))
    failures = failures + 1
    return
  end
  results[#results+1] = ("%-34s ok      %s  (%s)")
    :format(name, tostring(got), tostring(why))
end

-- THE YES/NO MENU, BOTH WAYS.  The cartridge tests its destination against 0
-- for the yes branch and 1 for the no branch -- 496 of the 511 sites do it on
-- the very next instruction -- so both values have to be right, and asserting
-- only one of them would pass with them swapped.
expect("g4_from_yesno", function(ctx) ctx.lastCheck = true;  return { VAR } end,
       VAR, 0, "MENU_YES is 0 -- a menu numbers its rows from the top")
expect("g4_from_yesno", function(ctx) ctx.lastCheck = false; return { VAR } end,
       VAR, 1, "MENU_NO is 1")

-- `survivepoison` -- the Gen 4 rule: poisoned AND at exactly 1 HP gets cured.
-- The arms that matter are the near misses, so 2 HP and 0 HP are both here:
-- `<= 1` instead of `== 1` would cure a fainted Pokemon, and nothing in the
-- script would notice.
expect("g4_survive_poison", function(ctx)
         ctx.save.party = { { status = "PSN", hp = 1 } }; return { VAR, 0 }
       end, VAR, 1, "poisoned at exactly 1 HP survives")
expect("g4_survive_poison", function(ctx)
         ctx.save.party = { { status = "PSN", hp = 2 } }; return { VAR, 0 }
       end, VAR, 0, "at 2 HP it is not yet the end of the road")
expect("g4_survive_poison", function(ctx)
         ctx.save.party = { { status = "PSN", hp = 0 } }; return { VAR, 0 }
       end, VAR, 0, "0 is not 1 -- a fainted mon is not cured")
expect("g4_survive_poison", function(ctx)
         ctx.save.party = { { status = "TOX", hp = 1 } }; return { VAR, 0 }
       end, VAR, 1, "badly poisoned counts too: the test is (TOXIC | POISON)")
expectState("g4_survive_poison", function(ctx)
              ctx.save.party = { { status = "PSN", hp = 1 } }; return { VAR, 0 }
            end,
            function(ctx) return ctx.save.party[1].status end,
            nil, "surviving CLEARS the status, which is the point of the command")
expectState("g4_survive_poison", function(ctx)
              ctx.save.party = { { status = "PSN", hp = 3 } }; return { VAR, 0 }
            end,
            function(ctx) return ctx.save.party[1].status end,
            "PSN", "a mon that did not survive keeps its poison")

-- `isitemtmhm` -- AT THE BOUNDARIES, because that is where an id range is
-- wrong. `Item_IsTMHM` is `item >= ITEM_TM01 && item <= ITEM_HM08`, which on
-- this cache is 328..427; 327 is Razor Fang and 428 the Explorer Kit. An
-- off-by-one at either end is invisible on a sample from the middle.
expect("g4_item_is_tmhm", {328, VAR}, VAR, 1, "TM01 is the low end of the range")
expect("g4_item_is_tmhm", {427, VAR}, VAR, 1, "HM08 is the high end")
expect("g4_item_is_tmhm", {419, VAR}, VAR, 1, "TM92, the last TM before the HMs")
expect("g4_item_is_tmhm", {327, VAR}, VAR, 0, "Razor Fang is one below TM01")
expect("g4_item_is_tmhm", {428, VAR}, VAR, 0, "the Explorer Kit is one above HM08")
expect("g4_item_is_tmhm", {17, VAR}, VAR, 0, "an ordinary item is not a TM")

-- `trysetunusedcollectedorbflag` -- the condition is the whole command, so both
-- sides of it. The ids are resolved by name, so this also checks the lookup.
expectState("g4_try_set_collected_orb_flag", {135},
            function(ctx) return ctx.save.underground
                                 and ctx.save.underground.collectedOrb end,
            true, "the Adamant Orb sets it")
expectState("g4_try_set_collected_orb_flag", {17},
            function(ctx) return ctx.save.underground
                                 and ctx.save.underground.collectedOrb end,
            nil, "an ordinary item does not")

-- `choosecustommessageword` -- no word-choice screen exists, so it answers the
-- cartridge's own cancelled path. BOTH destinations, because the script reads
-- one to branch and the other to use, and writing only the branch var would
-- pass a one-sided test and then put a stale word in a TV interview.
expect("g4_choose_message_word", { 0, VAR, VAR2 }, VAR, 0,
       "resultVar 0 is the cartridge's \"player backed out\"")
expect("g4_choose_message_word", { 0, VAR, VAR2 }, VAR2, 0xFFFF,
       "destVar 0xFFFF is what the C writes before the task even starts")

-- THE FIELD-MOVE FLAGS. Sub-functions 0 CLEAR, 1 SET, 2 CHECK -- and CHECK is
-- the only one with a destination, which is why the opcode is variable length.
-- All three directions, because a handler that ignored its sub-function byte
-- would pass any one of them alone.
expect("g4_field_move_flag", function(ctx)
         ctx.save.gen4FieldMoveFlags = { strength = true }
         return { "strength", 2, VAR }
       end, VAR, 1, "CHECK finds a flag that SET left behind")
expect("g4_field_move_flag", function(ctx) return { "strength", 2, VAR } end,
       VAR, 0, "CHECK on an unset flag is 0, not nil")
-- Each flag is its own: setting Strength must not answer for Flash.
expect("g4_field_move_flag", function(ctx)
         ctx.save.gen4FieldMoveFlags = { strength = true }
         return { "flash", 2, VAR }
       end, VAR, 0, "the three flags are separate")
expectState("g4_field_move_flag", { "defog", 1 },
            function(ctx) return ctx.save.gen4FieldMoveFlags.defog end,
            true, "SET writes the save, which is where the cartridge keeps it")
expectState("g4_field_move_flag", function(ctx)
              ctx.save.gen4FieldMoveFlags = { defog = true }
              return { "defog", 0 }
            end,
            function(ctx) return ctx.save.gen4FieldMoveFlags.defog end,
            nil, "CLEAR removes it")
-- THE MIRROR, which is the half that makes Strength do anything. The boulder
-- pusher reads `ow.strengthActive` and nothing else; Hoenn's boulders could
-- not be pushed for years because the flag was in the save and the pusher
-- never looked.
expectState("g4_field_move_flag", { "strength", 1 },
            function(ctx) return ctx.overworld.strengthActive end,
            true, "SET mirrors onto the field the boulder pusher reads")
expectState("g4_field_move_flag", function(ctx)
              ctx.overworld.strengthActive = true
              return { "strength", 0 }
            end,
            function(ctx) return ctx.overworld.strengthActive end,
            false, "CLEAR mirrors too, or Strength never wears off")

-- DEFOG AND FLASH CLEAR THE OVERWORLD WEATHER (0x0C3/0x0C4 are one function in
-- the cartridge). Both directions: the clear must be visible to the command
-- the scripts read weather with, and WITHOUT the clear that command must still
-- answer the map -- otherwise the test passes against a getter that always
-- says 0.
expectState("g4_clear_overworld_weather", {},
            function(ctx) return ctx.save.gen4WeatherCleared end,
            true, "the clear is recorded on the save")
expect("g4_overworld_weather", function(ctx)
         ctx.overworld.map.def = { weather = 5 }
         return { VAR }
       end, VAR, 5, "with no clear, the map's own weather byte answers")
expect("g4_overworld_weather", function(ctx)
         ctx.overworld.map.def = { weather = 5 }
         ctx.save.gen4WeatherCleared = true
         return { VAR }
       end, VAR, 0,
       "after Defog, the same map answers OVERWORLD_WEATHER_CLEAR (0)")

-- `usesurf` puts the player on the water. The Gen 1-3 mounts do this inline
-- around a textbox; the Sinnoh script has already printed its line and closed
-- the box, so this path must not print and must still change the state.
expectState("g4_use_surf", function(ctx)
              ctx.overworld.player = { surfing = false, elevation = 0,
                facingCell = function() return 1, 1 end }
              return { VAR }
            end,
            function(ctx) return ctx.overworld.player.surfing end,
            true, "the player is surfing afterwards")

-- THE TRAINER-BATTLE PREAMBLE, which until this pass wrote nothing at all.
-- Every one of these is reached by all 417 trainers in Sinnoh, so a wrong
-- answer here is wrong everywhere at once.
--
-- `gettrainermessagetypes` writes THREE vars and the zeroes are the
-- cartridge's own literals, not 'unset' -- so all three slots are asserted
-- separately.  Asserting only the first would pass with the other two
-- unwritten, which is precisely the bug the command exists to prevent.
local function singlesTypes(ctx) return { VAR, VAR2, VAR3 } end
expect("g4_trainer_message_types", singlesTypes, VAR,  0,
       "singles pre-battle is TRMSG_PRE_BATTLE")
expect("g4_trainer_message_types", singlesTypes, VAR2, 2,
       "singles post-battle is TRMSG_POST_BATTLE")
expect("g4_trainer_message_types", singlesTypes, VAR3, 0,
       "singles not-enough is a literal 0 in the C, which IS PRE_BATTLE")
expect("g4_trainer_message_types",
       function(ctx) return { VAR, VAR2, VAR3, "rematch" } end, VAR, 17,
       "rematch singles pre-battle is TRMSG_REMATCH")
expect("g4_trainer_message_types",
       function(ctx) return { VAR, VAR2, VAR3, "rematch" } end, VAR2, 0,
       "the rematch command writes a literal 0 for post-battle")

-- A disguised trainer is spotted by its MOVEMENT TYPE and nothing else.  Nine
-- objects in the cartridge carry one; 54 is MOVEMENT_TYPE_DISGUISE_ROCK, the
-- commonest of the four with five objects.
expect("g4_get_movement_type", function(ctx)
         ctx.overworld.map.def = { objects = {
           { localId = 3, movementType = 54 } } }
         return { VAR, 3 }
       end, VAR, 54, "MOVEMENT_TYPE_DISGUISE_ROCK is read off the object def")
-- ...and MOVEMENT_TYPE_NONE (0) for an object that is not there, which is the
-- cartridge's own default and not an error.
expect("g4_get_movement_type", function(ctx)
         ctx.overworld.map.def = { objects = {} }
         return { VAR, 3 }
       end, VAR, 0, "MOVEMENT_TYPE_NONE for an absent object")

-- The approach pair, derived from the two ids the overworld leaves on the
-- context.  BOTH directions, because a handler that always answered SINGLES
-- would pass a one-sided test and send every double battle down the single
-- branch.
expect("g4_approach_type", function(ctx)
         ctx.gen4ApproachingTrainers = { 5, 0 }; return { VAR }
       end, VAR, 0, "one trainer is APPROACH_TYPE_SINGLES")
expect("g4_approach_type", function(ctx)
         ctx.gen4ApproachingTrainers = { 5, 9 }; return { VAR }
       end, VAR, 1, "a non-zero second id is APPROACH_TYPE_DOUBLES")
-- No task was ever started, so the cartridge's own `*task == NULL` branch
-- applies and the answer is TRUE.  This is what stops
-- `Battles_WaitTrainerSinglesTaskDone` jumping to itself for ever.
expect("g4_approach_done", {0, VAR}, VAR, 1,
       "no task means done -- the C returns TRUE in exactly this case")

-- TRAINER_NONE is 0, and it is the answer for a trainer the V.S. Seeker has
-- not armed -- which is almost always.  `Battles_TryRematch` branches on NE,
-- so a nonzero default would re-challenge the player with a party that does
-- not exist.
expect("g4_get_rematch_trainer_id", function(ctx)
         ctx.npc = { def = { localId = 3 } }; return { 5, VAR }
       end, VAR, 0, "TRAINER_NONE for a trainer with no rematch armed")
-- ...AND THE OTHER DIRECTION, which is the half that makes the first one mean
-- anything: a handler hard-coded to 0 passes the case above and fails this.
-- The V.S. Seeker store is keyed "<map id>:<local id>", per object and not per
-- trainer, because one trainer id can stand on two maps.
expect("g4_get_rematch_trainer_id", function(ctx)
         ctx.npc = { def = { localId = 3 } }
         ctx.save.vsSeeker = { steps = 0, rematches = { ["C01:3"] = 412 } }
         return { 5, VAR }
       end, VAR, 412, "an armed object answers with its rematch trainer id")
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
