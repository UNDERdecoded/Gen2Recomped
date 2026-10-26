-- The move-effect execution surface: the ctx facade handed to every
-- move_effects record callback, and the staged damaging pipeline that
-- performMove drives through the record's stage fields
-- (gate/neverMiss/alwaysHits/accuracyRaw/hitCount/beforeAccuracy/chooseDamage/
-- onMiss/afterDamage
-- plus the post-damage secondary run).  The ctx is the only supported
-- surface handlers receive; everything else is engine-internal.

local HoldItems = require("src.battle.HoldItems")
local MoveEffects = require("src.battle.MoveEffects")
local Runtime = require("src.mods.Runtime")
local StatusRegistry = require("src.battle.StatusRegistry")
local Strings = require("src.core.Strings")
local Timing = require("src.core.Timing")
local HeldItems = require("src.battle.HeldItems")

local EffectRegistry = {}

-- A move that misses -- or that registers as missed, which in Gen 1 includes
-- a type immunity and damage floored to zero -- skips its animation and
-- falls into PlayerCheckIfFlyOrChargeEffect's `ld c, 30 / call DelayFrames`
-- (engine/battle/core.asm:3155-3158 and :3185; enemy twin at :5588) before
-- anything is printed.  EXPLODE_EFFECT is the exception: core.asm:3157
-- branches it to PlayPlayerMoveAnimation instead, so it pays the animation
-- rather than the hold -- the same condition that gates cancelMoveAnim.
local function missBeat(battle, record)
  -- BATTLE ARENA: a miss is -2 skill (src/battle/Gen3Arena.lua)
  if battle.arenaOutcome then battle.arenaOutcome.failed = true end
  if record and record.explode then return end
  battle:waitNext(Timing.MOVE_STATUS_OR_MISS)
end

-- pokered's <USER>/<TARGET> text macros print "Enemy " before the enemy
-- mon's nickname (home/text.asm PlaceMoveUsersName)
local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end
EffectRegistry.displayName = displayName

-- built once per performMove call; closes over the battle
function EffectRegistry.makeCtx(battle, user, target, move, moveInst, isCalled)
  local ctx
  ctx = {
    battle = battle, data = battle.data, rng = battle.rng,
    ruleset = battle.ruleset,
    user = user, target = target, move = move, moveInst = moveInst,
    isCalled = isCalled or false,
    field = battle.field,
    displayName = displayName,
    say = function(text) battle:sayNext(text) end,
    sayNext = function(text) battle:sayNext(text) end,
    anim = function(animName, isPlayer)
      battle:animNext(animName, isPlayer == nil and user.isPlayer or isPlayer)
    end,
    drain = function() battle:drainNext() end,
    -- applyDamage plus the faint queue, like the crash/self-hit paths
    damage = function(who, amount)
      local dealt = battle:applyDamage(who, amount)
      if who.mon.hp <= 0 then battle:onFaint(who) end
      return dealt
    end,
    inflict = function(who, statusId, opts)
      return StatusRegistry.inflict(battle, who, statusId, opts)
    end,
    cure = function(who)
      who.mon.status = nil
      who.toxicCounter = nil
    end,
    changeStage = function(who, stat, delta, fromEnemy)
      return MoveEffects.changeStage(battle, who, stat, delta, fromEnemy)
    end,
    computeDamage = function(opts)
      return battle:computeDamage(user, target, move, opts)
    end,
    accuracyRoll = function()
      return battle:accuracyRoll(move, user, target)
    end,
    callMove = function(moveId)
      if require("src.core.GameVersion").isGen3() then
        moveId = require("src.battle.EnemyMoveChoice").resolveMove(battle.data, moveId)
        if not moveId then return nil end
      end
      return battle:performMove(user, target, { id = moveId, pp = 1 }, true)
    end,
    side = function(who) return battle:sideOf(who) end,
  }
  return ctx
end

