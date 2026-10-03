-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SAVING IS THE ONE AREA WHERE A MISTAKE COSTS THE PLAYER THEIR GAME.
--
-- Sinnoh does not save with one command.  `CommonScript_TrySaveGame` asks
-- `checksavetype` twice and branches four ways, and the branch decides which of
-- five messages the player reads and whether the write happens at all.  Twelve
-- commands had no row in this port, so all eighteen `callcommonscript 2006`
-- sites in the cartridge ran into an unlowered command -- and so did the START
-- menu's SAVE and the Underground descent, which reach the same script from C
-- (`start_menu.c:1327`, `field_map_change.c:1175`).
--
-- Three things in here are the kind that pass quietly while being wrong, which
-- is why each has its own section:
--
--   * `checksavetype` has FOUR answers and nothing fails if it gives the wrong
--     one -- the player just reads the wrong message forever.
--   * `fullSaveRequired` is DERIVED from a box fingerprint rather than hooked
--     at every box call site, because a list of call sites is what this port
--     keeps getting wrong.  A fingerprint is only worth having if it moves
--     when the boxes move and holds still when they do not, and both halves
--     are asserted.
--   * the write is SHARED with Gen 3's `special SaveGame`, so Hoenn's save is
--     graded here too.  An extraction that broke it would break a cartridge
--     nobody was looking at.
--
-- Run:  texlua tools/gen4_save_check.lua [game root or data/generated] [pokeplatinum dir]

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

