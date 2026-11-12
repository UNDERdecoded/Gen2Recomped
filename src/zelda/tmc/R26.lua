-- Round 26 (team B): one dispatcher for the dungeon ports of round 26 so the
-- shared files (Enemies.lua, Dungeon.lua, Field.lua) carry a single anchored
-- line per hook.  Each module listed in R26.MODULES may export any of:
--   M.spawnEnemy(E, dat, def)  -> entity | false (drop it) | nil (not mine)
--       (called first in Enemies:spawn, before the id >= $60 cut-off: boss
--        parts and helpers $60+ are created here)
--   M.handles(e) / M.update(E, e) -> the enemy's per-frame code
--   M.spawnObject(d, e)       -> entity | false | nil   (Dungeon:spawnObject)
--   M.spawnManager(d, m, dat) -> true | nil              (Dungeon:spawnManager)
--   M.spawnProjectile(d, dat) -> entity | false | nil    (Dungeon:spawnProjectile)
--   M.roomInit(f)             -> after the room's lists and room code
-- A module that does not exist yet is skipped; any other load error is raised.
local R = {}

R.MODULES = {
  "src.zelda.tmc.EnemyFoW", "src.zelda.tmc.FoWObjects", "src.zelda.tmc.BossMazaal",
  "src.zelda.tmc.EnemyToD", "src.zelda.tmc.ToDObjects", "src.zelda.tmc.BossOctorok",
  "src.zelda.tmc.EnemyPoW", "src.zelda.tmc.PoWObjects", "src.zelda.tmc.BossGyorg",
  "src.zelda.tmc.EnemyDHC", "src.zelda.tmc.DHCObjects",
  "src.zelda.tmc.BossVaati", "src.zelda.tmc.BossVaati2", "src.zelda.tmc.BossVaati3",
  "src.zelda.tmc.CoFRest",
  "src.zelda.tmc.R27B", -- round 27b: the round-27 team B modules (R27B.lua)
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

function R.spawnEnemy(E, dat, def)
  for _, m in ipairs(mods()) do
    if m.spawnEnemy then local x = m.spawnEnemy(E, dat, def) if x ~= nil then return x end end
  end
  return nil
end

-- the owner of an enemy is remembered on it (e.r26) so update is one lookup
function R.handles(e)
  if e.r26 ~= nil then return e.r26 ~= false end
  for _, m in ipairs(mods()) do
    if m.handles and m.handles(e) then e.r26 = m return true end
  end
  e.r26 = false
  return false
end
function R.update(E, e)
  local m = e.r26
  if m then return m.update(E, e) end
end

function R.spawnObject(d, e)
  for _, m in ipairs(mods()) do
    if m.spawnObject then local x = m.spawnObject(d, e) if x ~= nil then return x end end
  end
  return nil
end

function R.spawnManager(d, m, dat)
  for _, mm in ipairs(mods()) do
    if mm.spawnManager then local x = mm.spawnManager(d, m, dat) if x ~= nil then return x end end
  end
  return nil
end

function R.spawnProjectile(d, dat)
  for _, m in ipairs(mods()) do
    if m.spawnProjectile then local x = m.spawnProjectile(d, dat) if x ~= nil then return x end end
  end
  return nil
end

function R.roomInit(f)
  for _, m in ipairs(mods()) do
    if m.roomInit then m.roomInit(f) end
  end
end

-- a manager / room-level updater with no sprite: lives only in the dungeon's
-- object list (Dungeon:update calls extUpdate), never drawn
function R.ticker(d, fn, fields)
  local t = fields or {}
  t.kind, t.id, t.hidden, t.ticker = t.kind or 9, t.id or -1, true, true
  t.extUpdate = fn
  d:track(t)
  return t
end

return R
