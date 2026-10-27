-- Native Gen2 PP arithmetic from Gen1Recomp 535a5ec0 Mon.lua.
-- Existing project rights/licences remain applicable. Contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
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
return P
