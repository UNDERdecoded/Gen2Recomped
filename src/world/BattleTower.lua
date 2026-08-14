-- The Battle Tower (Crystal only).
--
-- Everything the tower needs off the cartridge is in field.gen2BattleTower --
-- see RomExtractorGen2:gen2BattleTower for what each table is and where it was
-- read from.  This module is the run itself: the rules, the roll that picks an
-- opponent, the streak and the reward.  Gold and Silver have no Battle Tower,
-- so the record is nil there and every entry point below answers "not here".
--
-- The tower's OWN scripts drive all of it.  BattleTower1F, BattleTowerHallway,
-- BattleTowerElevator and BattleTowerBattleRoom already carry the extracted
-- ROM bytecode, and the handlers in Gen2Commands are the SpecialsPointers rows
-- that bytecode calls -- BattleTowerAction, BattleTowerRoomMenu,
-- CheckForBattleTowerRules, LoadOpponentTrainerAndPokemonWithOTSprite,
-- BattleTowerBattle.  Nothing here decides the order of events; the cartridge
-- script does.
--
-- State lives on save.g2BattleTower, mirroring the SRAM block at $BE45:
--   challenge -- sBattleTowerChallengeState: 0 idle, 1 challenge in progress
--                (quick saved), 2 left without saving, 3 challenge won and the
--                prize is owed, 4 prize collected
--   group     -- sBattleTowerLevelGroup, 1..10; the level cap is group * 10
--   beaten    -- sNrOfBeatenBattleTowerTrainers, 0..7
--   used      -- the seven sBattleTowerTrainers slots, so a challenge never
--                draws the same trainer twice
--   reward    -- sBattleTowerReward, rolled when the challenge starts
--   explained -- bit 1 of sBattleTowerSaveFileFlags (the rules were read)
--   opponent  -- the generated trainer currently standing in the battle room
--   streak    -- consecutive completed challenges; the cartridge only keeps
--                this in the (mobile) trainer rankings, so it is bookkeeping

local BattleTower = {}

-- wNrOfBeatenBattleTowerTrainers.  The battle room's script reads it with a
-- raw `readmem` after every win, so the count has to live in the same
-- address-keyed WRAM mirror g2_readmem reads.
local BEATEN_ADDRESS = 53092

local EGG_SPECIES = "SPECIES_253"

function BattleTower.data(game)
  local field = game and game.data and game.data.field
  return field and field.gen2BattleTower or nil
end

function BattleTower.available(game)
  return BattleTower.data(game) ~= nil
end

function BattleTower.state(save)
  if type(save) ~= "table" then return nil end
  local s = save.g2BattleTower
  if not s then
    s = { challenge = 0, group = 1, beaten = 0, used = {}, streak = 0 }
    save.g2BattleTower = s
  end
  s.used = s.used or {}
  return s
end

-- Keep the script-visible mirror in step with the state.  Doing it in one
-- place means the battle handler and the reset action cannot disagree.
function BattleTower.syncBeaten(save)
  local s = BattleTower.state(save)
  if not s then return end
  save.g2Wram = save.g2Wram or {}
  save.g2Wram[BEATEN_ADDRESS] = s.beaten or 0
end

BattleTower.BEATEN_ADDRESS = BEATEN_ADDRESS

-- ---------------------------------------------------------------------------
-- party rules
-- ---------------------------------------------------------------------------

local function isEgg(mon)
  if require("src.pokemon.Party").isEgg(mon) then return true end
  return mon and mon.species == EGG_SPECIES
end

