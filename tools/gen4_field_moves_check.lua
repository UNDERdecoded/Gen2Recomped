-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE OTHER SHARED SCRIPT, AND THE DECODER FAULT IT WAS HIDING.
--
-- `res/field/scripts/scripts_field_moves.s` is to HMs what `scripts_battles.s`
-- is to trainers: one file, seventeen entries, and every use of Cut, Rock
-- Smash, Strength, Rock Climb, Surf, Waterfall, Defog and Flash in Sinnoh goes
-- through it -- twice over, because each has a "press A on the obstacle" path
-- and a "use it from the party menu" path. Nine of its commands were unlowered,
-- 23 uses.
--
-- BUT THREE OF THE NINE WERE WORSE THAN UNLOWERED. `dostrengthfunc`,
-- `doflashfunc` and `dodefogfunc` are variable-length -- a sub-function byte,
-- plus a destination word only when that byte is FIELD_MOVE_FUNC_CHECK_ACTIVE
-- -- and `Gen4Script.decode` STOPS THE WALK at a command whose width it cannot
-- work out. Stopping is the right answer for a width nobody knows (the header
-- of `Gen4ScriptOps` records what a guessed width cost Gen 3), but "stop" means
-- every instruction after it is never decoded. So those were not three missing
-- rows, they were four truncated scripts.
--
-- Measured on the cartridge, same corpus, before and after teaching the
-- decoder the rule pokeplatinum states in `asm/macros/scrcmd.inc`:
--
--                     stopped=end   stopped=variable   stopped=overrun
--     before              4,070            8                 1
--     after               4,074            4                 1
--
-- and the four that moved are exactly `dostrengthfunc` x2, `doflashfunc` x1,
-- `dodefogfunc` x1. The remaining four (mysterygiftgive x2, calltvbroadcast,
-- dogroupconnectionaction) have no rule in hand and still stop, which is
-- correct.
--
-- Run:  texlua tools/gen4_field_moves_check.lua <cache dir> [pokeplatinum dir] [rom]
--
-- Sections 1-3 need nothing but the repository, so this check has something
-- that can fail with no cache, no pret and no cartridge present.

