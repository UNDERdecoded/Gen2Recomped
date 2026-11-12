-- Round 27 (team A): one dispatcher for the overworld story, side systems and
-- leftover overworld enemies, so the shared files (Enemies.lua, Dungeon.lua,
-- Field.lua, Native.lua) carry a single anchored line per hook.  It mirrors
-- team B's R26.lua.  Each module listed in R27A.MODULES may export any of:
--   M.spawnEnemy(E, dat, def)  -> entity | false (drop it) | nil (not mine)
--   M.handles(e) / M.update(E, e) -> the enemy's per-frame code (after the
--       round 26 dispatchers, so only ids nobody else claims reach it)
--   M.spawnObject(d, e)       -> entity | false | nil   (Dungeon:spawnObject)
--   M.spawnManager(d, m, dat) -> true | nil              (Dungeon:spawnManager)
--   M.spawnProjectile(d, dat) -> entity | false | nil    (Dungeon:spawnProjectile)
--   M.roomInit(f)             -> after the room's lists, room code and R26
--   M.giveItem(f, item, param) -> true when the item was fully handled here
--       (Field:giveItem; the item message is still shown by the caller)
--   M.frame(f, input)         -> true = this frame belongs to a screen of the
--       module (Field:update stops after the fade / BG3 steps)
--   M.draw(f, font)           -> over the HUD and the pause menu, under the
--       message box
-- Script natives: a module registers its ports into Native.N when it is
-- required (R27A.natives() is called from Native.call's first use).
-- A module that does not exist yet is skipped; any other load error is raised.
local R = {}

R.MODULES = {
  "src.zelda.tmc.Story27Town", "src.zelda.tmc.Story27Town2", "src.zelda.tmc.Story27Minish",
  "src.zelda.tmc.Story27Cutscene", "src.zelda.tmc.Kinstone27", "src.zelda.tmc.Figurines",
  "src.zelda.tmc.SideQuests27", "src.zelda.tmc.EnemyField3",
}

local loaded
local function mods()
  if loaded then return loaded end
  loaded = {}
  for _, name in ipairs(R.MODULES) do
    local ok, m = pcall(require, name)
    if ok then
      if type(m) == "table" then loaded[#loaded + 1] = m end
    elseif not tostring(m):find("module '" .. name .. "' not found", 1, true) then
      error(m, 0)
    end
  end
  return loaded
end
R.mods = mods
function R.reset() loaded = nil end -- tests
function R.natives() mods() end

function R.spawnEnemy(E, dat, def)
  for _, m in ipairs(mods()) do
    if m.spawnEnemy then local x = m.spawnEnemy(E, dat, def) if x ~= nil then return x end end
  end
  return nil
end

function R.handles(e)
  if e.r27a ~= nil then return e.r27a ~= false end
  for _, m in ipairs(mods()) do
    if m.handles and m.handles(e) then e.r27a = m return true end
  end
  e.r27a = false
  return false
end
function R.update(E, e)
  local m = e.r27a
  if m then return m.update(E, e) end
end

local function first(fn, ...)
  for _, m in ipairs(mods()) do
    if m[fn] then local x = m[fn](...) if x ~= nil then return x end end
  end
  return nil
end
function R.spawnObject(d, e) return first("spawnObject", d, e) end
function R.spawnManager(d, m, dat) return first("spawnManager", d, m, dat) end
function R.spawnProjectile(d, dat) return first("spawnProjectile", d, dat) end

function R.roomInit(f)
  for _, m in ipairs(mods()) do
    if m.roomInit then m.roomInit(f) end
  end
end

function R.giveItem(f, item, param)
  for _, m in ipairs(mods()) do
    if m.giveItem and m.giveItem(f, item, param) then return true end
  end
  return false
end

function R.frame(f, input)
  local stop = false
  for _, m in ipairs(mods()) do
    if m.frame and m.frame(f, input) then stop = true end
  end
  return stop
end

function R.draw(f, font)
  for _, m in ipairs(mods()) do
    if m.draw then m.draw(f, font) end
  end
end

-- a manager / room-level updater with no sprite (team B's R26.ticker)
function R.ticker(d, fn, fields) return require("src.zelda.tmc.R26").ticker(d, fn, fields) end

return R
