-- Native GBA Triple Kick owns a distinct per-hit accuracy/power script.
local M = {}
local V = require("src.core.GameVersion")
local cache = setmetatable({}, { __mode = "k" })
function M.builtin(id, base)
  if not V.isGen3() or not base or id ~= "TRIPLE_KICK_EFFECT" then
    return base
  end
  if cache[base] then
    return cache[base]
  end
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  out.gbaTripleKick = true
  -- The native opcode assigns 10/20/30, regardless of the extracted power.
  -- The earlier-generation approximation remains in the shared static record.
  out.powerMultiplier = nil
  cache[base] = out
  return out
end
return M
