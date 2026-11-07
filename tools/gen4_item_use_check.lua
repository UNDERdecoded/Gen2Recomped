-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- CAN SINNOH'S ITEMS ACTUALLY BE USED?
--
-- Reported from play: "pokeballs arent working in platinum they give an error
-- not the place this item should be used, make sure all items are cabable of
-- being used properly."
--
-- TWO CAUSES, both of them the same shape: a second cartridge spelling a thing
-- differently from the first, and one file knowing only the first spelling.
--
--  1. THE BALL POCKET.  Every one of Platinum's sixteen balls carries
--     `pocket = "POKE_BALLS"`; Emerald's twelve carry `"BALL"`.
--     `ItemEffects.isBall` knew one of those, so no Sinnoh ball was a ball and
--     `use` fell past the ball branch to the refusal.
--
--  2. EVERY MEDICINE IN THE GAME.  The rest of `use` dispatches on a NAME that
--     `alias` reads from the item record's `key`. A Platinum item record has no
--     `key` -- the cache is 446 rows keyed 0..445, published again as
--     ITEM_000.. because the bag's keys are strings -- so a Potion answered
--     "ITEM_017", every name test failed, and it too ended at the refusal.
--
-- The fix for the second one is not a name table. `ItemData.partyUseParam`
-- (pokeplatinum include/item.h) is a twenty-byte `ItemPartyParam` naming every
-- effect the item has on a party member, the extractor already writes it out,
-- and `ItemEffects.gen4RecordFor` decodes it into the record shape `gen3Use`
-- already runs. Section 1 checks the decode against the shipped bytes; section
-- 4 runs the items.
--
-- Usage: texlua tools/gen4_item_use_check.lua [platinum/data/generated]
--                                             [emerald/data/generated]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

-- A LOVE THAT DOES NOTHING.  `ItemEffects` reaches `src.core.Sound`, which
-- indexes the global `love` on its way to playing a heal chime; headless there
-- is none, and the run died in the middle of section 4 rather than reporting
-- anything. Silent is the right behaviour for a check.
love = love or {
  audio = { newSource = function() return nil end },
  sound = { newSoundData = function() return nil end },
  filesystem = { getInfo = function() return nil end },
  timer = { getTime = function() return 0 end },
  graphics = { getWidth = function() return 240 end,
               getHeight = function() return 160 end },
  system = { getOS = function() return "Linux" end },
}

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local plRoot = arg and arg[1] or "G:/Gen2Recomped/platinum/data/generated"
local emRoot = arg and arg[2] or "G:/Gen2Recomped/emerald/data/generated"
local function load(rootDir, name)
  local chunk = loadfile(rootDir .. "/" .. name .. ".lua")
  if not chunk then return nil end
  local okRun, value = pcall(chunk)
  return okRun and value or nil
end

local plItems = load(plRoot, "items")
if not plItems then
  io.write(("  cannot read %s/items.lua\n"):format(plRoot))
  io.write("\n  Pass the generated Platinum data root as the first argument.\n")
  os.exit(2)
end

local ItemEffects = require("src.inventory.ItemEffects")

-- the item table indexed the way the bag indexes it, which is by string
local byName = {}
local numeric, total = 0, 0
for id, def in pairs(plItems) do
  if type(def) == "table" and def.name then
    total = total + 1
    if type(id) == "number" then numeric = numeric + 1 end
    byName[def.name] = def
  end
end
io.write(("  %s: %d items, %d of them keyed by number\n")
         :format(plRoot, total, numeric))

-- ---------------------------------------------------------------------------
section("1. the twenty-byte struct decodes to what the cartridge ships")
-- ---------------------------------------------------------------------------
-- Not "does it return a table": the four facts below are the ones that pin the
-- LAYOUT, and each of them lands in a different part of it. A struct read one
-- bit out still returns a table.
ok(total >= 440, "only %d items loaded; Platinum has 446", total)
ok(numeric >= 440, "only %d items are numerically keyed; the whole point of "
   .. "the struct path is that there is no name to key on", numeric)

local function rec(name)
  local def = byName[name]
  if not def then return nil end
  return ItemEffects.gen4RecordFor(def)
