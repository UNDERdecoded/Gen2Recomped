-- Parity / regression: a box mon has no stat block, so the engine derives one
-- on demand (#233 STATS in the box, #304 withdraw).  macros/ram.asm's
-- box_struct is a prefix of party_struct that stops before MON_STATS;
-- status_screen.asm:64-77 recomputes on BOX_DATA before it draws, and
-- add_mon.asm's _MoveMon runs CalcStats on the way back to the party.  The
-- formula itself is home/move_mon.asm CalcStats, ported in Stats.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.ODDISH) then Data:load() end
local S = require("tests.harness").suite("parity box mon stats")
local check, eq = S.check, S.eq

local Stats = require("src.pokemon.Stats")
local SaveData = require("src.core.SaveData")
local Boxes = require("src.pokemon.Boxes")
local HudTiles = require("src.render.HudTiles")

-- A mon shaped like GenSave.decodeMon's box output: no `stats` key at all.
-- Gen 1 has no HP DV byte, it is the low bit of each of the other four
-- (home/pokemon.asm GetMonHeader), so 13/11/7/5 being odd makes the HP DV
-- 15.  The .sav round trip below only compares because of that.
local DVS = { hp = 15, attack = 13, defense = 11, speed = 7, special = 5 }
local STATEXP = { hp = 1200, attack = 900, defense = 400, speed = 0, special = 250 }

local function boxShapedMon(species, level, hp)
  return {
    species = species, level = level, exp = 1000,
    dvs = { hp = DVS.hp, attack = DVS.attack, defense = DVS.defense,
            speed = DVS.speed, special = DVS.special },
    statExp = { hp = STATEXP.hp, attack = STATEXP.attack,
                defense = STATEXP.defense, speed = STATEXP.speed,
                special = STATEXP.special },
    hp = hp, status = nil, otId = 12345, catchRate = 45,
    moves = { { id = "ABSORB", pp = 20 } },
    typeBytes = { 22, 3 },
  }
end

-- ================================================================== 1
-- Stats.ensure gives the same numbers as Stats.calc and never leaves a
-- current HP above the maximum it derived.
do
  local def = Data.pokemon.ODDISH
  local want = Stats.calc(def, 13, DVS, STATEXP)

  local mon = boxShapedMon("ODDISH", 13, 999) -- a PKHeX-tampered current HP
  eq(mon.stats, nil, "premise: a box-shaped mon starts with no stat block")
  Stats.ensure(def, mon)
  check(type(mon.stats) == "table", "ensure gives the box mon a stat block")
  for _, key in ipairs(Stats.ORDER) do
    eq(mon.stats[key], want[key], "ensure's " .. key .. " matches CalcStats")
  end
  eq(mon.hp, want.hp, "a tampered 999 HP clamps to the recomputed maximum")

  -- a stored HP under the maximum is what box_struct really holds; keep it
  local hurt = boxShapedMon("ODDISH", 13, 7)
  Stats.ensure(def, hurt)
  eq(hurt.hp, 7, "a stored current HP below the max is kept as stored")
  eq(hurt.stats.hp, want.hp, "and the maximum is the derived one")

  -- a fainted box mon stays fainted (the REVIVE case in the party menu)
  local fainted = boxShapedMon("ODDISH", 13, 0)
  Stats.ensure(def, fainted)
  eq(fainted.hp, 0, "a fainted box mon stays at 0 HP")

  -- idempotent, so a vanilla save round-trips with the numbers it was saved
  -- with rather than recomputed ones
  local party = boxShapedMon("ODDISH", 13, 7)
  party.stats = { hp = 1, attack = 2, defense = 3, speed = 4, special = 5 }
  local before = party.stats
  Stats.ensure(def, party)
  check(party.stats == before, "ensure leaves an existing stat block alone")
  eq(party.stats.hp, 1, "and does not clamp HP against a block it did not build")
  eq(party.hp, 7, "nor rewrite the stored HP")

  -- a species the merged data does not know must not raise here: validate's
  -- own quarantine pass owns that mon, and ensure runs before it
  local unknown = boxShapedMon("NOT_A_SPECIES", 13, 7)
  Stats.ensure(nil, unknown)
  eq(unknown.stats, nil, "an unknown species leaves stats nil instead of raising")
end

