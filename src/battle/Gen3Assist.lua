-- Native Assist keeps one candidate per eligible party move occurrence.
local A = {}
local Strings = require("src.core.Strings")
local BLOCKED = {
  [118] = true,
  [165] = true,
  [166] = true,
  [102] = true,
  [68] = true,
  [243] = true,
  [182] = true,
  [197] = true,
  [203] = true,
  [194] = true,
  [214] = true,
  [168] = true,
  [266] = true,
  [289] = true,
  [270] = true,
  [343] = true,
  [271] = true,
  [264] = true,
  [119] = true,
  [274] = true,
}
function A.party(battle, user)
  local party
  if user.isPlayer then
    party = battle.playerParty or battle.game and battle.game.save and battle.game.save.party or {}
  else
    party = battle.enemyParty or { user.mon }
    if battle.enemyPartyB then
      local combined = {}
      for _, m in ipairs(party) do
        combined[#combined + 1] = m
      end
      for _, m in ipairs(battle.enemyPartyB) do
        combined[#combined + 1] = m
      end
      party = combined
    end
  end
  local index
  for i, mon in ipairs(party) do
    if mon == user.mon then
      index = i
      break
    end
  end
  return party, index or user.partyIndex
end
function A.pool(battle, user)
  local party, own = A.party(battle, user)
  local pool = {}
  for i, mon in ipairs(party) do
    if i ~= own and mon and mon.species and mon.species ~= 0 and not mon.isEgg then
      for slot = 1, 4 do
        local inst = mon.moves and mon.moves[slot]
        local ref = type(inst) == "table" and inst.id or inst
        local id, def = require("src.battle.EnemyMoveChoice").resolveMove(battle.data, ref)
        local n = tonumber(ref) or def and tonumber(def.index or def.numId) or id
        if n and n ~= 0 and not BLOCKED[n] then
          pool[#pool + 1] = id or ref
        end
      end
    end
  end
  return pool
end
function A.pick(ctx)
  local b = ctx.battle
  local frame = b._gbaMoveFrame
  local pool = frame and frame.assistPool or A.pool(b, ctx.user)
  if #pool == 0 then
    if frame then
      frame.finished, frame.nativeNoHistory = true, true
    end
    ctx.say(Strings("But, it failed!"))
    return nil
  end
  b.nextInsert = (b.nextInsert or 0) + 1
  local row = {
    anim = ctx.move.id,
    attackerIsPlayer = ctx.user.isPlayer,
    attackerPosition = ctx.user.position,
    targetPosition = ctx.target and ctx.target.position,
    animContext = { moveTurn = 0 },
  }
  table.insert(b.queue, b.nextInsert, row)
  b.moveAnimRow = row
  return pool[ctx.rng(1, #pool)]
end
function A.call(ctx, pick)
  return require("src.battle.Gen3CalledMove").call(ctx, pick)
end
function A.record()
  return { kind = "full", announceAnim = false, gbaAssist = true, callsMove = A.pick }
end
return A
