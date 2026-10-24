-- WHO A MOVE HITS.
--
-- In a single battle the answer never varies: there is one other Pokemon on
-- the field and every attack goes to it.  That is why this engine carried
-- one `target` from the menu all the way to the damage roll and never asked
-- the move what it was for.
--
-- With four on the field the move has to be asked.  gBattleMoves carries a
-- `target` byte per move -- offset 6 of the 12-byte record, which the
-- extractor already reads -- and it is a bitfield, not an enum:
--
--     0x00  SELECTED         one you pick.  246 moves, the ordinary case.
--     0x01  DEPENDS          the effect decides (COUNTER, MIRROR COAT,
--                            BIDE, METRONOME, MIRROR MOVE...).  9 moves.
--     0x02  USER_OR_SELECTED yourself or one you pick.  0 moves on this
--                            cartridge; the branch exists, nothing reaches it.
--     0x04  RANDOM           a foe rolled for you and then locked in for the
--                            rampage: THRASH, OUTRAGE, PETAL DANCE, UPROAR.
--     0x08  BOTH             both foes.  22 moves -- SURF, BLIZZARD, ROCK
--                            SLIDE, ICY WIND, MUDDY WATER and the rest.
--     0x10  USER             yourself.  67 moves, every stat-up and screen.
--     0x20  FOES_AND_ALLY    both foes AND your own partner.  5 moves:
--                            EARTHQUAKE, MAGNITUDE, EXPLOSION, SELFDESTRUCT
--                            and SURF's underwater sibling.  This is the one
--                            that makes a double battle a different game.
--     0x40  OPPONENTS_FIELD  their side of the field, not a Pokemon: SPIKES.
--
-- THE GEN 1 AND GEN 2 SAFETY IS THE DEFAULT.  Those datasets carry no
-- `target` at all, so every move here reads nil, and nil takes the same arm
-- as SELECTED -- which in a single battle is "the one foe", exactly the
-- answer the engine gave before this file existed.

local Targeting = {}

Targeting.SELECTED         = 0x00
Targeting.DEPENDS          = 0x01
Targeting.USER_OR_SELECTED = 0x02
Targeting.RANDOM           = 0x04
Targeting.BOTH             = 0x08
Targeting.USER             = 0x10
Targeting.FOES_AND_ALLY    = 0x20
Targeting.OPPONENTS_FIELD  = 0x40
-- ONE KIND GEN 3 NEVER PRODUCES: the partner, and only the partner. Hoenn
-- has no move that names it, Sinnoh has exactly one -- HELPING HAND -- so the
-- kind is added here rather than invented at the Gen 4 call site.
Targeting.ALLY             = 0x80

