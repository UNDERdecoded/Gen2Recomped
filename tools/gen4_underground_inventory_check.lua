-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LAST OF `scripts_common.s` THAT COULD BE DERIVED: 19 holes -> 7.
--
-- `common_scripts` is the one band with reach (97 objects, plus everything
-- `callcommonscript` and `ScriptManager_Start` reach from C) that still had
-- unlowered commands. Pass 171 took the save dialogue (40 -> 25), pass 173 the
-- PC and the Hall of Fame (25 -> 19). This takes everything left whose subject
-- pokeplatinum actually names.
--
-- WHAT THIS GRADES, and the order is the order of how much can go wrong:
--
--   1. the inventory, which is the only part that writes state -- 40 slots
--      each, a zero sentinel, and a destination var that is the branch;
--   2. the two bank numbers, which are the part most likely to be quietly
--      wrong, checked three independent ways;
--   3. the honest answers -- `g4_no_feature` for the mailbox and the seal
--      case, `pending` for the capsule editor, a no-op for the transition --
--      asserted to be the answer they claim and not an accident;
--   4. `messagefromtrainertype`, whose entry comes off the object rather than
--      the stream;
--   5. the ceiling, from the other side: the seven that remain are named, so
--      a later pass cannot quietly re-open one.
--
-- A WRONG BANK NUMBER DOES NOT FAIL. It prints some other table's row -- a
-- trap called "Yellow Cushion" -- which is why the content agreement below is
-- an assertion rather than a note: `generated/traps.txt` line N+1 is the name
-- bank 630 holds at entry N, so the trap id IS its own bank index, and the
-- same holds for the sphere types in 628. Two tables from two different parts
-- of the cartridge agreeing item-for-item is worth more than either alone.
--
-- Run:  texlua tools/gen4_underground_inventory_check.lua <data/generated> [pokeplatinum]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local CACHE = arg and arg[1]
local PRET  = arg and arg[2]

local fails, checks, reports, skips = 0, 0, 0, 0
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
local function skip(fmt, ...)
  skips = skips + 1
  io.write("SKIP: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  if not p then return nil end
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function loadTable(dir, name)
  if not dir then return nil end
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local okRun, t = pcall(f)
  return okRun and t or nil
end
-- A comment does not grade the code it describes.
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end

love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end,
               newImage = function() return nil end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
  image = { newImageData = function() return nil end },
  math = { random = math.random },
}

local UG       = require("src.world.Gen4Underground")
local VM       = require("src.script.Gen4ScriptVM")
local Commands = require("src.script.Commands")
-- REQUIRED FOR ITS SIDE EFFECT, and that is not incidental: `Gen4Commands`
-- puts its 155-odd `g4_` verbs onto the SHARED `Commands` table as it loads,
-- and `Commands.registerInto` is load-order sensitive for exactly that reason
-- (a Hoenn boot once crashed on `g4_check_two_alive` being registered twice).
-- Without this line `Commands.g4_underground_give` is nil and every assertion
-- about a handler below would report the handler missing.
local Gen4Commands = require("src.script.Gen4Commands")
local Logger   = require("src.core.Logger")

-- ...so assert that it worked, before anything leans on it.
ok(type(Commands.g4_message_bank) == "function",
   "the Gen 4 verbs are not on the shared Commands table, so this check is "
   .. "grading an empty namespace rather than the port's handlers")

