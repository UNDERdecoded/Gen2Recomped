-- Parity test: the SHIFT free switch hands the WHOLE exp share to the mon
-- coming in (#275).  EnemySendOutFirstMon zeroes wPartyGainExpFlags and
-- wPartyFoughtCurrentEnemyFlags before jumping to SwitchPlayerMon, which sets
-- only the incoming mon's bit (engine/battle/core.asm:1436-1443, 2424-2433);
-- GiveExperiencePoints divides by the set bits (experience.asm:295-300), so a
-- leftover flag halves the payout.  The reset was never ported.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.RATTATA) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local Experience = require("src.battle.Experience")
local Screens = require("src.ui.Screens")
local S = require("tests.harness").suite("parity shift exp share")
local check, eq = S.check, S.eq

-- Minimal game stub: what BattleState.newTrainer / enemyMonFainted touch.
-- battleStyle is per-scenario, so the caller sets it.
local function freshGame(style)
  return {
    data = Data,
    save = {
      party = {
        Pokemon.new(Data, "BULBASAUR", 50),
        Pokemon.new(Data, "SQUIRTLE", 40),
      },
      player = { name = "RED" },
      inventory = {},
      options = { battleStyle = style },
      pokedex = { seen = {}, owned = {} },
      flags = {},
      money = 0,
    },
    stack = { push = function() end, pop = function() end, top = function() end },
  }
end