-- _CheckForBattleTowerRules (22:$7201) runs four checks in this order and
-- prints a line for EVERY one that fails, not just the first.  Returns the
-- list of failing rule numbers, so the caller can print them the same way.
--   1  the party is exactly three
--   2  no two of them are the same species
--   3  no two of them hold the same item (holding nothing does not count --
--      CheckPartyValueIsUnique skips a zero value, and skips eggs entirely)
--   4  none of them is an egg
function BattleTower.checkRules(game)
  local party = (game.save and game.save.party) or {}
  local failed = {}
  if #party ~= 3 then failed[#failed + 1] = 1 end
  local function duplicated(pick)
    local seen = {}
    for _, mon in ipairs(party) do
      if not isEgg(mon) then
        local value = pick(mon)
        if value and value ~= "" then
          if seen[value] then return true end
          seen[value] = true
        end
      end
    end
    return false
  end
  if duplicated(function(mon) return mon.species end) then
    failed[#failed + 1] = 2
  end
  if duplicated(function(mon) return mon.item end) then
    failed[#failed + 1] = 3
  end
  for _, mon in ipairs(party) do
    if isEgg(mon) then failed[#failed + 1] = 4 break end
  end
  return failed
end

-- BattleTowerRoomMenu_PlacePickLevelMenu: four rows until the Hall of Fame,
-- ten after it.
function BattleTower.levelChoices(game)
  local def = BattleTower.data(game)
  if not def then return 0 end
  local hof = game.save and game.save.hallOfFame
  if type(hof) == "table" and #hof > 0 then return #def.groups end
  return math.min(def.levelGroupsBeforeHallOfFame or 4, #def.groups)
end

function BattleTower.maxLevel(group) return (group or 1) * 10 end

-- BattleTower_LevelCheck (46:$5D93): every party mon must be at or under
-- wcd4f * 10.  Returns the first mon over the cap, or nil.
function BattleTower.levelCheck(game, group)
  local cap = BattleTower.maxLevel(group)
  for _, mon in ipairs((game.save and game.save.party) or {}) do
    if (mon.level or 0) > cap then return mon end
  end
  return nil
end

-- BattleTower_UbersCheck (46:$5DD1): the check returns early once the chosen
-- group is 7 or more, and otherwise rejects an uber below level 70 -- which,
-- with the level cap already at 60 or less, means "no ubers under L70".
function BattleTower.uberCheck(game, group)
  local def = BattleTower.data(game)
  if not def or (group or 1) >= 7 then return nil end
  local ubers = {}
  for _, species in ipairs(def.ubers or {}) do ubers[species] = true end
  for _, mon in ipairs((game.save and game.save.party) or {}) do
    if ubers[mon.species] and (mon.level or 0) < (def.uberMinLevel or 70) then
      return mon
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- the challenge
-- ---------------------------------------------------------------------------

local function rng()
  return (love and love.math and love.math.random) or math.random
end

-- ResetBattleTowerTrainersSRAM (5C:$46D6): the seven slots go to $FF and the
-- beaten count to zero.  The script calls this before every new challenge.
function BattleTower.resetTrainers(game)
  local s = BattleTower.state(game.save)
  if not s then return end
  s.used, s.beaten, s.opponent = {}, 0, nil
  BattleTower.syncBeaten(game.save)
end

-- BattleTower_RandomlyChooseReward (5C:$473E): `Random & 7`, with 6 and 7
-- folded back onto 0 and 1, plus $1A, rerolled when it lands on $1E.  That
-- makes HP UP and PROTEIN twice as likely as the other three, which is the
-- cartridge's own bias, not an approximation.
function BattleTower.rollReward(game)
  local def, s = BattleTower.data(game), BattleTower.state(game.save)
  if not (def and s and def.rewards and def.rewards[1]) then return nil end
  local random = rng()
  for _ = 1, 32 do
    local roll = random(0, 7)
    if roll >= 6 then roll = roll - 6 end
    local item = def.rewards[roll + 1]
    if item and item ~= def.rewardReject then
      s.reward = item
      return item
    end
  end
  s.reward = def.rewards[1]
  return s.reward
end

-- LoadOpponentTrainerAndPokemon (7E:$4000) + LoadRandomBattleTowerMon
-- (7E:$4081).  The trainer is `Random & $7F` rejected at 70 or more and
-- rejected again if it is one of the seven already fought this challenge; the
-- three mons are `Random & $1F` rejected at 21 or more, and a candidate is
-- rejected when its species OR its held item byte matches one already drawn.
function BattleTower.rollOpponent(game)
  local def, s = BattleTower.data(game), BattleTower.state(game.save)
  if not (def and s) then return nil end
  local group = def.groups[s.group] or def.groups[1]
  if not group then return nil end
  local random = rng()
  local used = {}
  for _, index in ipairs(s.used) do used[index] = true end

  local trainer, index
  for _ = 1, 256 do
    local roll = random(0, 127)
    if roll < #def.trainers and not used[roll] then
      index, trainer = roll, def.trainers[roll + 1]
      break
    end
  end
  if not trainer then
    -- every trainer already drawn (only reachable if the used list is wrong);
    -- take the first free one rather than spin
    for i = 0, #def.trainers - 1 do
      if not used[i] then index, trainer = i, def.trainers[i + 1] break end
    end
  end
  if not trainer then return nil end
  s.used[#s.used + 1] = index

  local party, species, items = {}, {}, {}
  for _ = 1, 3 do
    local picked
    for _ = 1, 512 do
      local roll = random(0, 31)
      local mon = roll < #group.mons and group.mons[roll + 1] or nil
      if mon and not species[mon.species] and not items[mon.itemByte or 0] then
        picked = mon
        break
      end
    end
    if not picked then break end
    species[picked.species] = true
    items[picked.itemByte or 0] = true
    party[#party + 1] = picked
  end
  if #party < 1 then return nil end

  -- BattleTowerText (47:$4000) rolls the personality ONCE, for the line before
  -- the battle, and reuses that index for the win and loss lines, so an
  -- opponent's three lines belong to the same person.
  local pool = def.texts and def.texts[trainer.female and "female" or "male"]
  local line = 1
  if pool and pool[1] then line = random(1, #pool[1]) end

  s.opponent = {
    index = index,
    name = trainer.name,
    class = trainer.class,
    classKey = trainer.classKey,
    sprite = trainer.sprite,
    female = trainer.female,
    line = line,
    party = party,
  }
  return s.opponent
end

-- `battletowertext <slot>`: 1 before the battle, 2 when the opponent wins,
-- 3 when the opponent loses.
function BattleTower.line(game, slot)
  local def, s = BattleTower.data(game), BattleTower.state(game.save)
  local opponent = s and s.opponent
  if not (def and opponent) then return nil end
  local pool = def.texts and def.texts[opponent.female and "female" or "male"]
  local lines = pool and pool[math.max(1, math.min(3, slot or 1))]
  return lines and lines[opponent.line] or nil
end

function BattleTower.recordWin(game)
  local def, s = BattleTower.data(game), BattleTower.state(game.save)
  if not (def and s) then return 0 end
  s.beaten = (s.beaten or 0) + 1
  if s.beaten >= (def.battles or 7) then
    s.streak = (s.streak or 0) + 1
    if (s.best or 0) < s.streak then s.best = s.streak end
  end
  BattleTower.syncBeaten(game.save)
  return s.beaten
end

function BattleTower.recordLoss(game)
  local s = BattleTower.state(game.save)
  if not s then return end
  s.streak = 0
  s.opponent = nil
end

return BattleTower