-- SINNOH SPELLS THIS FIELD DIFFERENTLY, AND THE TWO SPELLINGS OVERLAP.
--
-- A Gen 4 move record has no `target`. It has `range`, and the cache stores it
-- as `1 << (id - 1)` of pokeplatinum's `move_ranges.txt` order (id 0 stays 0):
-- verified over all 468 moves in the cache against pret's own per-move
-- `res/moves/<move>/data.json`, 468 of 468, no exceptions.
--
-- SO IT LOOKS LIKE A `target` BYTE AND IS NOT ONE. Both are small bitmasks and
-- they agree on 0 and on 0x10, which is exactly enough coincidence to make
-- `target = range` look right and be wrong:
--
--     mask  Sinnoh says              Hoenn's byte would say
--     0x02  RANDOM_OPPONENT          USER_OR_SELECTED
--     0x04  ADJACENT_OPPONENTS       RANDOM
--     0x08  ALL_ADJACENT             BOTH (foes only -- drops your partner)
--     0x20  USER_SIDE                FOES_AND_ALLY (hits three Pokemon)
--     0x40  FIELD                    OPPONENTS_FIELD
--
-- Assigning one to the other would aim THRASH at a choice, put EXPLOSION's
-- blast on the foes only, and turn REFLECT into a three-target attack. The
-- translation is therefore explicit, and `tools/gen4_targeting_check.lua`
-- asserts the two tables are NOT interchangeable so that nobody collapses
-- them back into one.
--
-- MAPPED WITH THE MOVE LISTS IN HAND rather than by the names lining up. The
-- two that are not a straight rename:
--   * USER_SIDE (REFLECT, LIGHT SCREEN, MIST, SAFEGUARD, TAILWIND, HEAL BELL,
--     AROMATHERAPY, LUCKY CHANT) and FIELD (RAIN DANCE, SANDSTORM, HAIL,
--     SUNNY DAY, GRAVITY, TRICK ROOM, HAZE, PERISH SONG, MUD SPORT, WATER
--     SPORT) name no Pokemon at all. They take USER because the effect record
--     does the real work and only needs somebody plausible to start from --
--     which is what Hoenn does with the same moves, whose own byte reads USER
--     for "every stat-up and screen".
--   * ME FIRST takes SELECTED: it picks one foe, then copies what that foe
--     was going to do.
local GEN4_RANGE = {
  [0]    = Targeting.SELECTED,         -- SINGLE_TARGET, 335 moves
  [1]    = Targeting.DEPENDS,          -- SINGLE_TARGET_SPECIAL, 11: COUNTER,
                                       -- MIRROR COAT, METRONOME, MIRROR MOVE,
                                       -- SLEEP TALK, ASSIST, COPYCAT, SNATCH,
                                       -- MAGIC COAT, METAL BURST, NATURE POWER
  [2]    = Targeting.RANDOM,           -- RANDOM_OPPONENT, 4: OUTRAGE, PETAL
                                       -- DANCE, THRASH, UPROAR -- the same
                                       -- four Hoenn rolls and then locks in
  [4]    = Targeting.BOTH,             -- ADJACENT_OPPONENTS, 24: BLIZZARD,
                                       -- ROCK SLIDE, ICY WIND, GROWL, LEER...
  [8]    = Targeting.FOES_AND_ALLY,    -- ALL_ADJACENT, 8: EARTHQUAKE,
                                       -- EXPLOSION, MAGNITUDE, SELFDESTRUCT,
                                       -- SURF, DISCHARGE, LAVA PLUME, TEETER
                                       -- DANCE -- Hoenn's own list, exactly
  [16]   = Targeting.USER,             -- USER, 62 moves
  [32]   = Targeting.USER,             -- USER_SIDE, 8 (see above)
  [64]   = Targeting.USER,             -- FIELD, 10 (see above)
  [128]  = Targeting.OPPONENTS_FIELD,  -- OPPONENT_SIDE, 3: SPIKES, TOXIC
                                       -- SPIKES, STEALTH ROCK
  [256]  = Targeting.ALLY,             -- ALLY, 1: HELPING HAND
  [512]  = Targeting.USER_OR_SELECTED, -- USER_OR_ALLY, 1: ACUPRESSURE -- the
                                       -- move that finally reaches the branch
                                       -- Hoenn leaves empty
  [1024] = Targeting.SELECTED,         -- SINGLE_TARGET_ME_FIRST, 1: ME FIRST
}
Targeting.GEN4_RANGE = GEN4_RANGE