end
local WANT = {
  -- the amounts, at byte 13
  { "Potion",       { heal = true, amount = 20 } },
  { "Super Potion", { heal = true, amount = 50 } },
  { "Hyper Potion", { heal = true, amount = 200 } },
  { "Max Potion",   { heal = true, amount = "all" } },
  { "Fresh Water",  { heal = true, amount = 50 } },
  -- the two sentinels, with the revive bit
  { "Revive",       { heal = true, revive = true, amount = "half" } },
  { "Max Revive",   { heal = true, revive = true, amount = "all" } },
  -- status, single and whole
  { "Antidote",     { cures = { "PSN" } } },
  { "Burn Heal",    { cures = { "BRN" } } },
  { "Awakening",    { cures = { "SLP" } } },
  { "Full Heal",    { cureAll = true } },
  { "Full Restore", { cureAll = true, heal = true, amount = "all" } },
  -- PP, one move and all of them, at byte 14
  { "Ether",        { pp = "one", amount = 10 } },
  { "Max Ether",    { pp = "one", amount = "all" } },
  { "Elixir",       { pp = "all", amount = 10 } },
  { "Max Elixir",   { pp = "all", amount = "all" } },
  { "PP Up",        { ppUp = true } },
  { "PP Max",       { ppMax = true } },
  -- the level, which must NOT come back as a revive
  { "Rare Candy",   { levelUp = true } },
  -- effort values, signed, at bytes 7..12
  { "HP Up",        { ev = "hp" } },
  { "Protein",      { ev = "attack" } },
  { "Iron",         { ev = "defense" } },
  { "Carbos",       { ev = "speed" } },
  { "Calcium",      { ev = "spatk" } },
  { "Zinc",         { ev = "spdef" } },
}
for _, row in ipairs(WANT) do
  local name, want = row[1], row[2]
  local r = rec(name)
  ok(r ~= nil, "%s decodes to no record at all", name)
  if r then
    for key, value in pairs(want) do
      if key == "cures" then
        local got = r.cures or {}
        ok(#got == #value and got[1] == value[1],
           "%s cures %s; the cartridge says %s", name,
           table.concat(got, ","), table.concat(value, ","))
      else
        ok(r[key] == value, "%s: %s is %s, the cartridge says %s",
           name, key, tostring(r[key]), tostring(value))
      end
    end
    -- and a Rare Candy must not ALSO look like a revive, which is what its
    -- own bit 0 would make it
    if want.levelUp then
      ok(not r.revive, "%s came back as a revive as well, so the revive arm "
         .. "would claim it and the level would never happen", name)
    end
  end
