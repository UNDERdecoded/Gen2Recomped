-- Native Gen2 PP arithmetic from Gen1Recomp 535a5ec0 Mon.lua.
-- Existing project rights/licences remain applicable. Contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
local P = {}
function P.bonus(base) return math.min(math.floor(base / 5), 7) end
function P.ups(def, slot)
  if type(slot) ~= 'table' then return 0 end
  local ups = tonumber(slot.ppUps)
  if ups == nil then
    local base, stored = def and tonumber(def.pp), tonumber(slot.maxPp)
    ups = 0
    if base and stored and stored > base then
      local bonus = P.bonus(base)
      if bonus > 0 and (stored - base) % bonus == 0 then
        ups = (stored - base) / bonus
      end
    end
  end
  return math.max(0, math.min(3, math.floor(ups)))
end
function P.maximum(def, slot)
  local base = def and tonumber(def.pp)
  if not base then
    return type(slot) == 'table' and (tonumber(slot.maxPp) or tonumber(slot.pp)) or 0
  end
  return base + P.ups(def, slot) * P.bonus(base)
end

-- Source consumers identify the saved slot first, then supply the live move
-- registry. Keep these operations on those same native tables.
local function definition(slot, moves)
  return type(slot)=='table' and moves and moves[slot.id] or nil
end
function P.forSlot(slot, moves)
  if type(slot)~='table' then return 0 end
  return P.maximum(definition(slot,moves),slot)
end
function P.partyMoves(mon)
  if type(mon)~='table' then return {} end
  local before=type(mon.volatile)=='table' and mon.volatile.preTransform
  return (before and before.moves) or mon.moves or {}
end
function P.restore(mon, moves)
  for _,slot in ipairs(type(mon)=='table' and mon.moves or {}) do
    if type(slot)=='table' and slot.id then
      local def=definition(slot,moves)
      local maximum=P.maximum(def,slot)
      if def and tonumber(def.pp) then slot.maxPp=maximum end
      slot.pp=maximum
    end
  end
end
function P.repair(mon, moves)
  for _,slot in ipairs(type(mon)=='table' and mon.moves or {}) do
    local def=definition(slot,moves)
    if def and tonumber(def.pp) then
      local ups=P.ups(def,slot)
      if ups>0 or slot.ppUps~=nil then slot.ppUps=ups end
      local maximum=P.maximum(def,slot)
      slot.maxPp=maximum
      slot.pp=math.max(0,math.min(maximum,math.floor(tonumber(slot.pp) or maximum)))
    end
  end
end
return P