-- `target` FIRST, because it is the native field wherever it exists: Hoenn
-- writes it for all 467 of its moves and no `range` at all, Sinnoh the other
-- way round. Gen 1 and Gen 2 carry neither and still land on SELECTED, which
-- in a single battle is "the one foe" -- the answer this engine gave before
-- any of this existed.
-- BLACK AND WHITE'S `target` IS AN ENUM, NOT HOENN'S BITFIELD (the move
-- record's +0x14, grouped over all 559 moves): 0 any adjacent, 1 user or ally
-- (Acupressure), 2 ally (Helping Hand), 3 adjacent foe (Me First), 4 every
-- adjacent Pokemon (Surf, Earthquake), 5 all adjacent foes (Growl, Rock
-- Slide), 6 the user's party, 7 the user, 8 everyone (Perish Song), 9 a
-- random foe (Thrash, Uproar), 10 the field, 11 the foes' side, 12 the user's
-- side, 13 the effect decides (Counter, Curse, Nature Power). Read as Hoenn's
-- bits, Surf hit ONE random foe and Growl one foe in a BW double.
local BW_TARGET = {
  [0] = 0x00, [1] = 0x02, [2] = 0x80, [3] = 0x00, [4] = 0x20, [5] = 0x08,
  [6] = 0x10, [7] = 0x10, [8] = 0x10, [9] = 0x04, [10] = 0x10, [11] = 0x40,
  [12] = 0x10, [13] = 0x01,
}
Targeting.BW_TARGET = BW_TARGET

local function kindOf(move)
  local t = move and tonumber(move.target)
  if t and move.bwEffect ~= nil and move.effectClass ~= nil then return BW_TARGET[t] or 0x00 end
  if t then return t end
  local r = move and tonumber(move.range)
  if r then return GEN4_RANGE[r] or Targeting.SELECTED end
  return Targeting.SELECTED
end
Targeting.kindOf = kindOf

-- EVERY POKEMON A CHOSEN-TARGET MOVE MAY BE AIMED AT, in the order the
-- selector should offer them.
--
-- The foes first, in position order, and then YOUR OWN PARTNER -- which is
-- not a mistake and not a nicety: a double battle on the cartridge lets you
-- aim at the Pokemon standing next to yours, and half of what makes HELPING
-- HAND, SKILL SWAP or a deliberate EARTHQUAKE-dodge work depends on it.  Foes
-- lead so that holding A takes the obvious one.
function Targeting.choices(battle, user)
  local out = {}
  for _, foe in ipairs(battle:foesOf(user)) do out[#out + 1] = foe end
  local ally = battle.partnerOf and battle:partnerOf(user)
  if ally and ally.mon and (ally.mon.hp or 0) > 0 then out[#out + 1] = ally end
  return out
end

-- Does the player have to be asked WHICH one?
--
-- Only when the move takes a single chosen target AND there is more than one
-- to choose from.  Everything else -- yourself, both of them, their field,
-- a move whose effect picks -- has exactly one answer already.
--
-- Counted over the whole candidate list rather than the foes alone: with one
-- foe left and a partner still standing there are still two answers, and the
-- cartridge still asks.
function Targeting.needsChoice(battle, user, move)
  if not (battle and battle.isDouble and battle:isDouble()) then return false end
  local k = kindOf(move)
  if k ~= Targeting.SELECTED and k ~= Targeting.USER_OR_SELECTED then
    return false
  end
  return #Targeting.choices(battle, user) > 1
end

-- WHO IT ACTUALLY HITS, in the order the cartridge resolves them: position
-- order, which for a player's move is OPPONENT_LEFT then OPPONENT_RIGHT.
--
-- `chosen` is the battler the player picked, when they were asked.  A single
-- battle passes the one foe it always passed and gets it straight back.
function Targeting.resolve(battle, user, move, chosen)
  local k = kindOf(move)

  -- BLACK AND WHITE: FOLLOW ME / RAGE POWDER draw every single-target move
  -- from the other side to themselves this turn (src/battle/Gen5MoveRules.lua)
  if battle.bw and (k == Targeting.SELECTED or k == Targeting.RANDOM) then
    local center = require("src.battle.Gen5MoveRules").centerOfAttention(battle, user, move)
    if center then return { center } end
  end

  if k == Targeting.USER then return { user } end

  -- THE PARTNER, AND NOTHING ELSE. HELPING HAND names the Pokemon standing
  -- next to yours, so with nobody there the move has no target and fails --
  -- which is what the cartridge does with it in a single battle, rather than
  -- quietly aiming it at a foe.
  if k == Targeting.ALLY then
    local ally = battle.partnerOf and battle:partnerOf(user)
    if ally and ally.mon and (ally.mon.hp or 0) > 0 then return { ally } end
    return {}
  end
  -- a field move has no Pokemon target; the caller reads the side instead
  if k == Targeting.OPPONENTS_FIELD then return {} end

  local foes = battle:foesOf(user)

  if k == Targeting.BOTH then return foes end

  if k == Targeting.FOES_AND_ALLY then
    local out = {}
    for _, f in ipairs(foes) do out[#out + 1] = f end
    -- YOUR OWN PARTNER IS IN THE BLAST.  This is not a special case bolted
    -- on: EXPLOSION and EARTHQUAKE name it in the move's own target byte.
    local ally = battle.partnerOf and battle:partnerOf(user)
    if ally and ally.mon and (ally.mon.hp or 0) > 0 then out[#out + 1] = ally end
    return out
  end

  if k == Targeting.RANDOM then
    -- rolled once and then held for as long as the rampage lasts, which is
    -- why it is remembered on the user rather than re-rolled each turn
    local held = user.thrashTarget
    if held and held.mon and (held.mon.hp or 0) > 0 then return { held } end
    if #foes == 0 then return {} end
    local pick = foes[1]
    if #foes > 1 and battle.rng then pick = foes[battle.rng(1, #foes)] end
    user.thrashTarget = pick
    return { pick }
  end

  -- SELECTED, USER_OR_SELECTED, and DEPENDS -- whose effect record does the
  -- real work and only needs somebody plausible to start from.
  if chosen and chosen.mon and (chosen.mon.hp or 0) > 0 then return { chosen } end

  -- NOBODY CHOSE, WHICH ON THE FOE'S SIDE IS EVERY SINGLE TURN.
  --
  -- The player is asked and the answer arrives in `chosen`; a trainer is not,
  -- so its move fell through to `redirect`, and redirect answers the FIRST
  -- battler in position order.  Position order on your side is left flank
  -- then right, so every foe in Hoenn aimed every single-target move it had
  -- at whichever Pokemon you led with, all battle, every battle.  That is the
  -- "they only ever attack my first one" report, and it is a tie-break
  -- standing in for a choice.
  --
  -- The cartridge makes it a choice: ChooseMoveOrAction_Doubles walks every
  -- battler the user could aim at, scores all four moves against each one,
  -- and keeps every (move, target) pair tied at the top -- then rolls among
  -- them.  A foe that genuinely has no preference therefore picks a SIDE of
  -- you at random, and the preference comes from the score.
  --
  -- The scorer is not ported yet (gBattleAI_ScriptsTable is read but not
  -- run), so what is faithful today is the tie-break with every score equal:
  -- a coin flip between whoever is standing.  That is a floor rather than the
  -- finished behaviour, and it is the half that stops the right-hand slot
  -- being untouchable.
  if not user.isPlayer and #foes > 1 and battle.rng then
    return { foes[battle.rng(1, #foes)] }
  end
  return Targeting.redirect(battle, user, move, chosen)
end

-- THE ONE YOU AIMED AT IS GONE.
--
-- Between choosing a move and the move going off, the target can faint --
-- your partner moved first, or its own ally hit it.  The cartridge does not
-- waste the turn: it re-points at whoever is still standing on that side.
-- With one foe there is nothing to re-point to and this answers the same
-- empty list the old `target.mon.hp <= 0` guard produced.
function Targeting.redirect(battle, user, move, target)
  if target and target.mon and (target.mon.hp or 0) > 0 then return { target } end
  local wanted = target and target.isPlayer
  local pool
  if wanted ~= nil and wanted == user.isPlayer then
    -- it was aimed at our own side (an ally-targeting move); look there
    local ally = battle.partnerOf and battle:partnerOf(user)
    pool = (ally and ally.mon and (ally.mon.hp or 0) > 0) and { ally } or {}
  else
    pool = battle:foesOf(user)
  end
  if #pool == 0 then return {} end
  return { pool[1] }
end

-- Public GBA actions retain positional targets until execution, so a switch
-- between selection and execution resolves the current occupant of that slot.
function Targeting.fromAction(battle, action)
  if type(action) ~= "table" or action.target == nil then
    return nil, false
  end
  local ref, id = action.target
  if type(ref) == "number" then
    id = ref
  elseif type(ref) == "table" then
    id = ref == battle.player and 0 or ref == battle.enemy and 1 or ref.position
  end
  if type(id) ~= "number" or id % 1 ~= 0 or id < 0 or id > 3 then
    return nil, true
  end
  if id == 0 then
    return battle.player, true
  end
  if id == 1 then
    return battle.enemy, true
  end
  return battle:battlerAt(id), true
end

function Targeting.actionTargets(battle, user, move, chosen)
  local kind = kindOf(move)
  local abilities = require("src.battle.Abilities")
  -- Gen 3 Lightning Rod redirects Electric selected attacks; it does not
  -- grant the later-generation immunity or Special Attack boost.
  if
    (kind == Targeting.SELECTED or kind == Targeting.DEPENDS or kind == Targeting.USER_OR_SELECTED)
    and move.type == "ELECTRIC"
    and abilities.of(chosen) ~= "LIGHTNING_ROD"
  then
    local rank = {}
    for i, id in ipairs(battle._actionTargetOrder or { 0, 1, 2, 3 }) do
      rank[id] = i
    end
    local best, bestRank
    for _, actor in battle:activeBattlers() do
      if
        actor.isPlayer ~= user.isPlayer
        and actor.mon
        and (actor.mon.hp or 0) > 0
        and abilities.of(actor) == "LIGHTNING_ROD"
      then
        local n = rank[actor.position] or 5
        if not bestRank or n < bestRank then
          best, bestRank = actor, n
        end
      end
    end
    if best then
      chosen = best
    end
  end
  local targets = Targeting.resolve(battle, user, move, chosen)
  if kind == Targeting.BOTH then
    for i, actor in ipairs(targets) do
      if actor == chosen and i > 1 then
        table.remove(targets, i)
        table.insert(targets, 1, actor)
        break
      end
    end
  elseif kind == Targeting.FOES_AND_ALLY then
    table.sort(targets, function(a, b)
      return a.position < b.position
    end)
  end
  return targets
end

function Targeting.gen3PPCost(battle, user, target, move)
  local extra = require("src.battle.Abilities").extraPP
  local kind, cost = kindOf(move), 1
  if
    battle:isDouble()
    and (kind == Targeting.BOTH or kind == Targeting.FOES_AND_ALLY or kind == Targeting.OPPONENTS_FIELD)
  then
    for _, actor in battle:activeBattlers() do
      if
        actor ~= user
        and actor.mon
        and (actor.mon.hp or 0) > 0
        and (kind == Targeting.FOES_AND_ALLY or actor.isPlayer ~= user.isPlayer)
      then
        cost = cost + extra(actor)
      end
    end
  elseif target and target ~= user and kind ~= Targeting.USER then
    cost = cost + extra(target)
  end
  return cost
end

return Targeting
