-- The Bug Catching Contest.
--
-- Every number here comes off the cartridge; field.gen2BugContest carries the
-- tables (see RomExtractorGen2:gen2BugContest) and this module is the run
-- itself.  The ROM routines each rule is taken from are named inline so the
-- behaviour can be re-checked against a disassembly rather than against this
-- file.
--
-- State lives on save.g2BugContest so it survives a save/quit mid-contest,
-- the way wParkBallsRemaining and wBugContestStartTime do on a cartridge:
--   active     -- the contest is running (ROM: wStatusFlags2 bit 2)
--   balls      -- wParkBallsRemaining, 20 at GiveParkBalls
--   endsAt     -- os.time() deadline, 20 minutes from StartBugContestTimer
--   caught     -- the one mon being scored, or nil
--   scores     -- this run's rolled AI scores, {id -> {score, species}}
--   party      -- the party held at the gate while only the lead competes

local BugContest = {}

local CONTEST_MAP = "NATIONAL_PARK_BUG_CONTEST"

local function data(game)
  local field = game and game.data and game.data.field
  return field and field.gen2BugContest or nil
end

local function state(save)
  return type(save) == "table" and save.g2BugContest or nil
end

function BugContest.state(save) return state(save) end

-- Whether the run is live.  Every caller guards on this, so a save that has
-- never entered the park behaves exactly as it did before.
function BugContest.active(save)
  local s = state(save)
  return (s and s.active) == true
end

function BugContest.contestMap() return CONTEST_MAP end

-- GiveParkBalls (04:$75DB) clears the caught mon, sets wParkBallsRemaining to
-- $14 and falls straight into StartBugContestTimer (04:$5490), which writes 20
-- minutes / 0 seconds.  Rolling the AI field here is
-- SelectRandomBugContestContestants' job on a cartridge; doing it at the same
-- moment keeps one save write instead of two and cannot desync, because
-- nothing reads the scores until judging.
function BugContest.start(game)
  local save, def = game.save, data(game)
  if not (save and def) then return false end
  save.g2BugContest = {
    active = true,
    balls = def.parkBalls or 20,
    endsAt = os.time() + (def.minutes or 20) * 60,
    caught = nil,
    scores = BugContest.rollContestants(game),
  }
  return true
end

-- ComputeAIContestantScores (04:$78B0): each of the nine entrants rolls
-- `Random & 3` over its three picks and re-rolls on 3, so the three are
-- equally likely.
function BugContest.rollContestants(game)
  local def = data(game)
  local scores = {}
  if not def then return scores end
  local rng = (love and love.math and love.math.random) or math.random
  for _, entry in ipairs(def.contestants or {}) do
    local picks = entry.picks or {}
    if #picks > 0 then
      local pick
      repeat pick = rng(0, 3) until pick < #picks
      local chosen = picks[pick + 1]
      scores[entry.id] = {
        score = chosen.score or 0,
        species = chosen.species,
        trainerClass = entry.trainerClass,
        trainerId = entry.trainerId,
      }
    end
  end
  return scores
end

-- ChooseWildEncounter_BugContest (25:$7D31).  `Random` is rejected at >= 200
-- and halved, giving 0-99 against rates that total exactly 100; the level is
-- min + Random % (max - min + 1), or just min when they are equal.
function BugContest.rollEncounter(game)
  local def = data(game)
  if not (def and def.mons and def.mons[1]) then return nil end
  local rng = (love and love.math and love.math.random) or math.random
  local roll
  repeat roll = rng(0, 255) until roll < 200
  roll = math.floor(roll / 2)
  for _, row in ipairs(def.mons) do
    roll = roll - (row.rate or 0)
    if roll < 0 then
      local low = row.minLevel or 5
      local high = row.maxLevel or low
      local level = low
      if high > low then level = low + rng(0, high - low) end
      return { species = row.species, level = level }
    end
  end
  return nil
end

-- Seconds left on the clock, floored at 0.  CheckBugContestTimer (04:$54A4)
-- compares against the wall clock rather than counting frames, which is why
-- this reads os.time() instead of accumulating dt.
function BugContest.secondsLeft(save)
  local s = state(save)
  if not (s and s.endsAt) then return 0 end
  return math.max(0, math.floor(s.endsAt - os.time()))
end

function BugContest.timedOut(save)
  return BugContest.active(save) and BugContest.secondsLeft(save) <= 0
