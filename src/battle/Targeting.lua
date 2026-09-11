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

local function kindOf(move)
  local t = move and tonumber(move.target)
  return t or Targeting.SELECTED
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

  if k == Targeting.USER then return { user } end
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

return Targeting