end
-- THE FRIENDSHIP STEPS, which are the tail of the struct and signed.
do
  local candy = rec("Rare Candy")
  ok(candy and candy.friendship and #candy.friendship == 3,
     "Rare Candy carries %s friendship steps, not three",
     tostring(candy and candy.friendship and #candy.friendship))
  if candy and candy.friendship then
    ok(candy.friendship[1] == 5 and candy.friendship[2] == 3
       and candy.friendship[3] == 2,
       "Rare Candy's friendship steps are %d/%d/%d; Gen 4's are 5/3/2",
       candy.friendship[1], candy.friendship[2], candy.friendship[3])
  end
  -- ...and the herbs, which are why those bytes have to be SIGNED. An unsigned
  -- read gives 246/246/241 and the check above would still pass.
  local root_ = rec("Energy Root")
  ok(root_ and root_.friendship and root_.friendship[1] == -10
     and root_.friendship[3] == -15,
     "the Energy Root's friendship steps are %s; the cartridge's are "
     .. "-10/-10/-15, and an unsigned read gives 246/246/241",
     root_ and root_.friendship
       and table.concat(root_.friendship, "/") or "absent")
end

-- ---------------------------------------------------------------------------
section("2. every ball is a ball")
-- ---------------------------------------------------------------------------
local balls, recognised, missed = 0, 0, {}
for id, def in pairs(plItems) do
  if type(def) == "table" and def.pocket == "POKE_BALLS" and def.name ~= "None" then
    balls = balls + 1
    if ItemEffects.isBall(id, def) then recognised = recognised + 1
    else missed[#missed + 1] = def.name end
  end
end
io.write(("  %d items in the POKE_BALLS pocket, %d recognised\n")
         :format(balls, recognised))
ok(balls >= 15, "only %d balls found in the pocket", balls)
ok(#missed == 0, "%d ball(s) are not recognised as balls: %s", #missed,
   table.concat(missed, ", "))
-- and the CONTROL: something that is not a ball must not answer yes, or the
-- count above is measuring a function that says true to everything
do
  local potion = byName["Potion"]
  ok(potion and not ItemEffects.isBall("ITEM_017", potion),
     "a Potion answers `isBall`, so the ball test says yes to anything")
  local tm = nil
  for _, def in pairs(plItems) do
    if type(def) == "table" and def.pocket == "TM_HM" then tm = def break end
  end
  ok(tm and not ItemEffects.isBall("ITEM_TM", tm),
     "a TM answers `isBall`")
end

-- ---------------------------------------------------------------------------
section("3. every item the cartridge says has a party use gets a record")
-- ---------------------------------------------------------------------------
-- `partyUse` is the cartridge's own gate: `Item_Get` reads the twenty-byte
-- struct only when it is TRUE, and reads the union's `dummy` byte when it is
-- FALSE. So the two halves of this section are the two directions of that gate,
-- and BOTH are needed -- a decoder that answers for everything satisfies the
-- first on its own, and one that answers for nothing satisfies the second.
local gated, decoded, blank, missing = 0, 0, 0, {}
local function allZero(def)
  local b = def.partyUseParam
  if type(b) ~= "string" then return true end
  for i = 1, #b do if b:byte(i) ~= 0 then return false end end
  return true
end
for id, def in pairs(plItems) do
  if type(def) == "table" and (tonumber(def.partyUse) or 0) == 1 then
    gated = gated + 1
    local r = ItemEffects.gen4RecordFor(def)
    if r then decoded = decoded + 1
    elseif allZero(def) then blank = blank + 1
    else missing[#missing + 1] = def.name end
  end
end
table.sort(missing)
io.write(("  %d items are gated in by `partyUse`, %d decode to a record, "
          .. "%d ship an all-zero struct\n"):format(gated, decoded, blank))
ok(gated > 100, "only %d items are gated in", gated)
ok(decoded > 40, "only %d decode to a record", decoded)
-- NOT "every gated item decodes": some genuinely ship twenty zero bytes, which
-- is the cartridge saying the item does nothing to a party member from the bag.
-- What must never happen is a struct with bits set in it decoding to nothing --
-- that is an effect being dropped.
ok(#missing == 0, "%d item(s) carry a non-empty struct that decodes to "
   .. "nothing, so an effect the cartridge states is being dropped: %s",
   #missing, table.concat(missing, " ", 1, math.min(#missing, 14)))

-- ...AND THE OTHER DIRECTION.  An item the gate excludes must decode to nil, or
-- a Great Ball's `dummy` byte of 2 reads as healPoison and every ball, rod and
-- piece of mail in the bag opens a party picker. Twenty-eight of them did.
local spurious = {}
for id, def in pairs(plItems) do
  if type(def) == "table" and (tonumber(def.partyUse) or 0) ~= 1
     and ItemEffects.gen4RecordFor(def) then
    spurious[#spurious + 1] = def.name
  end
end
table.sort(spurious)
ok(#spurious == 0, "%d items the cartridge's own gate excludes decode to a "
   .. "record anyway: %s", #spurious,
   table.concat(spurious, " ", 1, math.min(#spurious, 14)))

-- ---------------------------------------------------------------------------
section("4. and they actually work, run through ItemEffects.use")
-- ---------------------------------------------------------------------------
-- Everything above reads the record. This runs the engine's own `use` against a
-- real party member and looks at what happened to it, because a record that is
-- read correctly and then reaches no arm is exactly the bug being fixed.
local plPokemon = load(plRoot, "pokemon")
local plMoves = load(plRoot, "moves")
ok(plPokemon ~= nil, "could not read the Platinum species table")
if plPokemon then
  local data = { items = {}, pokemon = plPokemon, moves = plMoves or {},
                 constants = {}, text = {} }
  for id, def in pairs(plItems) do
    data.items[id] = def
    if type(id) == "number" then data.items[("ITEM_%03d"):format(id)] = def end
  end
  -- A SPECIES OF THE HARNESS'S OWN, not whichever row `next` lands on.
  -- `Stats.calc` reads base stats off the species record and a Rare Candy
  -- recalculates them, so the row has to be a complete one -- picking an
  -- arbitrary entry gave "attempt to perform arithmetic on a nil value
  -- (local 'base')", which is the harness being wrong and not the engine.
  local species = "CHECK_MON"
  data.pokemon[species] = {
    name = "CHECKMON",
    growthRate = "MEDIUM_FAST",
    baseStats = { hp = 60, atk = 60, def = 60, speed = 60,
                  spatk = 60, spdef = 60 },
    evYield = { hp = 1 },
  }
  local save = { player = { name = "RED" }, party = {} }
  local function mon(hp, max, status)
    -- both stat models' inputs, because `Stats.calc` picks by the species
    -- record and a nil `dvs` raises rather than answering
    return { species = species, level = 20, hp = hp,
             stats = { hp = max, atk = 20, def = 20, speed = 20,
                       spatk = 20, spdef = 20 },
             status = status, moves = {}, evs = {}, ivs = {},
             dvs = {}, statExp = {}, nature = 0 }
  end
  local function keyOf(name)
    for id, def in pairs(plItems) do
      if type(def) == "table" and def.name == name and type(id) == "number" then
        return ("ITEM_%03d"):format(id)
      end
    end
  end
  -- a Potion on a hurt Pokemon
  do
    local m = mon(10, 60)
    local kind = ItemEffects.use(data, save, keyOf("Potion"), m, nil, nil, nil)
    ok(kind == "consumed", "a Potion on a hurt Pokemon answered %q, not "
       .. "\"consumed\" -- this is the reported refusal", tostring(kind))
    ok(m.hp == 30, "a Potion took 10 HP to %d; Platinum's Potion is 20", m.hp)
  end
  -- a Potion on a full Pokemon must refuse, or the check above is measuring
  -- an arm that says yes to everything
  do
    local m = mon(60, 60)
    local kind = ItemEffects.use(data, save, keyOf("Potion"), m, nil, nil, nil)
    ok(kind == "failed", "a Potion on a full Pokemon answered %q",
       tostring(kind))
    ok(m.hp == 60, "a Potion on a full Pokemon changed its HP to %d", m.hp)
  end
  -- Full Restore: HP and status together
  do
    local m = mon(5, 60, "PSN")
    local kind = ItemEffects.use(data, save, keyOf("Full Restore"), m, nil, nil, nil)
    ok(kind == "consumed", "a Full Restore answered %q", tostring(kind))
    ok(m.hp == 60, "a Full Restore left %d of 60 HP", m.hp)
    ok(m.status == nil, "a Full Restore left the poison on")
  end
  -- Antidote: status only, and it must NOT touch HP
  do
    local m = mon(20, 60, "PSN")
    local kind = ItemEffects.use(data, save, keyOf("Antidote"), m, nil, nil, nil)
    ok(kind == "consumed", "an Antidote answered %q", tostring(kind))
    ok(m.status == nil, "an Antidote left the poison on")
    ok(m.hp == 20, "an Antidote healed %d HP as well", m.hp - 20)
  end
  -- Antidote on a burn: the wrong status, and it has to refuse
  do
    local m = mon(20, 60, "BRN")
    local kind = ItemEffects.use(data, save, keyOf("Antidote"), m, nil, nil, nil)
    ok(kind == "failed", "an Antidote cured a BURN (answered %q)",
       tostring(kind))
    ok(m.status == "BRN", "an Antidote cleared a burn")
  end
  -- Revive: half HP onto a fainted one
  do
    local m = mon(0, 60)
    local kind = ItemEffects.use(data, save, keyOf("Revive"), m, nil, nil, nil)
    ok(kind == "consumed", "a Revive on a fainted Pokemon answered %q",
       tostring(kind))
    ok(m.hp == 30, "a Revive brought it back with %d of 60; Gen 4's is half",
       m.hp)
  end
  -- Rare Candy: a level, not a revive
  do
    local m = mon(30, 60)
    local before = m.level
    local kind = ItemEffects.use(data, save, keyOf("Rare Candy"), m, nil, nil, nil)
    ok(kind == "consumed", "a Rare Candy answered %q", tostring(kind))
    ok(m.level == before + 1, "a Rare Candy took level %d to %d", before,
       m.level)
  end
  -- a ball, which must ask the caller to throw it rather than refuse
  do
    local kind = ItemEffects.use(data, save, keyOf("Poké Ball"), nil,
                                 { player = {}, enemy = {} }, nil, nil)
    ok(kind == "ball", "a Poke Ball answered %q, not \"ball\" -- this is the "
       .. "reported \"not the place this item should be used\"", tostring(kind))
  end
end

-- ---------------------------------------------------------------------------
section("5. Hoenn is untouched")
-- ---------------------------------------------------------------------------
local emItems = load(emRoot, "items")
if not emItems then
  io.write("  (no Emerald cache at " .. emRoot .. " -- skipped)\n")
else
  local emBalls, emOk = 0, 0
  for id, def in pairs(emItems) do
    if type(def) == "table" and def.pocket == "BALL" then
      emBalls = emBalls + 1
      if ItemEffects.isBall(id, def) then emOk = emOk + 1 end
    end
  end
  io.write(("  %d Emerald balls, %d recognised\n"):format(emBalls, emOk))
  ok(emBalls > 0, "no Emerald balls found; the check is measuring nothing")
  ok(emOk == emBalls, "%d Emerald ball(s) stopped being recognised",
     emBalls - emOk)
  -- an Emerald item must not pick up a Gen 4 record out of nowhere
  local leaked = 0
  for _, def in pairs(emItems) do
    if type(def) == "table" and ItemEffects.gen4RecordFor(def) then
      leaked = leaked + 1
    end
  end
  ok(leaked == 0, "%d Emerald items decode as Sinnoh structs, so Hoenn's "
     .. "medicine would be run off the wrong table", leaked)
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
