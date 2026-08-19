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
--
-- THE ORDER THE RUN IS TORN DOWN IN MATTERS, and getting it wrong is what made
-- the contest unwinnable.  On a cartridge the sequence is fixed by
-- BugContestResultsScript (engine/events/std_scripts.asm:317):
--
--     special BugContestJudging          <- needs `caught` and `scores`
--     ifequal 1/2/3 -> the real prize    <- needs the placing
--     special ContestReturnMons          <- hands the held party back
--     special CheckPartyFullAfterContest <- CONSUMES `caught` into the party
--     setscene NOOP                      <- stops the officer asking again
--
-- So nothing may drop `caught` before the LAST of those.  The port used to
-- clear the whole run inside ContestReturnMons, two lines early: judging then
-- scored an empty catch, the player placed last and got the consolation BERRY
-- every single time, and the mon they had caught was gone before anything
-- could add it to the party.

local BugContest = {}

local CONTEST_MAP = "NATIONAL_PARK_BUG_CONTEST"

local function data(game)
  local field = game and game.data and game.data.field
  return field and field.gen2BugContest or nil
end

local function state(save)
  return type(save) == "table" and save.g2BugContest or nil
end

-- ENGINE_BUG_CONTEST_TIMER is the flag the CARTRIDGE uses for "a run is in
-- progress", and it is not decoration: Route36NationalParkGate's
-- MAPCALLBACK_NEWMAP callback branches on it to pick the map's scene --
--
--     checkflag ENGINE_BUG_CONTEST_TIMER
--     iftrue .BugContestIsRunning        -> setscene LEAVE_CONTEST_EARLY
--     setscene SCENE_ROUTE36NATIONALPARKGATE_NOOP
--
-- and the LEAVE_CONTEST_EARLY scene is the officer asking "Do you want to
-- finish?", which on YES runs judging and `jumpstd BugContestResultsScript`
-- for the prize.
--
-- The extracted gate scripts SET it (Route36NationalParkGate:160/171,
-- Route35NationalParkGate:99) and BugContestResultsScript CLEARS it
-- (std_scripts.asm:318) -- but this module's own state was a second, separate
-- source of truth, and finish() only ever touched that one.  So the flag stayed
-- set after a run ended: arriving at the gate re-armed LEAVE_CONTEST_EARLY, the
-- officer asked again, and the player was handed another prize, over and over.
--
-- Keep the two in lockstep and that cannot happen.  Index 16 in this port's
-- Gold-numbered table; see Gen2Flags.ENGINE_FLAG_NAMES for why that number is
-- worth being careful about.
local ENGINE_BUG_CONTEST_TIMER = 16

-- Pre-naming, the extracted `setflag` wrote the generic FLAG_G2_0016 key, so a
-- save made before this clears both.  That is what un-sticks anyone currently
-- stuck in the officer loop.
local function setTimerFlag(save, on)
  if type(save) ~= "table" then return end
  local ok, Gen2Flags = pcall(require, "src.script.Gen2Flags")
  if not (ok and Gen2Flags and Gen2Flags.engineFlag) then return end
  save.flags = save.flags or {}
  local named = Gen2Flags.engineFlag(ENGINE_BUG_CONTEST_TIMER)
  save.flags[named] = on or nil
  save.flags[string.format("FLAG_G2_%04d", ENGINE_BUG_CONTEST_TIMER)] = on or nil
end

function BugContest.state(save) return state(save) end

-- Whether the run is live.  Every caller guards on this, so a save that has
-- never entered the park behaves exactly as it did before.
function BugContest.active(save)
  local s = state(save)
  return (s and s.active) == true
end