end

-- ContestScore (04:$7900).  The accumulator is 16-bit and every term is added
-- through .AddContestStat, which carries into the high byte:
--   4x the LOW byte of max HP
--   the low byte of each of Attack, Defense, Speed, Sp.Atk, Sp.Def
--   a term built from bit 1 of each of the four DVs
--   the low byte of current HP, shifted right three
--   +1 when the mon is holding an item
-- The low bytes are what the ROM reads, so a stat of 260 contributes 4, not
-- 260 -- that is the cartridge's own behaviour, not an approximation.
function BugContest.score(mon)
  if type(mon) ~= "table" then return 0 end
  local function low(v) return (math.floor(tonumber(v) or 0)) % 256 end
  local stats = mon.stats or mon
  local total = 4 * low(mon.maxHp or mon.maxHP or stats.hp)
  total = total + low(stats.attack) + low(stats.defense) + low(stats.speed)
    + low(stats.special or stats.spAttack) + low(stats.spDefense or stats.special)

  -- DV term: c = (def & 2) << 2 ; d = ((atk & 2) << 1) + c ;
  -- then ((spd & 2) >> 1) + 2*(spc & 2) + 2*d
  local dvs = mon.dvs or {}
  local atk, def = low(dvs.attack), low(dvs.defense)
  local spd, spc = low(dvs.speed), low(dvs.special)
  local c = (def % 4 >= 2) and 8 or 0
  local d = ((atk % 4 >= 2) and 4 or 0) + c
  total = total + ((spd % 4 >= 2) and 1 or 0)
    + 2 * ((spc % 4 >= 2) and 2 or 0) + 2 * d

  total = total + math.floor(low(mon.hp) / 8)
  if mon.item and mon.item ~= "" then total = total + 1 end
  return total % 65536
end

-- BugContest_JudgeContestants (04:$7819) sorts the player in against the AI
-- field; the player is contestant 1.  Returns the placing (1, 2, 3 or nil) and
-- the full ordered board, so the caller can show it.
function BugContest.judge(game)
  local save = game.save
  local s = state(save)
  if not s then return nil, {} end
  local board = {}
  for id, entry in pairs(s.scores or {}) do
    board[#board + 1] = { id = id, score = entry.score or 0,
                          species = entry.species }
  end
  board[#board + 1] = {
    id = 1, player = true,
    score = s.caught and BugContest.score(s.caught) or 0,
    species = s.caught and s.caught.species or nil,
  }
  -- Ties go to the lower contestant id, which puts the player (id 1) ahead of
  -- the AI field on an exact tie, matching the ROM's first-past comparison.
  table.sort(board, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.id < b.id
  end)
  local placing
  for index, row in ipairs(board) do
    if row.player then placing = index break end
  end
  if placing and placing > 3 then placing = nil end
  s.placing = placing
  s.board = board
  return placing, board
end

-- ContestReturnMons (04:$7A31): the held party comes back and the run ends.
-- Judging has already stamped the placing, which is what the extracted
-- BugContestResults_* scripts branch on for the prize.
function BugContest.finish(game)
  local save = game.save
  local s = state(save)
  if not s then return nil end
  local placing = s.placing
  if placing == nil then placing = (BugContest.judge(game)) end
  s.active = false
  return placing
end

-- Leaving early -- the START menu's QUIT (StartMenu_Quit, "Would you like to
-- end the Contest?") and the out-of-balls / time-up exits all land here.
function BugContest.leave(game)
  local s = state(game.save)
  if not s then return nil end
  return BugContest.finish(game)
end

-- One Park Ball per throw; at zero the run is over
-- (BugCatchingContestOutOfBallsScript, 04:$7603).
function BugContest.useBall(save)
  local s = state(save)
  if not (s and s.balls) then return 0 end
  s.balls = math.max(0, s.balls - 1)
  return s.balls
end

function BugContest.ballsLeft(save)
  local s = state(save)
  return (s and s.balls) or 0
end

-- BugContest_SetCaughtContestMon (03:$66CE): a second catch REPLACES the
-- first, and the caller is the one that asks the player to confirm.
function BugContest.setCaught(save, mon)
  local s = state(save)
  if not s then return end
  s.caught = mon
end

function BugContest.caught(save)
  local s = state(save)
  return s and s.caught or nil
end

return BugContest
