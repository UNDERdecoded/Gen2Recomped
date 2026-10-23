-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE: THE RULES THAT REACH PAST ONE MOVE.
--
-- src/battle/Gen5MoveEffects.lua resolves a move once it is going off. A few
-- of BW's effects and held items need the TURN instead -- what each Pokemon
-- chose, who goes first, who is switching, what the menu may offer -- and
-- some need a timer of their own. They live here, so the effect table stays
-- one record per effect:
--
--   the turn      `arrange` (BattleState:resolveTurn, once the order is
--                 known): what everybody chose (Sucker Punch, Me First),
--                 Quick Claw / Custap (bank 14 #1025, first in the bracket),
--                 Pursuit before the switch it is aimed at
--   the action    `beforeAction` (BattleState:executeAction): a Pokemon held
--                 in the sky does nothing, the Choice lock, the thaw flag
--                 (Flame Wheel, Sacred Fire, Flare Blitz, Scald, Fusion Flare:
--                 #303 "X's Move melted the ice!"), a sealed / grounded / heal-
--                 blocked move refused (#589 / #1086 / #890)
--   the menu      `moveBlocked` (the move list): the same refusals, plus the
--                 Choice lock (#905), before the turn is spent
--   the switch    `switchRefused` (the party screen): bound, Mean Look,
--                 Shadow Tag... "X can't be switched out!" (bank 18 #88),
--                 unless it holds a Shed Shell; `playerSwitch` (a single's
--                 switch): the foe's Pursuit lands first, at double power
--   accuracy      `accuracy` (BattleState:accuracyRoll): Telekinesis always
--                 hits, Gravity x5/3, the Micle Berry x1.2 (once)
--   damage        `adjust` (Gen5MoveEffects.damage): Me First x1.5, Wonder
--                 Room's Defense / Sp. Def swap
--   the targets   `centerOfAttention` (Targeting.resolve): Follow Me / Rage
--                 Powder
--   the turn end  a field token: Rollout / Uproar locks, Future Sight /
--                 Doom Desire landing (damage worked out THEN, Gen V), Sky
--                 Drop's release, Gravity holding everyone down
-- and `install(G5)` replaces the effect records that were partial.
--
-- Gen V's numbers (Bulbapedia, Showdown's gen5 mod): Rollout five turns,
-- doubling, Defense Curl x2; Uproar three turns; Beat Up one strike per
-- able, unstatused party member at 5 + its base Attack / 10, the user's
-- Attack; Gravity accuracy x5/3; Grip Claw seven turns of binding, Binding
-- Band an eighth; Nature Power by the battle's terrain (Tri Attack indoors,
-- Earthquake on plain ground and sand, Seed Bomb in grass, Hydro Pump on
-- water, Mud Bomb in a puddle, Rock Slide in a cave, Blizzard on snow, Ice
-- Beam on ice).

local T = require("src.battle.Gen5BattleText")

local R = {}

local floor = math.floor
local function H() return require("src.battle.Gen5HoldItems") end
local function Abil() return require("src.battle.Abilities") end
local function TC() return require("src.battle.TypeChart") end
local function Wx() return require("src.battle.Weather") end

local function turnOf(battle) return battle.turnCount or 0 end
local function sideIndex(b) return (b and b.isPlayer) and 1 or 2 end
local function maxHP(b)
  local m = b and b.mon
  if not m then return 1 end
  return (m.stats and m.stats.hp) or m.maxHP or m.maxHp or 1
end
local function hasType(b, t)
  for _, x in ipairs(b and b.curTypes or {}) do if x == t then return true end end
  return false
end
local function alive(b) return b and b.mon and (b.mon.hp or 0) > 0 end
local function sayNow(battle, text) if text and text ~= "" then battle:sayNext(text) end end
local function failed(battle) return T.std(battle, "failed", nil, "But it failed!") end
local function moveName(battle, id)
  local d = battle.data and battle.data.moves and battle.data.moves[id]
  return d and d.name or tostring(id)
end

local function activeList(battle)
  local out = {}
  if battle.activeBattlers then
    for _, b in battle:activeBattlers() do if b and b.mon then out[#out + 1] = b end end
  end
  if #out == 0 then
    if battle.player then out[#out + 1] = battle.player end
    if battle.enemy then out[#out + 1] = battle.enemy end
  end
  return out
end
R.activeList = activeList

local function onField(battle, b)
  for _, x in ipairs(activeList(battle)) do if x == b then return true end end
  return false
end

local function sideState(battle, b)
  battle.bw = battle.bw or { sides = { {}, {} }, field = {} }
  return battle.bw.sides[sideIndex(b)]
end

local function isDouble(battle) return battle.isDouble and battle:isDouble() or false end

-- the lock Rollout and Uproar put on their user: the engine's own rampage
-- lock (thrashTurns / thrashMove: no menu, no PP), marked as ours
local function lock(u, inst, kind)
  u.thrashTurns, u.thrashMove, u.bwLockKind = 1, inst, kind
end
local function unlock(u)
  if u.bwLockKind then
    u.thrashTurns, u.thrashMove, u.bwLockKind = nil, nil, nil
  end
end
R.unlock = unlock

-- ---------------------------------------------------------------------------
-- THE TERRAIN (Nature Power): what the battle was started on
-- ---------------------------------------------------------------------------

R.NATURE_POWER = { building = 161, plain = 89, sand = 89, grass = 402, water = 56,
                   puddle = 426, cave = 157, snow = 59, ice = 58 }
function R.terrain(battle)
  return battle.gen5Terrain or "plain"
end
function R.naturePowerMove(battle)
  return R.NATURE_POWER[R.terrain(battle)] or 89
end

-- ---------------------------------------------------------------------------
-- WHO IS STANDING IN FRONT (Follow Me / Rage Powder)
-- ---------------------------------------------------------------------------

function R.centerOfAttention(battle, user, move)
  if not (battle.bw and user) or not isDouble(battle) then return nil end
  local s = battle.bw.sides[user.isPlayer and 2 or 1]
  local c = s and s.center
  if not (c and c.turn == turnOf(battle) and alive(c.who) and onField(battle, c.who)) then return nil end
  if c.who.isPlayer == user.isPlayer then return nil end
  return c.who
end

-- ---------------------------------------------------------------------------
-- THE MENU / THE ACTION: what may not be used
-- ---------------------------------------------------------------------------

local function sealedBy(battle, b, moveId)
  for _, x in ipairs(activeList(battle)) do
    if x.isPlayer ~= b.isPlayer and x.bwImprison and alive(x) then
      for _, mv in ipairs(x.curMoves or {}) do if mv.id == moveId then return x end end
    end
  end
  return nil
end
R.sealedBy = sealedBy

-- the line refusing `def` for `b`, or nil. `choosing` adds the Choice lock,
-- which is only ever met at the menu (the action itself is redirected)
function R.moveBlocked(battle, b, def, choosing)
  if not (battle.bw and b and def) then return nil end
  local name = def.name or tostring(def.id)
  if choosing and b.bwChoiceLock and b.bwChoiceLock ~= def.id and H().choiceItem(b) then
    for _, mv in ipairs(b.curMoves or {}) do
      if mv.id == b.bwChoiceLock and (mv.pp or 0) > 0 then
        return T.set(battle, 905, b, { nil, name })
      end
    end
  end
  if sealedBy(battle, b, def.id) then return T.set(battle, 589, b, { nil, name }) end
  if def.gravityBanned and (battle.bw.field.gravity or 0) > 0 then
    return T.set(battle, 1086, b, { nil, name })
  end
  if def.healMove and b.bwHealBlock then return T.set(battle, 890, b, { nil, name }) end
  return nil
end

-- BattleState:executeAction, before anything else: skip (true), or a
-- replacement action (the Choice lock on a trainer's choice)
function R.beforeAction(battle, user, target, action)
  if not (battle.bw and user and action) then return false end
  R.ensure(battle)
  if user.bwSkyDropped and user.bwSkyDropped ~= user then return true end
  if action.special == "bwHeld" then return true end
  if action.special or not action.id then return false end
  local def = battle.data.moves[action.id]
  if not def then return false end
  local swap
  -- CHOICE: the trainer's pick is bent back to the locked move
  if H().choiceItem(user) then
    if user.bwChoiceLock and user.bwChoiceLock ~= action.id then
      for _, mv in ipairs(user.curMoves or {}) do
        if mv.id == user.bwChoiceLock and (mv.pp or 0) > 0 then swap = mv end
      end
    end
    if not action.struggle then user.bwChoiceLock = (swap or action).id end
  else
    user.bwChoiceLock = nil
  end
  if swap then def = battle.data.moves[swap.id] or def end
  -- the thaw flag: the move thaws its own user before it is used
  if user.mon.status == "FRZ" and def.thawsUser then
    user.mon.status = nil
    if battle.syncShownStatus then battle:syncShownStatus() end
    sayNow(battle, T.set(battle, 303, user, { nil, def.name }))
  end
  -- a refusal the menu did not get to ask (the foe's choice, a sealed move
  -- picked before Imprison went up)
  local why = R.moveBlocked(battle, user, def, false)
  if why then
    sayNow(battle, why)
    return true
  end
  return false, swap
end

-- the menu's own lock: a Pokemon held in the sky chooses nothing
function R.menuLock(battle, b)
  if battle.bw and b and b.bwSkyDropped then return { special = "bwHeld" } end
  return nil
end

-- ---------------------------------------------------------------------------
-- SWITCHING
-- ---------------------------------------------------------------------------

local function trappedBy(battle, b)
  if not b then return false end
  if b.bwBound or b.trapped then return true end
  for _, x in ipairs(activeList(battle)) do
    if x.isPlayer ~= b.isPlayer and alive(x) and Abil().trapsSwitch(x, b) then return true end
  end
  return false
end
R.trappedBy = trappedBy

-- the party screen asked to switch `mon` in: refused (and said) when the
-- Pokemon choosing cannot leave
function R.switchRefused(battle, mon)
  if not battle.bw then return false end
  local b = (battle.menuBattler and battle:menuBattler()) or battle.player
  if not (b and alive(b)) or H().shedShell(b) then return false end
  if hasType(b, "GHOST") and not (b.bwBound or b.trapped) then return false end
  if not trappedBy(battle, b) then return false end
  local text = battle.data.text and battle.data.text["TEXT_G5S_0018_00088"]
  local Strings = require("src.core.Strings")
  text = (type(text) == "string" and text ~= "") and T.fill(text, { b.name })
         or Strings("%s can't be switched\nout!", b.name)
  battle:say(text)
  return true
end

local function isPursuit(battle, action)
  local d = action and action.id and battle.data.moves[action.id]
  return d and d.bwEffect == 128 and d or nil
end

-- a single battle's switch (BattleState:resolveSwitch): the foe's choice is
-- made first, and a Pursuit catches the Pokemon on its way out
function R.playerSwitch(battle, newMon)
  if not battle.bw then return false end
  local eAct = battle:enemyAction()
  local leaving = battle.player
  battle.phase = "messages"
  battle.afterQueue = "menu"
  if isPursuit(battle, eAct) and alive(leaving) then
    battle:act(function()
      leaving.switchingOut = true
      battle:executeAction(battle.enemy, leaving, eAct)
      leaving.switchingOut = nil
    end)
    battle:act(function()
      if battle.result then return end
      if alive(leaving) then battle:switchPlayerInto(battle.POS and battle.POS.PLAYER_LEFT or 0, newMon) end
    end)
  else
    battle:act(function() battle:switchPlayerInto(battle.POS and battle.POS.PLAYER_LEFT or 0, newMon) end)
    battle:act(function() battle:executeAction(battle.enemy, battle.player, eAct) end)
  end
  battle:act(function() battle:endOfTurn() end)
  return true
end

-- ---------------------------------------------------------------------------
-- THE TURN
-- ---------------------------------------------------------------------------

local function priorityOf(battle, action)
  if not action then return 0 end
  if action.special == "playerSwitch" or action.special == "aiSwitch" then return 100 end
  if action.special then return 0 end
  local d = action.id and battle.data.moves[action.id]
  return d and (d.priority or 0) or 0
end

-- BattleState:resolveTurn hands the order it built: { battler, target, action }
function R.arrange(battle, order)
  if not battle.bw then return order end
  R.ensure(battle)
  local turn = turnOf(battle)
  -- what everybody chose this turn
  for _, e in ipairs(order) do
    local b = e[1]
    if b then
      b.bwChoice = { action = e[3], turn = turn }
      b.switchingOut = nil
    end
  end
  -- QUICK CLAW and CUSTAP, for a Pokemon about to use a move
  local first = {}
  for _, e in ipairs(order) do
    local b, act = e[1], e[3]
    if b and act and act.id and not act.special and alive(b) then
      local line = H().moveFirst(battle, b)
      if line then
        b.bwFirstTurn = turn
        first[b] = true
        battle:say(line)
      end
    end
  end
  -- first within the priority bracket: a stable pass over the speed order
  if next(first) then
    local keyed = {}
    for i, e in ipairs(order) do
      keyed[i] = { e = e, p = priorityOf(battle, e[3]), f = first[e[1]] and 1 or 0, i = i }
    end
    table.sort(keyed, function(a, b)
      if a.p ~= b.p then return a.p > b.p end
      if a.f ~= b.f then return a.f > b.f end
      return a.i < b.i
    end)
    for i, k in ipairs(keyed) do order[i] = k.e end
  end
  -- PURSUIT before the switch it is aimed at, at double power
  for si = 1, #order do
    local sw = order[si]
    local act = sw and sw[3]
    if act and (act.special == "aiSwitch" or act.special == "playerSwitch") then
      local leaver = sw[1]
      for pi = si + 1, #order do
        local pe = order[pi]
        if pe[1] and pe[1].isPlayer ~= leaver.isPlayer and isPursuit(battle, pe[3]) then
          local aimed = pe[2]
          if pe[1].isPlayer and battle.chosenTargets then aimed = battle.chosenTargets[pe[1].position] or aimed end
          if aimed == nil or aimed == leaver then
            table.remove(order, pi)
            local entry = { pe[1], leaver, pe[3] }
            table.insert(order, si, entry)
            leaver.switchingOut = true
            break
          end
        end
      end
    end
  end
  return order
end

-- ---------------------------------------------------------------------------
-- ACCURACY AND DAMAGE
-- ---------------------------------------------------------------------------

function R.accuracy(battle, move, user, target, accuracyRaw)
  if not (battle.bw and move and user and target) then return nil end
  -- TELEKINESIS: anything aimed at the lifted Pokemon hits (one-hit KOs
  -- excepted: their gate rolls on its own)
  if target.bwTelekinesis and (move.effectClass or 0) ~= 9 then return true end
  local mult = 1
  if (battle.bw.field.gravity or 0) > 0 then mult = mult * 5 / 3 end
  if user.bwMicle then
    user.bwMicle = nil
    mult = mult * 1.2
  end
  if mult == 1 then return nil end
  local base = accuracyRaw and (accuracyRaw * 100 / 255) or (move.accuracy or 100)
  local view = setmetatable({ accuracy = floor(base * mult) }, { __index = move })
  local Damage = require("src.battle.Damage")
  return Damage.accuracyRoll(battle.ruleset, view, user, target, battle.rng, nil, battle.data,
                             Wx().current(battle), battle.deepFog and battle:deepFog() or false)
end

-- Gen5MoveEffects.damage, before the engine's damage routine
function R.adjust(ctx, attacker, defender, mult)
  local battle = ctx.battle
  if ctx.user.bwMeFirst == turnOf(battle) then mult = mult * 1.5 end
  -- WONDER ROOM: every Pokemon's Defense and Sp. Def trade places
  if battle.bw and (battle.bw.field.wonderRoom or 0) > 0 and defender and defender.curStats then
    local stats = {}
    for k, v in pairs(defender.curStats) do stats[k] = v end
    stats.defense, stats.spdef = defender.curStats.spdef, defender.curStats.defense
    defender = setmetatable({ curStats = stats }, { __index = defender })
  end
  return attacker, defender, mult
end

-- ---------------------------------------------------------------------------
-- THE TURN'S END: a field token of our own
-- ---------------------------------------------------------------------------

local function landFuture(battle, side, pend)
  local victim
  for _, b in ipairs(activeList(battle)) do
    if sideIndex(b) == side and alive(b) and (pend.position == nil or b.position == pend.position) then victim = b end
  end
  if not victim then
    for _, b in ipairs(activeList(battle)) do if sideIndex(b) == side and alive(b) then victim = b end end
  end
  if not victim then return end
  local move = battle.data.moves[pend.moveId]
  sayNow(battle, T.set(battle, "tookAttack", victim, { nil, move and move.name or "" }))
  local user = pend.user
  local dmg, info = battle:computeDamage(user, victim, move, { rng = battle.rng, forceCrit = false })
  if not dmg or (info and info.typeMult == 0) then
    sayNow(battle, T.set(battle, "notAffected", victim))
    return
  end
  dmg = math.max(1, dmg)
  battle:applyDamage(victim, dmg)
  if info and info.typeMult and info.typeMult > 10 then sayNow(battle, T.std(battle, "superEffective"))
  elseif info and info.typeMult and info.typeMult < 10 then sayNow(battle, T.std(battle, "notVeryEffective")) end
  if victim.mon.hp <= 0 then battle:onFaint(victim) end
end

function R.upkeep(battle)
  if not battle.bw or battle.result then return end
  local turn = turnOf(battle)
  local field = battle.bw.field
  for _, b in ipairs(activeList(battle)) do
    -- ROLLOUT: the run stops on any turn it did not land
    if b.bwLockKind == "rollout" and not (b.bwRoll and b.bwRoll.turn == turn) then
      b.bwRoll = nil
      unlock(b)
    end
    -- UPROAR: locked while it lasts; a turn it did not run ends it
    if b.bwUproarInst then
      if b.bwUproarTurn ~= turn and b.uproarTurns then
        b.uproarTurns = nil
        sayNow(battle, T.set(battle, 718, b))
      end
      if b.uproarTurns and b.uproarTurns > 0 and alive(b) then
        lock(b, b.bwUproarInst, "uproar")
      else
        b.bwUproarInst, b.bwUproarTurn = nil, nil
        if b.bwLockKind == "uproar" then unlock(b) end
      end
    end
    -- SKY DROP: the lifted one comes down when its carrier is gone
    local by = b.bwSkyDropped
    if by and (not alive(by) or not onField(battle, by) or by.bwSkyDrop ~= b) then
      b.bwSkyDropped, b.invulnerable, b.hiddenAs = nil, nil, nil
      if alive(b) then sayNow(battle, T.set(battle, "freedSkyDrop", b)) end
    end
    -- GRAVITY holds everyone down while it lasts
    if (field.gravity or 0) > 0 then
      if not b.bwGrounded then b.bwGrounded, b.bwGravityGround = true, true end
    elseif b.bwGravityGround then
      b.bwGrounded, b.bwGravityGround = nil, nil
    end
  end
  -- FUTURE SIGHT / DOOM DESIRE
  local fut = battle.bw.future
  if fut then
    for side = 1, 2 do
      local pend = fut[side]
      if pend then
        pend.turns = pend.turns - 1
        if pend.turns <= 0 then
          fut[side] = nil
          landFuture(battle, side, pend)
        end
      end
    end
  end
end

function R.ensure(battle)
  local bw = battle.bw
  if not bw then return nil end
  if not bw.rulesToken and battle.field and battle.field.tokens then
    bw.rulesToken = { id = "bw_rules", onResidual = function(b) R.upkeep(b) end }
    table.insert(battle.field.tokens, bw.rulesToken)
  end
  return bw
end

-- ---------------------------------------------------------------------------
-- THE RECORDS: Gen5MoveEffects' partial effects, made whole
-- ---------------------------------------------------------------------------

local function F(spec) spec.kind = "full" return spec end
local function P(spec) spec.kind = "primary" return spec end

local function fail(ctx, text)
  ctx.battle:cancelMoveAnim()
  return { text or failed(ctx.battle) }
end

-- a damaging record's own pipeline, run from a `perform` (the record minus
-- its perform)
local function strike(ctx, rec)
  local plain = {}
  for k, v in pairs(rec) do if k ~= "perform" then plain[k] = v end end
  require("src.battle.EffectRegistry").runDamaging(ctx.battle, ctx, plain)
end

-- the charge moves charge THEMSELVES, so a Power Herb can cut the turn out
-- (the engine's charge turn has no seam between the line and the wait)
local function selfCharge(G5, old, opts)
  opts = opts or {}
  local spec = {}
  for k, v in pairs(old) do spec[k] = v end
  spec.charge = nil
  spec.perform = function(ctx, rec)
    local battle, user, move = ctx.battle, ctx.user, ctx.move
    -- the second turn: BattleState:performMove has already lifted the charge
    if user.bwCharged == ctx.moveInst and not user.charging
       and user.bwChargedTurn == turnOf(battle) - 1 then
      user.bwCharged, user.bwChargedTurn = nil, nil
      return strike(ctx, rec)
    end
    user.bwCharged, user.bwChargedTurn = nil, nil
    if opts.skipInSun and Wx().current(battle) == Wx().SUN then return strike(ctx, rec) end
    local Strings = require("src.core.Strings")
    local text = move.chargeText and Strings(move.chargeText, (user.isPlayer and "" or "Enemy ") .. user.name)
    local herbed = H().powerHerb(battle, user)
    if not herbed then battle:cancelMoveAnim() end
    if text then sayNow(battle, text) end
    if opts.onCharge then opts.onCharge(ctx) end
    if herbed then
      sayNow(battle, herbed)
      return strike(ctx, rec)
    end
    user.charging, user.chargeReady = ctx.moveInst, true
    user.bwCharged, user.bwChargedTurn = ctx.moveInst, turnOf(battle)
    if move.semiInvulnerable or opts.invulnerable then
      user.invulnerable = true
      user.hiddenAs = move.hiddenAs or "air"
    end
  end
  return F(spec)
end

-- ROLLOUT / ICE BALL: five turns, doubling, the user locked in
local function rollout()
  local function chain(ctx)
    local u, turn = ctx.user, turnOf(ctx.battle)
    local r = u.bwRoll
    if r and r.id == ctx.move.id and r.turn == turn - 1 then return r.n end
    return 0
  end
  return F({
    power = function(ctx)
      local mult = 2 ^ math.min(4, chain(ctx))
      if ctx.user.bwCurled then mult = mult * 2 end
      return (ctx.move.power or 30) * mult
    end,
    afterDamage = function(ctx, total)
      local u = ctx.user
      local n = chain(ctx)
      if total > 0 then n = n + 1 else n = 0 end
      if n > 0 and n < 5 and u.mon.hp > 0 then
        u.bwRoll = { id = ctx.move.id, turn = turnOf(ctx.battle), n = n }
        lock(u, ctx.moveInst, "rollout")
      else
        u.bwRoll = nil
        unlock(u)
      end
    end,
    onMiss = function(ctx) ctx.user.bwRoll = nil unlock(ctx.user) end,
  })
end

-- UPROAR: three turns, the user locked in, nobody sleeps
local function uproar()
  return F({ afterDamage = function(ctx, total)
    local battle, u = ctx.battle, ctx.user
    if not u.uproarTurns then
      u.uproarTurns = 3
      sayNow(battle, T.set(battle, "uproar", u))
      for _, b in ipairs(activeList(battle)) do
        if b.mon.status == "SLP" and alive(b) then
          b.mon.status, b.sleepTurns = nil, nil
          sayNow(battle, T.set(battle, 706, b))
        end
      end
    end
    u.bwUproarInst, u.bwUproarTurn = ctx.moveInst, turnOf(battle)
  end })
end

-- FUTURE SIGHT / DOOM DESIRE: the damage is worked out when it lands
local function futureSight()
  return F({ perform = function(ctx)
    local battle, user, target = ctx.battle, ctx.user, ctx.target
    battle.bw.future = battle.bw.future or {}
    local side = sideIndex(target)
    if battle.bw.future[side] then
      battle:cancelMoveAnim()
      sayNow(battle, failed(battle))
      return
    end
    R.ensure(battle)
    battle.bw.future[side] = { turns = 3, user = user, moveId = ctx.move.id, position = target.position }
    sayNow(battle, T.set(battle, ctx.move.id == 353 and "doomDesire" or "foresaw", user))
  end })
end

-- BEAT UP (Gen V): one strike per able, unstatused party member, each at
-- 5 + that member's base Attack / 10, on the user's Attack
local function beatUp(G5)
  return F({ perform = function(ctx, rec)
    local battle, user, target, move = ctx.battle, ctx.user, ctx.target, ctx.move
    local party = user.isPlayer and battle.game and battle.game.save and (battle.playerParty or battle.game.save.party)
                  or battle.enemyParty or {}
    local members = {}
    for _, mon in ipairs(party) do
      if (mon.hp or 0) > 0 and not mon.status and not mon.isEgg and not mon.egg then members[#members + 1] = mon end
    end
    if user.mon.status == nil then
      local seen = false
      for _, m in ipairs(members) do if m == user.mon then seen = true end end
      if not seen and alive(user) then table.insert(members, 1, user.mon) end
    end
    if #members == 0 then return sayNow(battle, failed(battle)), battle:cancelMoveAnim() end
    if target.protecting and move.protectAffected ~= false then
      battle:cancelMoveAnim()
      return sayNow(battle, T.set(battle, "protected", target))
    end
    if target.invulnerable or not battle:accuracyRoll(move, user, target) then
      battle:cancelMoveAnim()
      return sayNow(battle, T.set(battle, "avoided", target))
    end
    local total, hits, lastMult = 0, 0, 10
    for i, mon in ipairs(members) do
      if not alive(target) then break end
      local def = battle.data.pokemon and battle.data.pokemon[mon.species]
      local base = def and def.baseStats and def.baseStats.attack or 50
      local dmg, info = G5.damage(ctx, { power = function() return floor(base / 10) + 5 end })
      if not dmg then
        battle:cancelMoveAnim()
        return sayNow(battle, info)
      end
      local row
      if i == 1 then
        row = battle.moveAnimRow
      else
        battle.nextInsert = (battle.nextInsert or 0) + 1
        row = { anim = move.id, attackerIsPlayer = user.isPlayer, attackerPosition = user.position,
                targetPosition = target.position, animContext = { moveTurn = i - 1 } }
        table.insert(battle.queue, battle.nextInsert, row)
      end
      local dealt = battle:applyDamage(target, dmg, true)
      if row and dealt > 0 then row.hit = { sfx = "Damage", animType = user.isPlayer and 5 or 2 } end
      if info.crit then sayNow(battle, T.std(battle, "critical")) end
      total, hits, lastMult = total + dealt, hits + 1, info.typeMult or 10
    end
    if lastMult > 10 then sayNow(battle, T.std(battle, "superEffective"))
    elseif lastMult < 10 then sayNow(battle, T.std(battle, "notVeryEffective")) end
    sayNow(battle, T.std(battle, "hitTimes", { count = hits }))
    if rec.afterDamage then rec.afterDamage(ctx, total) end
    if total > 0 and battle.shellBellDrain then
      battle:shellBellDrain(user, total)
      if alive(target) then battle:holdItemTrigger(target, "hit") end
    end
    if target.mon.hp <= 0 then battle:onFaint(target) end
  end })
end

-- FOLLOW ME / RAGE POWDER / HELPING HAND / ALLY SWITCH
local function doubles()
  return P({ run = function(ctx)
    local battle, user = ctx.battle, ctx.user
    if not isDouble(battle) then return fail(ctx) end
    local m = ctx.move.bwEffect
    local partner = battle.partnerOf and battle:partnerOf(user)
    if m == 176 then
      if not alive(partner) then return fail(ctx) end
      partner.bwHelped = turnOf(battle)
      return { T.set(battle, 1044, user, { nil, partner.name }) }
    end
    if m == 172 then
      sideState(battle, user).center = { who = user, turn = turnOf(battle) }
      return { T.set(battle, "centerOfAttention", user) }
    end
    if m == 307 then
      if not alive(partner) then return fail(ctx) end
      local a, b = user.position, partner.position
      battle:placeBattler(b, user)
      battle:placeBattler(a, partner)
      -- the trainer's bookkeeping of which party member stands where
      if not user.isPlayer and battle.enemyIndex and battle.enemyIndexRight then
        battle.enemyIndex, battle.enemyIndexRight = battle.enemyIndexRight, battle.enemyIndex
      end
      return { T.set(battle, 1137, user, { nil, partner.name }) }
    end
    return fail(ctx)
  end })
end

-- SUCKER PUNCH: the target must be about to use a damaging move
local function suckerPunch()
  return F({ gate = function(ctx)
    local battle, t = ctx.battle, ctx.target
    local turn = turnOf(battle)
    if t.bwMovedTurn == turn then return false, failed(battle) end
    local c = t.bwChoice
    local act = c and c.turn == turn and c.action
    local d = act and act.id and not act.special and battle.data.moves[act.id]
    if not (d and (d.power or 0) > 0 and d.class ~= "status") then return false, failed(battle) end
    return true
  end })
end

-- ME FIRST: the target's chosen damaging move, first and at x1.5
local ME_FIRST_NO = { [448] = true, [68] = true, [343] = true, [264] = true, [382] = true,
                      [368] = true, [243] = true, [165] = true, [168] = true }
local function meFirst()
  return F({ callsMove = function(ctx)
    local battle, user, t = ctx.battle, ctx.user, ctx.target
    local turn = turnOf(battle)
    local c = t.bwChoice
    local act = c and c.turn == turn and c.action
    local d = act and act.id and not act.special and battle.data.moves[act.id]
    if t.bwMovedTurn == turn or not d or (d.power or 0) == 0 or d.class == "status"
       or ME_FIRST_NO[act.id] then
      sayNow(battle, failed(battle))
      return nil
    end
    user.bwMeFirst = turn
    return act.id
  end })
end

-- NATURE POWER: by the battle's terrain
local function naturePower()
  return F({ callsMove = function(ctx)
    local id = R.naturePowerMove(ctx.battle)
    sayNow(ctx.battle, T.std(ctx.battle, "naturePower", { moveName(ctx.battle, id) }))
    return id
  end })
end

-- GRAVITY: the field timer, and everything in the air comes down
local function gravity(old)
  return P({ run = function(ctx)
    local battle = ctx.battle
    local f = battle.bw.field
    if (f.gravity or 0) > 0 then return fail(ctx) end
    f.gravity = 5
    R.ensure(battle)
    local out = { T.std(battle, "gravity") }
    for _, b in ipairs(activeList(battle)) do
      if alive(b) then
        local up = hasType(b, "FLYING") or Abil().of(b) == "LEVITATE" or b.bwMagnetRise or b.bwTelekinesis
                   or (b.invulnerable and b.hiddenAs == "air")
        if b.invulnerable and b.hiddenAs == "air" then
          b.charging, b.chargeReady, b.invulnerable, b.hiddenAs, b.bwCharged = nil, nil, nil, nil, nil
        end
        b.bwMagnetRise, b.bwTelekinesis = nil, nil
        if not b.bwGrounded then b.bwGrounded, b.bwGravityGround = true, true end
        if up then out[#out + 1] = T.set(battle, 1083, b) end
      end
    end
    return out
  end })
end

-- TELEKINESIS: not on Diglett, Dugtrio or a rooted Pokemon
local function telekinesis(old)
  local run = old.run
  return P({ foe = true, run = function(ctx)
    local t = ctx.target
    local sp = t.mon and tonumber(t.mon.species)
    if sp == 50 or sp == 51 or t.ingrained or (ctx.battle.bw.field.gravity or 0) > 0 then return fail(ctx) end
    return run(ctx)
  end })
end

-- SKY DROP: the target is carried up with the user and dropped next turn
local function skyDrop()
  return F({ perform = function(ctx, rec)
    local battle, user, target = ctx.battle, ctx.user, ctx.target
    local held = user.bwSkyDrop
    if held and user.bwCharged == ctx.moveInst and not user.charging
       and user.bwChargedTurn == turnOf(battle) - 1 then
      user.bwCharged, user.bwChargedTurn, user.bwSkyDrop = nil, nil, nil
      if held.bwSkyDropped == user then held.bwSkyDropped, held.invulnerable, held.hiddenAs = nil, nil, nil end
      if alive(held) and onField(battle, held) then
        ctx.target = held
        return strike(ctx, rec)
      end
      battle:cancelMoveAnim()
      return sayNow(battle, failed(battle))
    end
    user.bwCharged, user.bwSkyDrop = nil, nil
    local weight = tonumber(target.def and target.def.weight) or 0
    if target.substituteHP or target.invulnerable or weight >= 2000 or target == user
       or (battle.bw.field.gravity or 0) > 0 then
      battle:cancelMoveAnim()
      return sayNow(battle, failed(battle))
    end
    if target.protecting then
      battle:cancelMoveAnim()
      return sayNow(battle, T.set(battle, "protected", target))
    end
    if not battle:accuracyRoll(ctx.move, user, target) then
      battle:cancelMoveAnim()
      return sayNow(battle, T.set(battle, "avoided", target))
    end
    battle:cancelMoveAnim()
    user.charging, user.chargeReady, user.bwCharged = ctx.moveInst, true, ctx.moveInst
    user.bwChargedTurn = turnOf(battle)
    user.invulnerable, user.hiddenAs = true, "air"
    user.bwSkyDrop = target
    target.bwSkyDropped = user
    target.invulnerable, target.hiddenAs = true, "air"
    R.ensure(battle)
    sayNow(battle, T.pair(battle, "skyDrop", user, target))
  end })
end

-- MIMIC (Gen V): the target's last move, at its full PP, until it leaves
local MIMIC_NO = { [102] = true, [165] = true, [166] = true, [448] = true, [144] = true }
local function mimic()
  return F({ perform = function(ctx)
    local battle, user, target, inst = ctx.battle, ctx.user, ctx.target, ctx.moveInst
    local last = target.lastMove
    local d = last and battle.data.moves[last]
    local known = false
    for _, mv in ipairs(user.curMoves or {}) do if mv.id == last then known = true end end
    local slot
    for i, mv in ipairs(user.curMoves or {}) do if mv == inst then slot = i end end
    if not slot and not ctx.isCalled then
      for i, mv in ipairs(user.curMoves or {}) do if mv.id == inst.id then slot = i break end end
    end
    if not d or MIMIC_NO[last] or known or not slot or target.substituteHP then
      battle:cancelMoveAnim()
      return sayNow(battle, failed(battle))
    end
    local entry = user.curMoves[slot]
    battle.mimicRestores = battle.mimicRestores or {}
    table.insert(battle.mimicRestores, { battler = user, entry = entry, id = entry.id, pp = entry.pp })
    entry.id, entry.pp, entry.mimic = last, tonumber(d.pp) or 5, true
    sayNow(battle, T.set(battle, 688, user, { nil, d.name }))
  end })
end

-- the binding moves: Grip Claw's seven turns, Binding Band's eighth
local function binding(old)
  local after = old.afterDamage
  local spec = {}
  for k, v in pairs(old) do spec[k] = v end
  spec.afterDamage = function(ctx, total)
    local t = ctx.target
    local was = t.bwBound
    if after then after(ctx, total) end
    if t.bwBound and t.bwBound ~= was then
      t.bwBound.turns = H().bindTurns(ctx.battle, ctx.user)
      t.bwBound.div = H().bindDivisor(ctx.user)
    end
  end
  return F(spec)
end

-- the weather moves: a rock makes it eight turns
local function weatherMove(old, kind)
  local run = old.run
  return P({ run = function(ctx)
    local out = run(ctx)
    local W = Wx()
    local field = ctx.battle.field
    if field and field.weather == W[kind] and not field.weatherPermanent then
      local extra = H().weatherTurns(ctx.user, kind)
      if extra > 0 and (field.weatherTurns or 0) <= W.TURNS then
        field.weatherTurns = (field.weatherTurns or W.TURNS) + extra
      end
    end
    return out
  end })
end

-- ATTRACT: a Destiny Knot passes it back
local function attract(old)
  local run = old.run
  return P({ foe = true, run = function(ctx)
    local out = run(ctx)
    local line = H().destinyKnot(ctx.battle, ctx.target)
    if line then out[#out + 1] = line end
    return out
  end })
end

-- Fling / Natural Gift under Magic Room
local function noMagicRoom(old)
  local gate = old.gate
  local spec = {}
  for k, v in pairs(old) do spec[k] = v end
  spec.gate = function(ctx)
    if (ctx.battle.bw.field.magicRoom or 0) > 0 then return false, failed(ctx.battle) end
    return gate(ctx)
  end
  return F(spec)
end

-- Low Kick / Grass Knot and Heavy Slam / Heat Crash weigh a Float Stone
local function weightOf(b)
  local w = tonumber(b and b.def and b.def.weight) or 1
  w = w - (b.bwWeightLoss or 0)
  local ab = Abil().of(b)
  if ab == "HEAVY_METAL" then w = w * 2 end
  if ab == "LIGHT_METAL" then w = floor(w / 2) end
  w = H().weight(b, math.max(1, w))
  return math.max(1, w)
end
R.weightOf = weightOf

-- the engine's lines for Uproar and Future Sight, in the cartridge's words
local function installText()
  if R._patterns == T.PATTERNS then return end
  R._patterns = T.PATTERNS
  local function who(name)
    if name:sub(1, 6) == "Enemy " then return { name = name:sub(7), isPlayer = false } end
    return { name = name, isPlayer = true }
  end
  table.insert(T.PATTERNS, 1, { "^(.-) calmed down%.$", function(battle, a) return T.set(battle, 718, who(a)) end })
  table.insert(T.PATTERNS, 1, { "^(.-) is making\nan UPROAR!$", function(battle, a) return T.set(battle, 715, who(a)) end })
  table.insert(T.PATTERNS, 1, { "^(.-) woke up in\nthe UPROAR!$", function(battle, a) return T.set(battle, 706, who(a)) end })
end

function R.install(G5)
  if R.installed == G5 then return end
  R.installed = G5
  local DEF = G5.DEF
  G5.adjust = R.adjust
  installText()
  -- the partial effects
  DEF.BW_ROLLOUT = rollout()
  DEF.BW_UPROAR = uproar()
  if DEF.BW_PURSUIT then DEF.BW_PURSUIT.status, DEF.BW_PURSUIT.note = nil, nil end
  DEF.BW_FUTURE_SIGHT = futureSight()
  DEF.BW_BEAT_UP = beatUp(G5)
  DEF.BW_FAIL_IN_SINGLES = doubles()
  DEF.BW_NATURE_POWER = naturePower()
  DEF.BW_SUCKER_PUNCH = suckerPunch()
  DEF.BW_ME_FIRST = meFirst()
  DEF.BW_GRAVITY = gravity(DEF.BW_GRAVITY)
  DEF.BW_TELEKINESIS = telekinesis(DEF.BW_TELEKINESIS)
  DEF.BW_SKY_DROP = skyDrop()
  DEF.BW_MIMIC = mimic()
  for _, name in ipairs({ "BW_IMPRISON", "BW_EMBARGO", "BW_WONDER_ROOM", "BW_MAGIC_ROOM" }) do
    if DEF[name] then DEF[name].status, DEF[name].note = nil, nil end
  end
  -- the held items' parts of the records
  DEF.BW_BIND = binding(DEF.BW_BIND)
  DEF.BW_WHIRLPOOL = binding(DEF.BW_WHIRLPOOL)
  DEF.BW_RAIN_DANCE = weatherMove(DEF.BW_RAIN_DANCE, "RAIN")
  DEF.BW_SUNNY_DAY = weatherMove(DEF.BW_SUNNY_DAY, "SUN")
  DEF.BW_SANDSTORM = weatherMove(DEF.BW_SANDSTORM, "SANDSTORM")
  DEF.BW_HAIL = weatherMove(DEF.BW_HAIL, "HAIL")
  DEF.BW_ATTRACT = attract(DEF.BW_ATTRACT)
  DEF.BW_FLING = noMagicRoom(DEF.BW_FLING)
  DEF.BW_NATURAL_GIFT = noMagicRoom(DEF.BW_NATURAL_GIFT)
  DEF.BW_LOW_KICK = F({ power = function(ctx)
    local w = weightOf(ctx.target)
    if w < 100 then return 20 elseif w < 250 then return 40 elseif w < 500 then return 60
    elseif w < 1000 then return 80 elseif w < 2000 then return 100 end
    return 120
  end })
  DEF.BW_HEAVY_SLAM = F({ power = function(ctx)
    local r = weightOf(ctx.user) / math.max(1, weightOf(ctx.target))
    if r >= 5 then return 120 elseif r >= 4 then return 100 elseif r >= 3 then return 80
    elseif r >= 2 then return 60 end
    return 40
  end })
  -- Power Herb: the charge moves charge themselves
  DEF.BW_CHARGE = selfCharge(G5, DEF.BW_CHARGE)
  DEF.BW_SOLARBEAM = selfCharge(G5, DEF.BW_SOLARBEAM, { skipInSun = true })
  DEF.BW_FLY = selfCharge(G5, DEF.BW_FLY, { invulnerable = true })
  DEF.BW_SHADOW_FORCE = selfCharge(G5, DEF.BW_SHADOW_FORCE, { invulnerable = true })
  DEF.BW_SKULL_BASH = selfCharge(G5, { kind = "full" }, { onCharge = function(ctx)
    for _, line in ipairs((G5.changeStats(ctx.battle, ctx.user, { { "defense", 1 } }, false))) do
      sayNow(ctx.battle, line)
    end
  end })
end

return R
