-- Native move-end command shared by King's Rock and Shell Bell. It reads
-- once, with a second player-slot read only for the flinch effect.
local V = require("src.core.GameVersion")
local Held = require("src.battle.HoldItems")
local Abilities = require("src.battle.Abilities")
local Strings = require("src.core.Strings")
local P = {}
function P.markMoved(battle, actor)
  actor.gbaMovedTurn = battle.turnCount or 0
end
function P.moved(battle, actor)
  return actor.gbaMovedTurn ~= nil and actor.gbaMovedTurn == (battle.turnCount or 0)
end
function P.damage(battle, damage, dealt, substitute)
  local frame = battle._gbaMoveFrame
  if not frame then
    return
  end
  if (frame.firstDmg or 0) == 0 then
    local rs = V.get() == "ruby" or V.get() == "sapphire"
    frame.firstDmg = substitute and not rs and damage or dealt
  end
  if not substitute and dealt > 0 then
    frame.targetDamaged = true
  end
end
local function maxHP(actor)
  return actor.mon.stats and actor.mon.stats.hp or actor.mon.maxHp or actor.mon.hp
end
function P.run(battle, frame)
  if not V.isGen3() or not frame or not frame.user or not frame.target or (frame.firstDmg or 0) == 0 then
    return false
  end
  local user, target = frame.user, frame.target
  local effect, parameter, def, changed = Held.effectOf(user, "flinch")
  if effect == "FLINCH" then
    -- The native command reads the canonical player battler even for an
    -- enemy attacker. A changed first answer alone selects its parameter.
    local player = battle.linkRole == "guest" and battle.enemy or battle.player
    local _, chance = Held.effectOf(player, "flinch")
    if changed then
      chance = parameter
    end
    if
      not frame.noEffect
      and frame.targetDamaged
      and (battle.rng or love.math.random)(0, 99) < (tonumber(chance) or 0)
      and frame.move
      and frame.move.flags
      and math.floor((tonumber(frame.move.flags) or 0) / 32) % 2 == 1
      and target.mon.hp > 0
    then
      if
        Abilities.of(target) ~= "SHIELD_DUST"
        and not (target.substituteHP and target.substituteHP > 0)
        and not Abilities.refusesFlinch(target)
        and not P.moved(battle, target)
      then
        target.flinched = true
      end
      return true
    end
  elseif effect == "SHELL_BELL" then
    if not frame.noEffect and user ~= target and user.mon.hp ~= maxHP(user) and user.mon.hp > 0 then
      local amount = math.floor(frame.firstDmg / math.max(1, tonumber(parameter) or 0))
      if amount == 0 then
        amount = 1
      end
      frame.firstDmg = 0
      battle.nextInsert = (battle.nextInsert or 0) + 1
      table.insert(battle.queue, battle.nextInsert, {
        anim = "HELD_ITEM_EFFECT",
        attackerIsPlayer = user.isPlayer,
        attackerPosition = user.position,
        targetPosition = user.position,
      })
      local label = def and def.name or "the item"
      battle:sayNext(Strings("%s's %s restored\na little HP!", user.name or user.mon.nickname, label))
      user.mon.hp = math.min(maxHP(user), user.mon.hp + amount)
      battle:drainNext(user, user.mon.hp)
      return true
    end
  end
  return false
end
return P
