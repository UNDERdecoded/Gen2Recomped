-- THE MOVE EFFECTS HOENN ADDED, and the ones Johto had that the engine never
-- got round to.
--
-- WHY THIS FILE EXISTS.  RomExtractorGen3 names a move's effect by joining
-- Emerald's effect NUMBERS against a Gen 2 dataset through the moves the two
-- generations share.  That join can only name an effect some Gen 2 move also
-- carries, so the fifty-seven effects Ruby and Sapphire introduced came out
-- as bare numbers and sixty moves -- DRAGON DANCE, CALM MIND, BULK UP,
-- WILL-O-WISP, TAUNT, YAWN, OVERHEAT, ENDEAVOR, BRICK BREAK and the rest --
-- printed "But, it failed!" every single time anybody used them.  The names
-- now exist (see GEN3_MOVE_EFFECTS); this file is what makes them run.
--
-- It also fills in a second, older hole: thirty-two effect names the
-- extractor has always produced and the registry has never had a record for,
-- which is why PROTECT, ENDURE, ENCORE, SPIKES, SAFEGUARD, PERISH SONG,
-- BATON PASS, DESTINY BOND, PAIN SPLIT, THIEF, RAPID SPIN, PURSUIT, ROLLOUT,
-- FURY CUTTER, SWAGGER, ATTRACT, TRI ATTACK, FORESIGHT and LOCK-ON did
-- nothing in Johto either.
--
-- HOW IT PLUGS IN.  MoveEffects merges these three tables into its own
-- before it assembles RECORDS, so everything downstream -- the merged
-- Data.move_effects registry, performMove's dispatch, a mod overriding one
-- of them -- sees them as ordinary records with no special case anywhere.
-- The merge is non-destructive: a name MoveEffects already defines wins, so
-- this file can never quietly redefine an effect that already worked.
--
-- WHAT IS NOT HERE, and deliberately -- eight effects, and each for a
-- reason rather than for want of time:
--
--   FOLLOW ME and HELPING HAND do nothing outside a DOUBLE battle, and this
--   engine fights one Pokemon a side.
--
--   MAGIC COAT, SNATCH and IMPRISON all reach INTO another battler's move
--   as it is being resolved -- bouncing it back, stealing it, forbidding it
--   -- which needs a resolution step performMove does not have.
--
--   ASSIST and NATURE POWER call a move chosen from outside the user's own
--   move list (the rest of the party; the terrain), and SECRET POWER's side
--   effect is chosen the same way.  The terrain half of that is real work
--   in the world layer, not the battle one.
--
-- Those eight still warn once and fall through to plain damage, which is
-- the honest behaviour for an effect that is not implemented.  Everything
-- else Emerald has runs.

local Status = require("src.battle.Status")
local StatusRegistry = require("src.battle.StatusRegistry")
local Strings = require("src.core.Strings")
local Weather = require("src.battle.Weather")

local Gen3MoveEffects = {
  primary = {},
  secondary = {},
  full = {},
  -- names that must run MoveHitTest before they land, the way the older
  -- status moves do
  accuracyChecked = {},
}

local P = Gen3MoveEffects.primary
local S = Gen3MoveEffects.secondary
local F = Gen3MoveEffects.full
local ACC = Gen3MoveEffects.accuracyChecked

-- MoveEffects is required lazily inside the callbacks: it requires THIS file
-- while it is still loading, so a top-level require here would be a cycle.
local function changeStage(battle, who, stat, delta, fromEnemy)
  return require("src.battle.MoveEffects").changeStage(battle, who, stat,
                                                       delta, fromEnemy)
end

local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end

local function maxHpOf(battler)
  local mon = battler and battler.mon
  if not mon then return 1 end
  return (mon.stats and mon.stats.hp) or mon.maxHp or 1
end