-- multi-hit count: the record's hitCount wins, then the move's multiHit
-- field, then a single hit
local function hitCount(ctx, record)
  if record and record.hitCount then
    return record.hitCount(ctx) or 1
  end
  local dist = ctx.move.multiHit
  if dist == nil then return 1 end
  if type(dist) == "number" then return dist end
  local r = ctx.rng(0, #dist - 1)
  return dist[r + 1]
end

local function ordinaryDamage(battle, ctx, record)
  return battle:computeDamage(ctx.user, ctx.target, ctx.move,
    { rng = battle.rng, explode = (record and record.explode) or nil,
      powerMultiplier = record and record.powerMultiplier and record.powerMultiplier(ctx) or nil,
      highCrit = record and record.highCrit or nil,
      power = record and record.gbaTripleKick and 10 * (ctx.gbaHit or 1) or nil })
end

-- The damaging pipeline, extracted from the performMove monolith: every
-- stage keeps its generation's check order and RNG consumption. GBA draws
-- hit count after accuracy and computes ordinary damage separately per hit;
-- older generations retain their pre-accuracy count and shared damage roll.
function EffectRegistry.runDamaging(battle, ctx, record)
  local user, target = ctx.user, ctx.target
  local move, moveInst = ctx.move, ctx.moveInst
  local neverMiss = record and record.neverMiss
  local gba = require("src.core.GameVersion").isGen3()
  local ordinaryMulti = gba and require("src.battle.Gen3MultiHit").ordinary(move)
  local tripleKick = gba and record and record.gbaTripleKick
  local nativeMulti = ordinaryMulti or tripleKick
  if gba and type(target.substituteHP) == "number" and target.substituteHP <= 0 then
    target.substituteHP = nil
  end
  -- alwaysHits is neverMiss's weaker sibling and the distinction is CheckHit's
  -- own ordering: .FlyDigMoves is tested BEFORE .ThunderRain
  -- (effect_commands.asm:1559-1563), so Thunder in rain skips the accuracy
  -- roll yet still misses a target part-way through Fly or Dig -- where Swift
  -- (neverMiss), tested ahead of the invulnerability check, hits it.  It is a
  -- predicate because the answer changes with the weather, turn by turn.
  local alwaysHits = record and record.alwaysHits
  if type(alwaysHits) == "function" then alwaysHits = alwaysHits(ctx) end
  -- accuracyRaw replaces the move's accuracy BYTE for this turn
  -- (BattleCommand_ThunderAccuracy), so it is a 0-255 threshold, not a percent
  local accuracyRaw = record and record.accuracyRaw and record.accuracyRaw(ctx)
  local nativeAccuracy = gba and (not neverMiss and not alwaysHits
    or move.gen3Effect == 17 or move.gen3Effect == 78 or move.gen3Effect == 152)

  -- PROTECT and DETECT, before anything else happens.  Only a move the
  -- cartridge marks PROTECT-affected is stopped, which is the second use the
  -- extracted flags byte is put to; a move with no flags recorded (every Gen
  -- 1 and Gen 2 one) is treated as affected, which is that generation's rule.
  local lockedOHKO = record and record.gbaOHKO
    and require("src.battle.Gen3LockOn").active(battle, user, target)
  if target.protecting and (not gba or target ~= user) and move.protectAffected ~= false and not lockedOHKO then
    battle:cancelMoveAnim()
    if record and record.onProtect and record.onProtect(ctx) then return end
    battle:sayNext(Strings("%s\nprotected itself!", displayName(target)))
    return
  end

  -- Swift ignores semi-invulnerability (MoveHitTest returns hit for
  -- SWIFT_EFFECT before the INVULNERABLE check), and so does SKY UPPERCUT,
  -- which reaches a target in the middle of FLY without being a never-miss
  -- move in any other respect -- hence the second, narrower field.
  if target.invulnerable and not nativeAccuracy and not neverMiss
     and not (record and record.neverMissInvulnerable) and not lockedOHKO then
    -- Explosion/Selfdestruct still animate on a miss (HandleIfPlayerMoveMissed)
    if not (record and record.explode) then battle:cancelMoveAnim() end
    missBeat(battle, record)
    battle:sayNext(Strings("%s's\nattack missed!", displayName(user)))
    -- MoveHitTest's INVULNERABLE branch sets the same wMoveMissed as a
    -- failed accuracy roll (core.asm:5260), and the miss handler still
    -- runs the explode effect ("even if Explosion or Selfdestruct
    -- missed, its effect still needs to be activated", core.asm:3223),
    -- so the user faints against a mid-Fly/Dig target too (#528)
    if record and record.onMiss then record.onMiss(ctx, "invulnerable") end
    return
  end

  -- OHKO speed gate, Dream Eater sleep gate
  if record and record.gate then
    local ok, failMsg = record.gate(ctx)
    if not ok then
      battle:cancelMoveAnim()
      if failMsg then battle:sayNext(failMsg) end
      if ctx.gbaOHKOMiss and record.onMiss then record.onMiss(ctx, "accuracy") end
      return
    end
  end

  local hits = not gba and hitCount(ctx, record) or 1

  if record and record.beforeAccuracy then record.beforeAccuracy(ctx) end

  if nativeAccuracy or not neverMiss and not alwaysHits then
    local hit, reason = battle:accuracyRoll(move, user, target, accuracyRaw)
    if not hit then
      if reason == "absorbed" then
        battle:cancelMoveAnim()
        if record and record.onMiss then record.onMiss(ctx, "absorbed") end
        return
      end
      -- Explosion/Selfdestruct still animate on a miss (HandleIfPlayerMoveMissed)
      if not (record and record.explode) then battle:cancelMoveAnim() end
      missBeat(battle, record)
      battle:sayNext(Strings("%s's\nattack missed!", displayName(user)))
      -- Jump Kick crash, Explode self-destruct
      if record and record.onMiss then record.onMiss(ctx, "accuracy") end
      user.trappingTurns = nil
      return
    end
  end

  if gba and record and record.gbaAfterAccuracy then record.gbaAfterAccuracy(ctx) end
  if gba then hits = hitCount(ctx, record) end

  -- damage per hit
  local dmg, info
  if move.id == "COUNTER" then
    -- HandleCounterMove: 2x the last damage dealt in battle, only if
    -- the opponent's last move was counterable with >0 power (and not
    -- Counter itself); wDamage is shared, so any last damage counts.
    -- counterable defaults to the Normal/Fighting whitelist.
    local lastId = target.lastMove
    local lm = lastId and lastId ~= "COUNTER" and battle.data.moves[lastId]
    local counterable = false
    if lm and (lm.power or 0) > 0 then
      if lm.counterable ~= nil then
        counterable = lm.counterable
      else
        counterable = lm.type == "NORMAL" or lm.type == "FIGHTING"
      end
    end
    if not counterable or (battle.lastDamage or 0) == 0 then
      battle:cancelMoveAnim()
      missBeat(battle, record)
      battle:sayNext(Strings("%s's\nattack missed!", displayName(user)))
      return
    end
    dmg = math.min(65535, battle.lastDamage * 2)
    info = { crit = false, typeMult = 10 }
  elseif record and record.chooseDamage then
    -- Counter/Super Fang/OHKO/fixed damage; (nil, msg) means the move
    -- failed with that text already chosen
    local chosen, extra = record.chooseDamage(ctx)
    if not chosen then
      battle:cancelMoveAnim()
      if extra then battle:sayNext(extra) end
      return
    end
    dmg, info = chosen, extra or { crit = false, typeMult = 10 }
  else
    dmg, info = ordinaryDamage(battle, ctx, record)
  end

  if battle.arenaOutcome then
    battle.arenaOutcome.typeMult = info.typeMult
    -- an ability that made it do nothing speaks against the user's skill
    -- (BattleArena_DeductSkillPoints)
    if info.typeMult == 0 and info.ability then battle.arenaOutcome.ability = true end
  end
  if info.typeMult == 0 then
    -- type immunity zeros damage and sets wMoveMissed in Gen 1, so no anim
    if not (record and record.explode) then battle:cancelMoveAnim() end
    missBeat(battle, record)
    -- AN ABILITY, NOT THE TYPE CHART.  info.ability is set only when
    -- Abilities.blocks stopped the move, and the three ABSORBS do more than
    -- stop it: a JOLTEON takes a quarter of its maximum HP back off a
    -- THUNDERBOLT and a VULPIX's fire moves are powered up for good.  When
    -- the ability speaks for itself the flat "It doesn't affect X!" line is
    -- not printed -- the cartridge prints one or the other, never both.
    if not (info.ability and battle.abilityAbsorb
            and battle:abilityAbsorb(target, move)) then
      battle:sayNext(Strings("It doesn't affect\n%s!", displayName(target)))
    end
    if record and record.onMiss then record.onMiss(ctx, "immune") end
    return
  end
  if info.missed then
    -- 0.25x floored the damage to zero: the original registers a miss
    if not (record and record.explode) then battle:cancelMoveAnim() end
    missBeat(battle, record)
    battle:sayNext(Strings("%s's\nattack missed!", displayName(user)))
    if record and record.onMiss then record.onMiss(ctx, "floored") end
    return
  end
  -- Focus Band belongs to the damage-adjustment seam below. GBA rolls on
  -- every direct strike, including nonlethal/Substitute hits; older rules
  -- keep their own eligibility. OHKO supplies its already evaluated result.
  battle.lastDamage = dmg -- wDamage (shared by both sides, read by Counter)

  -- the hit blink + damage sound ride each animation row, placed BEFORE
  -- that hit's drain so the blink precedes the bar.  Multi-hit moves
  -- replay PlayMoveAnimation per strike (pokered: GetPlayerAnimationType
  -- / GetEnemyAnimationType loop on wNumAttacksLeft); hit 1 reuses the
  -- announcement-time moveAnimRow, later hits queue fresh anim rows.
  -- Thrash/rage continuations have no announcement anim -- a bare
  -- hitRow carries the blink instead.
  local hitSfx = info.typeMult > 10 and "Super_Effective"
                 or info.typeMult < 10 and "Not_Very_Effective" or "Damage"
  -- GetPlayerAnimationType / GetEnemyAnimationType (engine/battle/core.asm
  -- :3159 / :5555): wAnimationType is 4 (blink the enemy pic) or 1 (shake
  -- the screen vertically) for a damaging move with no added effect, and
  -- 5 / 2 (a horizontal shake) as soon as the move HAS one -- which is why
  -- Bubblebeam and Confusion shake instead of blinking (#354)
  local added = move.effect ~= nil and move.effect ~= "NO_ADDITIONAL_EFFECT"
  local hitFx = { sfx = hitSfx,
                  animType = user.isPlayer and (added and 5 or 4)
                             or (added and 2 or 1),
                  blink = battle:animationsOn() and target or nil }

  local totalDealt = 0
  local landed, brokeSub = 0, false
  for h = 1, hits do
    if target.mon.hp <= 0 then break end
    if nativeMulti and (user.mon.hp <= 0 or h > 1 and user.mon.status == "SLP"
        and not require("src.battle.Gen3MultiHit").sleepTalk(battle)) then break end
    -- Unlike ordinary multi-hit moves, each reached native kick checks
    -- accuracy again before its critical/damage opcodes. A later miss ends
    -- the script quietly; already landed kicks still reach move-end (Rage).
    if tripleKick and h > 1 and (nativeAccuracy or not neverMiss and not alwaysHits) then
      local hit = battle:accuracyRoll(move, user, target, accuracyRaw)
      if not hit then break end
    end
    ctx.gbaHit = h
    if record and record.perHitDamage then
      local nextDamage, nextInfo = record.perHitDamage(ctx, h, dmg, info)
      if nextDamage == nil then break end
      dmg, info = nextDamage, nextInfo or info
    elseif nativeMulti and h > 1
        and not (record and record.chooseDamage) then
      dmg, info = ordinaryDamage(battle, ctx, record)
      if info.typeMult == 0 or info.missed then
        ctx.gbaNoEffect = true
        if info.typeMult == 0 then
          if not (info.ability and battle.abilityAbsorb and battle:abilityAbsorb(target, move)) then
            battle:sayNext(Strings("It doesn't affect\n%s!", displayName(target)))
          end
        else
          battle:sayNext(Strings("%s's\nattack missed!", displayName(user)))
        end
        if record and record.onMiss then record.onMiss(ctx, info.typeMult == 0 and "immune" or "floored") end
        break
      end
    end
    local hitRow
    if h == 1 then
      hitRow = battle.moveAnimRow
      if not hitRow then
        battle.nextInsert = (battle.nextInsert or 0) + 1
        hitRow = { hitRow = true }
        table.insert(battle.queue, battle.nextInsert, hitRow)
      end
    else
      battle.nextInsert = (battle.nextInsert or 0) + 1
      -- FireRed re-enters attackanimation for every strike with
      -- sB_ANIM_TURN advanced to that strike.  The move-animation bytecode
      -- uses that value for alternating multi-hit arms (DOUBLESLAP,
      -- FURY_ATTACK, TRIPLE_KICK, ARM_THRUST, ...).  Keep the exact battler
      -- slots too: a replay from the right slot of a double battle must not
      -- silently fall back to the left/main battlers after hit one.
      local baseCtx = battle.moveAnimRow and battle.moveAnimRow.animContext
      local hitCtx = {}
      if type(baseCtx) == "table" then
        for k, v in pairs(baseCtx) do hitCtx[k] = v end
      end
      hitCtx.moveTurn = h - 1
      hitRow = { anim = move.id, attackerIsPlayer = user.isPlayer,
                 attackerPosition = user.position,
                 targetPosition = target and target.position,
                 animContext = hitCtx }
      table.insert(battle.queue, battle.nextInsert, hitRow)
    end
    local hadSub = target.substituteHP ~= nil
    local hitDamage = dmg
    if not hadSub then
      -- This seam is reached only by direct attack damage. Weather, poison,
      -- Leech Seed and confusion self-hit never roll Focus Band here.
      hitDamage = HeldItems.limitDirectDamage(battle.data, target, hitDamage,
                                              battle.rng)
    end
    battle.lastDamage = hitDamage
    -- ...and the one applyDamage a Gen 3 FOCUS BAND answers: a move landing
    -- on someone
    local substituteBefore = target.substituteHP
    local dealt, endured = battle:applyDamage(target, hitDamage, true, info.damageAdjustment)
    if (info.gbaSetDamage or info.gbaBeatUp) and substituteBefore then dealt = math.min(dealt, substituteBefore) end
    totalDealt = totalDealt + dealt
    if gba and not hadSub and require("src.battle.Damage").isSpecial(move.type) then
      ctx.gbaSpecialHit = true
    end
    -- MIRROR COAT is COUNTER's special twin and needs the SPECIAL half of
    -- the damage kept separately; battle.lastDamage is shared by both and
    -- cannot answer for it.  Cleared at the head of every turn.
    if info.gbaBeatUp then
      -- Scripted Beat Up records each strike, including Endure's zero HP
      -- loss; Substitute strikes leave the previous counter memory alone.
      if not hadSub then target.specialDamageTaken = dealt end
    elseif dealt > 0 and not (hadSub and require("src.core.GameVersion").isGen3()) then
      if require("src.battle.Damage").isSpecial(move.type) then
        target.specialDamageTaken = (target.specialDamageTaken or 0) + dealt
      else
        target.physicalDamageTaken = (target.physicalDamageTaken or 0) + dealt
      end
    end
    landed = h
    if dealt > 0 then hitRow.hit = hitFx end
    -- PrintCriticalOHKOText + DisplayEffectiveness run inside the
    -- multi-hit loop (core.asm .moveDidNotMiss before the jump back
    -- to GetPlayerAnimationType), so crit/effectiveness reprint on
    -- every strike -- damage was only rolled once
    if info.crit then battle:sayNext(Strings("Critical hit!")) end
    if info.ohko then battle:sayNext(Strings("One-hit KO!")) end
    -- PrintCriticalOHKOText closes with `ld c, 20 / jp DelayFrames` at its
    -- .done label (core.asm:3812-3814) -- and the no-crit path jumps to that
    -- same label (:3799), so this hold is paid on EVERY landed hit, not just
    -- critical ones.  It sits between the crit text and DisplayEffectiveness
    -- (:3228-3229), which is where the beat before "It's super effective!"
    -- comes from.
    battle:waitNext(Timing.CRIT_OHKO_TEXT)
    if info.typeMult > 10 then
      battle:sayNext(Strings("It's super\neffective!"))
    elseif info.typeMult < 10 then
      battle:sayNext(Strings("It's not very\neffective..."))
    end
    -- GBA's zero-power default script never runs the HP-damage command.
    -- Keep explicit custom/fixed damage and the earlier generations' events.
    if Runtime.wants("battle.damage_dealt") and (dealt > 0 or move.power ~= 0
        or (record and record.chooseDamage) or not require("src.core.GameVersion").isGen3()) then
      local eventCritical = info.crit
      if info.gbaBeatUp then eventCritical = false end
      local gba = require("src.core.GameVersion").isGen3()
      local eventKind
      if info.gbaBeatUp then eventKind = "special"
      elseif gba then
        local physical = info.physical
        if physical == nil then physical = not require("src.battle.Damage").isSpecial(move.type) end
        eventKind = physical and "physical" or "special"
      end
      Runtime.emit("battle.damage_dealt", {
        battle = battle, user = user, target = target, move = move,
        damage = dealt, crit = eventCritical, typeMult = info.eventTypeMult or info.typeMult,
        substitute = (gba or info.gbaSetDamage or info.gbaBeatUp) and hadSub or nil,
        kind = eventKind,
      })
    end
    if battle.firstBattle then
      require("src.battle.Gen3Critical").noteHit(battle, user, target, dealt, hadSub)
    end
    if hadSub and not target.substituteHP and not info.gbaBeatUp then
      -- Older AttackSubstitute ends the move; GBA continues against real HP.
      brokeSub = true
      if not gba then break end
    end
    if nativeMulti and endured then break end
  end
  hits = landed > 0 and landed or hits
  if hits > 1 and not info.gbaBeatUp then
    -- player: _MultiHitText; enemy: _HitXTimesText (always plural)
    if user.isPlayer then
      battle:sayNext(Strings("Hit the enemy\n%d times!", hits))
    else
      battle:sayNext(Strings("Hit %d times!", hits))
    end
  end

  -- post-damage effect bookkeeping (recoil/drain/trap/thrash/...)
  ctx.rawDamage, ctx.totalDealt = dmg, totalDealt
  ctx.brokeSub, ctx.hits = brokeSub, hits
  if record and record.afterDamage then
    record.afterDamage(ctx, totalDealt)
  elseif moveInst.struggle then
    -- struggle recoils even when its effect id resolves to no record
    local recoil = math.max(1, math.floor(dmg / 2))
    battle:sayNext(Strings("%s's\nhit with recoil!", displayName(user)))
    battle:applyDamage(user, recoil)
  end

  -- Native chance runs before effect-level faint/Substitute/ability guards.
  local nativeSecondary = require("src.core.GameVersion").isGen3()
    and require("src.battle.Gen3Secondary").run(ctx, record)
  -- Other/custom records retain their existing post-damage handler.
  if not nativeSecondary and record and record.run and record.kind ~= "primary"
     and target.mon.hp > 0 and totalDealt > 0 then
    for _, m in ipairs(record.run(ctx)) do
      battle:sayNext(m)
    end
  end
  if record == nil then
    MoveEffects.warnUnknown(move.effect)
  end

  if gba then require("src.battle.Gen3Rage").moveEnd(battle, ctx, landed) end

  if gba and ctx.gbaSpecialHit and target ~= user and target.mon.hp > 0
      and target.mon.status == "FRZ" and require("src.battle.Abilities").normalizeType(move.type) == "FIRE" then
    target.mon.status = nil
    battle:sayNext(Strings("Fire defrosted\n%s!", displayName(target)))
  end

  -- King's Rock is an explicit command in selected Gen II move scripts.  It
  -- rolls once after the completed attack (not once per hit) and cannot pass a
  -- Substitute.  Some native-flinch scripts (notably Sky Attack and Snore)
  -- also execute King's Rock, so HeldItems decides eligibility from the move
  -- effect rather than suppressing all flinch-capable moves.
  if totalDealt > 0 and target.mon.hp > 0 then
    -- BattleCommand_KingsRock checks the target's Substitute at the point the
    -- command runs.  If an earlier hit broke the Substitute, the held-item
    -- flinch is therefore allowed.
    HeldItems.tryKingsRock(battle.data, user, target, move, battle.rng,
                           target.substituteHP ~= nil)
  end

  -- ON CONTACT.  STATIC, POISON POINT, FLAME BODY and ROUGH SKIN answer the
  -- attacker after the move has finished, and only for a move that actually
  -- touches -- which is why the flags byte had to be extracted first.  A
  -- move that dealt nothing (a miss returned long ago, a substitute ate it)
  -- never gets here, matching the cartridge's own gate.
  if totalDealt > 0 and battle.abilityOnContact then
    battle:abilityOnContact(user, target, move)
  end

  -- COLOR CHANGE, which runs on the same gate and just after it: a KECLEON
  -- that took damage becomes the type of the move that dealt it.  Only a
  -- move that actually did damage, and never when it is already that type --
  -- so a KECLEON hit by TACKLE stays NORMAL and says nothing.
  if totalDealt > 0 and target.mon.hp > 0 and not target.substituteHP
     and battle.abilityColorChange then
    battle:abilityColorChange(target, move, totalDealt)
  end

  -- HELD ITEMS, in the order ItemBattleEffects runs them after a hit:
  -- KING'S ROCK flinches the target, SHELL BELL feeds the attacker, and a
  -- SITRUS BERRY the hit dropped below half goes off immediately rather
  -- than waiting for the end of the turn.
  local gba = require("src.core.GameVersion").isGen3()
  if gba then require("src.battle.GbaItemSchedule").moveEnd(battle) end
  if totalDealt > 0 and battle.shellBellDrain then
    local flinch = HoldItems.flinchChance(user, move)
    if flinch > 0 and target.mon.hp > 0 and not target.substituteHP
       and (battle.rng or love.math.random)(0, 99) < flinch
       and not require("src.battle.Abilities").refusesFlinch(target) then
      target.flinched = true
    end
    battle:shellBellDrain(user, totalDealt)
    if not gba and target.mon.hp > 0 then battle:holdItemTrigger(target, "hit") end
  end

  if target.mon.hp <= 0 then
    battle:onFaint(target)
  end
  if user.mon.hp <= 0 then
    battle:onFaint(user)
  end
end

return EffectRegistry
