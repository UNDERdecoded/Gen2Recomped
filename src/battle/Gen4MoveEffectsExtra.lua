-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE EIGHT HOENN EFFECTS SINNOH STILL RAN AS "But, it failed!" (or a bare
-- hit): Helping Hand 176, Follow Me 172, Imprison 192, Magic Coat 183,
-- Snatch 195, Assist 180, Nature Power 173, Secret Power 197.
-- src/battle/Gen3MoveEffects.lua left them out on purpose (singles-only
-- engine, no interception step); the engine has doubles now, and this file
-- adds the interception step for Platinum / HGSS.
--
-- READ FROM CODE (pokeplatinum res/battle/scripts/effects/effect_script_NNNN.s
-- and src/battle/battle_script.c):
--   BtlCmd_TryHelpingHand   doubles only; the partner alive, not switching,
--                           not done this turn, neither already helped ->
--                           the partner's power x15/10 this turn
--                           (CalcMoveDamage `turnFlags.helpingHand`)
--   BtlCmd_FollowMe         the side's followMe user draws single-target moves
--   BtlCmd_TryImprison      fails unless a foe knows one of the user's moves;
--                           those moves are then sealed for the other side
--   BtlCmd_TrySetMagicCoat  fails when the user is the last to move; this turn
--                           a MOVE_FLAG_CAN_MAGIC_COAT (bit 2) move aimed at it
--                           is bounced back
--   BtlCmd_TrySnatch        fails when last; the next MOVE_FLAG_CAN_SNATCH
--                           (bit 3) move anybody else uses this turn is taken
--   BtlCmd_TryAssist        a random move of the user's OTHER party members,
--                           not an invoker and Metronome-able
--   BtlCmd_GetTerrainMove   sTerrainMove by battle terrain
--   BtlCmd_GetTerrainSecondaryEffect  sTerrainSideEffect by battle terrain
-- Every record answers only on a Gen 4 cartridge; elsewhere (Emerald) it does
-- what it did before this file: a status move fails, Secret Power just hits.

local Strings = require("src.core.Strings")

local M = {}
local function G4ref() return M.G4 or require("src.battle.Gen4MoveEffects") end

local FAILED = "But, it failed!"

local function gen4() return require("src.core.GameVersion").isGen4() == true end
local function genNo()
  local ok, g = pcall(function() local V = require("src.core.GameVersion") return V.generation(V.get()) end)
  return ok and tonumber(g) or 0
end
-- Ruby / Sapphire / Emerald / FireRed / LeafGreen run the same rules (pokeemerald
-- battle_script_commands.c: Cmd_trysethelpinghand, _tryimprison,
-- _assistattackselect, _trysetmagiccoat, _trysetsnatch, _callenvironmentattack,
-- _getsecretpowereffect; Cmd_setreflect / _setlightscreen 5 turns on the
-- side; Cmd_setrain & co fail in their own weather; the bind 3..6 / 16ths)
local function gen34() local g = genNo() return g == 3 or g == 4 end
M.gen34 = gen34

-- the effect state: Gen 4 keeps it in Gen4MoveEffects' g4fx, Gen 3 in its own
-- table (so nothing of Sinnoh's -- Gravity, Tailwind, Stealth Rock -- is ever
-- switched on for a Hoenn battle)
local function ST(battle)
  if gen4() then return G4ref().state(battle) end
  local s = battle.g3x
  if not s then
    s = { field = {}, sides = { [true] = {}, [false] = {} } }
    battle.g3x = s
  end
  return s
end
M.state = ST
local function peek(battle) return battle.g4fx or battle.g3x end
local function turnOf(battle) return battle.turnCount or 0 end
local function who(b) return b.isPlayer and b.name or ("Enemy " .. b.name) end
local function alive(b) return b and b.mon and (b.mon.hp or 0) > 0 end
local function bit(flags, n) return math.floor((tonumber(flags) or 0) / 2 ^ n) % 2 == 1 end

M.FLAG_MAGIC_COAT, M.FLAG_SNATCH = 2, 3