-- Whether the save is carrying a finished run whose prize has not been
-- collected -- the window BugContestResults_* runs in.  A contest cannot be
-- re-entered in this state; the gate has to pay out first.
function BugContest.awaitingResults(save)
  local s = state(save)
  return s ~= nil and s.active ~= true and s.placing ~= nil
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
  -- A fresh run REPLACES whatever was there, including a finished one whose
  -- prize was already handed over.  Starting from a clean table is what stops
  -- a previous run's clock, ball count or placing leaking into this one.
  --
  -- ...EXCEPT the party the officer is holding.  The gate script's order is
  -- `special ContestDropOffMons` FIRST and `special GiveParkBalls` several
  -- lines later (maps/Route36NationalParkGate.asm:192 then :172), so by the
  -- time this runs the rest of the player's team is already parked on the save
  -- -- and overwriting the table wholesale would delete four or five Pokemon.
  local held = state(save)
  held = held and held.party or nil
  setTimerFlag(save, true)
  save.g2BugContest = {
    active = true,
    balls = def.parkBalls or 20,
    endsAt = os.time() + (def.minutes or 20) * 60,
    caught = nil,
    party = held,
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

-- `clearflag ENGINE_BUG_CONTEST_TIMER`, the first line of
-- BugContestResultsScript (std_scripts.asm:317).  Called from the judging
-- special, one line later in the same script.
--
-- It ends the RUN, not the results: the clock, the Park Balls, the contest
-- encounter table and the START menu's contest panel all go quiet, while the
-- placing, the caught mon, the rolled scores and the held party stay exactly
-- where they are -- the prize branch, ContestReturnMons and
-- CheckPartyFullAfterContest have not read them yet.  BugContest.clear is what
-- finally drops the lot.
function BugContest.finish(game)
  local save = game.save
  local s = state(save)
  if not s then return nil end
  local placing = s.placing
  if placing == nil then placing = (BugContest.judge(game)) end
  -- Tear the LIVE surfaces down, not just the flag.  BugContestResultsScript
  -- does `clearflag ENGINE_BUG_CONTEST_TIMER` and GiveParkBalls' counter is
  -- gone with the run, so nothing should be able to read a ball count or a
  -- clock afterwards -- the START menu's contest panel and every timer check
  -- go quiet even if a caller forgets to ask `active` first.  Leaving these
  -- set is what showed 20 Park Balls and a counting-down timer in the menu
  -- after the contest was over, and what let a second entry believe there was
  -- still time on the clock.
  s.active = false
  s.balls = 0
  s.endsAt = nil
  -- BugContestResultsScript's own `clearflag ENGINE_BUG_CONTEST_TIMER`, done
  -- here as well so the gate cannot re-arm its LEAVE_CONTEST_EARLY scene even
  -- if the extracted results script never reaches that line.
  setTimerFlag(save, false)
  -- placing, board, caught and scores deliberately SURVIVE: the extracted
  -- BugContestResults_* scripts branch on the placing for the prize, and
  -- judging has already run by the time we get here.  BugContest.clear is
  -- what drops them, once the gate has paid out.
  return placing
end

-- BugContestResultsScript's tail: the run is fully done with, prize and all.
-- Separate from finish so a crash or a reload between the two cannot lose the
-- placing before the officer has handed anything over.
--
-- HAND THE PARTY BACK FIRST, unconditionally.  save.g2BugContest is the only
-- thing holding the four or five mons the officer took, so dropping the table
-- with `party` still on it DELETES THEM -- and the results script only reaches
-- ContestReturnMons when EVENT_LEFT_MONS_WITH_CONTEST_OFFICER is set, which is
-- exactly the kind of condition that can go wrong.  returnParty is idempotent,
-- so paying for it here costs nothing and cannot lose a save's party.
function BugContest.clear(save)
  if type(save) == "table" then
    BugContest.returnParty(save)
    save.g2BugContest = nil
  end
  setTimerFlag(save, false)
end

-- Leaving early -- the START menu's QUIT (StartMenu_Quit, "Would you like to
-- end the Contest?") and the out-of-balls / time-up exits all land here.
--
-- It does NOT judge and it does NOT tear anything down.  StartMenu_Quit
-- (engine/menus/start_menu.asm:411) is three instructions -- it queues
-- BugCatchingContestReturnToGateScript and returns -- and every one of the
-- three exits goes through that same script, which warps to the gate and only
-- THEN runs BugContestResultsScript.  Finishing the run here instead meant
-- judging ran against a run that had already been zeroed.
--
-- The run stays live (balls, clock, caught mon, ENGINE_BUG_CONTEST_TIMER) so
-- that the gate's own bytecode can end it in the cartridge's order.
function BugContest.leave(game)
  local ow = game and game.overworld
  if not (ow and ow.bugContestReturnToGate) then return false end
  return ow:bugContestReturnToGate()
end

-- ParkBallMultiplier (engine/items/item_effects.asm:746):
--
--     ld a, b / srl a / add b / ld b, a / ret nc / ld b, $ff
--
-- the species catch rate x 1.5, saturating at 255.  It is the only thing
-- that makes a Park Ball better than a Poke Ball.
function BugContest.parkBallRate(catchRate)
  local rate = math.floor(tonumber(catchRate) or 0)
  return math.min(255, rate + math.floor(rate / 2))
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

-- Take the caught mon OUT of the run: CheckPartyFullAfterContest ends with
-- `xor a / ld [wContestMonSpecies], a`, so the mon belongs to the party (or the
-- box) from then on and can never be scored or handed over twice.
function BugContest.takeCaught(save)
  local s = state(save)
  if not s then return nil end
  local mon = s.caught
  s.caught = nil
  return mon
end

-- ---------------------------------------------------------------------
-- the party the officer holds
-- ---------------------------------------------------------------------

-- ContestDropOffMons (engine/events/bug_contest/contest_2.asm:75).  Only the
-- lead competes.  The ROM does not MOVE anything: it writes 1 to wPartyCount
-- and a -1 terminator over the second species, so the rest of the party is
-- simply masked out of view until ContestReturnMons recomputes the count.
--
-- It ANSWERS, and the gate reads that answer on the very next line
-- (`special ContestDropOffMons / iftrue .FirstMonIsFainted`): 1 when the lead
-- has fainted, 0 otherwise.  A fainted lead is refused and NOTHING is dropped
-- off -- the routine returns before it masks anything.
--
-- Returns `fainted`.
function BugContest.holdParty(save)
  if type(save) ~= "table" then return false end
  local party = save.party or {}
  local lead = party[1]
  if not lead or (tonumber(lead.hp) or 0) <= 0 then return true end
  if #party <= 1 then
    -- nothing to hold: the ROM still masks, but with one mon there is nothing
    -- behind the terminator.  Leave `party` nil so returnParty is a no-op.
    return false
  end
  -- The gate calls this BEFORE GiveParkBalls, so there is usually no run on
  -- the save yet -- make somewhere to put them rather than dropping them.
  -- BugContest.start carries `party` across when it builds the real run.
  local s = state(save)
  if not s then
    s = {}
    save.g2BugContest = s
  end
  local held = {}
  for index = 2, #party do held[#held + 1] = party[index] end
  for index = #party, 2, -1 do party[index] = nil end
  s.party = held
  return false
end

-- ContestReturnMons (contest_2.asm:99): the species byte goes back and the
-- count is recomputed.  Idempotent -- a second call finds nothing held -- which
-- matters because the results script only reaches it when the player actually
-- left mons behind (EVENT_LEFT_MONS_WITH_CONTEST_OFFICER), while the teardown
-- below calls it unconditionally as a safety net.
function BugContest.returnParty(save)
  local s = state(save)
  if not (s and s.party) then return false end
  save.party = save.party or {}
  for _, mon in ipairs(s.party) do
    save.party[#save.party + 1] = mon
  end
  s.party = nil
  return true
end

return BugContest