package.path = "./?.lua;" .. package.path

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = { getWidth = function() return 256 end, getHeight = function() return 192 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local CACHE = arg and arg[1]
local PP = arg and arg[2]
local ROM = arg and arg[3]
if not CACHE then
  io.write("usage: texlua tools/gen4_field_moves_check.lua "
           .. "<cache dir> [pokeplatinum dir] [rom]\n")
  os.exit(2)
end

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

local Ops = require("src.import.Gen4ScriptOps")
local Script = require("src.import.Gen4Script")

-- ---------------------------------------------------------------------------
section("1. the variable-width rule, on bytes built to the cartridge's shape")
local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end

ok(Ops.FIELD_MOVE_FUNC.CLEAR_ACTIVE == 0, "CLEAR_ACTIVE is %s, expected 0",
   tostring(Ops.FIELD_MOVE_FUNC.CLEAR_ACTIVE))
ok(Ops.FIELD_MOVE_FUNC.SET_ACTIVE == 1, "SET_ACTIVE is %s, expected 1",
   tostring(Ops.FIELD_MOVE_FUNC.SET_ACTIVE))
ok(Ops.FIELD_MOVE_FUNC.CHECK_ACTIVE == 2, "CHECK_ACTIVE is %s, expected 2",
   tostring(Ops.FIELD_MOVE_FUNC.CHECK_ACTIVE))

-- All three opcodes share one rule, and all three must be wired to it -- the
-- cheap mistake is wiring the one you were debugging.
for _, op in ipairs({ 0x1CF, 0x1D0, 0x1D1 }) do
  ok(Ops.VARIABLE_SPEC[op] ~= nil,
     "0x%03X (%s) has no variable-width rule", op, Ops.name(op))
  for func, want, size in
    (function() local i = 0
       local rows = { { 0, "b", 3 }, { 1, "b", 3 }, { 2, "bw", 5 } }
       return function() i = i + 1
         local r = rows[i]; if r then return r[1], r[2], r[3] end end
     end)() do
    local bytes = u16(op) .. string.char(func)
    ok(Ops.specAt(op, bytes, 1) == want,
       "0x%03X sub-function %d: spec %s, expected %s", op, func,
       tostring(Ops.specAt(op, bytes, 1)), want)
    ok(Ops.sizeAt(op, bytes, 1) == size,
       "0x%03X sub-function %d: %s bytes, expected %d", op, func,
       tostring(Ops.sizeAt(op, bytes, 1)), size)
  end
  -- A SUB-FUNCTION THE CARTRIDGE DOES NOT DEFINE IS NOT A WIDTH TO INVENT.
  -- `ScrCmd_DoStrengthFunc`'s default arm is GF_ASSERT(FALSE), so the honest
  -- answer is nil, and nil still stops the walk.
  ok(Ops.specAt(op, u16(op) .. string.char(7), 1) == nil,
     "0x%03X accepted sub-function 7 and gave it a width", op)
  -- ...and with no bytes to look at, it cannot answer either.
  ok(Ops.specAt(op) == nil, "0x%03X answered a spec with no bytes given", op)
  ok(Ops.size(op) == nil,
     "0x%03X is no longer marked variable in COMMANDS; `size` must still refuse "
     .. "it, because several callers have only an opcode to give", op)
end

-- The four that remain variable must STILL refuse, or this check has quietly
-- blessed a guess somewhere else. (0x289, givepoffin, left this list: it is
-- NOT variable -- ScrCmd_GivePoffin reads a var and six more words, sixteen
-- bytes every time -- and is checked as the fixed width it is just below.)
ok(Ops.size(0x289) == 16, "0x289 (givepoffin) is a fixed 16 bytes, got %s", tostring(Ops.size(0x289)))
-- (0x23E, mysterygiftgive, left too: its width is its STAGE operand's, from
-- the MysteryGiftGive macro, and tools/gen4_mystery_gift_check.lua checks all
-- nine stages.)
ok(Ops.sizeAt(0x23E, u16(0x23E) .. u16(1) .. u16(0x40ED), 1) == 6,
   "0x23E (mysterygiftgive) stage 1 is 6 bytes")
for _, op in ipairs({ 0x21D, 0x235, 0x237, 0x27C }) do
  ok(Ops.VARIABLE_SPEC[op] == nil,
     "0x%03X (%s) has gained a width rule; if that is real, add it to this "
     .. "list's counterpart and move it", op, Ops.name(op))
  ok(Ops.sizeAt(op, u16(op) .. string.char(1), 1) == nil,
     "0x%03X resolved a width it has no rule for", op)
end

-- ---------------------------------------------------------------------------
section("2. a mixed stream decodes through, and a bad one still stops")
local stream = u16(0x1CF) .. string.char(1)                 -- SET    (3 bytes)
            .. u16(0x1D0) .. string.char(1)                 -- SET    (3)
            .. u16(0x1CF) .. string.char(2) .. u16(0x4000)  -- CHECK  (5)
            .. u16(0x1D1) .. string.char(0)                 -- CLEAR  (3)
            .. u16(0x002)                                   -- end
local ins, stopped = Script.decode(stream, 1)
ok(stopped == "end", "mixed stream stopped at %s, expected end", tostring(stopped))
ok(#ins == 5, "mixed stream decoded %d instructions, expected 5", #ins)
-- THE OFFSETS ARE THE ASSERTION. A width that is wrong by one still yields the
-- right instruction count on a stream this short; it does not yield the right
-- positions.
local wantAt = { 1, 4, 7, 12, 15 }
for i, at in ipairs(wantAt) do
  ok(ins[i] and ins[i].at == at,
     "instruction %d is at %s, expected %d", i, tostring(ins[i] and ins[i].at), at)
end
ok(ins[3] and ins[3].args and ins[3].args[2] == 0x4000,
   "the CHECK form did not carry its destination var (got %s)",
   tostring(ins[3] and ins[3].args and ins[3].args[2]))
ok(ins[1] and ins[1].args and ins[1].args[2] == nil,
   "the SET form carried a second operand it should not have")
local badIns, badStopped = Script.decode(u16(0x1CF) .. string.char(7) .. u16(0x002), 1)
ok(badStopped == "variable",
   "an undefined sub-function stopped at %s, expected variable",
   tostring(badStopped))
ok(#badIns == 1, "an undefined sub-function decoded %d instructions, expected 1",
   #badIns)

-- ---------------------------------------------------------------------------
section("3. the nine lowerings, and a handler for every row they emit")
-- THE DETECTOR'S OWN CANARY, first. Everything below and in section 4 rests
-- on `Gen4ScriptVM.lowered`, and a detector that answered "yes" to everything
-- would report zero holes everywhere -- silently, which is the bad direction.
-- So: one command that is lowered, one that is deliberately not, and one that
-- is lowered THROUGH A LOOP.
--
-- That last one is a regression test for a real mistake. The census this check
-- grew out of matched `L.name =` and `L["name"] =` with a pattern and so could
-- not see
--
--     for _, name in ipairs({ "getberrygrowthstage", ... }) do
--       L[operation] = function(ins, s) ... end
--     end
--
-- and reported the 118-object berry-tree band as having fourteen holes when it
-- has none. Asking the table cannot make that mistake; this line is here so
-- nobody reintroduces the pattern.
local VMprobe = require("src.script.Gen4ScriptVM")
ok(VMprobe.lowered("playhmcutin") == true,
   "`lowered` does not recognise playhmcutin, which this pass lowered")
ok(VMprobe.lowered("getberrygrowthstage") == true,
   "`lowered` does not recognise getberrygrowthstage -- it is assigned inside a "
   .. "loop, and a source-pattern detector misses exactly that")
ok(VMprobe.lowered("dogroupconnectionaction") == false,
   "`lowered` claims dogroupconnectionaction is lowered; it is not, and a "
   .. "detector that says yes to everything reports no holes anywhere")
ok(VMprobe.lowered("no_such_command_at_all") == false,
   "`lowered` claims a command that does not exist is lowered")
local vm = slurp("src/script/Gen4ScriptVM.lua") or ""
local cmds = slurp("src/script/Gen4Commands.lua") or ""
ok(#vm > 0, "src/script/Gen4ScriptVM.lua did not open")
ok(#cmds > 0, "src/script/Gen4Commands.lua did not open")
for _, op in ipairs({ "playhmcutin", "usesurf", "usewaterfall", "userockclimb",
                      "dostrengthfunc", "doflashfunc", "dodefogfunc" }) do
  ok(vm:find("L%." .. op .. "%s*=") ~= nil,
     "`%s` is not lowered; it will take the unknown-command path", op)
end
-- The two numbered ones are keyed as strings, because `0c3` is not an
-- identifier.
for _, op in ipairs({ "0c3", "0c4" }) do
  ok(vm:find('L%["' .. op .. '"%]%s*=') ~= nil, "`%s` is not lowered", op)
end
-- ONE ROW FOR BOTH, because the two opcodes are the same function byte for byte
-- in pokeplatinum. Two rows doing the same thing is how a port fixes one and
-- not the other.
ok(vm:find('L%["0c4"%]%s*=%s*L%["0c3"%]') ~= nil,
   "0x0C4 does not share 0x0C3's row; they are byte-identical in the cartridge "
   .. "and must not drift apart")
for _, name in ipairs({ "g4_hm_cut_in", "g4_use_surf", "g4_use_waterfall",
                        "g4_use_rock_climb", "g4_clear_overworld_weather",
                        "g4_field_move_flag" }) do
  local hasFn = cmds:find("function Commands%." .. name .. "%s*%(") ~= nil
  local hasAssign = cmds:find("Commands%." .. name .. "%s*=") ~= nil
  local isPending = cmds:find('pending%("' .. name .. '"') ~= nil
  ok(hasFn or hasAssign or isPending, "no handler for %s", name)
  ok(vm:find('"' .. name .. '"') ~= nil, "nothing emits %s", name)
end
-- The cut-in blocks on the cartridge, so it must block here.
ok(cmds:find("Commands%.meta%.g4_hm_cut_in") ~= nil,
   "`g4_hm_cut_in` is not declared blocking; the cartridge pauses the script on "
   .. "it (ScriptContext_WaitForHMCutInFinished) and a non-blocking cut-in would "
   .. "play under the next line of dialogue")
-- THE CLEAR MUST BE READ BACK. A write nothing reads is the fault this port has
-- hit five times; here it would mean Defog clearing the fog and the very next
-- `getoverworldweather` reporting fog.
ok(cmds:find("gen4WeatherCleared") ~= nil,
   "nothing records a cleared overworld weather")
local reads = 0
for _ in cmds:gmatch("gen4WeatherCleared") do reads = reads + 1 end
ok(reads >= 3,
   "`gen4WeatherCleared` appears %d time(s); it must be written by the clear "
   .. "command AND read by `g4_overworld_weather`, or the clear is invisible",
   reads)
ok(cmds:find("function Commands%.g4_overworld_weather") ~= nil
   and cmds:match("function Commands%.g4_overworld_weather.-end")
       :find("gen4WeatherCleared") ~= nil,
   "`g4_overworld_weather` does not consult the cleared flag")

-- ---------------------------------------------------------------------------
if PP then
  section("4. `scripts_field_moves.s` end to end, against pokeplatinum")
  local inc = slurp(PP .. "/asm/macros/scrcmd.inc")
  local enum = slurp(PP .. "/include/data/scripts/scrcmd.h")
  if not (inc and enum) then
    report("pokeplatinum sources not found under %s -- section 4 skipped", PP)
  else
    local macroConst = {}
    for name, body in inc:gmatch("%.macro%s+(%S+)(.-)%.endm") do
      local c = body:match("%.short%s+([A-Za-z][A-Za-z0-9_]*)")
      if c then macroConst[name] = c end
    end
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
    -- THE REAL TABLE, NOT A REGEX OVER THE SOURCE -- and this is a correction,
    -- not a tidy-up. The regex matched `L.name =` and `L["name"] =` and missed
    -- the nine berry commands, which are lowered inside a loop:
    --
    --     for _, name in ipairs({ "getberrygrowthstage", ... }) do
    --       L[operation] = function(ins, s) ... end
    --     end
    --
    -- so a census built that way reported `scripts_berry_tree_interaction.s`
    -- (118 objects) as having fourteen unlowered uses when it has none. It
    -- under-reports coverage, which is the safe direction for a 0-holes
    -- assertion and the wrong direction for deciding what to work on next --
    -- it sent a whole pass after work that was already finished.
    --
    -- `Gen4ScriptVM.lowered(name)` asks the table itself and existed all along.
    local VM = require("src.script.Gen4ScriptVM")
    local function isLowered(nm) return VM.lowered(nm) end
    -- EVERY BAND WITH REAL REACH, not just the two files this pass touched.
    --
    -- A script band is a shared file that many map objects route into, and the
    -- cache records which band each object uses, so "reach" is countable rather
    -- than guessed. Ranked by it, the bands are:
    --
    --     688  field_moves                  every HM use in Sinnoh
    --     407  single_battles               every trainer you walk up to
    --     329  visible_items                every item ball
    --     262  hidden_items                 every hidden item
    --     118  berry_tree_interactions      every berry tree
    --      97  common_scripts               callcommonscript, from anywhere
    --      28  pokemon_center_daily_trainers
    --      10  double_battles
    --
    -- THE INVARIANT IS THE ASSERTION: no band with reach >= 10 may contain an
    -- unlowered command, with `common_scripts` the single named exception. That
    -- is worth more than a list of filenames, because it covers bands nobody
    -- has thought about yet -- a new band, or a band whose reach grows past ten
    -- on the next re-extract, is caught without this file changing.
    local Bands = require("src.import.Gen4ScriptBands")
    local reach = {}
    local maps = slurp(CACHE .. "/maps.lua")
    if not maps then
      report("%s/maps.lua did not open, so band reach could not be counted "
             .. "-- the invariant below was not tested", CACHE)
    else
      for band in maps:gmatch('scriptBand = "([a-z_]+)"') do
        reach[band] = (reach[band] or 0) + 1
      end
      -- A FLOOR ON THE COUNT ITSELF: if the field were ever renamed, every band
      -- would read reach 0, the invariant would cover nothing, and this section
      -- would pass over an empty set.
      local counted = 0
      for _, v in pairs(reach) do counted = counted + v end
      ok(counted >= 1990,
         "only %d object(s) carry a scriptBand (was 1,992); the reach count is "
         .. "measuring nothing and the invariant below is vacuous", counted)

      -- 43 -> 40 in pass 170 (`survivepoison`, `blackoutfrombattle2`,
      -- `hatchegg`), then 40 -> 25 in pass 171, which took the whole save
      -- dialogue: `checksavetype` x2, `trysavegame`, `storesaveresult`,
      -- `show`/`hidesavingicon`, `waitabpresstime`, `opensaveinfo`,
      -- `closesaveinfo` x3, 0x258, 0x259, `saveextradata` and
      -- `checkismiscsaveinit` -- fifteen uses across twelve opcodes, graded
      -- in tools/gen4_save_check.lua.
      --
      -- What is left groups as the PC and the Hall of Fame screen (6), the
      -- Underground's traps, spheres, seals and shard counter (8), the
      -- contest backdrop (2), the mailbox (2) and seven others.
      -- 25 -> 19 in pass 173, which took the PC: the three prop-animation
      -- rows, the storage TV bulletin, the Hall of Fame corruption check
      -- and its browser.  The PC is also the pass that made any of this
      -- reachable -- `Field_TileBehaviorToScript` had no Gen 4 arm, so
      -- CommonScript_PC was never started; see tools/gen4_tile_script_check.
      --
      -- 19 -> 7 in pass 176, which took everything left that could be derived:
      -- `givetrap` and `givesphere` onto a real 40-slot inventory, the trap
      -- (630) and item (628) name banks, the contest backdrop names (388),
      -- `countmailinmailbox` and `countuniquesealsinsealcase` onto
      -- `g4_no_feature` (neither system exists here and zero is the true
      -- answer), `opensealcapsuleeditor` to `pending`, `messagefromtrainertype`
      -- onto the band's own bank with the entry off `ctx.npc`, and
      -- `waitfortransition` to a no-op because the warp owns the teardown.
      -- Graded in tools/gen4_underground_inventory_check.lua.
      --
      -- THE SEVEN THAT REMAIN ARE NOT A BACKLOG OF THE SAME KIND.  Five
      -- (`0a5`, `0b3`, `1b3`, `205`, `2f6`) are unnamed in pokeplatinum too --
      -- a bare `sub_0209ACF4(ctx->task)` with no identified subject, and
      -- `2f6` gates on a Wi-Fi login this port has no path to. Lowering one
      -- would mean guessing what it does, which is the mistake the header of
      -- Gen4ScriptOps records the cost of. The other two (`showshardcost`,
      -- `closeshardcostwindow`) need `sTeachableMoves`' four shard costs,
      -- which are not in the cache and want their own extraction stage.
      local EXPECTED_HOLES = { common_scripts = 7 }
      local offenders = {}
      for _, b in ipairs(Bands.BANDS) do
        local band, file = b[2], b[3]
        local body = slurp(PP .. "/res/field/scripts/" .. file .. ".s")
        if body and (reach[band] or 0) >= 10 then
          local uses, holes, seen, list = 0, 0, {}, {}
          for line in body:gmatch("[^\r\n]+") do
            local mac = line:match("^%s*([A-Za-z_][A-Za-z0-9_]*)")
            if mac and macroConst[mac] then
              uses = uses + 1
              local i = constIndex[macroConst[mac]]
              local nm = i and opName[i]
              if nm and not isLowered(nm) then
                holes = holes + 1
                if not seen[nm] then
                  seen[nm] = true
                  list[#list + 1] = ("%s (0x%03X)"):format(nm, i)
                end
              end
            end
          end
          io.write(("   %4d  %-30s %4d uses, %3d unlowered\n")
                   :format(reach[band], band, uses, holes))
          local allowed = EXPECTED_HOLES[band]
          if allowed then
            -- A CEILING, so fixing some of them passes and losing ground fails.
            ok(holes <= allowed,
               "%s has %d unlowered use(s), up from %d -- it is the one band with "
               .. "reach that still has holes and it may only shrink: %s",
               band, holes, allowed, table.concat(list, ", "))
          elseif holes > 0 then
            offenders[#offenders + 1] =
              ("%s (reach %d, %d uses): %s"):format(band, reach[band], holes,
                                                    table.concat(list, ", "))
          end
        end
      end
      ok(#offenders == 0,
         "%d band(s) with reach >= 10 contain unlowered commands and are not the "
         .. "named exception: %s", #offenders, table.concat(offenders, "; "))
      -- ...and the two this pass is named for, by name, so the invariant above
      -- cannot pass by failing to find them.
      for _, band in ipairs({ "field_moves", "single_battles" }) do
        ok((reach[band] or 0) >= 10,
           "band %s has reach %d, so the invariant above skipped it",
           band, reach[band] or 0)
      end
    end
    -- The rule this check is about, re-derived from pret rather than trusted.
    local rule = inc:match("%.macro%s+DoStrengthFunc(.-)%.endm")
    if rule then
      ok(rule:find("FIELD_MOVE_FUNC_CHECK_ACTIVE") ~= nil,
         "DoStrengthFunc's macro no longer conditions on "
         .. "FIELD_MOVE_FUNC_CHECK_ACTIVE; the width rule this check encodes "
         .. "was read from it")
      ok(rule:find("%.byte") ~= nil and rule:find("%.short") ~= nil,
         "DoStrengthFunc's macro no longer emits a byte and a conditional short")
    else
      report("could not find DoStrengthFunc's macro to re-derive the rule from")
    end
  end
else
  io.write("\n   (no pokeplatinum dir given -- section 4 skipped)\n")
end

-- ---------------------------------------------------------------------------
if ROM then
  section("5. the truncation census, on the cartridge")
  local okRom, NdsRom = pcall(require, "src.import.NdsRom")
  local okNarc, Narc = pcall(require, "src.import.NarcArchive")
  local rom = okRom and okNarc and NdsRom.open(ROM)
  if not rom then
    report("%s did not open as a DS cartridge -- section 5 skipped", tostring(ROM))
  else
    local bytes = rom:read("/fielddata/script/scr_seq.narc")
    local arc = bytes and Narc.parse(bytes)
    if not arc then
      report("scr_seq.narc did not parse out of %s", tostring(ROM))
    else
      local tally, byOp, total = {}, {}, 0
      for m = 0, arc.count - 1 do
        local data = arc:get(m)
        if data and #data > 4 then
          local okE, entries = pcall(Script.entries, data)
          if okE and type(entries) == "table" then
            for _, at in ipairs(entries) do
              local okD, list, why = pcall(Script.decode, data, at)
              if okD and type(list) == "table" then
                total = total + 1
                tally[why] = (tally[why] or 0) + 1
                if why ~= "end" then
                  local last = list[#list]
                  local key = ("%s 0x%03X"):format(why, last and last.op or -1)
                  byOp[key] = (byOp[key] or 0) + 1
                end
              end
            end
          end
        end
      end
      io.write(("   %d scripts in scr_seq.narc: end=%d variable=%d "
                .. "unknown=%d overrun=%d\n")
               :format(total, tally["end"] or 0, tally.variable or 0,
                       tally.unknown or 0, tally.overrun or 0))
      -- FLOORS AND CEILINGS, both, because this moves in both directions:
      -- lowering `variable` is the work, and raising it is a regression.
      ok(total >= 4079, "only %d scripts were walked (was 4,079)", total)
      ok((tally["end"] or 0) >= 4074,
         "only %d scripts terminate cleanly (was 4,074)", tally["end"] or 0)
      ok((tally.variable or 0) <= 4,
         "%d scripts stop at a variable-length command (was 4 after the "
         .. "field-move rule landed, 8 before it) -- a rise here means a "
         .. "truncation somebody should see", tally.variable or 0)
      ok((tally.unknown or 0) == 0,
         "%d script(s) in scr_seq.narc stop at an unknown opcode", tally.unknown or 0)
      -- AND THE THREE MUST NOT BE AMONG THEM. The count above could stay at 4
      -- while the membership changed.
      for _, op in ipairs({ 0x1CF, 0x1D0, 0x1D1 }) do
        local key = ("variable 0x%03X"):format(op)
        ok(byOp[key] == nil,
           "%s (%s) still truncates %d script(s); the width rule is not being "
           .. "applied", key, Ops.name(op), byOp[key] or 0)
      end
      local names = {}
      for k, v in pairs(byOp) do names[#names + 1] = ("%s x%d"):format(k, v) end
      table.sort(names)
      if #names > 0 then
        io.write(("   still stopping: %s\n"):format(table.concat(names, ", ")))
      end
    end
  end
else
  io.write("\n   (no rom given -- section 5 skipped)\n")
end

io.write(("\n%d checks, %d failed, %d reported\n"):format(checks, fails, reports))
os.exit(fails == 0 and 0 or 1)