local function active(battle)
  local out = {}
  if battle.sides then
    for s = 1, 2 do
      local side = battle.sides[s]
      for _, b in ipairs(side and side.battlers or {}) do
        if alive(b) then out[#out + 1] = b end
      end
    end
  end
  if #out == 0 then
    for _, b in ipairs({ battle.player, battle.enemy }) do if alive(b) then out[#out + 1] = b end end
  end
  return out
end
M.active = active

local function partnerOf(battle, b)
  if not (battle.isDouble and battle:isDouble()) then return nil end
  local p = battle.partnerOf and battle:partnerOf(b)
  if alive(p) then return p end
  return nil
end

-- every other battler on the field has had its turn
local function lastToMove(battle, user)
  for _, b in ipairs(active(battle)) do
    if b ~= user and b.actedTurn ~= turnOf(battle) then return false end
  end
  return true
end

-- sTerrainMove / sTerrainSideEffect, by Gen4Battle.TERRAINS name
M.TERRAIN_MOVE = {
  plain = 89, sand = 89, grass = 402, puddle = 402, mountain = 157, cave = 157,
  snow = 59, water = 56, ice = 58, building = 161, great_marsh = 426, bridge = 403,
}
M.TERRAIN_SPECIAL_MOVE = 161
M.TERRAIN_EFFECT = {
  plain = { "stat", "accuracy" }, sand = { "stat", "accuracy" },
  grass = { "status", "SLP" }, puddle = { "status", "SLP" },
  mountain = { "flinch" }, cave = { "flinch" },
  snow = { "status", "FRZ" }, ice = { "status", "FRZ" },
  water = { "stat", "attack" }, building = { "status", "PAR" },
  great_marsh = { "stat", "speed" }, bridge = { "stat", "evasion" },
}
M.TERRAIN_SPECIAL_EFFECT = { "status", "PAR" }

M.TERRAIN_MOVE3 = {
  GRASS = "STUN_SPORE", LONG_GRASS = "RAZOR_LEAF", SAND = "EARTHQUAKE", UNDERWATER = "HYDRO_PUMP",
  WATER = "SURF", POND = "BUBBLE_BEAM", MOUNTAIN = "ROCK_SLIDE", CAVE = "SHADOW_BALL",
  BUILDING = "SWIFT", PLAIN = "SWIFT",
}
-- sMovesForbiddenToCopy + IsInvalidForSleepTalkOrAssist (pokeemerald), by name
M.GEN3_NO_ASSIST = {}
for _, n in ipairs({ "METRONOME", "STRUGGLE", "SKETCH", "MIMIC", "COUNTER", "MIRROR_COAT",
                     "PROTECT", "DETECT", "ENDURE", "DESTINY_BOND", "SLEEP_TALK", "THIEF",
                     "FOLLOW_ME", "SNATCH", "HELPING_HAND", "COVET", "TRICK", "FOCUS_PUNCH",
                     "ASSIST", "MIRROR_MOVE", "NONE" }) do
  M.GEN3_NO_ASSIST[n] = true
end
M.TERRAIN_EFFECT3 = {
  GRASS = { "status", "PSN" }, LONG_GRASS = { "status", "SLP" }, SAND = { "stat", "accuracy" },
  UNDERWATER = { "stat", "defense" }, WATER = { "stat", "attack" }, POND = { "stat", "speed" },
  MOUNTAIN = { "confuse" }, CAVE = { "flinch" },
}
function M.terrain3(battle)
  if battle.g3TerrainName then return battle.g3TerrainName end
  local ok, t = pcall(function() return require("src.battle.Gen3Battle").terrainFor(battle.game) end)
  t = ok and t or "PLAIN"
  battle.g3TerrainName = t
  return t
end

function M.terrain(battle)
  if battle.g4TerrainName then return battle.g4TerrainName end
  local ok, t = pcall(function() return require("src.battle.Gen4Battle").terrainFor(battle.game) end)
  t = ok and t or "plain"
  battle.g4TerrainName = t
  return t
end

-- ---------------------------------------------------------------------------
-- the records
-- ---------------------------------------------------------------------------

function M.install(G4, h)
  M.G4 = G4
  local P, F, S = G4.primary, G4.full, G4.secondary

  P.HELPING_HAND_EFFECT = function(battle, user)
    if not gen34() then return { Strings(FAILED) } end
    ST(battle)
    local partner = partnerOf(battle, user)
    local t = turnOf(battle)
    if not partner or (gen4() and (partner.actedTurn == t or partner.g4Gone or partner.switchingOut))
       or user.g4HelpedTurn == t or partner.g4HelpedTurn == t then
      return { Strings(FAILED) }
    end
    partner.g4HelpedTurn = t
    return { Strings("%s is ready to\nhelp %s!", who(user), who(partner)) }
  end

  P.FOLLOW_ME_EFFECT = function(battle, user)
    if not gen34() then return { Strings(FAILED) } end
    local s = ST(battle)
    s.sides[user.isPlayer and true or false].followMe = { who = user, turn = turnOf(battle) }
    return { Strings("%s became the\ncenter of attention!", who(user)) }
  end

  P.IMPRISON_EFFECT = function(battle, user)
    if not gen34() then return { Strings(FAILED) } end
    ST(battle)
    if user.g4Imprison then return { Strings(FAILED) } end
    local mine = {}
    for _, mv in ipairs(user.curMoves or {}) do if mv.id then mine[mv.id] = true end end
    local shared = false
    for _, b in ipairs(active(battle)) do
      if b.isPlayer ~= user.isPlayer then
        for _, mv in ipairs(b.curMoves or {}) do if mine[mv.id] then shared = true end end
      end
    end
    if not shared then return { Strings(FAILED) } end
    user.g4Imprison = true
    return { Strings("%s sealed the\nopponent's move(s)!", who(user)) }
  end

  P.MAGIC_COAT_EFFECT = function(battle, user)
    if not gen34() then return { Strings(FAILED) } end
    ST(battle)
    if lastToMove(battle, user) then return { Strings(FAILED) } end
    user.g4MagicCoatTurn = turnOf(battle)
    return { Strings("%s shrouded\nitself with\nMAGIC COAT!", who(user)) }
  end

  P.SNATCH_EFFECT = function(battle, user)
    if not gen34() then return { Strings(FAILED) } end
    ST(battle)
    if lastToMove(battle, user) then return { Strings(FAILED) } end
    user.g4SnatchTurn = turnOf(battle)
    return { Strings("%s waits for a\ntarget to make\na move!", who(user)) }
  end

  F.ASSIST_EFFECT = {
    callsMove = function(ctx)
      local battle, user = ctx.battle, ctx.user
      if not gen34() then ctx.say(Strings(FAILED)) return nil end
      ST(battle)
      local party = require("src.battle.Gen5MoveEffects").sideParty(battle, user) or {}
      local pool = {}
      for _, mon in ipairs(party) do
        if mon ~= user.mon and not mon.isEgg and not mon.egg then
          for _, mv in ipairs(mon.moves or {}) do
            local id = mv.id
            local ok
            if type(id) == "string" then ok = not M.GEN3_NO_ASSIST[id] and h.moveDef(battle, id) ~= nil
            else ok = id ~= 0 and not h.INVOKER[id] and h.moveDef(battle, id) ~= nil and h.canBeCalled(battle, user, id) end
            if id and ok then
              pool[#pool + 1] = id
            end
          end
        end
      end
      if #pool == 0 then ctx.say(Strings(FAILED)) return nil end
      return pool[battle.rng(1, #pool)]
    end,
  }

  F.NATURE_POWER_EFFECT = {
    callsMove = function(ctx)
      local battle = ctx.battle
      if not gen34() then ctx.say(Strings(FAILED)) return nil end
      local id
      if gen4() then id = M.TERRAIN_MOVE[M.terrain(battle)] or M.TERRAIN_SPECIAL_MOVE
      else id = M.TERRAIN_MOVE3[M.terrain3(battle)] or "SWIFT" end
      local d = h.moveDef(battle, id)
      ctx.say(Strings("%s turned into\n%s!", ctx.move.name or "NATURE POWER", d and d.name or "?"))
      return id
    end,
  }

  -- SECRET POWER: an ordinary hit; the side effect is the terrain's, on the
  -- move's own chance (30)
  S.SECRET_POWER_EFFECT = function(battle, user, target, move)
    if not gen34() then return {} end
    if not alive(target) then return {} end
    if not h.activates(battle, user, target, tonumber(move and move.effectChance) or 30) then return {} end
    local e
    if gen4() then e = M.TERRAIN_EFFECT[M.terrain(battle)] or M.TERRAIN_SPECIAL_EFFECT
    else e = M.TERRAIN_EFFECT3[M.terrain3(battle)] or { "status", "PAR" } end
    if e[1] == "confuse" then
      if target.confusedTurns or target.substituteHP then return {} end
      if require("src.battle.Abilities").refusesStatus(target, "CONFUSION") then return {} end
      target.confusedTurns = battle.rng(2, 5)
      return { Strings("%s became\nconfused!", who(target)) }
    end
    if e[1] == "status" then return h.inflict(battle, user, target, e[2], move) end
    if e[1] == "flinch" then h.flinch(target) return {} end
    return h.stage(battle, target, e[2], -1, true)
  end
end

-- ---------------------------------------------------------------------------
-- the seams (BattleState)
-- ---------------------------------------------------------------------------

-- Gen4Damage: Helping Hand's x15/10 on the helped Pokemon's move this turn
function M.helped(battle, attacker)
  return battle ~= nil and attacker ~= nil and attacker.g4HelpedTurn == turnOf(battle)
end

-- Targeting.resolve (Platinum / HGSS doubles): Follow Me draws every
-- single-target move from the other side; Lightning Rod / Storm Drain draw an
-- Electric / Water one (BattleSystem_..Redirect: the ability's holder on the
-- field, not the user, not the user's own side in Gen 4)
function M.redirect(battle, user, move)
  if not (battle and user and move) then return nil end
  local s = peek(battle)
  local t = turnOf(battle)
  if s then
    local fm = s.sides[not user.isPlayer]
    local c = fm and fm.followMe
    if c and c.turn == t and alive(c.who) and c.who.isPlayer ~= user.isPlayer then return c.who end
  end
  return M.abilityRedirect(battle, user, move)
end

function M.abilityRedirect(battle, user, move)
  local A = require("src.battle.Abilities")
  local mtype = A.normalizeType(move.type)
  local want = (mtype == "ELECTRIC" and "LIGHTNING_ROD") or (mtype == "WATER" and "STORM_DRAIN") or nil
  if not want or A.of(user) == "MOLD_BREAKER" then return nil end
  for _, b in ipairs(active(battle)) do
    -- (Hoenn spells it LIGHTNINGROD: pokeemerald redirects too, no immunity)
    local ab = A.of(b)
    if ab == "LIGHTNINGROD" then ab = "LIGHTNING_ROD" end
    if b ~= user and ab == want then
      -- Gen 4 draws only from the other side; Gen 5 from anyone (INFERRED)
      if b.isPlayer ~= user.isPlayer or battle.bw then return b end
    end
  end
  return nil
end

-- Imprison: is this move sealed for `b`? the imprisoner, or nil
function M.sealedBy(battle, b, moveId)
  for _, x in ipairs(active(battle)) do
    if x.isPlayer ~= b.isPlayer and x.g4Imprison then
      for _, mv in ipairs(x.curMoves or {}) do if mv.id == moveId then return x end end
    end
  end
  return nil
end
-- THE CHOICE LOCK, Hoenn and Sinnoh (pokeemerald battle_util.c: choicedMove,
-- BattleScript_SelectingNotAllowedMoveChoiceItem; pokeplatinum
-- CHECK_INVALID_CHOICE_ITEM): once a Choice item's holder has used a move it
-- may select nothing else until it leaves the field or loses the item. The
-- port had no lock at all before Black / White.
function M.choiceHeld(b)
  if not (b and b.mon) then return false end
  if gen4() then return require("src.battle.Gen5HoldItems").choiceItem(b) == true end
  local e = require("src.battle.HoldItems").effectOf(b)
  return e == "CHOICE_BAND"
end
function M.choiceLock(battle, user, action)
  if not gen34() or not (action and action.id) or action.special or action.struggle then return end
  -- a lock whose item is gone (Trick, Knock Off, Thief) is released here, as
  -- the move runs -- on both machines of a link battle.  The menu used to
  -- release it, which only ever touched the menu's own Pokemon.
  if user.g34Choice ~= nil and not M.choiceHeld(user) then user.g34Choice = nil end
  if user.g34Choice == nil and M.choiceHeld(user) then user.g34Choice = action.id end
end
function M.choiceRefusal(battle, b, d)
  local locked = b and b.g34Choice
  if not (locked and d and d.id) then return nil end
  -- (read-only: the lock is released in choiceLock, not by asking)
  if not M.choiceHeld(b) then return nil end
  local known = false
  for _, m in ipairs(b.curMoves or {}) do if m.id == locked and (m.pp or 0) > 0 then known = true end end
  if not known then return nil end
  if d.id == locked then return nil end
  local itemId = b.mon.item or b.mon.heldItem
  local idef = battle.data and battle.data.items and battle.data.items[itemId]
  local mdef = battle.data and battle.data.moves and battle.data.moves[locked]
  return Strings("The %s allows the\nuse of only\n%s!", idef and idef.name or "item", mdef and mdef.name or "one move")
end

-- the move menu / the AI's list / the Struggle test, on a Hoenn cartridge
-- (Platinum / HGSS ask Gen4MoveEffects.menuRefusal): the line, or nil
function M.menuRefusal(battle, b, d)
  if not (battle and battle.g3x and b and d and d.id) then return nil end
  if M.sealedBy(battle, b, d.id) then return M.sealedLine(b, d) end
  return M.choiceRefusal(battle, b, d)
end

function M.beforeMove(battle, user, action)
  if not (action and action.id) or action.special or action.struggle then return false end
  if not M.sealedBy(battle, user, action.id) then return false end
  local d = battle.data and battle.data.moves and battle.data.moves[action.id]
  battle:sayNext(M.sealedLine(user, d))
  return true
end
function M.sealedLine(b, d)
  return Strings("%s can't use the\nsealed %s!", who(b), d and d.name or "move")
end

-- performMove, before a status move's accuracy and effect: Snatch takes a
-- snatchable move, Magic Coat bounces a reflectable one. Returns the new
-- (user, target) pair and says the line, or nil.
function M.intercept(battle, user, target, move)
  if not (gen34() and peek(battle) and move) then return nil end
  local t = turnOf(battle)
  if bit(move.flags, M.FLAG_SNATCH) then
    for _, b in ipairs(active(battle)) do
      if b ~= user and b.g4SnatchTurn == t then
        b.g4SnatchTurn = nil
        battle:sayNext(Strings("%s snatched\n%s's move!", who(b), who(user)))
        local newTarget = (target == user) and b or target
        return b, newTarget
      end
    end
  end
  if bit(move.flags, M.FLAG_MAGIC_COAT) and target and target ~= user
     and target.g4MagicCoatTurn == t and alive(target) then
    battle:sayNext(Strings("%s's %s\nwas bounced back\nby MAGIC COAT!", who(user), move.name or "move"))
    return target, user
  end
  return nil
end


-- ===========================================================================
-- THE SIDE CONDITIONS AND BINDING, SINNOH'S WAY (battle parity pass 2)
-- ===========================================================================
-- Platinum / HGSS ran Reflect / Light Screen as Gen 1's battler flags (no
-- timer: up until the Pokemon left) and Wrap / Bind / Fire Spin as Gen 1's
-- lock (the user repeating the move, the target unable to act). READ FROM
-- CODE (pokeplatinum):
--   BtlCmd_TryReflect / TryLightScreen  a SIDE condition, fails if already up,
--     NUM_SCREEN_TURNS 5, + the Light Clay's parameter (3); counted down at the
--     end of each turn (battle_controller_player.c), "...wore off!"
--   effect_script_0136/0137/0115/0164   Rain Dance / Sunny Day / Sandstorm /
--     Hail fail when that weather is already up; 5 turns, + the rock's
--     parameter (3)
--   subscript_bind_start                3..6 turns (Random 3, 3), 6 with a
--     Grip Claw; MON_COND_CHECK_STATE_BIND: each end of turn the count drops,
--     then maxHP/16 ("X is hurt by Wrap!") or "X was freed from Wrap!"; the
--     user moves on freely, the target cannot switch or flee (Shed Shell frees)

local function heldEffect(b)
  local H = require("src.battle.Gen5HoldItems")
  local he, param = H.held(b)
  return he, param or 0, H.HE
end

local function sideState(battle, b)
  return ST(battle).sides[b.isPlayer and true or false]
end

-- the battlers standing on b's side
local function sideBattlers(battle, isPlayer)
  local out = {}
  for _, x in ipairs(active(battle)) do if x.isPlayer == isPlayer then out[#out + 1] = x end end
  return out
end

-- mirror the side's screens onto its battlers (Damage reads battler flags)
function M.syncScreens(battle)
  local s = peek(battle)
  if not s then return end
  for _, isPlayer in ipairs({ true, false }) do
    local side = s.sides[isPlayer]
    for _, b in ipairs(sideBattlers(battle, isPlayer)) do
      for _, key in ipairs({ "reflect", "lightScreen" }) do
        local mirror = b.g4ScreenMirror or {}
        b.g4ScreenMirror = mirror
        -- a flag this file set and something else cleared (Brick Break,
        -- Defog) broke the side's screen
        if mirror[key] and not b[key] then side[key] = nil end
        if (side[key] or 0) > 0 then b[key], mirror[key] = true, true
        elseif mirror[key] then b[key], mirror[key] = nil, nil end
      end
    end
  end
end

function M.screen(battle, user, key)
  local side = sideState(battle, user)
  M.syncScreens(battle)
  if (side[key] or 0) > 0 then return { Strings(FAILED) } end
  local turns = 5
  local he, param, HE = heldEffect(user)
  if he == HE.LIGHT_CLAY then turns = turns + (param > 0 and param or 3) end
  side[key] = turns
  M.syncScreens(battle)
  if key == "reflect" then
    return { Strings("REFLECT raised\n%s's DEFENSE!", user.isPlayer and "your team" or "the foe's team") }
  end
  return { Strings("LIGHT SCREEN raised\n%s's SP. DEF!", user.isPlayer and "your team" or "the foe's team") }
end

local ROCK = { RAIN = "DAMP_ROCK", SUN = "HEAT_ROCK", SANDSTORM = "SMOOTH_ROCK", HAIL = "ICY_ROCK" }
-- a weather move on Platinum / HGSS; nil = not this cartridge (the caller
-- keeps its own rule)
function M.weatherMove(battle, user, weather)
  if not gen34() then return nil end
  local W = require("src.battle.Weather")
  local field = battle.field or {}
  if field.weather == weather then return { Strings(FAILED) } end
  W.start(battle, weather)
  local he, param, HE = heldEffect(user)
  if user and he == HE[ROCK[weather]] then
    field.weatherTurns = (field.weatherTurns or 5) + (param > 0 and param or 3)
  end
  return { Strings(W.STARTED_TEXT[weather] or "The weather changed!") }
end

-- TRAPPING_EFFECT's hit on Platinum / HGSS: the target is bound
function M.bind(ctx)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  if not alive(target) or target.substituteHP or target.g4Bound then return end
  local he, _, HE = heldEffect(user)
  local turns = (he == HE.GRIP_CLAW) and 6 or battle.rng(3, 6)
  target.g4Bound = { by = user, turns = turns, move = ctx.move.name or "the move" }
  ctx.say(Strings("%s was trapped\nby %s!", who(target), ctx.move.name or "the move"))
end

-- a bound Pokemon cannot leave (Shed Shell frees; a Ghost is not exempt in Gen 4)
function M.bound(battle, b)
  local bd = b and b.g4Bound
  if not (bd and alive(bd.by)) then return false end
  local he, _, HE = heldEffect(b)
  return he ~= HE.SHED_SHELL
end

function M.endOfTurn(battle)
  local s = peek(battle)
  if not s then return end
  -- MON_COND_CHECK_STATE_BIND, each battler
  for _, b in ipairs(active(battle)) do
    local bd = b.g4Bound
    if bd then
      if not alive(bd.by) then
        b.g4Bound = nil
      else
        bd.turns = bd.turns - 1
        if bd.turns > 0 then
          battle:sayNext(Strings("%s is hurt\nby %s!", who(b), bd.move))
          if require("src.battle.Abilities").of(b) ~= "MAGIC_GUARD" then
            battle:applyDamage(b, math.max(1, math.floor(((b.mon.stats and b.mon.stats.hp) or 1) / 16)))
            battle:drainNext()
            if b.mon.hp <= 0 then battle:onFaint(b) end
          end
        else
          b.g4Bound = nil
          battle:sayNext(Strings("%s was freed\nfrom %s!", who(b), bd.move))
        end
      end
    end
  end
  -- the screens
  M.syncScreens(battle)
  for _, isPlayer in ipairs({ true, false }) do
    local side = s.sides[isPlayer]
    for _, row in ipairs({ { "reflect", "REFLECT" }, { "lightScreen", "LIGHT SCREEN" } }) do
      local key = row[1]
      if (side[key] or 0) > 0 then
        side[key] = side[key] - 1
        if side[key] == 0 then
          side[key] = nil
          battle:sayNext(Strings("%s's %s\nwore off!", isPlayer and "Your team" or "The foe's team", row[2]))
        end
      end
    end
  end
  M.syncScreens(battle)
end

-- Custap Berry / Quick Claw on Platinum / HGSS (BattleSystem_CompareBattlerSpeed:
-- either one puts the holder first in its priority bracket); the line, or nil
function M.moveFirst(battle, b)
  return require("src.battle.Gen5HoldItems").moveFirst(battle, b)
end

-- FRISK / ANTICIPATION / FOREWARN (SWITCH_IN_CHECK_STATE_*): the line, or nil
function M.switchInNotice(battle, b)
  if not gen4() and not battle.bw then return nil end   -- (Frisk & co: Platinum on)
  local A = require("src.battle.Abilities")
  local ab = A.of(b)
  local foes = {}
  for _, x in ipairs(active(battle)) do if x.isPlayer ~= b.isPlayer then foes[#foes + 1] = x end end
  if #foes == 0 then return nil end
  if ab == "FRISK" then
    local holders = {}
    for _, f in ipairs(foes) do if f.mon.item and f.mon.item ~= 0 then holders[#holders + 1] = f end end
    if #holders == 0 then return nil end
    local f = holders[#holders == 2 and battle.rng(1, 2) or 1]
    local def = battle.data and battle.data.items and battle.data.items[f.mon.item]
    return Strings("%s frisked its foe\nand found one\n%s!", who(b), def and def.name or "item")
  end
  if ab == "ANTICIPATION" then
    local TC = require("src.battle.TypeChart")
    for _, f in ipairs(foes) do
      for _, mv in ipairs(f.curMoves or f.mon.moves or {}) do
        local d = battle.data and battle.data.moves and battle.data.moves[mv.id]
        if d and (tonumber(d.power) or 0) > 0 then
          local m = TC.effectiveness(A.normalizeType(d.type), b.curTypes or {})
          local ohko = type(d.effect) == "string" and d.effect:find("OHKO", 1, true)
          if (m > 10 and not (d.fixedDamage)) or (ohko and (b.mon.level or 0) <= (f.mon.level or 0)) then
            return Strings("%s shuddered!", who(b))
          end
        end
      end
    end
    return nil
  end
  if ab == "FOREWARN" then
    local best, bestPower = nil, 0
    for _, f in ipairs(foes) do
      for _, mv in ipairs(f.curMoves or f.mon.moves or {}) do
        local d = battle.data and battle.data.moves and battle.data.moves[mv.id]
        if d then
          local p = tonumber(d.power) or 0
          if p == 1 then
            local e = tostring(d.effect)
            if e:find("OHKO", 1, true) then p = 150
            elseif e:find("COUNTER", 1, true) or e:find("MIRROR_COAT", 1, true) or e:find("METAL_BURST", 1, true) then p = 120
            else p = 80 end
          end
          if p > bestPower or (p == bestPower and p > 0 and battle.rng(0, 1) == 1) then best, bestPower = d, p end
        end
      end
    end
    if not best then
      local f = foes[1]
      local list = f.curMoves or f.mon.moves or {}
      if #list == 0 then return nil end
      best = battle.data.moves[list[battle.rng(1, #list)].id]
    end
    return Strings("It was alerted to\n%s!", best and best.name or "a move")
  end
  return nil
end

-- STALL (BattleSystem_CompareBattlerSpeed, READ): within a priority bracket,
-- after Quick Claw / Custap and Lagging Tail, a Stall holder moves last.
-- Returns true (a first), false (b first) or nil (no say)
-- LAGGING TAIL / FULL INCENSE (HOLD_EFFECT_PRIORITY_DOWN, 107)
-- HOENN's EFFECT SPORE (pokeemerald AbilityBattleEffects): Random() % 10 == 0,
-- then Random() & 3 redrawn while 0: 1 sleep, 2 poison, 3 burn -> paralysis.
-- Ten percent in all, a third each -- not Sinnoh's thirty
M.EFFECT_SPORE3 = { outOf = 30, table = { [0] = "SLP", [1] = "PSN", [2] = "PAR" } }

function M.lagging(b)
  local H = require("src.battle.Gen5HoldItems")
  return H.held(b) == H.HE.LAGGING_TAIL
end

function M.stallOrder(a, b)
  local A = require("src.battle.Abilities")
  local sa, sb = A.of(a) == "STALL", A.of(b) == "STALL"
  if sa == sb then return nil end
  return sb
end

return M
