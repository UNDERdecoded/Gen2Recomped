-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S BUG-CATCHING CONTEST: the native side the field
-- scripts call into (pokeheartgold src/overlay_bug_contest.c,
-- scrcmd_pokemon_misc.c 1455-1551, encounter_check.c, field_control.c).
--
--   * BugContestAction 0 <weekday> starts a run: twenty Sport Balls, the party
--     cut to its first healthy Pokemon (the rest held), five rival entrants
--     with their scores, and the day's encounter table; any other action ends
--     it -- the party back, the lead's state kept, and the caught Pokemon
--     added to the party (or the PC when the party held six before)
--   * the clock is REAL minutes, counted while flag 0x996 is set; at twenty
--     the field runs std 10400 (time up)
--   * the park's land tiles roll the contest table while 0x996 is set, with a
--     one-perfect-IV reroll; the battle is a Gen 2-shaped contest battle (BALL
--     in the bag's place, 1.5x catch, the catch kept aside)
--   * judging: the score is rarity + level / max level + IVs / 186 + HP / max
--     HP (each x100, integer division); ties go to the later entrant, so the
--     player (index 5) wins them; the prizes are Sun Stone / Everstone /
--     Sitrus Berry / Shed Shell, the first a random stone with the national dex
--
-- The run is kept in save.g2BugContest with `hgss = true`, which is the table
-- the shared battle code (BattleState:bugContestBall / storeContestMon) reads
-- for its ball count and the caught Pokemon -- and src/world/BugContest's
-- Gen 2 field hooks skip it (BugContest.active answers false for it).

local M = {}

M.FLAG_RUNNING = 0x996
M.CONTEST_MAP = "D22R0102"
M.JUDGING_MAP, M.JUDGING_X, M.JUDGING_Y = "D22R0101", 46, 50
M.BALLS, M.MINUTES = 20, 20
M.LAND_RATE = 25

-- mushi_encount.csv: four sets of ten { species, lvMin, lvMax, score }; the
-- slot chances are 20 20 10 10 10 10 5 5 5 5 %
M.SLOTS = { 20, 20, 10, 10, 10, 10, 5, 5, 5, 5 }
M.ENCOUNTERS = {
  [0] = { { 10, 7, 18, 60 }, { 13, 7, 18, 60 }, { 11, 9, 18, 60 }, { 14, 9, 18, 60 }, { 12, 12, 15, 80 },
          { 15, 12, 15, 80 }, { 48, 10, 16, 80 }, { 46, 10, 17, 80 }, { 123, 13, 14, 100 }, { 127, 13, 14, 100 } },
  [1] = { { 10, 24, 36, 60 }, { 13, 24, 36, 60 }, { 11, 26, 36, 60 }, { 14, 26, 36, 60 }, { 12, 27, 30, 80 },
          { 15, 27, 30, 80 }, { 48, 25, 32, 80 }, { 46, 27, 34, 80 }, { 123, 27, 28, 100 }, { 127, 27, 28, 100 } },
  [2] = { { 265, 24, 36, 60 }, { 266, 24, 36, 60 }, { 290, 26, 36, 80 }, { 313, 26, 36, 80 }, { 401, 27, 30, 60 },
          { 402, 27, 30, 80 }, { 269, 25, 32, 80 }, { 415, 27, 34, 80 }, { 123, 27, 28, 100 }, { 127, 27, 28, 100 } },
  [3] = { { 265, 24, 36, 60 }, { 268, 24, 36, 60 }, { 290, 26, 36, 80 }, { 314, 26, 36, 80 }, { 401, 27, 30, 60 },
          { 402, 27, 30, 80 }, { 267, 25, 32, 80 }, { 415, 27, 34, 80 }, { 123, 27, 28, 100 }, { 127, 27, 28, 100 } },
}

-- mushi_trainer.csv: per entrant, the rows { day (7 any), species, score, randmod }
-- that count -- day 7 always, a weekday's only with the national dex
M.CONTESTANTS = {
  [0] = { { 7, 123, 320, 20 }, { 7, 127, 300, 30 }, { 2, 123, 320, 20 }, { 2, 127, 300, 30 },
          { 4, 123, 320, 20 }, { 4, 127, 300, 30 }, { 6, 127, 320, 20 }, { 6, 123, 300, 30 } },
  [1] = { { 7, 127, 300, 30 }, { 7, 123, 320, 20 }, { 2, 127, 300, 30 }, { 2, 123, 320, 20 },
          { 4, 127, 300, 30 }, { 4, 123, 320, 20 }, { 6, 123, 300, 30 }, { 6, 127, 320, 20 } },
  [2] = { { 7, 46, 280, 50 }, { 7, 48, 280, 50 }, { 2, 46, 280, 50 }, { 2, 46, 280, 50 },
          { 4, 415, 280, 50 }, { 4, 313, 280, 50 }, { 6, 402, 280, 50 }, { 6, 314, 280, 50 } },
  [3] = { { 7, 48, 280, 50 }, { 7, 46, 280, 50 }, { 2, 48, 280, 50 }, { 2, 48, 280, 50 },
          { 4, 313, 280, 50 }, { 4, 415, 280, 50 }, { 6, 314, 280, 50 }, { 6, 402, 280, 50 } },
  [4] = { { 7, 15, 260, 50 }, { 7, 12, 260, 50 }, { 2, 15, 260, 50 }, { 2, 12, 260, 50 },
          { 4, 402, 260, 50 }, { 4, 290, 260, 50 }, { 6, 415, 260, 50 }, { 6, 290, 260, 50 } },
  [5] = { { 7, 12, 260, 50 }, { 7, 15, 260, 50 }, { 2, 12, 260, 50 }, { 2, 15, 260, 50 },
          { 4, 290, 260, 50 }, { 4, 402, 260, 50 }, { 6, 290, 260, 50 }, { 6, 415, 260, 50 } },
  [6] = { { 7, 14, 240, 90 }, { 7, 11, 240, 90 }, { 2, 14, 240, 90 }, { 2, 11, 240, 90 },
          { 4, 401, 240, 90 }, { 4, 269, 240, 90 }, { 6, 401, 240, 90 }, { 6, 267, 240, 90 } },
  [7] = { { 7, 11, 240, 90 }, { 7, 14, 240, 90 }, { 2, 11, 240, 90 }, { 2, 14, 240, 90 },
          { 4, 269, 240, 90 }, { 4, 401, 240, 90 }, { 6, 267, 240, 90 }, { 6, 401, 240, 90 } },
  [8] = { { 7, 13, 220, 110 }, { 7, 10, 220, 110 }, { 2, 13, 220, 110 }, { 2, 10, 220, 110 },
          { 4, 266, 220, 110 }, { 4, 265, 220, 110 }, { 6, 268, 220, 110 }, { 6, 265, 220, 110 } },
  [9] = { { 7, 10, 220, 110 }, { 7, 13, 220, 110 }, { 2, 10, 220, 110 }, { 2, 13, 220, 110 },
          { 4, 265, 220, 110 }, { 4, 266, 220, 110 }, { 6, 265, 220, 110 }, { 6, 268, 220, 110 } },
}
-- sOpponentClasses (trainer classes, names in msg_0246 78..87)
M.CLASSES = { [0] = "Bug Catcher", "Bug Catcher", "Ace Trainer", "Pokéfan", "Bug Catcher", "Camper",
              "Picnicker", "Bug Catcher", "Youngster", "School Kid" }

M.PRIZES = { [0] = 80, 229, 158, 295 }                        -- 1st (no national dex) .. other
M.NATIONAL_STONES = { 80, 81, 82, 83, 84, 85, 107, 108, 109, 110 }

local function rand(n) return love.math.random(0, n - 1) end
local function Game() return package.loaded["src.core.Game"] end

local function flagSet(save, id)
  local f = save and save.flags
  return f ~= nil and (f[("FLAG_G4_%04X"):format(id)] == true)
end

function M.state(save)
  local s = type(save) == "table" and save.g2BugContest or nil
  return (s and s.hgss) and s or nil
end

-- the run exists and its clock is counting (0x996)
function M.running(save)
  return M.state(save) ~= nil and flagSet(save, M.FLAG_RUNNING)
end

local function nationalDex(save)
  local ok, Flags = pcall(require, "src.script.Flags")
  if ok and Flags.hasNationalDex then
    local okN, yes = pcall(Flags.hasNationalDex, save)
    if okN then return yes and true or false end
  end
  return save and save.pokedex and save.pokedex.national == true or false
end

-- BugContest_New(weekday)
function M.start(save, weekday)
  if type(save) ~= "table" then return nil end
  local national = nationalDex(save)
  local party = save.party or {}
  local Party = require("src.pokemon.Party")
  local lead = 1
  for i, mon in ipairs(party) do
    if (mon.hp or 0) > 0 and not Party.isEgg(mon) then lead = i; break end
  end
  local held = {}
  for i, mon in ipairs(party) do held[i] = mon end
  local s = {
    hgss = true, active = true, balls = M.BALLS, elapsed = 0, seconds = 0,
    national = national, day = tonumber(weekday) or 0, party = nil,
    partyBak = held, lead = lead, partyCount = #party, caught = nil,
  }
  save.party = { party[lead] }
  -- five distinct entrants and their scores
  local ids, used = {}, {}
  while #ids < 5 do
    local id = rand(10)
    if not used[id] then used[id] = true; ids[#ids + 1] = id end
  end
  s.contestants = {}
  for i, id in ipairs(ids) do
    local pool = {}
    for _, row in ipairs(M.CONTESTANTS[id]) do
      local keep = row[1] == 7 or (national and row[1] == s.day)
      if keep then pool[#pool + 1] = row end
    end
    local row = pool[rand(#pool) + 1]
    s.contestants[i] = { id = id, species = row[2], score = row[3] + rand(2 * row[4]) - row[4] }
  end
  s.set = national and math.floor(s.day / 2) or 0
  if not M.ENCOUNTERS[s.set] then s.set = 0 end
  save.g2BugContest = s
  return s
end

-- the contest table's roll (overlay_bug_contest.c 171-189)
function M.roll(save)
  local s = M.state(save)
  if not s then return nil end
  local roll, at = rand(100), 0
  local rows = M.ENCOUNTERS[s.set]
  for i, chance in ipairs(M.SLOTS) do
    at = at + chance
    if roll < at then
      local r = rows[i]
      return { species = r[1], level = r[2] + rand(r[3] - r[2] + 1), score = r[4], lvMax = r[3] }
    end
  end
  return nil
end

-- a wild Pokemon re-rolled up to four times for one perfect IV
function M.wildMon(data, species, level)
  local Pokemon = require("src.pokemon.Pokemon")
  local mon
  for _ = 1, 4 do      -- generateWildNonShinyAndAddToParty: `i < 4`
    mon = Pokemon.new(data, species, level)
    local iv = mon.ivs or mon.dvs or {}
    for _, v in pairs(iv) do if tonumber(v) == 31 then return mon end end
  end
  return mon
end

local function encounterFor(s, species)
  for _, r in ipairs(M.ENCOUNTERS[s.set] or {}) do
    if r[1] == species then return r end
  end
  return nil
end

-- the player's score (overlay_bug_contest.c 314-345)
function M.score(save)
  local s = M.state(save)
  local mon = s and s.caught
  if not mon then return 0 end
  local e = encounterFor(s, tonumber(mon.species))
  if not e then return 0 end
  local iv = mon.ivs or {}
  local ivSum = 0
  for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do ivSum = ivSum + (tonumber(iv[k]) or 0) end
  if ivSum == 0 then for _, v in pairs(iv) do ivSum = ivSum + (tonumber(v) or 0) end end
  local maxHp = math.max(1, tonumber(mon.maxHp or (mon.stats and mon.stats.hp)) or 1)
  return e[4] + math.floor((mon.level or 1) * 100 / e[3]) + math.floor(ivSum * 100 / 186)
       + math.floor((mon.hp or maxHp) * 100 / maxHp)
end

-- BugContest_Judge: the ranking (selection sort, ties to the later entrant)
-- and the prize
function M.judge(save)
  local s = M.state(save)
  if not s then return nil end
  local all = {}
  for i = 1, 5 do all[i] = s.contestants[i] end
  all[6] = { id = 5, player = true, species = s.caught and tonumber(s.caught.species) or 0, score = M.score(save) }
  -- overlay_bug_contest.c 79-92 as written: one swap per place, with the
  -- LAST entrant at or above the running best (swapping at every hit, as
  -- this did, shuffles the tied ones below it differently)
  local order = { 1, 2, 3, 4, 5, 6 }
  for i = 1, 5 do
    local best, at = all[order[i]].score, i
    for j = i + 1, 6 do
      if all[order[j]].score >= best then best, at = all[order[j]].score, j end
    end
    order[i], order[at] = order[at], order[i]
  end
  s.ranking, s.all = order, all
  s.placement = 3
  for p = 1, 3 do if order[p] == 6 then s.placement = p - 1 end end
  if s.placement == 0 then
    s.prize = s.national and M.NATIONAL_STONES[rand(10) + 1] or M.PRIZES[0]
  else
    s.prize = M.PRIZES[s.placement]
  end
  return s.placement, s.prize, s.caught and tonumber(s.caught.species) or 0
end

-- BugContest_Delete: the party back, the lead as it is now, the catch kept
function M.finish(save)
  local s = M.state(save)
  if not s then return end
  local now = save.party and save.party[1]
  local party = {}
  for i, mon in ipairs(s.partyBak or {}) do party[i] = mon end
  if now and party[s.lead] then party[s.lead] = now end
  save.party = party
  if s.caught then
    if (s.partyCount or #party) >= 6 then
      local ok, Boxes = pcall(require, "src.pokemon.Boxes")
      if ok then Boxes.deposit(save, s.caught) end
    else
      save.party[#save.party + 1] = s.caught
    end
    s.wentToPc = (s.partyCount or #party) >= 6
  end
  save.g2BugContest = nil
end

-- the clock: real seconds while 0x996 is set; whole minutes count
function M.tick(save, dt)
  local s = M.state(save)
  if not (s and flagSet(save, M.FLAG_RUNNING)) then return false end
  s.seconds = (s.seconds or 0) + (dt or 0)
  while s.seconds >= 60 do
    s.seconds = s.seconds - 60
    s.elapsed = (s.elapsed or 0) + 1
  end
  return s.elapsed >= M.MINUTES
end

function M.minutesLeft(save)
  local s = M.state(save)
  local left = 1
  if s and (s.elapsed or 0) < M.MINUTES then left = M.MINUTES - (s.elapsed or 0) end
  return left
end

-- a std (common) script by its id, compiled for the runner
function M.stdRows(data, id)
  local ms = data and data.map_scripts
  local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
  if not (ms and okB) then return nil end
  local kind, name, index = Bands.classify(id)
  if kind ~= "band" then return nil end
  local band = ms.bands and ms.bands[name]
  local label = band and band.entries and band.entries[index + 1]
  if not label then return nil end
  return require("src.script.Gen4ScriptVM").compile(data, label)
end

function M.runStd(ow, id)
  local G = Game()
  local rows = G and M.stdRows(G.data, id)
  if not (ow and rows) then return false end
  if ow.queueScript then ow:queueScript(rows, { mapId = ow.map and ow.map.id })
  else ow.runner:run(rows, { mapId = ow.map and ow.map.id }) end
  return true
end

local function busy(ow)
  return (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
      or (ow.pendingScripts and #ow.pendingScripts > 0) or ow.transitioning or ow.warping
end

-- every field frame: the clock and its expiry (std 10400), and what a battle
-- left behind (out of balls -> judging; the last ball caught -> std 10401;
-- a loss -> healed and to judging)
function M.update(ow, dt)
  local G = Game()
  local save = G and G.save
  if not M.state(save) then return end
  local due = M.tick(save, dt or (1 / 60))
  local G2 = G.stack and G.stack:top()
  if G2 ~= ow then return end
  local s = M.state(save)
  if s.afterBattle and not busy(ow) then
    local r = s.afterBattle
    s.afterBattle = nil
    if r == "lose" then
      for _, mon in ipairs(save.party or {}) do
        mon.hp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp
        mon.status = nil
      end
      ow:setMap(M.JUDGING_MAP, M.JUDGING_X, M.JUDGING_Y, "down")
      return
    end
    if (s.balls or 0) <= 0 then
      if r == "caught" then M.runStd(ow, 10401)
      else ow:setMap(M.JUDGING_MAP, M.JUDGING_X, M.JUDGING_Y, "down") end
      return
    end
  end
  if due and not s.timeUp and not busy(ow) and flagSet(save, M.FLAG_RUNNING) then
    s.timeUp = true
    M.runStd(ow, 10400)
  end
end

-- the park's land encounter while the clock runs (encounter_check.c):
-- returns a BattleState or nil
function M.encounter(ow)
  local G = Game()
  local save = G and G.save
  if not (M.running(save) and ow.map and ow.map.id == M.CONTEST_MAP) then return nil end
  local p = ow.player
  if not (ow.map.isGrassCell and ow.map:isGrassCell(p.cellX, p.cellY)) then return nil end
  -- the park's ordinary walking check (FieldSystem_PerformLandOrSurfEncounterCheck:
  -- inhibit steps, the movement roll, ability / flute / Cleanse Tag) against
  -- its grassRate, 25 of 100 (src/world/Gen45EncounterRate.lua)
  if not require("src.world.Gen45EncounterRate").walking(ow, G.data, save, { rate = M.LAND_RATE }) then return nil end
  local e = M.roll(save)
  if not e then return nil end
  -- GenerateBugContestEncounter_Internal: Repel turns away a Pokemon below
  -- the first healthy party member's level
  if (tonumber(save.repelSteps) or 0) > 0 then
    local Party = require("src.pokemon.Party")
    local lead = Party.firstHealthy(save.party or {})
    if lead and (tonumber(lead.level) or 0) > (tonumber(e.level) or 0) then return nil end
  end
  -- generateWildNonShinyAndAddToParty: Synchronize / Cute Charm
  local L = require("src.world.Gen4WildLead").choose(G.data, save,
    { { species = e.species, level = e.level } }, "grass", "radar", love.math.random)
  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(G, e.species, e.level,
    L and (L.nature or L.gender) and { nature = L.nature, gender = L.gender } or nil)
  local mon = M.wildMon(G.data, e.species, e.level)
  if mon and battle.enemy then battle.enemy.mon.ivs = mon.ivs or battle.enemy.mon.ivs end
  battle:makeBugContest()
  battle.contestBallName = "SPORT BALL"
  return battle
end

return M