local function append(into, list)
  for _, line in ipairs(list or {}) do into[#into + 1] = line end
  return into
end

-- Raise or lower several of the user's or target's stats in one move, which
-- is the shape most of Hoenn's new status moves take.
local function stagesOn(who, rows)
  return function(battle, user, target)
    local subject = (who == "user") and user or target
    local out = {}
    local moved = false
    for _, row in ipairs(rows) do
      local before = subject.stages[row[1]] or 0
      append(out, changeStage(battle, subject, row[1], row[2], who ~= "user"))
      if (subject.stages[row[1]] or 0) ~= before then moved = true end
    end
    -- one "Nothing happened!" for the whole move rather than one per stat
    if not moved then return { Strings("Nothing happened!") } end
    local kept = {}
    for _, line in ipairs(out) do
      if tostring(line):find("Nothing happened", 1, true) == nil then
        kept[#kept + 1] = line
      end
    end
    return kept
  end
end

local function confuse(battle, target, pierceSub)
  if target.confusedTurns or (target.substituteHP and not pierceSub) then
    return { Strings("But, it failed!") }
  end
  if require("src.battle.Abilities").refusesStatus(target, "CONFUSION") then
    return { Strings("But, it failed!") }
  end
  target.confusedTurns = battle.rng(2, 5)
  return { Strings("%s\nbecame confused!", displayName(target)) }
end

-- ---------------------------------------------------------------------
-- STAT-STAGE MOVES: the whole reason a Hoenn team is built the way it is
-- ---------------------------------------------------------------------

P.BULK_UP_EFFECT = stagesOn("user", { { "attack", 1 }, { "defense", 1 } })
P.CALM_MIND_EFFECT = stagesOn("user", { { "spatk", 1 }, { "spdef", 1 } })
P.DRAGON_DANCE_EFFECT = stagesOn("user", { { "attack", 1 }, { "speed", 1 } })
P.COSMIC_POWER_EFFECT = stagesOn("user", { { "defense", 1 }, { "spdef", 1 } })
P.TICKLE_EFFECT = stagesOn("target", { { "attack", -1 }, { "defense", -1 } })
ACC.TICKLE_EFFECT = true

-- CHARGE raises Sp.Def AND doubles the user's next Electric move.  The flag
-- is spent by Damage.compute and cleared the moment it is used.
P.CHARGE_UP_EFFECT = function(battle, user)
  user.charged = true
  local out = changeStage(battle, user, "spdef", 1, false)
  table.insert(out, 1, Strings("%s began\ncharging power!", displayName(user)))
  return out
end

-- ---------------------------------------------------------------------
-- CONFUSION, AND THE TWO MOVES THAT PAY FOR IT
-- ---------------------------------------------------------------------

-- SWAGGER hands the target two attack stages and confuses it; FLATTER does
-- the same with one Sp.Atk stage.  Both raise the stat EVEN IF the confusion
-- fails, which is what makes them a gamble rather than a trade.
local function praiseAndConfuse(stat, delta)
  return function(battle, user, target)
    local out = changeStage(battle, target, stat, delta, false)
    return append(out, confuse(battle, target, false))
  end
end
P.SWAGGER_EFFECT = praiseAndConfuse("attack", 2)
ACC.SWAGGER_EFFECT = true
P.FLATTER_EFFECT = praiseAndConfuse("spatk", 1)
ACC.FLATTER_EFFECT = true

-- TEETER DANCE confuses and asks for nothing in return
P.TEETER_DANCE_EFFECT = function(battle, user, target)
  return confuse(battle, target, false)
end
ACC.TEETER_DANCE_EFFECT = true

-- ---------------------------------------------------------------------
-- STATUS MOVES
-- ---------------------------------------------------------------------

P.WILL_O_WISP_EFFECT = function(battle, user, target, move)
  if target.mon.status then return { Strings("But, it failed!") } end
  local msgs = StatusRegistry.inflict(battle, target, "BRN",
                                      { user = user,
                                        moveType = move and move.type,
                                        source = move and move.id })
  if #msgs == 0 then return { Strings("But, it failed!") } end
  return msgs
end
ACC.WILL_O_WISP_EFFECT = true

-- REFRESH: the user shakes off its own burn, poison or paralysis.  Sleep and
-- freeze are NOT covered -- a sleeping Pokemon cannot choose to use it.
local REFRESHABLE = { BRN = true, PSN = true, PAR = true }
P.REFRESH_EFFECT = function(battle, user)
  if not REFRESHABLE[user.mon.status] then
    return { Strings("But, it failed!") }
  end
  user.mon.status = nil
  user.toxicCounter = nil
  return { Strings("%s's\nstatus returned to\nnormal!", displayName(user)) }
end

-- YAWN does not put the target to sleep now; it makes it DROWSY, and the
-- sleep lands at the end of the following turn.  BattleState:endOfTurn ticks
-- the counter, which is why this only has to set it.
P.YAWN_EFFECT = function(battle, user, target)
  if target.mon.status or target.drowsyTurns then
    return { Strings("But, it failed!") }
  end
  if require("src.battle.Abilities").refusesStatus(target, "SLP") then
    return { Strings("But, it failed!") }
  end
  target.drowsyTurns = 2
  return { Strings("%s\nbecame drowsy!", displayName(target)) }
end
ACC.YAWN_EFFECT = true

-- TAUNT: the target cannot choose a status move for the next few turns.
P.TAUNT_EFFECT = function(battle, user, target)
  if target.tauntTurns then return { Strings("But, it failed!") } end
  target.tauntTurns = 3
  return { Strings("%s fell for\nthe taunt!", displayName(target)) }
end
ACC.TAUNT_EFFECT = true

-- TORMENT: the target cannot use the same move twice in a row.
P.TORMENT_EFFECT = function(battle, user, target)
  if target.tormented then return { Strings("But, it failed!") } end
  target.tormented = true
  return { Strings("%s was\nsubjected to\nTORMENT!", displayName(target)) }
end
ACC.TORMENT_EFFECT = true

-- ATTRACT: infatuation, and it needs the two to be of OPPOSITE genders --
-- which is the whole rule, and the reason a genderless Pokemon is immune.
P.ATTRACT_EFFECT = function(battle, user, target)
  -- ...AND THE GENDER HAS TO BE FOUND, not merely read.  `mon.gender` is
  -- only there once something has stamped one; a wild Pokemon carries none,
  -- and asking the field alone made every ATTRACT in the game fail against
  -- one.  Pokemon.genderOf computes it from the species ratio and the
  -- personality the way GetGenderFromSpeciesAndPersonality does.
  local data = battle and battle.data
  if not require("src.pokemon.Pokemon").oppositeGenders(data, user.mon,
                                                        target.mon) then
    return { Strings("But, it failed!") }
  end
  if target.infatuated then return { Strings("But, it failed!") } end
  -- OBLIVIOUS simply does not notice
  if require("src.battle.Abilities").refusesStatus(target, "INFATUATION") then
    return { Strings("But, it failed!") }
  end
  target.infatuated = user
  return { Strings("%s\nfell in love!", displayName(target)) }
end
ACC.ATTRACT_EFFECT = true

-- SAFEGUARD: the user's side refuses every status for five turns.
P.SAFEGUARD_EFFECT = function(battle, user)
  if user.safeguardTurns then return { Strings("But, it failed!") } end
  user.safeguardTurns = 5
  return { Strings("%s's party is\ncovered by a veil!", displayName(user)) }
end

-- HEAL BELL / AROMATHERAPY: the whole party's statuses go.
P.HEAL_BELL_EFFECT = function(battle, user)
  user.mon.status = nil
  user.toxicCounter = nil
  local party = user.isPlayer and battle.game and battle.game.save
                and battle.game.save.party
  for _, mon in ipairs(party or {}) do mon.status = nil end
  return { Strings("A bell chimed!") }
end

-- PERISH SONG: both sides faint in three turns unless they leave.
P.PERISH_SONG_EFFECT = function(battle, user, target)
  local set = false
  for _, b in ipairs({ user, target }) do
    if b and b.mon and b.mon.hp > 0 and not b.perishTurns then
      b.perishTurns = 3
      set = true
    end
  end
  if not set then return { Strings("But, it failed!") } end
  return { Strings("All POKéMON that\nhear the song will\nfaint in three turns!") }
end

-- ---------------------------------------------------------------------
-- PROTECTION, AND THE COUNTER THAT KEEPS IT HONEST
-- ---------------------------------------------------------------------
--
-- PROTECT, DETECT and ENDURE share one rule: each consecutive use halves
-- the odds, and any other move resets the run.  `protectRun` is that
-- counter and is cleared by BattleState whenever the user does anything
-- else, so a spammed PROTECT fails the way the cartridge makes it fail.
local function protection(field, text)
  return function(battle, user)
    local run = user.protectRun or 0
    -- 1/1, then 1/2, 1/4, 1/8...  A run of four is already a coin flip
    -- three times over, which is what stops it being a stall lock.
    local odds = 1
    for _ = 1, run do odds = odds * 2 end
    if run > 0 and battle.rng(1, odds) ~= 1 then
      user.protectRun = 0
      return { Strings("But, it failed!") }
    end
    user.protectRun = run + 1
    user[field] = true
    return { Strings(text, displayName(user)) }
  end
end
P.PROTECT_EFFECT = protection("protecting",
                              Strings.source("%s\nprotected itself!"))
P.ENDURE_EFFECT = protection("enduring",
                             Strings.source("%s braced\nitself!"))

-- ---------------------------------------------------------------------
-- MOVE-CHOICE INTERFERENCE
-- ---------------------------------------------------------------------

-- ENCORE: the target must repeat its last move for a few turns.
P.ENCORE_EFFECT = function(battle, user, target)
  if target.encoreTurns or not target.lastMove then
    return { Strings("But, it failed!") }
  end
  target.encoreTurns = 3
  target.encoreMove = target.lastMove
  return { Strings("%s got\nan ENCORE!", displayName(target)) }
end
ACC.ENCORE_EFFECT = true

-- LOCK-ON / MIND READER: the user's next move cannot miss.
P.LOCK_ON_EFFECT = function(battle, user, target)
  user.lockedOn = target
  return { Strings("%s took aim\nat %s!", displayName(user),
                   displayName(target)) }
end

-- FORESIGHT / ODOR SLEUTH: a Ghost stops being immune to Normal and
-- Fighting, and its evasion stops counting.
P.FORESIGHT_EFFECT = function(battle, user, target)
  if target.identified then return { Strings("But, it failed!") } end
  target.identified = true
  return { Strings("%s was\nidentified!", displayName(target)) }
end

-- DESTINY BOND: if the user faints this turn, so does whoever did it.
P.DESTINY_BOND_EFFECT = function(battle, user)
  user.destinyBond = true
  return { Strings("%s is trying\nto take its foe\nwith it!",
                   displayName(user)) }
end

-- PAIN SPLIT: both sides end on the average of their HP.
P.PAIN_SPLIT_EFFECT = function(battle, user, target)
  if target.substituteHP then return { Strings("But, it failed!") } end
  local total = user.mon.hp + target.mon.hp
  local each = math.floor(total / 2)
  user.mon.hp = math.min(maxHpOf(user), each)
  target.mon.hp = math.min(maxHpOf(target), each)
  return { Strings("The battlers shared\ntheir pain!") }
end

-- SPIKES: laid on the FOE's side; the engine's side tokens already tick and
-- clear, so this is a token rather than a battler flag.
P.SPIKES_EFFECT = function(battle, user, target)
  local side = battle.sideOf and battle:sideOf(target)
  if not side then return { Strings("But, it failed!") } end
  if side.spikes then return { Strings("But, it failed!") } end
  side.spikes = true
  return { Strings("SPIKES were\nscattered all around\nthe foe's side!") }
end

-- BATON PASS: the stat stages and the volatiles go with the switch.  The
-- switch itself is BattleState's; this records what must survive it.
P.BATON_PASS_EFFECT = function(battle, user)
  user.batonPass = {
    stages = user.stages,
    confusedTurns = user.confusedTurns,
    substituteHP = user.substituteHP,
    leechSeeded = user.leechSeeded,
    perishTurns = user.perishTurns,
  }
  user.wantsSwitch = true
  return { Strings("%s\npassed the baton!", displayName(user)) }
end

-- ---------------------------------------------------------------------
-- WEATHER
-- ---------------------------------------------------------------------

-- HAIL is the fourth weather and the only one Hoenn added.  Weather.lua
-- carries its text and its damage rule alongside the other three.
P.HAIL_EFFECT = function(battle)
  Weather.start(battle, Weather.HAIL)
  return { Strings(Weather.STARTED_TEXT[Weather.HAIL] or "It started to hail!") }
end

-- ---------------------------------------------------------------------
-- DAMAGING MOVES THAT DO SOMETHING ELSE AS WELL
-- ---------------------------------------------------------------------

-- The user pays for the power: SUPERPOWER drops its own attack and defence,
-- OVERHEAT and PSYCHO BOOST drop their own Sp.Atk two stages.
local function selfCost(rows)
  return {
    afterDamage = function(ctx)
      for _, row in ipairs(rows) do
        for _, m in ipairs(ctx.changeStage(ctx.user, row[1], row[2], false)) do
          ctx.say(m)
        end
      end
    end,
  }
end
F.SUPERPOWER_EFFECT = selfCost({ { "attack", -1 }, { "defense", -1 } })
F.OVERHEAT_EFFECT = selfCost({ { "spatk", -2 } })

-- FACADE: twice as strong while the user is burned, poisoned or paralysed,
-- which is the opposite of what a status usually does to a Pokemon.
local FACADE_STATUS = { BRN = true, PSN = true, PAR = true }
F.FACADE_EFFECT = {
  beforeAccuracy = function(ctx)
    if FACADE_STATUS[ctx.user.mon.status] then ctx.powerBoost = 2 end
  end,
  powerMultiplier = function(ctx)
    return FACADE_STATUS[ctx.user.mon.status] and 2 or 1
  end,
}

-- REVENGE: twice as strong if the user was hit this turn.  Its priority is
-- -4, so it almost always was.
F.REVENGE_EFFECT = {
  powerMultiplier = function(ctx)
    return ctx.user.hurtThisTurn and 2 or 1
  end,
}

-- SMELLING SALT: twice as strong against a paralysed target, and it CURES
-- the paralysis afterwards -- so it is worth exactly one hit.
F.SMELLINGSALT_EFFECT = {
  powerMultiplier = function(ctx)
    return ctx.target.mon.status == "PAR" and 2 or 1
  end,
  afterDamage = function(ctx)
    if ctx.target.mon.status ~= "PAR" then return end
    ctx.target.mon.status = nil
    ctx.say(Strings("%s's\nPARALYSIS was\ncured!", displayName(ctx.target)))
  end,
}

-- ERUPTION and WATER SPOUT: full power at full health and nothing much at
-- one HP.  power * currentHP / maxHP, floored at 1.
F.ERUPTION_EFFECT = {
  powerMultiplier = function(ctx)
    local max = maxHpOf(ctx.user)
    if max <= 0 then return 1 end
    return math.max(1, ctx.user.mon.hp) / max
  end,
}

-- ENDEAVOR brings the target down to the user's HP and does nothing to a
-- target that is already lower.
F.ENDEAVOR_EFFECT = {
  chooseDamage = function(ctx)
    local diff = ctx.target.mon.hp - ctx.user.mon.hp
    if diff <= 0 then return nil, Strings("But, it failed!") end
    return diff, { crit = false, typeMult = 10 }
  end,
}

-- BRICK BREAK smashes REFLECT and LIGHT SCREEN before it lands, and does so
-- even against a target it is not very effective on.
F.BRICK_BREAK_EFFECT = {
  beforeAccuracy = function(ctx)
    local t = ctx.target
    if t.reflect or t.lightScreen then
      t.reflect, t.lightScreen = nil, nil
      ctx.say(Strings("The wall shattered!"))
    end
  end,
}

-- SKY UPPERCUT reaches a target in the middle of FLY.
F.SKY_UPPERCUT_EFFECT = { neverMissInvulnerable = true }

-- KNOCK OFF takes the target's held item away for the rest of the battle.
F.KNOCK_OFF_EFFECT = {
  afterDamage = function(ctx)
    local mon = ctx.target.mon
    local id = mon.item or mon.heldItem
    if not id or ctx.target.substituteHP then return end
    -- STICKY HOLD keeps hold of it
    if require("src.battle.Abilities").keepsItem(ctx.target) then
      return
    end
    mon.item, mon.heldItem = nil, nil
    ctx.target.knockedOffItem = id
    local def = ctx.data and ctx.data.items and ctx.data.items[id]
    ctx.say(Strings("%s knocked off\n%s's %s!", displayName(ctx.user),
                    displayName(ctx.target), (def and def.name) or "item"))
  end,
}

-- THIEF and COVET take it and KEEP it, but only if the thief's hands are
-- empty -- which is the rule that stops a THIEF user farming items.
F.THIEF_EFFECT = {
  afterDamage = function(ctx)
    local from, to = ctx.target.mon, ctx.user.mon
    local id = from.item or from.heldItem
    if not id or (to.item or to.heldItem) or ctx.target.substituteHP then
      return
    end
    if require("src.battle.Abilities").keepsItem(ctx.target) then
      return
    end
    from.item, from.heldItem = nil, nil
    to.item = id
    local def = ctx.data and ctx.data.items and ctx.data.items[id]
    ctx.say(Strings("%s stole\n%s's %s!", displayName(ctx.user),
                    displayName(ctx.target), (def and def.name) or "item"))
  end,
}

-- FAKE OUT flinches, and only ever on the user's FIRST turn out.
F.FAKE_OUT_EFFECT = {
  gate = function(ctx)
    if (ctx.user.turnsOut or 1) > 1 then
      return false, Strings("But, it failed!")
    end
    return true
  end,
  afterDamage = function(ctx)
    if ctx.target.substituteHP then return end
    if require("src.battle.Abilities").refusesFlinch(ctx.target) then return end
    ctx.target.flinched = true
  end,
}

-- PURSUIT is twice as strong against a Pokemon that is switching out.
F.PURSUIT_EFFECT = {
  powerMultiplier = function(ctx)
    return ctx.target.switchingOut and 2 or 1
  end,
}

-- RAPID SPIN clears what is stuck to the user and to its side.
F.RAPID_SPIN_EFFECT = {
  afterDamage = function(ctx)
    local u = ctx.user
    local freed = u.trappedBy or u.leechSeeded
    u.trappedBy, u.trappedTurns, u.leechSeeded = nil, nil, nil
    local side = ctx.battle.sideOf and ctx.battle:sideOf(u)
    if side and side.spikes then side.spikes = nil freed = true end
    if freed then
      ctx.say(Strings("%s spun free!", displayName(u)))
    end
  end,
}

-- FURY CUTTER and ROLLOUT/ICE BALL double each turn they keep landing, and
-- reset the moment they miss or the user does something else.
local function rampingPower(cap)
  return {
    powerMultiplier = function(ctx)
      local run = math.min(cap, (ctx.user.rampRun or 0))
      local mult = 1
      for _ = 1, run do mult = mult * 2 end
      return mult
    end,
    afterDamage = function(ctx)
      ctx.user.rampRun = math.min(cap, (ctx.user.rampRun or 0) + 1)
      ctx.user.rampMove = ctx.move.id
    end,
    onMiss = function(ctx)
      ctx.user.rampRun, ctx.user.rampMove = nil, nil
    end,
  }
end
F.FURY_CUTTER_EFFECT = rampingPower(4)
F.ROLLOUT_EFFECT = rampingPower(4)

-- SNORE only works while the user is asleep, which is the joke.
F.SNORE_EFFECT = {
  gate = function(ctx)
    if ctx.user.mon.status ~= "SLP" then
      return false, Strings("But, it failed!")
    end
    return true
  end,
}

-- ---------------------------------------------------------------------
-- SIDE EFFECTS ON DAMAGING MOVES
-- ---------------------------------------------------------------------

-- MIST BALL and the two that raise a stat on the way past.  These use the
-- move's OWN chance byte, which the extractor now writes, rather than a
-- number baked in here.
-- THE SECONDARY CHANCE, in one place, so SERENE GRACE and SHIELD DUST get
-- their say on Hoenn's own effects as well as the shared ones.
--
-- `who` says whose secondary it is: a boost the USER gives itself is not the
-- defender's business at all, so SHIELD DUST does not refuse it -- it refuses
-- the half that happens TO the defender.
local function secondaryOdds(battle, user, target, move, fallback, toTarget)
  local chance = tonumber(move and move.effectChance) or fallback
  return require("src.battle.Abilities").secondaryOdds(
    user, toTarget and target or nil, chance)
end

local function sideStage(who, stat, delta, fallback)
  return function(battle, user, target, move)
    local chance = secondaryOdds(battle, user, target, move, fallback,
                                   who ~= "user")
    if battle.rng(0, 255) >= chance then return {} end
    local subject = (who == "user") and user or target
    if who ~= "user" and subject.substituteHP then return {} end
    return changeStage(battle, subject, stat, delta, who ~= "user")
  end
end
S.SP_ATK_DOWN_HIT_EFFECT = sideStage("target", "spatk", -1, 128)
S.ATTACK_UP_HIT_EFFECT = sideStage("user", "attack", 1, 26)
S.DEFENSE_UP_HIT_EFFECT = sideStage("user", "defense", 1, 26)

-- ANCIENTPOWER and SILVER WIND raise ALL FIVE at once, or none of them.
S.ALL_UP_HIT_EFFECT = function(battle, user, target, move)
  local chance = secondaryOdds(battle, user, target, move, 26, false)
  if battle.rng(0, 255) >= chance then return {} end
  local out = {}
  for _, stat in ipairs({ "attack", "defense", "speed", "spatk", "spdef" }) do
    append(out, changeStage(battle, user, stat, 1, false))
  end
  return { Strings("%s's stats\nrose!", displayName(user)) }
end

-- TRI ATTACK burns, freezes or paralyses, one in three each.
S.TRI_ATTACK_EFFECT = function(battle, user, target, move)
  local chance = secondaryOdds(battle, user, target, move, 51, true)
  if battle.rng(0, 255) >= chance then return {} end
  local pick = ({ "BRN", "FRZ", "PAR" })[battle.rng(1, 3)]
  return StatusRegistry.inflict(battle, target, pick,
                                { secondary = true, user = user,
                                  moveType = move and move.type,
                                  source = move and move.id })
end

-- POISON FANG poisons BADLY, which is the whole difference between it and
-- POISON STING.
S.POISON_FANG_EFFECT = function(battle, user, target, move)
  local chance = secondaryOdds(battle, user, target, move, 77, true)
  if battle.rng(0, 255) >= chance then return {} end
  return StatusRegistry.inflict(battle, target, "PSN",
                                { secondary = true, toxic = true, user = user,
                                  moveType = move and move.type,
                                  source = move and move.id })
end

-- BLAZE KICK and POISON TAIL are high-crit moves with a side effect, so the
-- crit half is a full-record field and the status half is a secondary run.
local function highCritStatus(status)
  return function(battle, user, target, move)
    local chance = secondaryOdds(battle, user, target, move, 26, true)
    if battle.rng(0, 255) >= chance then return {} end
    return StatusRegistry.inflict(battle, target, status,
                                  { secondary = true, user = user,
                                    moveType = move and move.type,
                                    source = move and move.id })
  end
end
S.BLAZE_KICK_EFFECT = highCritStatus("BRN")
S.POISON_TAIL_EFFECT = highCritStatus("PSN")
-- the raised crit rate these two carry is on the MOVE data now (the
-- extractor sets it from the effect number), so it is not repeated here
F.BLAZE_KICK_EFFECT = {}
F.POISON_TAIL_EFFECT = {}

-- ---------------------------------------------------------------------
-- THE SECOND PASS: the ones that needed somewhere to keep their state
-- ---------------------------------------------------------------------
--
-- Everything below stores something on the battler and is spent by the turn
-- loop -- a wish waiting a turn, a stockpile counter, an ability on loan.
-- Each is noted where the turn loop pays it out.

-- MEMENTO: the user faints and takes the foe's attack and Sp.Atk down two
-- stages with it.  The faint is the price, not a side effect.
P.MEMENTO_EFFECT = function(battle, user, target)
  if target.substituteHP then return { Strings("But, it failed!") } end
  local out = {}
  append(out, changeStage(battle, target, "attack", -2, true))
  append(out, changeStage(battle, target, "spatk", -2, true))
  user.mon.hp = 0
  table.insert(out, 1, Strings("%s's MEMENTO!", displayName(user)))
  return out
end
ACC.MEMENTO_EFFECT = true

-- GRUDGE: if the user is knocked out by a move this turn, that move loses
-- every PP it had.  BattleState:onFaint spends it.
P.GRUDGE_EFFECT = function(battle, user)
  user.grudge = true
  return { Strings("%s wants the foe\nto bear a grudge!", displayName(user)) }
end

-- WISH: half of maximum HP, arriving at the END OF THE NEXT TURN -- which is
-- what makes it a switch-in heal rather than a RECOVER.
P.WISH_EFFECT = function(battle, user)
  if user.wishTurns then return { Strings("But, it failed!") } end
  user.wishTurns = 2
  user.wishHeal = math.max(1, math.floor(maxHpOf(user) / 2))
  return { Strings("%s made a wish!", displayName(user)) }
end

-- INGRAIN: a sixteenth back every turn, and the Pokemon can no longer be
-- switched out or forced out.
P.INGRAIN_EFFECT = function(battle, user)
  if user.ingrained then return { Strings("But, it failed!") } end
  user.ingrained = true
  return { Strings("%s planted its\nroots!", displayName(user)) }
end

-- UPROAR: three turns of forced attacking during which NOBODY can sleep --
-- and anybody already asleep wakes up.
P.UPROAR_EFFECT = function(battle, user, target)
  user.uproarTurns = 3
  local out = { Strings("%s caused an\nUPROAR!", displayName(user)) }
  for _, b in ipairs({ battle.player, battle.enemy }) do
    if b and b.mon and b.mon.status == "SLP" then
      b.mon.status = nil
      out[#out + 1] = Strings("%s woke up!", displayName(b))
    end
  end
  return out
end

-- STOCKPILE, SPIT UP and SWALLOW share one counter that caps at three.
P.STOCKPILE_EFFECT = function(battle, user)
  local n = user.stockpile or 0
  if n >= 3 then return { Strings("But, it failed!") } end
  user.stockpile = n + 1
  return { Strings("%s STOCKPILED %d!", displayName(user), user.stockpile) }
end

P.SWALLOW_EFFECT = function(battle, user)
  local n = user.stockpile or 0
  if n <= 0 then return { Strings("But, it failed!") } end
  user.stockpile = 0
  local max = maxHpOf(user)
  -- a quarter, a half, all of it
  local heal = (n == 1 and math.floor(max / 4))
               or (n == 2 and math.floor(max / 2)) or max
  if user.mon.hp >= max then return { Strings("But, it failed!") } end
  user.mon.hp = math.min(max, user.mon.hp + math.max(1, heal))
  return { Strings("%s\nregained health!", displayName(user)) }
end

-- SPIT UP is a damaging move whose power IS the counter: 100, 200, 300.
F.SPIT_UP_EFFECT = {
  gate = function(ctx)
    if (ctx.user.stockpile or 0) <= 0 then
      return false, Strings("But, it failed!")
    end
    return true
  end,
  powerMultiplier = function(ctx)
    return math.max(1, ctx.user.stockpile or 1)
  end,
  afterDamage = function(ctx)
    ctx.user.stockpile = 0
  end,
}

-- FOCUS PUNCH: priority -3, and it fails outright if the user was hit before
-- it got to move.  hurtThisTurn is set by applyDamage and cleared at the
-- head of every turn, which is exactly the window this needs.
F.FOCUS_PUNCH_EFFECT = {
  gate = function(ctx)
    if ctx.user.hurtThisTurn then
      return false, Strings("%s lost its\nfocus and couldn't\nmove!",
                            displayName(ctx.user))
    end
    return true
  end,
}

-- WEATHER BALL: twice the power and the weather's own type.  Both halves
-- have to move together or it is just a stronger Normal move.
-- ...and it is the weather that is HAVING AN EFFECT, not the weather that is
-- set: an AIR LOCK on the field leaves WEATHER BALL a 50-power Normal move
-- in the middle of a thunderstorm, which is exactly what the ability does to
-- everything else that reads the sky.
local function activeWeather(ctx)
  local battle = ctx and (ctx.battle or (ctx.user and ctx.user.battle))
  if battle then return require("src.battle.Weather").current(battle) end
  return ctx and ctx.field and ctx.field.weather or nil
end

local WEATHER_BALL_TYPE = {
  RAIN = "WATER", SUN = "FIRE", SANDSTORM = "ROCK", HAIL = "ICE",
}
F.WEATHER_BALL_EFFECT = {
  powerMultiplier = function(ctx)
    return activeWeather(ctx) and 2 or 1
  end,
  beforeAccuracy = function(ctx)
    local weather = activeWeather(ctx)
    local newType = weather and WEATHER_BALL_TYPE[weather]
    if not newType then return end
    -- a shallow copy: the move record in the dataset is shared and must
    -- not be edited, and the pipeline reads ctx.move from here on
    local copy = {}
    for k, v in pairs(ctx.move) do copy[k] = v end
    copy.type = newType
    ctx.move = copy
  end,
}

-- MUD SPORT and WATER SPORT halve one type for the rest of the battle.
-- Kept on the FIELD rather than a battler, because they outlive a switch.
local function sport(field, muted, text)
  return function(battle, user)
    local f = battle.field
    if not f then return { Strings("But, it failed!") } end
    if f[field] then return { Strings("But, it failed!") } end
    f[field] = muted
    return { Strings(text, displayName(user)) }
  end
end
P.MUD_SPORT_EFFECT = sport("mudSport", "ELECTRIC",
                           Strings.source("%s\nweakened ELECTRIC's\npower!"))
P.WATER_SPORT_EFFECT = sport("waterSport", "FIRE",
                             Strings.source("%s\nweakened FIRE's\npower!"))

-- RECYCLE: the berry the Pokemon ate comes back.  HoldItems' consume path
-- records what left, which is the only reason this can be honest about
-- WHICH item to return.
P.RECYCLE_EFFECT = function(battle, user)
  local id = user.lastConsumedItem
  if not id or user.mon.item or user.mon.heldItem then
    return { Strings("But, it failed!") }
  end
  user.mon.item = id
  user.lastConsumedItem = nil
  local def = battle.data and battle.data.items and battle.data.items[id]
  return { Strings("%s found one\n%s!", displayName(user),
                   (def and def.name) or "item") }
end

-- TRICK: the two Pokemon swap what they are holding, including holding
-- nothing.  It fails only if NEITHER has anything.
P.TRICK_EFFECT = function(battle, user, target)
  local a = user.mon.item or user.mon.heldItem
  local b = target.mon.item or target.mon.heldItem
  if not (a or b) or target.substituteHP then
    return { Strings("But, it failed!") }
  end
  if require("src.battle.Abilities").keepsItem(target) then
    return { Strings("But, it failed!") }
  end
  user.mon.item, user.mon.heldItem = b, nil
  target.mon.item, target.mon.heldItem = a, nil
  return { Strings("%s switched\nitems with its\nopponent!", displayName(user)) }
end
ACC.TRICK_EFFECT = true

-- SKILL SWAP and ROLE PLAY trade abilities.  The override lives on the
-- battler, so it leaves with the Pokemon on a switch.
P.SKILL_SWAP_EFFECT = function(battle, user, target)
  local A = require("src.battle.Abilities")
  local mine, theirs = A.of(user), A.of(target)
  if not (mine and theirs) or mine == theirs then
    return { Strings("But, it failed!") }
  end
  user.abilityOverride, target.abilityOverride = theirs, mine
  return { Strings("%s swapped\nabilities with its\nopponent!",
                   displayName(user)) }
end
ACC.SKILL_SWAP_EFFECT = true

P.ROLE_PLAY_EFFECT = function(battle, user, target)
  local A = require("src.battle.Abilities")
  local theirs = A.of(target)
  if not theirs or A.of(user) == theirs then
    return { Strings("But, it failed!") }
  end
  user.abilityOverride = theirs
  return { Strings("%s's ability\nbecame %s!", displayName(user),
                   (tostring(theirs):gsub("_", " "))) }
end
ACC.ROLE_PLAY_EFFECT = true

-- CAMOUFLAGE: the user takes on the terrain's type.  This engine's battles
-- carry the map they were started from, so the terrain is a real question
-- rather than a constant -- and NORMAL is the cartridge's own answer for
-- the ordinary case (a building, a plain route in the link/battle screens).
local TERRAIN_TYPE = {
  CAVE = "ROCK", SAND = "GROUND", GRASS = "GRASS", WATER = "WATER",
  UNDERWATER = "WATER", MOUNTAIN = "ROCK", BUILDING = "NORMAL",
}
Gen3MoveEffects.TERRAIN_TYPE = TERRAIN_TYPE

P.CAMOUFLAGE_EFFECT = function(battle, user)
  local terrain = battle.terrain or (battle.field and battle.field.terrain)
  local newType = TERRAIN_TYPE[terrain or ""] or "NORMAL"
  if #(user.curTypes or {}) == 1 and user.curTypes[1] == newType then
    return { Strings("But, it failed!") }
  end
  user.curTypes = { newType }
  return { Strings("%s transformed\ninto the %s type!", displayName(user),
                   newType) }
end

-- CONVERSION 2: the user takes a type that RESISTS the move that just hit
-- it.  Derived from the type chart rather than a table, so a dataset with a
-- different chart is believed.
P.CONVERSION2_EFFECT = function(battle, user, target)
  local last = target.lastMove and battle.data and battle.data.moves
               and battle.data.moves[target.lastMove]
  if not last or not last.type then return { Strings("But, it failed!") } end
  local TypeChart = require("src.battle.TypeChart")
  local order = battle.data.constants and battle.data.constants.typeOrder
  local candidates = {}
  for _, t in ipairs(order or {}) do
    if TypeChart.effectiveness(last.type, { t }) < 10 then
      candidates[#candidates + 1] = t
    end
  end
  if #candidates == 0 then return { Strings("But, it failed!") } end
  local pick = candidates[battle.rng(1, #candidates)]
  user.curTypes = { pick }
  return { Strings("%s transformed\ninto the %s type!", displayName(user),
                   pick) }
end

-- SLEEP TALK: a random OTHER move, and only while asleep.
P.SLEEP_TALK_EFFECT = function(battle, user, target, move)
  if user.mon.status ~= "SLP" then return { Strings("But, it failed!") } end
  local pool = {}
  for _, m in ipairs(user.curMoves or user.mon.moves or {}) do
    if m.id ~= move.id and m.id ~= "SLEEP_TALK" then pool[#pool + 1] = m.id end
  end
  if #pool == 0 then return { Strings("But, it failed!") } end
  user.callsMoveId = pool[battle.rng(1, #pool)]
  return {}
end

-- SKETCH copies the target's last move PERMANENTLY, onto the party mon as
-- well as the battle copy -- which is the whole difference between it and
-- MIMIC.
P.SKETCH_EFFECT = function(battle, user, target, move)
  local copied = target.lastMove
  if not copied then return { Strings("But, it failed!") } end
  local slot
  for i, m in ipairs(user.curMoves or user.mon.moves or {}) do
    if m.id == move.id then slot = i break end
  end
  if not slot then return { Strings("But, it failed!") } end
  local def = battle.data and battle.data.moves and battle.data.moves[copied]
  local fresh = { id = copied, pp = (def and def.pp) or 5,
                  maxPp = (def and def.pp) or 5 }
  if user.curMoves then user.curMoves[slot] = fresh end
  if user.mon.moves then user.mon.moves[slot] = fresh end
  return { Strings("%s SKETCHED\n%s!", displayName(user),
                   (def and def.name) or copied) }
end

-- MIRROR COAT is COUNTER's special twin: twice whatever SPECIAL damage the
-- user took this turn.
F.MIRROR_COAT_EFFECT = {
  chooseDamage = function(ctx)
    local taken = ctx.user.specialDamageTaken or 0
    if taken <= 0 then return nil, Strings("But, it failed!") end
    return math.min(65535, taken * 2), { crit = false, typeMult = 10 }
  end,
}

-- FUTURE SIGHT and DOOM DESIRE land TWO TURNS LATER, on whoever is standing
-- there then.  The damage is rolled now, which is the cartridge's rule.
F.FUTURE_SIGHT_EFFECT = {
  perform = function(ctx)
    local side = ctx.battle.sideOf and ctx.battle:sideOf(ctx.target)
    if not side or side.futureSight then
      ctx.battle:cancelMoveAnim()
      ctx.say(Strings("But, it failed!"))
      return
    end
    local dmg = ctx.computeDamage({ rng = ctx.rng })
    side.futureSight = { turns = 3, damage = math.max(1, dmg),
                         move = ctx.move.id }
    ctx.say(Strings("%s foresaw\nan attack!", displayName(ctx.user)))
  end,
}

-- BEAT UP strikes once per healthy party member.
F.BEAT_UP_EFFECT = {
  hitCount = function(ctx)
    local party = ctx.user.isPlayer and ctx.battle.game
                  and ctx.battle.game.save and ctx.battle.game.save.party
    if not party then return 1 end
    local n = 0
    for _, mon in ipairs(party) do
      if (mon.hp or 0) > 0 and not mon.status then n = n + 1 end
    end
    return math.max(1, n)
  end,
}

-- GUST and EARTHQUAKE reach a target that is in the air or underground, and
-- hit it for double when they do.
local function reachesHidden(kind)
  return {
    neverMissInvulnerable = true,
    powerMultiplier = function(ctx)
      return (ctx.target.invulnerable
              and ctx.target.charging
              and ctx.target.hiddenAs == kind) and 2 or 1
    end,
  }
end
F.GUST_EFFECT = reachesHidden("air")
F.EARTHQUAKE_EFFECT = reachesHidden("underground")

-- ---------------------------------------------------------------------------
-- THE THREE THE GEN 2 JOIN GOT BEHAVIOURALLY WRONG.
--
-- The extractor names an effect number by joining against a Gen 2 dataset
-- through the moves both generations share.  That is sound wherever a move
-- kept its behaviour, and confidently wrong wherever it did not -- which is
-- exactly these three, all found by checking the port's names against
-- pret/pokeemerald rather than by anything going visibly wrong in a battle.
-- ---------------------------------------------------------------------------

-- HIGH CRITICAL.  Nothing to run: the raised rate is set on the move data by
-- the extractor and Damage.critRoll has read `move.highCrit` since Kanto.
-- The record exists so the effect is not reported as unimplemented, and so
-- that a mod can override the whole effect if it wants to.
F.HIGH_CRITICAL_EFFECT = {}

-- LOW KICK is WEIGHT-BASED in Gen 3, and its move entry says so: power 1,
-- secondary chance 0.  The 1 is a placeholder the real power multiplies.
--
-- The table is pret's sWeightToDamageTable, in HECTOGRAMS, and the rule is
-- "the first threshold GREATER than the target's weight wins; heavier than
-- every threshold is 120".  The port stores weight in kilograms, so the
-- comparison is done in tenths to keep the cartridge's own numbers.
local LOW_KICK_POWER = {
  { 100, 20 }, { 250, 40 }, { 500, 60 }, { 1000, 80 }, { 2000, 100 },
}
local LOW_KICK_HEAVIEST = 120

Gen3MoveEffects.LOW_KICK_POWER = LOW_KICK_POWER

function Gen3MoveEffects.lowKickPower(defender)
  local def = defender and defender.def
  local kg = def and tonumber(def.weight)
  -- a dataset with no weight (every Gen 1 and Gen 2 one) gets the lightest
  -- rung rather than a nil, which is the arm that does the least harm
  if not kg then return LOW_KICK_POWER[1][2] end
  local hectograms = math.floor(kg * 10 + 0.5)
  for _, row in ipairs(LOW_KICK_POWER) do
    if row[1] > hectograms then return row[2] end
  end
  return LOW_KICK_HEAVIEST
end

F.LOW_KICK_EFFECT = {
  powerMultiplier = function(ctx)
    -- the move's own power is 1, so the multiplier IS the power
    return Gen3MoveEffects.lowKickPower(ctx.target)
  end,
}

-- TRIPLE KICK hits three times and its power escalates 10, 20, 30.
--
-- This pipeline rolls the damage ONCE and applies it per hit, so a per-hit
-- ramp is not something it can express.  Three hits at twice the base power
-- is the same TOTAL -- 3 x 2 x 10 is 60, and 10 + 20 + 30 is 60 -- so the
-- damage a Hitmontop does over the move is right even though it is spread
-- evenly rather than escalating.  Said plainly here rather than left to be
-- discovered: what is not modelled is the ramp, and the cartridge's rule
-- that the move stops early if a kick misses.
F.TRIPLE_KICK_EFFECT = {
  hitCount = function() return 3 end,
  powerMultiplier = function() return 2 end,
}

-- COUNTER already has a home: runDamaging special-cases it by move id,
-- because its damage comes from a battle-wide record rather than the
-- attacker's stats.  The record exists so the effect stops being reported as
-- unimplemented, and carries nothing -- adding stage callbacks here would
-- fight the special case rather than replace it.
F.COUNTER_EFFECT = {}

return Gen3MoveEffects