-- every info/warn, so an "honest answer" can be asserted to SAY so
local said
do
  local realInfo, realWarn = Logger.info, Logger.warn
  local function tap(real)
    return function(fmt, ...)
      if said then
        local okF, line = pcall(string.format, tostring(fmt), ...)
        said[#said + 1] = okF and line or tostring(fmt)
      end
      return real(fmt, ...)
    end
  end
  Logger.info, Logger.warn = tap(realInfo), tap(realWarn)
end
local function capture(fn)
  said = {}
  local value = fn()
  local lines = said
  said = nil
  return value, table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
section("1. the inventory, which is the only part that writes state")
-- ---------------------------------------------------------------------------
-- NOTHING HERE NEEDS A CACHE OR A CARTRIDGE, so this check has something that
-- can fail with no input at all.
ok(UG.MAX_TRAP_SLOTS == 40 and UG.MAX_SPHERE_SLOTS == 40,
   "the slot caps are %s traps / %s spheres; pokeplatinum's "
   .. "include/underground/defs.h says 40 and 40",
   tostring(UG.MAX_TRAP_SLOTS), tostring(UG.MAX_SPHERE_SLOTS))
ok(UG.MAX_SPHERE_SIZE == 99,
   "MAX_SPHERE_SIZE is %s, not 99", tostring(UG.MAX_SPHERE_SIZE))
ok(UG.TRAP_NONE == 0 and UG.SPHERE_NONE == 0,
   "the empty-slot sentinels are %s and %s; both are line one of their "
   .. "generated enum, so both are 0",
   tostring(UG.TRAP_NONE), tostring(UG.SPHERE_NONE))

do
  local save = {}
  ok(UG.trapCount(save) == 0 and UG.sphereCount(save) == 0,
     "a fresh save does not start with an empty inventory (%d traps, %d spheres)",
     UG.trapCount(save), UG.sphereCount(save))
  -- fill it exactly to the cap, then one more
  local added = 0
  for i = 1, UG.MAX_TRAP_SLOTS do
    if UG.addTrap(save, 1 + (i % 28)) then added = added + 1 end
  end
  ok(added == UG.MAX_TRAP_SLOTS,
     "only %d of %d traps went in before the cap", added, UG.MAX_TRAP_SLOTS)
  ok(UG.trapCount(save) == UG.MAX_TRAP_SLOTS,
     "the trap count reads %d after %d adds", UG.trapCount(save), added)
  -- THE REFUSAL IS THE RETURN VALUE, and the return value is the branch.
  ok(UG.addTrap(save, 5) == false,
     "a 41st trap was accepted; `Underground_TryAddTrap` answers FALSE when "
     .. "`FindEmptyTrapSlot` returns -1 and the script branches on that")
  ok(UG.trapCount(save) == UG.MAX_TRAP_SLOTS,
     "the refused trap still changed the count, to %d", UG.trapCount(save))

  -- THE SENTINEL, which all three adders answer the same way -- and that
  -- sameness is the point, because the first version of this port answered it
  -- three different ways in three sibling functions.
  --
  -- `Underground_TryAddTrap` does not reject TRAP_NONE.  It finds the first
  -- free slot, writes TRAP_NONE into it, and answers TRUE: the slot it found
  -- really was free, which is the whole question the branch asks.  Storing the
  -- sentinel densely WOULD be wrong -- `#list` would grow while the cartridge's
  -- slot still reads as empty -- so the faithful dense equivalent is to answer
  -- yes and store nothing.  Refusing outright, which is what this check used
  -- to assert, gets the state right and the ANSWER wrong.
  local fresh = {}
  ok(UG.addTrap(fresh, UG.TRAP_NONE) == true,
     "TRAP_NONE was refused; the cartridge found a free slot and answered "
     .. "TRUE, and a free slot is what the caller is being told about")
  ok(UG.trapCount(fresh) == 0,
     "TRAP_NONE was stored (count %d); densely, that slot would stop reading "
     .. "as empty", UG.trapCount(fresh))
  -- ...and on a FULL inventory the sentinel gets the honest no, because then
  -- there genuinely is no free slot.  Without this half the assertion above
  -- is satisfied by `return true`.
  local packed = {}
  while UG.addTrap(packed, 1) do end
  ok(UG.addTrap(packed, UG.TRAP_NONE) == false,
     "TRAP_NONE answered yes on a full trap inventory, where no slot is free")
end

do
  local save = {}
  ok(UG.addSphere(save, 2, 40) == true, "a plain sphere was refused")
  local s = UG.spheres(save)[1]
  ok(s and s.type == 2 and s.size == 40,
     "the stored sphere is %s; `TryAddSphere` writes the type AND the size, "
     .. "into the same slot index of two parallel arrays",
     s and ("type " .. tostring(s.type) .. " size " .. tostring(s.size))
       or "absent")
  -- the size SATURATES, it does not refuse: the cartridge's own growth code
  -- caps at MAX_SPHERE_SIZE
  ok(UG.addSphere(save, 3, 500) == true,
     "an oversized sphere was refused rather than clamped")
  ok(UG.spheres(save)[2].size == UG.MAX_SPHERE_SIZE,
     "an oversized sphere stored size %d rather than clamping to %d",
     UG.spheres(save)[2].size, UG.MAX_SPHERE_SIZE)
  ok(UG.addSphere(save, 3, 0) == true and UG.spheres(save)[3].size == 1,
     "a zero-size sphere stored size %s; a sphere with no size is not a "
     .. "sphere", tostring((UG.spheres(save)[3] or {}).size))
  -- the same sentinel contract as TRAP_NONE, asserted here rather than assumed
  local sphereCountBefore = UG.sphereCount(save)
  ok(UG.addSphere(save, UG.SPHERE_NONE, 10) == true,
     "SPHERE_NONE was refused; it answers like TRAP_NONE or the three adders "
     .. "have drifted apart again")
  ok(UG.sphereCount(save) == sphereCountBefore,
     "SPHERE_NONE was stored (count %d, was %d)",
     UG.sphereCount(save), sphereCountBefore)
  local before = UG.sphereCount(save)
  while UG.addSphere(save, 1, 5) do end
  ok(UG.sphereCount(save) == UG.MAX_SPHERE_SLOTS,
     "the sphere inventory filled to %d, not %d",
     UG.sphereCount(save), UG.MAX_SPHERE_SLOTS)
  ok(before < UG.MAX_SPHERE_SLOTS,
     "the loop above had nothing to do, so the cap was not exercised")
  -- the two inventories are SEPARATE 40-slot arrays, not one shared 40
  ok(UG.trapCount(save) == 0,
     "filling the spheres put %d trap(s) in the trap inventory; they are two "
     .. "arrays in the cartridge and must be two here",
     UG.trapCount(save))
end

-- AND THE SAVE SLOT IS THE ONE THE DIG SPOTS ALREADY USE, so a save written
-- before the inventory existed grows the fields rather than needing a
-- migration -- and the two do not tread on each other.
do
  local save = { underground = { spots = { { x = 1, z = 2 } } } }
  UG.addTrap(save, 7)
  ok(#save.underground.spots == 1,
     "adding a trap disturbed the dig-spot list")
  ok(save.underground.traps ~= nil,
     "the trap inventory did not land in save.underground, so it is not in "
     .. "the same place the rest of the Underground's state is")
end

-- ---------------------------------------------------------------------------
section("1b. the goods PC -- the third inventory, and a wrong answer fixed")
-- ---------------------------------------------------------------------------
-- `checkhasroomforgoodsinpc` was on `g4_no_feature`, which writes 0 -- and 0
-- here means "no room". Sixteen of the goods PC's seventeen script uses were
-- telling the player their PC was full on a save where it holds nothing.
--
-- That is the distinction this section exists to hold: an ABSENT feature
-- answering "no" is honest, and a PRESENT one answering "no" is a lie. The
-- first assertion is the one that would have caught it.
ok(UG.MAX_GOODS_PC_SLOTS == 200,
   "the goods PC holds %s slots; include/underground/defs.h says 200",
   tostring(UG.MAX_GOODS_PC_SLOTS))
ok(UG.GOOD_NONE == 0,
   "UG_GOOD_NONE is %s; it is line one of generated/goods.txt, so 0",
   tostring(UG.GOOD_NONE))
do
  local save = {}
  ok(UG.goodsPCCount(save) == 0,
     "a fresh save starts with %d good(s) in the PC", UG.goodsPCCount(save))
  -- THE BUG, ASSERTED DIRECTLY.
  ok(UG.roomInGoodsPC(save) == true,
     "an empty goods PC reports no room -- which is what `g4_no_feature`'s 0 "
     .. "told sixteen script sites")
  local added = 0
  for i = 1, UG.MAX_GOODS_PC_SLOTS do
    if UG.addGoodToPC(save, 1 + (i % 40)) then added = added + 1 end
  end
  ok(added == UG.MAX_GOODS_PC_SLOTS,
     "only %d of %d goods went in before the cap", added, UG.MAX_GOODS_PC_SLOTS)
  -- ...and only NOW is there no room, which is the other half: a ceiling that
  -- is never reached is as untested as one that is always reached.
  ok(UG.roomInGoodsPC(save) == false,
     "a full goods PC still reports room, so the cap means nothing")
  ok(UG.addGoodToPC(save, 5) == false,
     "a 201st good was accepted")
  ok(UG.goodsPCCount(save) == UG.MAX_GOODS_PC_SLOTS,
     "the refused good still changed the count, to %d",
     UG.goodsPCCount(save))
  local fresh = {}
  ok(UG.addGoodToPC(fresh, UG.GOOD_NONE) == true,
     "UG_GOOD_NONE was refused; `Underground_TryAddGoodPC` answers TRUE for "
     .. "the free slot it found, whatever it wrote there")
  ok(UG.goodsPCCount(fresh) == 0,
     "UG_GOOD_NONE was stored (count %d)", UG.goodsPCCount(fresh))
  -- ONE ANSWER, NOT THREE.  The sentinel contract is asserted per-adder above;
  -- this is the invariant behind those three assertions, so a future fourth
  -- inventory that answers differently is caught without anyone remembering to
  -- add a case.
  do
    local adders = {
      { "addTrap", function(sv) return UG.addTrap(sv, UG.TRAP_NONE) end,
        UG.trapCount },
      { "addSphere", function(sv) return UG.addSphere(sv, UG.SPHERE_NONE, 5) end,
        UG.sphereCount },
      { "addGoodToPC", function(sv) return UG.addGoodToPC(sv, UG.GOOD_NONE) end,
        UG.goodsPCCount },
    }
    for _, a in ipairs(adders) do
      local sv = {}
      local answer = a[2](sv)
      ok(answer == true and a[3](sv) == 0,
         "%s handles the NONE sentinel differently from its siblings "
         .. "(answered %s, stored %d)", a[1], tostring(answer), a[3](sv))
    end
  end

  -- THREE SEPARATE ARRAYS, which is what the cartridge has. Filling one must
  -- not crowd the others.
  local mixed = {}
  for _ = 1, 10 do UG.addGoodToPC(mixed, 3) end
  UG.addTrap(mixed, 4)
  UG.addSphere(mixed, 2, 30)
  ok(UG.goodsPCCount(mixed) == 10 and UG.trapCount(mixed) == 1
     and UG.sphereCount(mixed) == 1,
     "the three inventories are not independent: %d goods, %d traps, %d "
     .. "spheres", UG.goodsPCCount(mixed), UG.trapCount(mixed),
     UG.sphereCount(mixed))
end

-- AND THROUGH THE HANDLERS, because the var is the branch.
--
-- Every destination var is SEEDED with a sentinel first.  `getVar` answers 0
-- for a var nobody wrote, and 0 is also the honest "no room" -- so without a
-- seed a handler that forgets to write at all passes the full-PC assertion
-- and fails the empty-PC one with the same message as a genuinely inverted
-- answer.  A planted fault proved exactly that.  The seed is what separates
-- "answered no" from "did not answer".
do
  local VARS = 0x4000
  local SEED = 7  -- neither 1 nor 0, so silence is visible
  local function ctxWith(save)
    local ctx = { save = save or {} }
    ctx.game = { save = ctx.save }
    Gen4Commands.setVar(ctx.save, VARS, SEED)
    return ctx
  end
  local function answered(ctx)
    local v = Gen4Commands.getVar(ctx.save, VARS)
    if v == SEED then return "nothing -- the var was never written" end
    return tostring(v)
  end
  local function fullSave()
    local save = {}
    for _ = 1, UG.MAX_GOODS_PC_SLOTS do UG.addGoodToPC(save, 7) end
    return save
  end
  local ctx = ctxWith()
  Commands.g4_underground_room(ctx, "goodsPC", 0, 0, VARS)
  ok(Gen4Commands.getVar(ctx.save, VARS) == 1,
     "`checkhasroomforgoodsinpc` answered %s on an empty PC, not 1",
     answered(ctx))
  local ctx2 = ctxWith(fullSave())
  Commands.g4_underground_room(ctx2, "goodsPC", 0, 0, VARS)
  ok(Gen4Commands.getVar(ctx2.save, VARS) == 0,
     "`checkhasroomforgoodsinpc` answered %s on a full PC, not 0",
     answered(ctx2))
  -- `sendgoodtopc` goes through the same row as a trap
  local ctx3 = ctxWith()
  Commands.g4_underground_give(ctx3, "goodPC", 9, 0, VARS)
  ok(Gen4Commands.getVar(ctx3.save, VARS) == 1
     and UG.goodsPCCount(ctx3.save) == 1,
     "`sendgoodtopc` answered %s and left %d good(s)",
     answered(ctx3), UG.goodsPCCount(ctx3.save))
  ok(UG.goodsPC(ctx3.save)[1] == 9,
     "`sendgoodtopc` stored %s, not the good id 9 it was handed",
     tostring(UG.goodsPC(ctx3.save)[1]))
  local ctx4 = ctxWith(fullSave())
  Commands.g4_underground_give(ctx4, "goodPC", 9, 0, VARS)
  ok(Gen4Commands.getVar(ctx4.save, VARS) == 0,
     "`sendgoodtopc` into a full PC answered %s, not 0", answered(ctx4))
  -- an unknown kind must answer "no room" rather than silently "yes"
  local ctx5 = ctxWith()
  Commands.g4_underground_room(ctx5, "somethingElse", 0, 0, VARS)
  ok(Gen4Commands.getVar(ctx5.save, VARS) == 0,
     "an unknown inventory answered %s, so a future command added to this "
     .. "row would answer yes without an implementation", answered(ctx5))
  -- the middle operand is read and dropped by the cartridge, so passing a
  -- different one must not change the answer
  local ctx6 = ctxWith()
  Commands.g4_underground_room(ctx6, "goodsPC", 0, 0x4055, VARS)
  ok(Gen4Commands.getVar(ctx6.save, VARS) == 1,
     "the middle operand changed the answer (%s); "
     .. "`Underground_IsRoomForGoodsInPC` ignores its second argument",
     answered(ctx6))
end

-- ...AND THEY NO LONGER LOWER ONTO `g4_no_feature`.
do
  local src = code(slurp("src/script/Gen4ScriptVM.lua"))
  for name, verb in pairs({ checkhasroomforgoodsinpc = "g4_underground_room",
                            sendgoodtopc = "g4_underground_give" }) do
    local body = src:match("L%." .. name .. "%s*=%s*function.-\nend")
    ok(body ~= nil, "`%s` has no lowering", name)
    if body then
      ok(body:find(verb) ~= nil, "`%s` does not lower onto %s", name, verb)
      ok(body:find("g4_no_feature") == nil,
         "`%s` still lowers onto g4_no_feature, which writes 0 -- and 0 means "
         .. "\"no room\"", name)
      -- OPERAND ORDER, which the handler tests above cannot see: they call the
      -- handler directly, so a lowering that passes args[2] where args[1]
      -- belongs is invisible to them.  A planted swap proved that.
      --
      -- Both scrcmds read three operands in one fixed order --
      -- `ScriptContext_GetVar`, `ScriptContext_GetVar`,
      -- `ScriptContext_GetVarPointer` -- so the lowering must forward 1, 2, 3
      -- in that order.  (For `SendGoodToPC` the first is the good id and the
      -- second is dropped; for `CheckHasRoomForGoodsInPC` both are dropped.
      -- Either way the THIRD is the destination, and that is the one a swap
      -- would silently move.)
      local order = {}
      for n in body:gmatch("ins%.args%[(%d)%]") do order[#order + 1] = n end
      ok(table.concat(order, ",") == "1,2,3",
         "`%s` forwards its operands as [%s], not [1,2,3]; the cartridge reads "
         .. "var, var, destVarPointer in that order", name,
         table.concat(order, ","))
    end
  end
end

-- ---------------------------------------------------------------------------
section("2. the destination var is the branch")
-- ---------------------------------------------------------------------------
-- Both cartridge handlers end `*destVar = ...TryAdd...(...)` and every call
-- site follows with a `gotoif` on it. An unlowered row did not merely fail to
-- add the trap -- it left the var holding the previous comparison's value.
do
  local function run(kind, a, b, destVar, save)
    local ctx = { save = save or {}, game = { save = save or {} } }
    ctx.game.save = ctx.save
    Commands.g4_underground_give(ctx, kind, a, b, destVar)
    return ctx
  end
  local VARS = 0x4000
  local ctx = run("trap", 3, 0, VARS)
  -- THE PORT'S OWN READER, not a guess at where vars live.  The first draft of
  -- this reached into `save.vars[id]` and every assertion read nil -- the store
  -- is somewhere else, and a check that pokes at a structure instead of asking
  -- the module is grading its own guess.
  local function varOf(c, id) return Gen4Commands.getVar(c.save, id) end
  ok(varOf(ctx, VARS) == 1,
     "a trap that fitted wrote %s to the destination var, not 1",
     tostring(varOf(ctx, VARS)))
  -- now a full inventory, which is the arm that would otherwise never run
  local full = {}
  for _ = 1, UG.MAX_TRAP_SLOTS do UG.addTrap(full, 4) end
  local ctx2 = run("trap", 3, 0, VARS, full)
  ok(varOf(ctx2, VARS) == 0,
     "a trap that did NOT fit wrote %s, not 0 -- which is the branch the "
     .. "cartridge's \"your bag is full\" line hangs off",
     tostring(varOf(ctx2, VARS)))
  local ctx3 = run("sphere", 2, 30, VARS)
  ok(varOf(ctx3, VARS) == 1 and UG.sphereCount(ctx3.save) == 1,
     "a sphere that fitted wrote %s and left %d sphere(s)",
     tostring(varOf(ctx3, VARS)), UG.sphereCount(ctx3.save))
  -- the row must survive having no destination at all (a mod, or a decoder
  -- that read a zero operand) rather than raising mid-script
  local okCall = pcall(run, "trap", 3, 0, nil)
  ok(okCall, "the row raised when handed no destination var")
end

-- ---------------------------------------------------------------------------
section("3. the lowerings, and nothing lowered to the wrong thing")
-- ---------------------------------------------------------------------------
-- A CANARY FIRST, because `lowered` answering yes to everything would report
-- every assertion below as satisfied -- and `Gen4ScriptVM` has twice come back
-- as the command audit's inert stub, where it answers nil for all of them.
ok(VM.lowered("message") == true,
   "the detector says `message` is not lowered, so it is not reading the real "
   .. "table and every assertion in this section is vacuous")
ok(VM.lowered("showshardcost") == false,
   "the detector says `showshardcost` IS lowered; it is one of the seven this "
   .. "pass deliberately left, so the detector is answering yes to everything")

local THIS_PASS = {
  "givetrap", "givesphere",
  "bufferundergroundtrapname", "bufferundergrounditemname",
  "buffercontestbackdropname",
  "countmailinmailbox", "countuniquesealsinsealcase",
  "opensealcapsuleeditor",
  "messagefromtrainertype", "waitfortransition",
}
for _, name in ipairs(THIS_PASS) do
  ok(VM.lowered(name) == true, "`%s` is not lowered", name)
end

-- The bank numbers, read out of the lowering's own source rather than retyped.
do
  local src = code(slurp("src/script/Gen4ScriptVM.lua"))
  local want = {
    bufferundergroundtrapname  = 630,
    bufferundergrounditemname  = 628,
    buffercontestbackdropname  = 388,
    bufferundergroundgoodsname = 626,
  }
  for name, bank in pairs(want) do
    local body = src:match("L%." .. name .. "%s*=%s*function.-\nend")
    ok(body ~= nil, "could not find the lowering for `%s`", name)
    if body then
      local got = tonumber(body:match('bank:(%d+)'))
      ok(got == bank,
         "`%s` lowers onto bank %s; pokeplatinum's text_banks.txt puts it at "
         .. "%d (line %d, minus one)", name, tostring(got), bank, bank + 1)
    end
  end
end

-- ---------------------------------------------------------------------------
section("4. the bank numbers, three ways")
-- ---------------------------------------------------------------------------
local texts = loadTable(CACHE, "text")
if not texts then
  skip("no text.lua in this cache, so the bank numbers are unverified "
       .. "against their contents")
else
  local Gen4Text = require("src.import.Gen4Text")
  local function entry(bank, i)
    return texts[Gen4Text.label(bank, i)]
  end
  local function size(bank)
    local n = 0
    for i = 0, 400 do if entry(bank, i) then n = n + 1 end end
    return n
  end
  -- (a) the banks exist and are not empty
  for _, b in ipairs({ { 626, "goods" }, { 628, "items" }, { 630, "traps" },
                       { 388, "contest backdrops" } }) do
    local n = size(b[1])
    ok(n > 0, "bank %d (%s) has no entries in this cache", b[1], b[2])
    report("bank %d (%s): %d entries", b[1], b[2], n)
  end

  -- (b) THE CONTENT AGREES WITH THE ENUM, item for item. This is the assertion
  -- that a wrong bank number cannot survive: bank 630 entry 1 must be the name
  -- of `generated/traps.txt` line 2.
  if not PRET then
    skip("no pokeplatinum checkout, so the trap and sphere enums could not be "
         .. "read and the content agreement is untested")
  else
    local traps = slurp(PRET .. "/generated/traps.txt")
    local spheres = slurp(PRET .. "/generated/sphere_types.txt")
    ok(traps ~= nil and spheres ~= nil,
       "generated/traps.txt or sphere_types.txt is not readable")
    if traps and spheres then
      local names = {}
      for line in traps:gmatch("[^\r\n]+") do names[#names + 1] = line end
      ok(names[1] == "TRAP_NONE",
         "traps.txt line 1 is %q, not TRAP_NONE -- the zero sentinel this "
         .. "port's TRAP_NONE was read from", tostring(names[1]))
      -- the enum's own words, turned into the words the bank would use
      local WORDS = { MOVE = "Move", HURL = "Hurl", HOLE = "Hole",
                      PIT = "Pit", SMOKE = "Smoke", ROCK = "Rock",
                      FOAM = "Foam", BUBBLE = "Bubble" }
      local tested, agreed = 0, 0
      for i = 2, #names do
        local kind = names[i]:match("^TRAP_([A-Z]+)")
        local word = kind and WORDS[kind]
        local text = entry(630, i - 1)
        if word and type(text) == "string" then
          tested = tested + 1
          if text:find(word, 1, true) then agreed = agreed + 1 end
        end
      end
      ok(tested >= 12,
         "only %d trap name(s) could be compared, which is too few to have "
         .. "established anything", tested)
      ok(agreed == tested,
         "%d of %d trap names in bank 630 do not match the enum row at the "
         .. "same index -- the trap id is supposed to BE its own bank index, "
         .. "and if it is not then bank 630 is the wrong bank", 
         tested - agreed, tested)
      report("%d trap id(s) agree with bank 630 entry-for-entry", agreed)

      -- the spheres, the same way
      local sph = {}
      for line in spheres:gmatch("[^\r\n]+") do sph[#sph + 1] = line end
      local st, sa = 0, 0
      for i = 2, #sph do
        local colour = sph[i]:match("^SPHERE_([A-Z]+)")
        local text = entry(628, i - 1)
        if colour and colour ~= "MAX" and type(text) == "string" then
          st = st + 1
          local pretty = colour:sub(1, 1) .. colour:sub(2):lower()
          if text:find(pretty, 1, true) then sa = sa + 1 end
        end
      end
      ok(st >= 5, "only %d sphere type(s) could be compared", st)
      ok(sa == st,
         "%d of %d sphere names in bank 628 do not match sphere_types.txt at "
         .. "the same index", st - sa, st)
      report("%d sphere type(s) agree with bank 628 entry-for-entry", sa)

      -- (c) and the line-number rule itself, from the file the numbers came
      -- from, so none of the four is a number somebody typed.
      local banksTxt = slurp(PRET .. "/generated/text_banks.txt")
      if not banksTxt then
        skip("generated/text_banks.txt is not readable")
      else
        local line, index = 0, {}
        for name in banksTxt:gmatch("[^\r\n]+") do
          line = line + 1
          index[name] = line - 1
        end
        for name, bank in pairs({
          TEXT_BANK_UNDERGROUND_GOODS = 626,
          TEXT_BANK_UNDERGROUND_ITEMS = 628,
          TEXT_BANK_UNDERGROUND_TRAPS = 630,
          TEXT_BANK_CONTEST_BACKDROP_NAMES = 388,
          -- 634 IS `UNDERGROUND_COMMON`, NOT `..._QUESTIONS`.  Named here
          -- because the Underground menu (#198) reads 634 for its row labels
          -- and the first draft of this check asserted the wrong constant
          -- against it: QUESTIONS is the line BELOW, so bank 633.  The menu's
          -- number was right and the name in this check was wrong, which is
          -- the direction worth recording -- bank 634 holds "GREET",
          -- "QUESTION", "GIVE GOODS", "EXIT", which are labels, not questions.
          TEXT_BANK_UNDERGROUND_COMMON = 634,
          TEXT_BANK_UNDERGROUND_QUESTIONS = 633,
        }) do
          ok(index[name] == bank,
             "%s is line %s of text_banks.txt, so bank %s; this port uses %d",
             name, tostring(index[name] and index[name] + 1),
             tostring(index[name]), bank)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
section("5. the honest answers, asserted to be answers")
-- ---------------------------------------------------------------------------
-- `g4_no_feature` writes the var AND says so. The writing is the part that
-- matters -- the `gotoif` behind these reads it -- and the saying is what stops
-- an absent system looking like a present one.
do
  local VARS = 0x4000
  for _, case in ipairs({ { "the mailbox" }, { "the seal case" } }) do
    local ctx = { save = {} }
    ctx.game = { save = ctx.save }
    local _, log = capture(function()
      Commands.g4_no_feature(ctx, VARS, case[1])
      return nil
    end)
    ok(Gen4Commands.getVar(ctx.save, VARS) == 0,
       "a `%s` row left the destination var %s rather than 0, so the branch "
       .. "behind it reads the previous comparison", case[1],
       tostring(Gen4Commands.getVar(ctx.save, VARS)))
  end
  -- ...and it is reported at least once per subject, which is what makes an
  -- absent system visible in a log rather than silent.
  local ctx = { save = {} }
  local _, log = capture(function()
    Commands.g4_no_feature(ctx, VARS, "a subject nothing else uses")
    return nil
  end)
  ok(log:find("does not have", 1, true) ~= nil,
     "a no-feature answer said nothing: %q", log)
end

-- `pending` is the OTHER answer, and the distinction is load-bearing: a no-op
-- claims there is nothing to do.
ok(type(Commands.g4_open_seal_capsule_editor) == "function",
   "`g4_open_seal_capsule_editor` has no handler, so the row the lowering "
   .. "emits reaches nothing")

-- EVERY VERB ASSIGNED FROM `pending(...)`, AS AN INVARIANT RATHER THAN A LIST,
-- and it found a live one on its first run.
--
-- `pending` installs the handler itself and used to return nothing, so the
-- `Commands.x = pending("x", ...)` spelling **overwrote the handler with nil**.
-- The bare `pending("x", ...)` spelling worked. Two verbs were on the broken
-- side: `g4_open_hall_of_fame`, which pass 173 added and raised the pending pin
-- for, and `g4_open_seal_capsule_editor` from this pass. The PC's Hall of Fame
-- row did not step over anything -- it reached no verb at all.
--
-- The subject derives itself: a new `Commands.x = pending(...)` is covered the
-- day it is written.
do
  local src = code(slurp("src/script/Gen4Commands.lua"))
  local assigned, missing = 0, {}
  for verb in src:gmatch('Commands%.([a-z_0-9]+)%s*=%s*pending%s*%(') do
    assigned = assigned + 1
    if type(Commands[verb]) ~= "function" then
      missing[#missing + 1] = verb
    end
  end
  ok(assigned >= 2,
     "only %d verb(s) are assigned from `pending(...)`, which is too few for "
     .. "this sweep to have found the spelling it is about", assigned)
  ok(#missing == 0,
     "%d verb(s) assigned from `pending(...)` are not functions, so the row "
     .. "the lowering emits reaches nothing: %s", #missing,
     table.concat(missing, ", "))
  -- ...and the bare spelling still works, so the fix did not trade one for
  -- the other.
  local bare = 0
  for verb in src:gmatch('\n%s*pending%s*%(%s*"([a-z_0-9]+)"') do
    bare = bare + 1
    ok(type(Commands[verb]) == "function",
       "`%s` is installed by a bare pending() call and is not a function", verb)
  end
  ok(bare >= 2, "only %d bare pending() call(s) found", bare)
  report("%d assigned and %d bare pending() verb(s), all installed",
         assigned, bare)
end
do
  local _, log = capture(function()
    Commands.g4_open_seal_capsule_editor({ save = {} })
    return nil
  end)
  ok(log:find("not built", 1, true) ~= nil,
     "the capsule editor row ran silently; `pending` exists to say the thing "
     .. "behind the row is unbuilt: %q", log)
end

-- `waitfortransition` lowers to a no-op WITH ITS REASON. A no-op whose reason
-- is a blank is how a hole becomes invisible.
do
  local src = code(slurp("src/script/Gen4ScriptVM.lua"))
  local body = src:match("L%.waitfortransition%s*=%s*function.-\nend")
  ok(body ~= nil, "`waitfortransition` has no lowering")
  if body then
    local reason = body:match('"g4_noop",%s*"([^"]+)"')
    ok(reason ~= nil and #reason > 8,
       "`waitfortransition` lowers to a no-op with the reason %q; a no-op has "
       .. "to say what owns the work instead", tostring(reason))
  end
end

-- ---------------------------------------------------------------------------
section("6. messagefromtrainertype, whose entry is not in the stream")
-- ---------------------------------------------------------------------------
do
  local shown
  local realShow = Commands.show_text
  Commands.show_text = function(_, id) shown = id ; return nil end
  local Gen4Text = require("src.import.Gen4Text")

  local ctx = { save = {}, npc = { def = { trainerType = 7 } } }
  ctx.game = { save = ctx.save, data = { text = {} } }
  Commands.g4_message_trainer_type(ctx, 213)
  ok(shown == Gen4Text.label(213, 7),
     "the row showed %s; the entry is the TARGET OBJECT's trainer type (7) of "
     .. "the band's own bank (213)", tostring(shown))

  -- A DIFFERENT TYPE MUST SHOW A DIFFERENT LINE. Without this, a handler that
  -- hard-coded entry 0 would satisfy a single-case assertion.
  shown = nil
  ctx.npc.def.trainerType = 3
  Commands.g4_message_trainer_type(ctx, 213)
  ok(shown == Gen4Text.label(213, 3),
     "changing the object's trainer type to 3 showed %s, so the entry is not "
     .. "read from the object at all", tostring(shown))

  -- ...and no object is 0, with a warning, rather than a raise mid-script.
  shown = nil
  local ctx2 = { save = {}, game = { save = {}, data = { text = {} } } }
  local okCall, log = capture(function()
    return pcall(Commands.g4_message_trainer_type, ctx2, 213)
  end)
  ok(okCall, "the row raised with no target object")
  ok(shown == Gen4Text.label(213, 0),
     "with no target object the row showed %s rather than the bank's entry 0",
     tostring(shown))
  ok(log:find("no target object", 1, true) ~= nil,
     "running with no target object said nothing: %q", log)

  Commands.show_text = realShow
end

-- ---------------------------------------------------------------------------
section("7. the ceiling, from the other side")
-- ---------------------------------------------------------------------------
-- `gen4_field_moves_check` owns the ceiling (7). This owns the LIST, so a
-- later pass cannot lower one of the seven and leave the ceiling at seven --
-- which would hide a new hole behind a fixed one.
do
  local REMAIN = { "0a5", "0b3", "1b3", "205", "2f6",
                   "showshardcost", "closeshardcostwindow" }
  local stillOpen = 0
  for _, name in ipairs(REMAIN) do
    if VM.lowered(name) == false then stillOpen = stillOpen + 1 end
  end
  ok(stillOpen == #REMAIN,
     "%d of the %d commands this pass deliberately left are now lowered; "
     .. "lower the ceiling in gen4_field_moves_check to match, or this list "
     .. "is hiding a hole somebody opened",
     #REMAIN - stillOpen, #REMAIN)
  report("the %d commands left in common_scripts: %s",
         #REMAIN, table.concat(REMAIN, ", "))
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
