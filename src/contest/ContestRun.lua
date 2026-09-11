-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A POKéMON CONTEST, scored the way the cartridge scores one.
--
-- Six rounds, and the FIRST ONE IS NOT AN APPEAL.  CalculateRound1Points
-- (0x080DB09D) fills every contestant's opening score with its CONDITION --
-- the pentagon number, neighbours and sheen included -- so a Pokémon walks in
-- already ahead or behind on what it has eaten.  The five appeal rounds that
-- follow are added on top, doubled:
--
--     total = appealTotal * 2 + conditionPoints
--
-- WHAT AN APPEAL IS WORTH, in order, because the order is what makes the
-- numbers come out right:
--
--   1. the move's contest effect's own appeal, in TENTHS of a heart;
--   2. a COMBO doubles it -- but only if the same Pokémon's previous move
--      published a starter id this move lists, and only if the judge was
--      still watching (which the previous move's own starter id set);
--   3. a REPEAT costs ten times how many times running you have used it, so
--      the second use is two hearts down and the third three;
--   4. the CROWD pays one heart for a move of the contest's own category --
--      and SIX when that move fills the meter, which is the single biggest
--      number in the system;
--   5. JAMMING comes off the OTHER contestants' scores, not off yours.
--
-- THE CROWD TABLE is five by five of -1, 0 and +1, and its diagonal is all
-- +1: a Cool move in a Cool contest always excites. The meter rises by that
-- number and never goes below zero, and a repeated move contributes nothing
-- to it at all.
--
-- TIES break on condition and then on a per-contest random number drawn
-- distinct for all four, so a tie always resolves.
local ContestRun = {}

local Contest = require("src.pokemon.Contest")

ContestRun.ROUNDS = 5
ContestRun.CONTESTANTS = 4

local function record(data)
  return (data and data.constants and data.constants.gen3Contests) or nil
end
ContestRun.record = record

local function scoring(data)
  local r = record(data)
  return (r and r.scoring) or {
    heart = 10, rounds = 5, repeatPenalty = 10,
    crowdBonus = 10, crowdFullBonus = 60, applauseMax = 4,
    round2Multiplier = 2,
  }
end

local function categoryIndex(data, category)
  local r = record(data)
  local list = (r and r.categories) or { "COOL", "BEAUTY", "CUTE", "SMART", "TOUGH" }
  for i, name in ipairs(list) do
    if name:lower() == tostring(category):lower() then return i end
  end
  return 1
end
ContestRun.categoryIndex = categoryIndex

-- ---------------------------------------------------------------------------
-- ENTERING
--
-- GetContestEntryEligibility, and its answers are NOT a simple yes/no -- the
-- lobby script branches on all five, and two of them let you in:
--
--   0  the ribbon count is BELOW the rank -- you have not cleared the one
--      under it, and the receptionist turns you away
--   1  it is exactly the rank -- a fresh entry, which is the normal case
--   2  it is above -- you have already won here, and you may enter again
--   3  an egg
--   4  fainted
-- ---------------------------------------------------------------------------
ContestRun.ENTRY = { BELOW = 0, AT = 1, ABOVE = 2, EGG = 3, FAINTED = 4 }

function ContestRun.eligibility(mon, category, rank)
  if type(mon) ~= "table" then return ContestRun.ENTRY.BELOW end
  if mon.isEgg or mon.egg then return ContestRun.ENTRY.EGG end
  if (mon.hp or 0) <= 0 then return ContestRun.ENTRY.FAINTED end
  local have = math.floor(tonumber((mon.ribbons or {})[category]) or 0)
  if have > rank then return ContestRun.ENTRY.ABOVE end
  if have < rank then return ContestRun.ENTRY.BELOW end
  return ContestRun.ENTRY.AT
end

function ContestRun.mayEnter(answer)
  return answer == ContestRun.ENTRY.AT or answer == ContestRun.ENTRY.ABOVE
end

-- ---------------------------------------------------------------------------
-- THE OPPONENTS
--
-- SetContestants draws three of the twenty-four opponents in the rank whose
-- pool bit matches the category -- and which twenty-four is not the whole
-- story: nine of each block are marked post-game, so the Master Rank before
-- the Hall of Fame is a different set of trainers from the one after it.
-- ---------------------------------------------------------------------------
function ContestRun.pool(data, category, rank, postGame)
  local r = record(data)
  local want = (r and r.categories and r.categories[categoryIndex(data, category)])
               or "COOL"
  local out = {}
  for _, row in ipairs((r and r.opponents) or {}) do
    -- BEFORE THE HALL OF FAME the nine gated entries in each block are not
    -- drawn at all; after it the pool GROWS to the full twenty-four rather
    -- than swapping, which is why the Master Rank feels harder afterwards.
    if row.rank == rank and (postGame or row.postGame ~= true) then
      for _, name in ipairs(row.categories or {}) do
        if name == want then out[#out + 1] = row break end
      end
    end
  end
  return out
end

function ContestRun.chooseOpponents(data, category, rank, postGame, rng)
  rng = rng or love.math.random
  local pool = ContestRun.pool(data, category, rank, postGame)
  local picked = {}
  for _ = 1, 3 do
    if #pool == 0 then break end
    local i = rng(1, #pool)
    picked[#picked + 1] = table.remove(pool, i)
  end
  return picked
end

-- ---------------------------------------------------------------------------
-- SETTING ONE UP
-- ---------------------------------------------------------------------------

-- An opponent's record read as a Pokémon this engine can score.
local function opponentMon(data, row)
  return {
    species = row.species,
    nickname = row.nickname,
    trainer = row.trainer,
    moves = row.moves,
    contest = {
      cool = row.contest.cool, beauty = row.contest.beauty,
      cute = row.contest.cute, smart = row.contest.smart,
      tough = row.contest.tough, sheen = row.contest.sheen,
    },
  }
end

function ContestRun.new(data, opts)
  opts = opts or {}
  local rng = opts.rng or love.math.random
  local category = opts.category or "cool"
  local rank = math.max(0, math.min(3, math.floor(tonumber(opts.rank) or 0)))
  local run = {
    data = data,
    category = category,
    rank = rank,
    rng = rng,
    round = 0,
    applause = 0,
    contestants = {},
    playerIndex = 1,
  }

  local opponents = ContestRun.chooseOpponents(data, category, rank,
                                               opts.postGame, rng)
  local entries = { { mon = opts.mon, player = true,
                      trainer = opts.trainerName } }
  for _, row in ipairs(opponents) do
    entries[#entries + 1] = { mon = opponentMon(data, row), row = row,
                              trainer = row.trainer }
  end

  for i, entry in ipairs(entries) do
    run.contestants[i] = {
      index = i,
      mon = entry.mon,
      player = entry.player or false,
      trainer = entry.trainer,
      -- ROUND ONE: the condition, which is the score before a single move
      condition = Contest.condition(entry.mon, category),
      appealTotal = 0,
      baseAppeal = 0,
      prevMove = nil,
      currMove = nil,
      repeatCount = 0,
      judgesAttention = false,
      jamReduction = 0,
      nervous = false,
      used = {},
    }
  end
  -- the turn order starts as the seating order and is rebuilt every round
  run.order = {}
  for i = 1, #run.contestants do run.order[i] = i end
  return run
end

-- ---------------------------------------------------------------------------
-- ONE APPEAL
-- ---------------------------------------------------------------------------

local function moveDef(data, id)
  return (data.moves or {})[id]
end

-- AreMovesContestCombo: the PREVIOUS move's starter id has to appear in THIS
-- move's follow list.  The follow list holds starter ids, not move numbers,
-- which is the thing that looks wrong until it is read twice.
function ContestRun.combo(data, prevId, currId)
  if not (prevId and currId) then return false end
  local prev = moveDef(data, prevId)
  local curr = moveDef(data, currId)
  local starter = prev and prev.comboStarter
  if not (starter and starter ~= 0 and curr and curr.comboFollows) then
    return false
  end
  for _, id in ipairs(curr.comboFollows) do
    if id == starter then return true end
  end
  return false
end

function ContestRun.excitement(data, category, moveCategory)
  local r = record(data)
  local table_ = r and r.excitement
  if not table_ then return 0 end
  local c = categoryIndex(data, category)
  local m = categoryIndex(data, moveCategory)
  local row = table_[c]
  return (row and row[m]) or 0
end

-- Scores one contestant's move, and returns the jam it deals to everybody
-- else so the caller can apply it after the appeal itself is settled.
function ContestRun.appeal(run, who, moveId)
  local data = run.data
  local S = scoring(data)
  local c = run.contestants[who]
  if not c then return 0 end
  local def = moveDef(data, moveId)

  c.prevMove = c.currMove
  c.currMove = moveId

  -- a repeat, and how many in a row
  if c.prevMove and c.prevMove == moveId then
    c.repeated = true
    c.repeatCount = (c.repeatCount + 1) % 8
  else
    c.repeated = false
    c.repeatCount = 0
  end

  local appeal = math.floor(tonumber(def and def.contestAppeal) or 0)
  local jam = math.floor(tonumber(def and def.contestJam) or 0)
  local base = appeal

  -- the combo, which doubles the base -- and then this move's own starter id
  -- decides whether the judge is still watching next turn
  if c.judgesAttention and ContestRun.combo(data, c.prevMove, moveId) then
    base = base + appeal
    c.comboed = true
  else
    c.comboed = false
  end
  c.judgesAttention = (def and def.comboStarter and def.comboStarter ~= 0)
                      and true or false

  -- the repeat penalty
  if c.repeated then
    base = base - (c.repeatCount + 1) * (S.repeatPenalty or 10)
  end

  -- nervous: the appeal is thrown away entirely
  if c.nervous then base = 0 end

  -- the crowd
  local moveCategory = def and def.contestCategory
  local e = moveCategory and ContestRun.excitement(data, run.category, moveCategory) or 0
  if c.repeated then e = 0 end
  local crowd = 0
  if e > 0 then
    crowd = (run.applause + e > (S.applauseMax or 4))
            and (S.crowdFullBonus or 60) or (S.crowdBonus or 10)
  end
  base = base + crowd
  run.applause = math.max(0, run.applause + e)

  c.baseAppeal = base
  c.nervous = false
  return jam
end

-- ApplyJam: it comes off the TARGET's appeal for this round, after their own
-- shield, and a target whose shield covers it is simply "not startled".
function ContestRun.applyJam(run, from, jam)
  if jam <= 0 then return end
  for i, c in ipairs(run.contestants) do
    if i ~= from then
      local left = jam - (c.jamReduction or 0)
      if left > 0 then
        c.baseAppeal = c.baseAppeal - left
        c.jammed = (c.jammed or 0) + left
      end
    end
  end
end

-- One whole round: every contestant appeals in turn order, then the totals
-- and the standings are updated.
function ContestRun.round(run, moves)
  run.round = run.round + 1
  for _, c in ipairs(run.contestants) do
    c.baseAppeal, c.jammed = 0, 0
  end
  for _, who in ipairs(run.order) do
    local id = moves[who]
    if id then
      local jam = ContestRun.appeal(run, who, id)
      ContestRun.applyJam(run, who, jam)
    end
  end
  for _, c in ipairs(run.contestants) do
    c.appealTotal = c.appealTotal + c.baseAppeal
  end
  ContestRun.rankLive(run)
  return run.round >= ContestRun.ROUNDS
end

-- The live standings the screen shows between rounds.
function ContestRun.rankLive(run)
  local order = {}
  for i, c in ipairs(run.contestants) do order[#order + 1] = { i, c.appealTotal } end
  table.sort(order, function(a, b) return a[2] > b[2] end)
  for place, row in ipairs(order) do
    run.contestants[row[1]].place = place
  end
end

-- ---------------------------------------------------------------------------
-- THE RESULT
-- ---------------------------------------------------------------------------
function ContestRun.finish(run)
  local S = scoring(run.data)
  local mult = S.round2Multiplier or 2
  local rows = {}
  local seen = {}
  for i, c in ipairs(run.contestants) do
    c.round2 = c.appealTotal * mult
    c.total = c.round2 + c.condition
    -- a DISTINCT random per contestant, so a tie can always be broken
    local tie
    repeat tie = run.rng(0, 65535) until not seen[tie]
    seen[tie] = true
    rows[#rows + 1] = { index = i, total = c.total,
                        condition = c.condition, tie = tie }
  end
  table.sort(rows, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    if a.condition ~= b.condition then return a.condition > b.condition end
    return a.tie > b.tie
  end)
  local standings = {}
  for place, row in ipairs(rows) do
    run.contestants[row.index].place = place
    standings[place] = row.index
  end
  run.standings = standings
  run.winner = standings[1]
  return standings
end

function ContestRun.playerWon(run)
  return run.winner == run.playerIndex
end

-- GiveMonContestRibbon, gated the way the cartridge gates it: first place
-- only, and the counter only ever advances by one.
function ContestRun.award(run)
  if not ContestRun.playerWon(run) then return false end
  local mon = run.contestants[run.playerIndex].mon
  return Contest.giveContestRibbon(mon, run.category, run.rank)
end

-- GiveMonArtistRibbon: Master Rank, first place, and more than 799 points --
-- which is a very high bar, and is exactly the bar the museum's artist uses
-- to decide whether to paint you.
ContestRun.ARTIST_POINTS = 799
ContestRun.ARTIST_RANK = 3

function ContestRun.artistReady(run)
  if not ContestRun.playerWon(run) then return false end
  if run.rank ~= ContestRun.ARTIST_RANK then return false end
  local c = run.contestants[run.playerIndex]
  return (c.total or 0) > ContestRun.ARTIST_POINTS
end

return ContestRun