-- Drain the queue, running act rows and answering the SHIFT prompt.  `yes`
-- picks YES (the free switch) or NO; `pick` is the party mon the battle
-- PartyMenu would hand back.  Text rows are collected in order so the exp
-- line can be read the way the player reads it.
local function pump(b, yes, pick, seen)
  local origPush = Screens.push
  Screens.push = function(_, id, opts)
    if id == "PartyMenu" and opts and opts.onSwitch and pick then
      opts.onSwitch(pick)
    end
  end
  local ok, err = pcall(function()
    local n = 0
    while #b.queue > 0 and n < 500 do
      n = n + 1
      local item = table.remove(b.queue, 1)
      if item.fn then
        b.nextInsert = 0
        item.fn()
      elseif item.text then
        seen[#seen + 1] = item.text
        if item.choice and item.text:find("change POKéMON", 1, true) then
          item.choice(yes)
        end
      end
    end
  end)
  Screens.push = origPush
  return ok, err
end

-- the number _ExpPointsText prints (wExpAmountGained), out of the port's
-- "%s gained\n%d EXP. Points!" row
local function expLine(seen)
  for _, t in ipairs(seen) do
    local n = t:match("gained\n(%d+) EXP%. Points!")
    if n then return tonumber(n), t end
  end
  return nil
end

-- OPP_YOUNGSTER 1 is RATTATA 11 / EKANS 11 in both versions: two slots, so
-- there is a second mon to KO after the switch.
local YOUNGSTER, ROSTER = "OPP_YOUNGSTER", 1

-- Set up the fight at the moment the first enemy mon drops, with the lead the
-- only participant (as markParticipant left it), so the caller only has to pump.
local function atFirstKO(style)
  local Game = freshGame(style)
  local b = BattleState.newTrainer(Game, YOUNGSTER, ROSTER)
  b.enemyParty[1].hp = 0
  b.enemyIndex = 1
  b.enemy.mon = b.enemyParty[1]
  b.participants = { [Game.save.party[1]] = true }
  b:enemyMonFainted()
  return Game, b
end

-- KO whatever is out now and read back the exp line for it.
local function koAndRead(b)
  local before = {}
  for i, mon in ipairs(b.game.save.party) do before[i] = mon.exp end
  local seen = {}
  b.enemy.mon.hp = 0
  -- updateQueue zeroes this before every act row it runs; calling
  -- enemyMonFainted straight from the test has to do the same, or the *Next
  -- inserters index past the end of the drained queue and leave a hole
  b.nextInsert = 0
  b:enemyMonFainted()
  local ok, err = pump(b, false, nil, seen)
  local delta = {}
  for i, mon in ipairs(b.game.save.party) do delta[i] = mon.exp - before[i] end
  return ok, err, seen, delta
end

do
  local Game, b = atFirstKO("shift")
  eq(#b.enemyParty, 2, "OPP_YOUNGSTER roster " .. ROSTER .. " has two mons")
  local lead, reserve = Game.save.party[1], Game.save.party[2]

  -- KO one: the SHIFT prompt, answered YES with the reserve picked.
  local seen = {}
  local ok, err = pump(b, true, reserve, seen)
  check(ok, "the SHIFT switch pumped without error: " .. tostring(err))
  check(b.player.mon == reserve, "the free switch put the reserve on the field")
  check(b.enemy.mon.hp > 0, "the foe's second mon is out")

  -- The participant set is the mechanism; the exp number below is the symptom.
  check(b.participants[reserve] == true, "the switch-in is a participant")
  check(b.participants[lead] == nil,
        "the mon that was out when the foe fainted is no longer one (#275)")

  -- KO two: the reserve fights alone, so it must be paid as a single
  -- participant.
  local ok2, err2, seen2, delta = koAndRead(b)
  check(ok2, "the second KO pumped without error: " .. tostring(err2))

  local foeDef = Data.pokemon[b.enemyParty[2].species]
  local solo = Experience.gainFor(foeDef, b.enemyParty[2].level, true, 1, nil,
                                  Data.constants)
  local halved = Experience.gainFor(foeDef, b.enemyParty[2].level, true, 2, nil,
                                    Data.constants)
  check(solo > halved,
        "the two divisors are distinguishable for this foe (" ..
        solo .. " vs " .. halved .. ")")

  local shown, line = expLine(seen2)
  check(shown ~= nil, "the KO printed an EXP. Points! line")
  eq(shown, solo, "the switch-in is paid a whole share, not a split one (#275)")
  check(shown ~= halved,
        "the printed number is not the two-way split (" .. tostring(line) .. ")")
  eq(delta[2], solo, "the reserve's exp rose by exactly that share")
  eq(delta[1], 0, "the mon left behind is paid nothing for a KO it missed")

  local lines = 0
  for _, t in ipairs(seen2) do
    if t:find("EXP%. Points!") then lines = lines + 1 end
  end
  eq(lines, 1, "exactly one mon is announced as gaining exp")
end

-- Control: SET style has no free switch, so the lead fights both mons and is
-- paid a whole share for each.  Pin it here: the SHIFT switch-in above must
-- earn the same number.
do
  local Game, b = atFirstKO("set")
  local seen = {}
  local ok = pump(b, false, nil, seen)
  check(ok, "SET style pumped without error")
  check(b.player.mon == Game.save.party[1], "SET style never offered a switch")

  local ok2, _, seen2, delta = koAndRead(b)
  check(ok2, "the SET second KO pumped without error")
  local foeDef = Data.pokemon[b.enemyParty[2].species]
  local solo = Experience.gainFor(foeDef, b.enemyParty[2].level, true, 1, nil,
                                  Data.constants)
  local shown = expLine(seen2)
  eq(shown, solo, "SET style pays the lead a whole share")
  eq(delta[1], solo, "and the lead's exp rises by it")
end

-- The path the reset must NOT touch: the party-menu SwitchPlayerMon
-- (core.asm:2424-2433, from PartyMenuOrRockOrRun) sets the incoming mon's bit
-- without zeroing the flag bytes, which is the exp-share trick every player
-- uses: send a weak mon in, switch it straight out, it still splits the KO.
do
  local Game = freshGame("shift")
  local b = BattleState.newTrainer(Game, YOUNGSTER, ROSTER)
  local lead, reserve = Game.save.party[1], Game.save.party[2]
  b.participants = { [lead] = true }
  b:resolveSwitch(reserve)
  local n = 0
  while #b.queue > 0 and n < 200 do
    n = n + 1
    local item = table.remove(b.queue, 1)
    if item.fn then b.nextInsert = 0; item.fn() end
  end
  check(b.player.mon == reserve, "the voluntary switch went through")
  check(b.participants[reserve] == true, "the mon coming in participates")
  check(b.participants[lead] == true,
        "a VOLUNTARY switch keeps the outgoing mon flagged (the exp share)")
end

S.finish()