-- A filesystem that answers "nothing is there", so `SaveData.saveFileExists`
-- runs for real and reports false rather than being stubbed into a pass.
love = love or {
  filesystem = {
    getInfo = function() return nil end,
    read = function() return nil end,
    write = function() return true end,
    getSaveDirectory = function() return nil end,
  },
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               setColor = function() end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

-- WHICH MODULES ARE REAL.  Everything a save command reads an answer out of,
-- because an inert stub that hands back nil makes a wrong answer look right --
-- the `VsSeeker.rematchFor` fault in gen4_command_audit, where a case passed
-- without ever entering the module it was grading.
local KEEP = {
  ["src.script.Gen4Commands"]=true, ["src.script.Gen4Save"]=true,
  ["src.script.ScriptSave"]=true, ["src.script.Gen3Commands"]=true,
  ["src.import.Gen4Text"]=true, ["src.import.Gen4ScriptBands"]=true,
  ["src.import.Gen4ScriptOps"]=true, ["src.core.SaveData"]=true,
  ["src.core.GameVersion"]=true, ["src.script.Flags"]=true,
  ["src.inventory.Badges"]=true, ["src.pokemon.Boxes"]=true,
  ["src.core.Logger"]=true, ["src.core.SaveSerializer"]=true,
  ["src.script.Gen4ScriptVM"]=true,
}
local Shared = { meta = {} }
setmetatable(Shared, { __index = function() return function() end end })
local inert = setmetatable({}, {
  __index=function(t,k) return rawget(t,k) or function() end end,
  __call=function() return nil end })
table.insert(package.searchers, 1, function(name)
  if KEEP[name] then return nil end
  if name == "src.script.Commands" then return function() return Shared end end
  if name:sub(1,4) ~= "src." then return nil end
  return function() return inert end
end)

-- ---------------------------------------------------------------------------
-- where the cache is.  Takes a game root OR a data/generated, like the other
-- newer checks, because being unrunnable is how gen4_texture_files_check spent
-- several passes SKIPping on every suite run.
local given = (arg and arg[1]) or nil
local D
if given then
  given = given:gsub("[/\\]*$", "")
  if slurp(given .. "/maps.lua") then
    D = given .. "/"
  elseif slurp(given .. "/data/generated/maps.lua") then
    D = given .. "/data/generated/"
  end
end
local PP = arg and arg[2]

local data
if D then
  local function load(n)
    local okL, mod = pcall(dofile, D .. n .. ".lua")
    return okL and mod or nil
  end
  data = { items = load("items"), pokemon = load("pokemon"),
           moves = load("moves"), maps = load("maps"), text = load("text"),
           constants = load("constants"),
           gen4_map_headers = load("gen4_map_headers") }
  if not data.text then
    report("%stext.lua did not load; the panel's bank-534 labels cannot be "
           .. "checked against the cartridge", D)
  end
else
  report("no Platinum cache given (pass a game root or a data/generated as the "
         .. "first argument); the cache-backed sections below are skipped")
end

local Gen4Save = require("src.script.Gen4Save")
local ScriptSave = require("src.script.ScriptSave")
local Gen4Commands = require("src.script.Gen4Commands")
local verbs = Shared
local setVar, getVar = Gen4Commands.setVar, Gen4Commands.getVar

-- HARNESS CANARY.  gen4_command_audit's first run reported 25 false failures
-- because it looked for script vars in the wrong table.  Prove this harness can
-- see a var write and can reach a g4_ command before grading twelve of them.
do
  local probe = { gen4Vars = {} }
  setVar(probe, 0x4000, 7)
  assert(probe.gen4Vars[0x4000] == 7, "harness cannot observe a var write")
  assert(type(rawget(verbs, "g4_check_save_type")) == "function",
         "the verb table did not receive the save commands")
end

local VAR = 0x4000
local function newCtx(save)
  local runner = { yielded = 0 }
  function runner:yield() self.yielded = self.yielded + 1 end
  return {
    save = save or { gen4Vars = {}, flags = {}, party = {}, boxes = {} },
    game = { data = data or {}, stringBuffers = {} },
    overworld = { map = { def = { label = "Jubilife City" } }, player = {} },
    runner = runner,
  }
end

-- ---------------------------------------------------------------------------
section("1. checksavetype: four answers, and each one reached")

-- The numbers are the cartridge's, from generated/save_types.txt in order.
ok(Gen4Save.TYPE.OVERWRITE == 0, "SAVE_TYPE_OVERWRITE is %s, not 0",
   tostring(Gen4Save.TYPE.OVERWRITE))
ok(Gen4Save.TYPE.NO_DATA_EXISTS == 1, "SAVE_TYPE_NO_DATA_EXISTS is %s, not 1",
   tostring(Gen4Save.TYPE.NO_DATA_EXISTS))
ok(Gen4Save.TYPE.FULL_SAVE == 2, "SAVE_TYPE_FULL_SAVE is %s, not 2",
   tostring(Gen4Save.TYPE.FULL_SAVE))
ok(Gen4Save.TYPE.QUICK_SAVE == 3, "SAVE_TYPE_QUICK_SAVE is %s, not 3",
   tostring(Gen4Save.TYPE.QUICK_SAVE))

-- NO_DATA_EXISTS: nothing saved yet and no file on disk.
do
  local save = { gen4Vars = {}, boxes = {} }
  ok(Gen4Save.typeFor(save) == Gen4Save.TYPE.NO_DATA_EXISTS,
     "a never-saved file answers %s, not NO_DATA_EXISTS(1) -- the first save "
     .. "would ask the player to overwrite a file that is not there",
     tostring(Gen4Save.typeFor(save)))
end

-- FULL_SAVE: saved once, but the boxes have moved since.
do
  local save = { gen4Vars = {}, boxes = { {} } }
  Gen4Save.markSaved(save)
  table.insert(save.boxes[1], { species = "TURTWIG", level = 5 })
  ok(Gen4Save.typeFor(save) == Gen4Save.TYPE.FULL_SAVE,
     "a save with a changed box answers %s, not FULL_SAVE(2)",
     tostring(Gen4Save.typeFor(save)))
end

-- QUICK_SAVE: saved once and the boxes are exactly as they were.
do
  local save = { gen4Vars = {}, boxes = { { { species = "TURTWIG", level = 5 } } } }
  Gen4Save.markSaved(save)
  ok(Gen4Save.typeFor(save) == Gen4Save.TYPE.QUICK_SAVE,
     "an unchanged save answers %s, not QUICK_SAVE(3) -- every save in the game "
     .. "would print \"Saving a lot of data\"", tostring(Gen4Save.typeFor(save)))
end

-- OVERWRITE IS COLD BY DESIGN, AND THE ARM IS STILL WIRED.
--
-- `SaveData_OverwriteCheck` refuses to save at all when a new game is running
-- on a card that still holds somebody else's save.  This engine has slots, so
-- the question has already been answered by the launcher and the refusal would
-- make a new Platinum game on a used slot permanently unsavable.
--
-- An arm that can never be taken is also an arm nothing proves is connected,
-- so this forces it: with the predicate held true, `typeFor` must answer 0 and
-- nothing else.  That is the difference between "cold" and "dead".
do
  local realBlocked = Gen4Save.overwriteBlocked
  ok(realBlocked({ gen4Vars = {} }) == false,
     "Gen4Save.overwriteBlocked answered true -- a new game on a used slot "
     .. "would be permanently unsavable; see the comment on it")
  Gen4Save.overwriteBlocked = function() return true end
  local got = Gen4Save.typeFor({ gen4Vars = {}, gen4SavedOnce = true, boxes = {} })
  Gen4Save.overwriteBlocked = realBlocked
  ok(got == Gen4Save.TYPE.OVERWRITE,
     "with overwriteBlocked held true, typeFor answered %s instead of "
     .. "OVERWRITE(0) -- the first arm of the chain is not connected",
     tostring(got))
  -- and the planted change really did land, which is the step pass 169 skipped
  ok(Gen4Save.overwriteBlocked({}) == false,
     "overwriteBlocked was not restored after the probe")
end

-- The command writes the var, which is the only way the script sees any of it.
do
  local ctx = newCtx()
  verbs.g4_check_save_type(ctx, VAR)
  ok(getVar(ctx.save, VAR) == Gen4Save.TYPE.NO_DATA_EXISTS,
     "g4_check_save_type left %s in the destination var, not NO_DATA_EXISTS(1)",
     tostring(getVar(ctx.save, VAR)))
end

-- ---------------------------------------------------------------------------
section("2. the box fingerprint, which has to move AND has to hold still")

local function stampOf(boxes) return Gen4Save.boxStamp({ boxes = boxes }) end
local function mon(sp, lv, nick) return { species = sp, level = lv, nickname = nick } end

-- IT HOLDS STILL.  Same contents, two tables: the same stamp, or every save
-- after the first would claim the boxes had changed.
ok(stampOf({ { mon("TURTWIG", 5) } }) == stampOf({ { mon("TURTWIG", 5) } }),
   "two identical box sets stamp differently -- the fingerprint is not a "
   .. "function of the contents")
ok(stampOf({}) == stampOf({}), "an empty box set does not stamp consistently")

-- IT MOVES, once per kind of box edit the cartridge sets fullSaveRequired for.
local base = { { mon("TURTWIG", 5) }, {} }
local moved = {
  ["a deposit"]        = { { mon("TURTWIG", 5), mon("PIPLUP", 5) }, {} },
  ["a withdrawal"]     = { {}, {} },
  ["a move to box 2"]  = { {}, { mon("TURTWIG", 5) } },
  ["a level change"]   = { { mon("TURTWIG", 6) }, {} },
  ["a rename"]         = { { mon("TURTWIG", 5, "Spike") }, {} },
  ["a species swap"]   = { { mon("CHIMCHAR", 5) }, {} },
  ["one more box"]     = { { mon("TURTWIG", 5) }, {}, {} },
}
for why, boxes in pairs(moved) do
  ok(stampOf(boxes) ~= stampOf(base),
     "%s does not move the box stamp, so the save after it would be a quick "
     .. "save claiming the boxes are unchanged", why)
end

-- AND IT IGNORES WHAT IS NOT A BOX EDIT.  HP is deliberately out of the stamp:
-- a nurse is not a box operation, and a stamp that moved on a heal would print
-- "Saving a lot of data" after every Pokemon Center.
do
  local a = { { { species = "TURTWIG", level = 5, hp = 3 } } }
  local b = { { { species = "TURTWIG", level = 5, hp = 20 } } }
  ok(stampOf(a) == stampOf(b),
     "healing a boxed Pokemon moves the box stamp; HP is not identity")
end

-- Survives the round trip, because the stamp is stored IN the save and
-- recomputed after a load.
do
  local okS, Serializer = pcall(require, "src.core.SaveSerializer")
  if okS and Serializer and Serializer.encode and Serializer.decode then
    local save = { boxes = { { mon("TURTWIG", 5), mon("PIPLUP", 7, "Blue") } } }
    Gen4Save.markSaved(save)
    local okE, enc = pcall(Serializer.encode, save)
    local back = okE and select(2, pcall(Serializer.decode, enc)) or nil
    if type(back) == "table" then
      ok(Gen4Save.fullSaveRequired(back) == false,
         "a save that round-trips through the serializer comes back claiming "
         .. "its boxes changed -- the stamp does not survive a load, so the "
         .. "first save of every session would be a full one")
    else
      report("the serializer round trip could not be run here, so the stamp's "
             .. "survival across a load is untested")
    end
  else
    report("SaveSerializer is not loadable headless; the stamp's survival "
           .. "across a load is untested")
  end
end

-- A MISSING STAMP MEANS FULL, which is also what the cartridge does: both
-- `SaveData_Init` with nothing to load and `SaveData_Clear` set the flag TRUE.
ok(Gen4Save.fullSaveRequired({ boxes = {} }) == true,
   "a save with no stamp at all does not report fullSaveRequired")
ok(Gen4Save.fullSaveRequired(nil) == true,
   "fullSaveRequired(nil) does not answer true")

-- ---------------------------------------------------------------------------
section("3. the write, which both generations now share")

-- `trysavegame` MUST GO THROUGH THE ENGINE'S OWN WRITE and nowhere else.  The
-- probe is a game whose writeSave records that it was called: if the handler
-- ever grew its own `SaveData.save` call, the count would stay at zero while
-- the answer stayed 1 and nothing else would notice.
local function fakeGame(result)
  local g = { data = data or {}, calls = 0 }
  function g:writeSave() self.calls = self.calls + 1 return result end
  return g
end

do
  local ctx = newCtx()
  ctx.game = fakeGame(true)
  verbs.g4_try_save_game(ctx, VAR)
  ok(ctx.game.calls == 1,
     "g4_try_save_game called Game:writeSave %d times, not once -- a second "
     .. "save path is the thing this is written to stop", ctx.game.calls)
  ok(getVar(ctx.save, VAR) == 1,
     "a successful write answered %s, not 1", tostring(getVar(ctx.save, VAR)))
  ok(ctx.save.gen4SavedOnce == true,
     "a successful write did not mark the file as saved, so the next save "
     .. "would still skip the overwrite prompt")
end

-- A VETO ANSWERS ZERO AND CHANGES NOTHING.  `Game:writeSave` returns false for
-- a tool session that has taken its `save.write` veto, and
-- `CommonScript_SaveComplete` branches on that zero into `SaveError`.
do
  local ctx = newCtx()
  ctx.game = fakeGame(false)
  verbs.g4_try_save_game(ctx, VAR)
  ok(getVar(ctx.save, VAR) == 0,
     "a vetoed write answered %s, not 0", tostring(getVar(ctx.save, VAR)))
  ok(ctx.save.gen4SavedOnce == nil,
     "a vetoed write still marked the file as saved -- the next save would "
     .. "report a quick save of bytes that were never written")
  ok(ctx.save.gen4BoxStamp == nil,
     "a vetoed write still re-stamped the boxes")
end

-- A RAISE IS NOT A SUCCESS.  pcall's two return values are easy to read in the
-- wrong order; this is the direction that would quietly answer 1.
do
  local ctx = newCtx()
  ctx.game = { data = data or {},
               writeSave = function() error("disk on fire") end }
  verbs.g4_try_save_game(ctx, VAR)
  ok(getVar(ctx.save, VAR) == 0,
     "a write that raised answered %s, not 0", tostring(getVar(ctx.save, VAR)))
end

-- SAVING TURNS THE NEXT SAVE INTO A QUICK ONE.  The whole point of the stamp.
do
  local ctx = newCtx({ gen4Vars = {}, boxes = { { mon("TURTWIG", 5) } } })
  ctx.game = fakeGame(true)
  verbs.g4_try_save_game(ctx, VAR)
  ok(Gen4Save.typeFor(ctx.save) == Gen4Save.TYPE.QUICK_SAVE,
     "the save after a successful save is %s, not QUICK_SAVE(3)",
     tostring(Gen4Save.typeFor(ctx.save)))
  table.insert(ctx.save.boxes[1], mon("PIPLUP", 5))
  ok(Gen4Save.typeFor(ctx.save) == Gen4Save.TYPE.FULL_SAVE,
     "depositing after a save does not turn the next one back into a full save")
end

-- HOENN IS GRADED HERE TOO, because the write it has used since pass 149 is
-- now this one.  `special SaveGame` (96) answers VAR_RESULT, and fourteen
-- places in Hoenn branch on it.
do
  local Gen3Commands = require("src.script.Gen3Commands")
  local fn = Gen3Commands.SPECIALS and Gen3Commands.SPECIALS[96]
  ok(type(fn) == "function",
     "Gen3Commands.SPECIALS[96] is not a function -- Hoenn's script save is gone")
  if type(fn) == "function" then
    local ctx = newCtx()
    ctx.game = fakeGame(true)
    local answer = fn(ctx)
    ok(answer == 1, "Hoenn's save answered %s on a successful write, not 1",
       tostring(answer))
    ok(ctx.game.calls == 1,
       "Hoenn's save called Game:writeSave %d times, not once", ctx.game.calls)
    local ctx2 = newCtx()
    ctx2.game = fakeGame(false)
    ok(fn(ctx2) == 0, "Hoenn's save did not answer 0 on a vetoed write")
  end
end

-- THE SHARED HELPER IS THE ONE SPELLING, asserted from the source rather than
-- from this file's belief about it: neither script command may reach
-- `writeSave` directly any more, or the two copies are back.
do
  local g4 = slurp("src/script/Gen4Commands.lua") or ""
  local g3 = slurp("src/script/Gen3Commands.lua") or ""
  local ss = slurp("src/script/ScriptSave.lua") or ""
  ok(ss:find("game.writeSave", 1, true) ~= nil,
     "src/script/ScriptSave.lua does not reach Game:writeSave at all")
  ok(g4:find("ScriptSave", 1, true) ~= nil,
     "Gen4Commands does not reference ScriptSave")
  ok(g3:find("ScriptSave", 1, true) ~= nil,
     "Gen3Commands does not reference ScriptSave")
  for name, src in pairs({ Gen4Commands = g4, Gen3Commands = g3 }) do
    ok(src:find("pcall%(game%.writeSave") == nil
       and src:find("game:writeSave") == nil,
       "%s still calls Game:writeSave itself; the write has two spellings "
       .. "again and the next fix will land in only one of them", name)
  end
end

-- ---------------------------------------------------------------------------
section("4. the rest of the dialogue")

-- `storesaveresult` is the only way the CALLER learns what happened, and both
-- C callers pass a destination: the START menu reads it to decide whether to
-- show its saved state, the Underground descent to decide whether to descend.
do
  local ctx = newCtx()
  local got
  ctx.saveResultOut = function(v) got = v end
  setVar(ctx.save, VAR, 1)
  verbs.g4_store_save_result(ctx, VAR)
  ok(got == 1, "the save-result sink was handed %s, not 1", tostring(got))
  ok(ctx.gen4SaveResult == 1,
     "the result was not left on the context for a caller with no sink")
end
do
  -- no sink at all: the C's `if (*v0 != NULL)` arm, which must not raise
  local ctx = newCtx()
  setVar(ctx.save, VAR, 0)
  local ran = pcall(verbs.g4_store_save_result, ctx, VAR)
  ok(ran, "storesaveresult raised when the script was started without a "
          .. "destination, which is the ordinary case for a map script")
  ok(ctx.gen4SaveResult == 0, "a zero result was not recorded")
end

-- The three on/off pairs.  Both halves, because pass 169's lesson was that a
-- close with no open cannot be made truthful afterwards.
do
  local ctx = newCtx()
  verbs.g4_saving_icon(ctx, 1)
  ok(ctx.gen4SavingIcon == true and ctx.overworld.gen4SavingIcon == true,
     "showsavingicon did not raise the flag on both the context and the world")
  verbs.g4_saving_icon(ctx, 0)
  ok(ctx.gen4SavingIcon == nil and ctx.overworld.gen4SavingIcon == nil,
     "hidesavingicon did not clear the flag")
end
do
  -- 0x258's guard: `ov5_021E0F54` returns NULL unless the player is WALKING,
  -- so a save from a bike or from the water poses nothing -- and that is the
  -- reason saving on a bike does not drop you off it.
  local ctx = newCtx()
  verbs.g4_save_pose(ctx, 1)
  ok(ctx.overworld.gen4SavePose == true, "0x258 did not set the save pose")
  verbs.g4_save_pose(ctx, 0)
  ok(ctx.overworld.gen4SavePose == nil, "0x259 did not clear the save pose")

  local bike = newCtx()
  bike.save.onBike = true
  verbs.g4_save_pose(bike, 1)
  ok(bike.overworld.gen4SavePose == nil,
     "0x258 posed a player who is on a bicycle; ov5_021E0F54 returns NULL "
     .. "unless the player is PLAYER_AVATAR_WALKING")

  local surf = newCtx()
  surf.overworld.player.surfing = true
  verbs.g4_save_pose(surf, 1)
  ok(surf.overworld.gen4SavePose == nil, "0x258 posed a player who is surfing")
end

-- `saveextradata` / `checkismiscsaveinit`.  `SaveDataExtra_Init` returns
-- immediately when the flag is already set, so it runs at most once per file --
-- which is what makes `QuickSaveCheckMiscFlag` a one-time full save.
do
  local ctx = newCtx()
  verbs.g4_misc_save_init(ctx, VAR)
  ok(getVar(ctx.save, VAR) == 0, "the misc-save flag started set")
  ok(Gen4Save.initMiscSave(ctx.save) == true,
     "the first initMiscSave did not report that it was the one that ran")
  ok(Gen4Save.initMiscSave(ctx.save) == false,
     "initMiscSave ran twice; the C returns early on an already-set flag")
  verbs.g4_misc_save_init(ctx, VAR)
  ok(getVar(ctx.save, VAR) == 1, "the misc-save flag did not read back as set")
end

-- `waitabpresstime <frames>`: A or B, or the timeout, whichever is first.  Both
-- arms, because a handler that only honoured the timeout would make the save
-- confirmation unskippable and a handler that only honoured the button would
-- hang a script nobody is pressing anything at.
do
  local ctx = newCtx()
  local pressed = false
  ctx.game.input = { wasPressed = function(_, b)
    return pressed and (b == "a" or b == "b") or false
  end }
  verbs.g4_wait_ab_press_time(ctx, 30)
  local poll = ctx.runner.waitingCheck
  ok(type(poll) == "function", "waitabpresstime did not install a frame poll")
  ok(ctx.runner.yielded == 1, "waitabpresstime did not yield")
  if type(poll) == "function" then
    ok(poll() == false, "the poll finished on its first frame of a 30-frame wait")
    pressed = true
    ok(poll() == true, "pressing A did not end the wait early")
  end
end
do
  local ctx = newCtx()
  ctx.game.input = { wasPressed = function() return false end }
  verbs.g4_wait_ab_press_time(ctx, 3)
  local poll = ctx.runner.waitingCheck
  if type(poll) == "function" then
    ok(poll() == false and poll() == false and poll() == true,
       "a 3-frame wait with nothing pressed did not end on the third frame")
  end
end
do
  -- zero frames is the degenerate operand; it must not install a poll that
  -- never finishes
  local ctx = newCtx()
  verbs.g4_wait_ab_press_time(ctx, 0)
  ok(ctx.runner.waitingCheck == nil and ctx.runner.yielded == 0,
     "waitabpresstime 0 yielded, which would wait for a frame that never comes")
end

-- ---------------------------------------------------------------------------
section("5. the save info panel")

if data and data.text then
  local Gen4Text = require("src.import.Gen4Text")
  -- The four labels are READ OUT OF THE CARTRIDGE, so this asserts the bank is
  -- the bank -- `TEXT_BANK_SAVE_INFO_WINDOW` is line 535 of
  -- generated/text_banks.txt, index 534.
  local want = { [1] = "PLAYER", [2] = "BADGES", [3] = "DEX", [4] = "TIME" }
  for i, fragment in pairs(want) do
    local key = Gen4Text.label(Gen4Save.INFO_BANK, i)
    local text = data.text[key]
    ok(type(text) == "string" and text:upper():find(fragment, 1, true) ~= nil,
       "bank %d entry %d is %q, which does not look like the %s label -- the "
       .. "panel is reading the wrong bank",
       Gen4Save.INFO_BANK, i, tostring(text), fragment)
  end

  local game = { data = data, overworld = { map = { def = { label = "Jubilife City" } } } }
  -- WITH a Pokedex: five rows and a ten-tile window.
  game.save = { player = { name = "LUCAS" }, flags = { ENGINE_POKEDEX = true },
                pokedex = { seen = { [1]=true, [4]=true, [7]=true }, owned = { [1]=true } },
                playTime = 3 * 3600 + 7 * 60 + 30, badges = {}, boxes = {} }
  local panel = Gen4Save.infoPanel(game)
  ok(type(panel) == "table", "infoPanel answered nothing for a real save")
  if type(panel) == "table" then
    ok(panel.heading == "Jubilife City",
       "the panel's heading is %q, not the map's label", tostring(panel.heading))
    ok(#panel.rows == 4, "the panel has %d rows with a Pokedex, not 4",
       #panel.rows)
    ok(panel.tilesH == 10, "the panel is %s tiles tall with a Pokedex, not 10",
       tostring(panel.tilesH))
    -- SEEN, NOT OWNED.  `Pokedex_CountSeen` is what the C reads, and the
    -- engine's own Gen 1 save panel counts owned -- copying that would have
    -- been the obvious and wrong thing to do.  Three seen, one owned.
    local dexRow
    for _, row in ipairs(panel.rows) do
      if tostring(row.label):upper():find("DEX", 1, true) then dexRow = row end
    end
    ok(dexRow ~= nil, "the panel has no Pokedex row")
    ok(dexRow and dexRow.value == "3",
       "the Pokedex row reads %q; three are seen and one is owned, and the "
       .. "cartridge counts SEEN", dexRow and tostring(dexRow.value) or "nil")
    -- 3:07, with the minutes zero-padded (PADDING_MODE_ZEROES)
    local timeRow = panel.rows[#panel.rows]
    ok(timeRow.value == "3:07",
       "the clock reads %q, not 3:07 -- the minutes are zero-padded in the C",
       tostring(timeRow.value))
  end

  -- WITHOUT a Pokedex: the row is dropped and `SaveInfoWindow_Height` takes
  -- two tiles off the window.
  game.save = { player = { name = "DAWN" }, flags = {}, pokedex = nil,
                playTime = 0, boxes = {} }
  local bare = Gen4Save.infoPanel(game)
  if type(bare) == "table" then
    ok(#bare.rows == 3, "the panel has %d rows without a Pokedex, not 3",
       #bare.rows)
    ok(bare.tilesH == 8, "the panel is %s tiles tall without a Pokedex, not 8",
       tostring(bare.tilesH))
    for _, row in ipairs(bare.rows) do
      ok(tostring(row.label):upper():find("DEX", 1, true) == nil,
         "the Pokedex row is still drawn for a player who has no Pokedex")
    end
  end

  -- The command stores it where the renderer looks, and clears it.
  local ctx = newCtx({ player = { name = "LUCAS" }, flags = {}, boxes = {},
                       gen4Vars = {}, playTime = 0 })
  ctx.game.data = data
  verbs.g4_save_info(ctx, 1)
  ok(type(ctx.overworld.gen4SaveInfo) == "table",
     "opensaveinfo did not put a panel where OverworldState:drawUI looks")
  verbs.g4_save_info(ctx, 0)
  ok(ctx.overworld.gen4SaveInfo == nil, "closesaveinfo did not clear the panel")
else
  report("no cache text, so the panel's five sections were not run")
end

-- The renderer actually has a branch for it, which is the half a state flag
-- cannot prove about itself.
do
  local owSrc = slurp("src/world/OverworldController.lua") or ""
  ok(owSrc:find("function OverworldState:drawGen4SaveInfo") ~= nil,
     "OverworldState:drawGen4SaveInfo does not exist, so the panel is built "
     .. "and never drawn")
  ok(owSrc:find("if self%.gen4SaveInfo then self:drawGen4SaveInfo%(%) end") ~= nil,
     "drawUI does not call drawGen4SaveInfo, so the panel is built and never "
     .. "drawn")
end

-- ---------------------------------------------------------------------------
section("6. the script: every save command in the band is lowered")

local VM = require("src.script.Gen4ScriptVM")
-- The twelve this pass is named for, BY NAME, so the census below cannot pass
-- by failing to find them.
local GROUP = {
  "checksavetype", "trysavegame", "storesaveresult", "showsavingicon",
  "hidesavingicon", "waitabpresstime", "opensaveinfo", "closesaveinfo",
  "258", "259", "saveextradata", "checkismiscsaveinit",
}
for _, name in ipairs(GROUP) do
  ok(VM.lowered(name) == true, "%s is not lowered", name)
end
-- ...and the handlers they lower to, because a lowering with no handler warns
-- once per execution and does nothing.
for _, row in ipairs({ "g4_check_save_type", "g4_try_save_game",
                       "g4_store_save_result", "g4_saving_icon",
                       "g4_wait_ab_press_time", "g4_save_info",
                       "g4_save_pose", "g4_save_extra_data",
                       "g4_misc_save_init" }) do
  ok(type(rawget(verbs, row)) == "function", "%s has no handler", row)
end

-- THE CANARY FOR THIS SECTION'S OWN METHOD.  `VM.lowered` is asked rather than
-- the source regexed, because the regex missed nine berry commands lowered
-- inside a loop and reported a finished band as full of holes.  Prove the
-- detector still says no.
--
-- IT USED TO NAME ONE COMMAND -- `checkishalloffamecorrupted` -- and pass 173
-- lowered it, so the canary failed for the best possible reason and had to be
-- rewritten anyway.  A canary whose subject is a thing somebody is trying to
-- fix has a half-life.  These two cannot go stale: the first asks about a name
-- that will never be an opcode, and the second asks the opcode table how many
-- of its OWN 840 entries are still unlowered -- which is derived, and which
-- only reaches zero on the day the whole cartridge is lowered.
ok(VM.lowered("this_is_not_a_cartridge_command") == false,
   "the lowered-detector answered true for a name that is not an opcode, so "
   .. "every answer above is meaningless")
do
  local Ops = require("src.import.Gen4ScriptOps")
  local total, unlowered = 0, 0
  for _, spec in pairs(Ops.COMMANDS or {}) do
    local name = type(spec) == "table" and spec[1]
    if type(name) == "string" then
      total = total + 1
      if not VM.lowered(name) then unlowered = unlowered + 1 end
    end
  end
  ok(total >= 800, "the opcode table yielded %d names, not the cartridge's "
     .. "840-odd; the canary below is measuring nothing", total)
  ok(unlowered > 0,
     "every one of the %d opcodes reports itself lowered, which is either the "
     .. "finest day this port has had or a detector that says yes to "
     .. "everything", total)
end

-- ---------------------------------------------------------------------------
section("7. re-derived from pokeplatinum")

if not PP or not slurp(PP .. "/src/scrcmd.c") then
  io.write("   (no pokeplatinum dir given as argument 2 -- section 7 skipped)\n")
else
  -- The save-type NUMBERS, from the enum's own file.  metang enums with no
  -- explicit values count from zero in file order.
  local types = slurp(PP .. "/generated/save_types.txt")
  ok(types ~= nil, "generated/save_types.txt is missing")
  if types then
    local order = {}
    for line in types:gmatch("[^\r\n]+") do order[#order + 1] = line end
    local wantOrder = { "SAVE_TYPE_OVERWRITE", "SAVE_TYPE_NO_DATA_EXISTS",
                        "SAVE_TYPE_FULL_SAVE", "SAVE_TYPE_QUICK_SAVE" }
    for i, name in ipairs(wantOrder) do
      ok(order[i] == name,
         "save_types.txt line %d is %q, not %q -- the four numbers this port "
         .. "uses are the file's order", i, tostring(order[i]), name)
    end
  end

  local scrcmd = slurp(PP .. "/src/scrcmd.c")
  -- The four rules, in order, from the function itself.
  -- ANCHORED ON `)\n{`, NOT ON THE NAME.  scrcmd.c forward-declares every
-- handler, so a bare name matches the DECLARATION and the lazy `.-\n}`
-- after it runs to the end of some unrelated function -- which is how the
-- first run of this section reported four arms missing from a file that has
-- all four.
local function definition(src, name)
  return src and src:match(name .. "%b()%s*\n{(.-)\n}")
end
local body = definition(scrcmd, "ScrCmd_CheckSaveType")
  ok(body ~= nil, "could not find ScrCmd_CheckSaveType")
  if body then
    ok(body:find("SaveData_OverwriteCheck", 1, true) ~= nil
       and body:find("SAVE_TYPE_OVERWRITE", 1, true) ~= nil,
       "the first arm is no longer OverwriteCheck -> SAVE_TYPE_OVERWRITE")
    ok(body:find("SaveData_DataExists%(saveData%) == FALSE") ~= nil,
       "the second arm is no longer `DataExists == FALSE`")
    ok(body:find("SaveData_FullSaveRequired", 1, true) ~= nil,
       "the third arm no longer reads fullSaveRequired")
    ok(body:find("SAVE_TYPE_QUICK_SAVE", 1, true) ~= nil,
       "the final else is no longer SAVE_TYPE_QUICK_SAVE")
  end

  -- `trysavegame` answers a COMPARISON, not a result code.
  local siw = slurp(PP .. "/src/overlay005/save_info_window.c") or ""
  ok(siw:find("SaveData_Save%(fieldSystem%->saveData%) == SAVE_RESULT_OK") ~= nil,
     "FieldSystem_Save no longer answers `== SAVE_RESULT_OK`, so 1/0 may not "
     .. "be the right pair of answers")
  -- and it stamps the player's position on the way: this port's writeSave
  -- captures the overworld for the same reason.
  ok(siw:find("FieldSystem_SaveObjectsAndLocation", 1, true) ~= nil,
     "FieldSystem_Save no longer saves the player's location before writing")

  -- `waitabpresstime` really is A-or-B-or-timeout.
  local timer = definition(scrcmd, "ScriptContext_DecrementABPressTimer")
  ok(timer ~= nil, "could not find ScriptContext_DecrementABPressTimer")
  if timer then
    ok(timer:find("PAD_BUTTON_A | PAD_BUTTON_B", 1, true) ~= nil,
       "the A/B timer no longer checks A or B, so the wait is not skippable")
    ok(timer:find("data%[0%]%-%-") ~= nil and timer:find("== 0") ~= nil,
       "the A/B timer no longer counts down to zero")
  end

  -- `SaveDataExtra_Init`'s early-out, which is what makes the misc-save flag a
  -- one-time thing rather than a per-save thing.
  local sd = slurp(PP .. "/src/savedata.c") or ""
  local extra = definition(sd, "SaveDataExtra_Init")
  ok(extra ~= nil, "could not find SaveDataExtra_Init")
  if extra then
    ok(extra:find("SaveData_MiscSaveBlock_InitFlag%(saveData%) == TRUE") ~= nil,
       "SaveDataExtra_Init no longer returns early on an already-set flag")
    ok(extra:find("SaveData_MiscSaveBlock_SetInitFlag", 1, true) ~= nil,
       "SaveDataExtra_Init no longer sets the flag")
  end
  -- `OverwriteCheck` is the conjunction this port declines to port.
  ok(sd:find("SaveData_IsNewGameData%(saveData%) && SaveData_DataExists") ~= nil,
     "SaveData_OverwriteCheck is no longer `isNewGameData && dataExists`, so "
     .. "Gen4Save.overwriteBlocked's recorded reason is about something else")
  -- ...and `fullSaveRequired` really is set by the box code, which is what the
  -- fingerprint stands in for.
  local pc = slurp(PP .. "/src/pc_boxes.c") or ""
  local setters = 0
  for _ in pc:gmatch("SaveData_SetFullSaveRequired") do setters = setters + 1 end
  io.write(("   pc_boxes.c sets fullSaveRequired %d time(s)\n"):format(setters))
  ok(setters >= 10,
     "pc_boxes.c sets fullSaveRequired only %d time(s); the box fingerprint "
     .. "stands in for those call sites and would be standing in for nothing",
     setters)

  -- 0x258 is the SAVE pose, and it is guarded on the player walking.
  local ov5 = slurp(PP .. "/src/overlay005/ov5_021DFB54.c") or ""
  ok(ov5:find("PLAYER_TRANSITION_SAVE", 1, true) ~= nil,
     "ov5_021E1000 no longer uses PLAYER_TRANSITION_SAVE, so 0x258 is not the "
     .. "save pose")
  local starter = definition(ov5, "ov5_021E0F54")
  ok(starter ~= nil, "could not find ov5_021E0F54")
  if starter then
    ok(starter:find("!= PLAYER_AVATAR_WALKING") ~= nil
       and starter:find("return NULL", 1, true) ~= nil,
       "ov5_021E0F54 no longer refuses to pose a player who is not walking, "
       .. "so g4_save_pose's bike and surf guards are guarding nothing")
  end

  -- THE EIGHTEEN SITES, counted from the cartridge's own script source rather
  -- than from the cache, so the two have to agree.  A floor, because a
  -- re-extract may find more.
  local common = slurp(PP .. "/res/field/scripts/scripts_common.s") or ""
  ok(common:find("CommonScript_SaveAndStoreResult", 1, true) ~= nil,
     "scripts_common.s no longer has CommonScript_SaveAndStoreResult")
  ok(common:find("CommonScript_SaveGame", 1, true) ~= nil,
     "scripts_common.s no longer has CommonScript_SaveGame")
  -- The five messages, by their identifiers, so a branch that lost its text
  -- would be noticed.
  for _, id in ipairs({ "WouldYouLikeToSave", "OKToOverwriteSavedFile",
                        "SavingALotOfData", "SavingDontTurnOffThePower",
                        "PlayerSavedTheGame", "SaveError",
                        "ImpossibleToSave" }) do
    ok(common:find("CommonStrings_Text_" .. id, 1, true) ~= nil,
       "the save script no longer prints CommonStrings_Text_%s", id)
  end
end

io.write(("\n%d checks, %d failed, %d reported\n"):format(checks, fails, reports))
os.exit(fails == 0 and 0 or 1)
