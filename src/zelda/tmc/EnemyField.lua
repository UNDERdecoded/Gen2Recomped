-- Round 26 (team A): the overworld enemies' dispatcher.  Enemies:update
-- calls EnemyField.handles(e) / EnemyField.update(E, e) once (one anchored
-- line before the generic model); the ports live in their own modules:
--
--   EnemyField1.lua  Leever $02, Rock ChuChu $0A, Keaton $30, Crow $31,
--                    Scissors Beetle $40, Cucco (aggr.) $41, Ghini $4E,
--                    Acro Bandit $2E
--   EnemyField2.lua  Spear Moblin $15, Bomb Peahat $1B, Armos $2A,
--                    Cloud Piranha $3F, Takkuri $45, Bow Moblin $46,
--                    Lakitu $47 (+ Lakitu Cloud $48)
--
-- Each module exports handles(e) and update(E, e).  A module that fails to
-- load (missing, an error) is skipped: the enemy keeps the generic model.
local M = {}

local NAMES = { "src.zelda.tmc.EnemyField1", "src.zelda.tmc.EnemyField2" }
local mods

local function load()
  if mods then return mods end
  mods = {}
  for _, n in ipairs(NAMES) do
    local ok, m = pcall(require, n)
    if ok and type(m) == "table" and m.handles and m.update then mods[#mods + 1] = m end
  end
  return mods
end

function M.handles(e)
  for _, m in ipairs(load()) do
    if m.handles(e) then e._fieldMod = m return true end
  end
  return false
end

function M.update(E, e)
  local m = e._fieldMod
  if not m then
    for _, x in ipairs(load()) do if x.handles(e) then m = x break end end
  end
  if m then return m.update(E, e) end
end

-- tests: replace the module list
function M._setModules(list) mods = list end

return M