-- ================================================================== 2
-- The real .sav path: encode -> decode is what an imported battery save does
-- to a box mon (SaveFileIO -> SaveConvert.importSav -> GenSave.decode).
do
  local GenSave = require("src.save_convert.GenSave")
  GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())

  local save = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
  Boxes.ensure(save)
  -- the same mon in the party and in box 1, so the two structs can be
  -- compared against each other after the round trip
  save.party = { boxShapedMon("ODDISH", 13, 20) }
  Stats.ensure(Data.pokemon.ODDISH, save.party[1])
  save.boxes[1] = { boxShapedMon("ODDISH", 13, 20) }
  Stats.ensure(Data.pokemon.ODDISH, save.boxes[1][1])

  local bytes = GenSave.encode(save, Data, nil)
  eq(#bytes, GenSave.SAVE_SIZE, "the fixture save encodes to a 32768-byte .sav")

  local imported = GenSave.decode(bytes, Data)
  check(type(imported.party[1]) == "table", "the .sav decodes a party mon")
  check(type((imported.boxes[1] or {})[1]) == "table", "and a box 1 mon")
  local pmon, bmon = imported.party[1], imported.boxes[1][1]
  check(type(pmon.stats) == "table",
        "premise: party_struct carries stats, so the party mon has them")
  eq(bmon.stats, nil,
     "premise: box_struct does not, so the imported box mon has none (#233)")

  -- Game:restoreSave runs this on every load, which is the only thing that
  -- reaches a save already sitting on disk
  SaveData.validate(imported, Data)
  -- guarded: without the repair every line below raises the reported crash
  -- itself, which would hide the rest of the suite
  if check(type(bmon.stats) == "table", "validate repairs the imported box mon") then
    local want = Stats.calc(Data.pokemon[bmon.species], bmon.level, bmon.dvs,
                            bmon.statExp)
    for _, key in ipairs(Stats.ORDER) do
      eq(bmon.stats[key], want[key], "repaired box " .. key .. " matches CalcStats")
    end
    eq(bmon.stats.hp, pmon.stats.hp,
       "the box copy ends up with the same max HP the party copy stored")
    check(bmon.hp <= bmon.stats.hp, "current HP can never sit above the maximum")
    -- the exact expression src/render/HudTiles.lua drawHPBar died on
    check(type(bmon.stats.hp) == "number",
          "mon.stats.hp is a number (the nil index)")
  end

  -- the call SummaryMenu:draw and PartyMenu:draw both make (#233 / #304)
  local okDraw, err = pcall(HudTiles.drawHPBar, Data, 11, 3, bmon, 1)
  check(okDraw, "drawHPBar over a repaired box mon does not raise: " .. tostring(err))

  -- box_struct has no stat fields, so the repair must not move a byte of the
  -- exported .sav
  local reexported = GenSave.encode(imported, Data)
  eq(#reexported, GenSave.SAVE_SIZE, "the repaired save re-exports to 32768 bytes")
  local firstDiff
  for i = 1, #bytes do
    if bytes:byte(i) ~= reexported:byte(i) then firstDiff = i break end
  end
  eq(firstDiff, nil,
     "the stat repair leaves the .sav byte-identical on export (box_struct "
     .. "has no stat fields)")
end

-- ================================================================== 3
-- Every list a stats-less mon can sit in: party, all twelve boxes, and the
-- daycare (status_screen.asm treats DAYCARE_DATA like BOX_DATA).
do
  local save = SaveData.newGame()
  Boxes.ensure(save)
  save.party = { boxShapedMon("PIDGEY", 9, 5) }
  save.boxes[1] = { boxShapedMon("RATTATA", 4, 3) }
  save.boxes[7] = { boxShapedMon("ZUBAT", 22, 40) }
  save.daycare = { mon = boxShapedMon("ODDISH", 13, 6) }

  SaveData.validate(save, Data)
  check(type(save.party[1].stats) == "table", "validate repairs a party slot")
  check(type(save.boxes[1][1].stats) == "table", "validate repairs box 1")
  check(type(save.boxes[7][1].stats) == "table", "validate repairs box 7")
  check(type(save.daycare.mon.stats) == "table", "validate repairs the daycare mon")

  -- the level clamp runs first, so the derived stats use a sane level
  local wild = boxShapedMon("PIDGEY", 250, 5)
  local save2 = SaveData.newGame()
  Boxes.ensure(save2)
  save2.boxes[1] = { wild }
  SaveData.validate(save2, Data)
  eq(wild.level, 100, "an out-of-range level clamps to 100")
  eq(wild.stats and wild.stats.hp,
     Stats.calc(Data.pokemon.PIDGEY, 100, wild.dvs, wild.statExp).hp,
     "and the derived stats use the clamped level, not the stored one")
end

-- ================================================================== 4
-- #233's own site: SummaryMenu.new ports status_screen.asm's
-- .DontRecalculate branch, and Bill's PC hands it the box mon directly.
do
  local realSound = package.loaded["src.core.Sound"]
  package.loaded["src.core.Sound"] = { play = function() end,
                                       playCry = function() end }
  local SummaryMenu = require("src.ui.SummaryMenu")
  local mon = boxShapedMon("ODDISH", 13, 20)
  local game = { data = Data, save = SaveData.newGame() }
  local ok, screen = pcall(SummaryMenu.new, game, mon)
  check(ok, "opening STATS on a stats-less box mon does not raise: "
            .. tostring(screen))
  check(type(mon.stats) == "table",
        "SummaryMenu.new recalculates the block before it draws (#233)")
  if ok and screen then
    local okDraw, err = pcall(function()
      HudTiles.drawHPBar(Data, 11, 3, screen.mon, 1)
    end)
    check(okDraw, "and its HP bar draws: " .. tostring(err))
  end
  package.loaded["src.core.Sound"] = realSound
end

-- ================================================================== 5
-- #304's own site: the box -> party transfer, which is the only thing that
-- covers a mon a mod drops into a box mid-session.  withdraw is a
-- file-local, reached through upvalues as tests/parity_bills_pc.lua does.
do
  local BoxMenu = require("src.ui.BoxMenu")

  local function getUpvalue(fn, name)
    local i = 1
    while true do
      local n, v = debug.getupvalue(fn, i)
      if not n then return nil end
      if n == name then return v end
      i = i + 1
    end
  end
  local function setUpvalue(fn, name, val)
    local i = 1
    while true do
      local n = debug.getupvalue(fn, i)
      if not n then return false end
      if n == name then debug.setupvalue(fn, i, val); return true end
      i = i + 1
    end
  end

  local withdraw = getUpvalue(BoxMenu.new, "withdraw")
  check(type(withdraw) == "function", "found BoxMenu's withdraw upvalue")

  if type(withdraw) == "function" then
    -- capture the list menu's opts instead of building a real one
    local captured
    check(setUpvalue(withdraw, "ListMenu", {
      new = function(_, _, items, opts)
        captured = { items = items, opts = opts }
        return { kind = "list", items = items, close = function() end }
      end,
    }), "stubbed ListMenu on withdraw")
    -- the WITHDRAW row is what fires onAction; run it straight
    check(setUpvalue(withdraw, "monSubmenu",
                     function(_, _, _, onAction) onAction() end),
          "stubbed monSubmenu on withdraw")
    check(setUpvalue(withdraw, "afterTransfer", function() end),
          "stubbed afterTransfer on withdraw")

    local realSound = package.loaded["src.core.Sound"]
    package.loaded["src.core.Sound"] = { play = function() end,
                                         playCry = function() end }

    local save = SaveData.newGame()
    Boxes.ensure(save)
    save.party = {}
    save.boxes[1] = { boxShapedMon("ODDISH", 13, 20) }
    local mon = save.boxes[1][1]
    local game = { data = Data, save = save,
                   stack = { push = function() end, pop = function() end } }

    withdraw(game)
    check(captured ~= nil, "withdraw opened its box list")
    if captured then
      eq(#captured.items, 1, "the list has the one box mon in it")
      captured.opts.onChoose(captured.items[1],
                             { index = 1, close = function() end })
      eq(#save.boxes[1], 0, "the mon left the box")
      eq(#save.party, 1, "and landed in the party")
      eq(save.party[1], mon, "it is the same mon table")
      check(type(mon.stats) == "table",
            "withdraw ran CalcStats on the way out (#304)")
      local want = Stats.calc(Data.pokemon.ODDISH, 13, mon.dvs, mon.statExp)
      eq(mon.stats and mon.stats.hp, want.hp,
         "the withdrawn mon's max HP is the derived one")
      local okDraw, err = pcall(HudTiles.drawHPBar, Data, 5, 5, mon, 2)
      check(okDraw, "the party row's HP bar draws for it: " .. tostring(err))
    end

    package.loaded["src.core.Sound"] = realSound
    -- run_tests.lua dofiles the parity suites in one interpreter, so a later
    -- suite would inherit these stubs
    package.loaded["src.ui.BoxMenu"] = nil
  end
end

S.finish()
