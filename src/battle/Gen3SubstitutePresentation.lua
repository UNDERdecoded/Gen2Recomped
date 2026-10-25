-- Substitute has independent gameplay HP and controller-owned presentation.
-- A move can expose its user without removing the protective Substitute.
local M = {}
local V = require("src.core.GameVersion")

local function protected(user)
  return user and (tonumber(user.substituteHP) or 0) > 0
end

function M.mark(battle, row, user, left)
  local frame = battle._gbaMoveFrame
  if not V.isGen3() or not frame or not row or not row.anim then
    return
  end
  if not protected(user) then
    return
  end
  frame.presentationOwner = frame.presentationOwner or {}
  row.gbaPresentationOwner = frame.presentationOwner
  row.gbaBehindSubstitute = protected(user)
  row.gbaMultiHitLeft = left or 0
end

local function special(row, name)
  return {
    anim = name,
    gbaSubstituteSpecial = true,
    gbaSubstituteMove = row.anim,
    attackerIsPlayer = row.attackerIsPlayer,
    attackerPosition = row.attackerPosition,
    targetPosition = row.attackerPosition,
  }
end

-- Finalize only this call's surviving animation rows. A called move owns its
-- own group; a multi-hit call keeps one lowered sprite until its final strike.
function M.finish(battle, frame)
  local owner = frame and frame.presentationOwner
  if not owner then
    return
  end
  local lowered, i, last = false, 1, 0
  for index in pairs(battle.queue) do
    if type(index) == "number" and index % 1 == 0 and index > last then
      last = index
    end
  end
  local function insert(index, row)
    -- Existing action callbacks can leave holes before later queued rows.
    -- Preserve every row and hole instead of relying on Lua's sparse length.
    for j = last, index, -1 do
      battle.queue[j + 1] = battle.queue[j]
    end
    battle.queue[index], last = row, last + 1
    if battle.nextInsert and index <= battle.nextInsert + 1 then
      battle.nextInsert = battle.nextInsert + 1
    end
  end
  while i <= last do
    local row = battle.queue[i]
    if row and row.gbaPresentationOwner == owner then
      row.gbaPresentationOwner = nil
      if row.gbaBehindSubstitute then
        if not lowered then
          insert(i, special(row, "SUBSTITUTE_TO_MON"))
          lowered, i = true, i + 1
        end
        if (row.gbaMultiHitLeft or 0) < 2 then
          insert(i + 1, special(row, "MON_TO_SUBSTITUTE"))
          lowered, i = false, i + 1
        end
      end
      row.gbaBehindSubstitute, row.gbaMultiHitLeft = nil, nil
    end
    i = i + 1
  end
end

function M.showing(battle, user)
  local state = battle._gbaSubstitutePresentation and battle._gbaSubstitutePresentation[user]
  if state then
    return state.substitute
  end
  return protected(user)
end

function M.offset(battle, user)
  local state = battle._gbaSubstitutePresentation and battle._gbaSubstitutePresentation[user]
  return state and state.x or 0
end

local function actor(battle, row)
  if row.attackerPosition ~= nil then
    return battle:battlerAt(row.attackerPosition)
  end
  return row.attackerIsPlayer and battle.player or battle.enemy
end

function M.beginSwap(battle, user, substitute)
  battle._gbaSubstitutePresentation = battle._gbaSubstitutePresentation or {}
  local states = battle._gbaSubstitutePresentation
  states[user] = states[user] or { substitute = protected(user), x = 0 }
  local pos = tonumber(user.position) or (user.isPlayer and 0 or 1)
  local coords = (battle.data.constants or {}).gen3BattlerCoords
  local layout = coords and (battle:isDouble() and coords.doubles or coords.singles)
  local point = layout and layout[pos + 1]
  return {
    user = user,
    state = states[user],
    phase = "out",
    baseX = tonumber(point and point.x) or (user.isPlayer and 72 or 176),
    direction = user.isPlayer and -1 or 1,
    substitute = substitute,
  }
end

-- Damage calculation can remove the logical protection before its queued
-- break animation runs. Preserve the displayed doll until that command swaps it.
function M.broken(battle, user)
  if not V.isGen3() then
    return
  end
  battle._gbaSubstitutePresentation = battle._gbaSubstitutePresentation or {}
  local states = battle._gbaSubstitutePresentation
  states[user] = states[user] or { substitute = true, x = 0 }
  require("src.battle.Gen3EffectPresentation").queue(battle, user, "SUBSTITUTE_FADE")
end

function M.start(battle, row)
  if not V.isGen3() then
    return false
  end
  local user = actor(battle, row)
  if not user then
    return false
  end
  local move = battle.data.moves[row.gbaSubstituteMove]
  local number = move and tonumber(move.index)
  if not battle:animationsOn() and number ~= 144 and number ~= 164 then
    return false
  end
  local lower = row.anim == "SUBSTITUTE_TO_MON"
  battle._gbaSubstitutePresentation = battle._gbaSubstitutePresentation or {}
  local states = battle._gbaSubstitutePresentation
  local state = states[user]
  if not state then
    state = { substitute = protected(user), x = 0 }
    states[user] = state
  end
  if lower then
    if not state.substitute then
      return false
    end
    state.lowered = true
  else
    if not state.lowered then
      return false
    end
    state.lowered = nil
    if not protected(user) then
      return false
    end
  end
  battle._gbaSubstituteTransition = M.beginSwap(battle, user, not lower)
  return true
end

-- Native SwapMonSpriteToFromSubstitute moves five pixels per controller tick.
-- The exchange happens offscreen, on its own tick, before the return trip.
function M.stepSwap(transition)
  if not transition then
    return false
  end
  local state = transition.state
  if transition.phase == "out" then
    state.x = state.x + transition.direction * 5
    local right = transition.baseX + state.x + 32
    if right < 0 or right > 304 then
      transition.phase = "exchange"
    end
  elseif transition.phase == "exchange" then
    state.substitute = transition.substitute
    transition.phase = "in"
  else
    state.x = state.x - transition.direction * 5
    if state.x * transition.direction <= 0 then
      state.x = 0
      state.substitute = transition.substitute
      return false
    end
  end
  return true
end

function M.update(battle)
  if M.stepSwap(battle._gbaSubstituteTransition) then
    return true
  end
  battle._gbaSubstituteTransition = nil
  return false
end

function M.reconcile(battle)
  battle._gbaSubstituteTransition, battle._gbaSubstitutePresentation = nil, nil
end

return M
