-- Round 27 (team B): the round-27 modules (Vaati scripts, the ending and
-- credits, the dungeon leftovers, the caves / Royal Crypt objects) behind one
-- entry of R26.MODULES.  This module forwards the R26 interface
-- (spawnEnemy / handles / update / spawnObject / spawnManager /
-- spawnProjectile / roomInit) to every module in R27B.MODULES that exists,
-- and merges their M.ROM_RANGES into its own (ExtractR26 reads them from
-- here).  A module that does not exist yet is skipped; any other load error
-- is raised (as R26 does).
local R = {}

R.MODULES = {
  "src.zelda.tmc.VaatiScripts",    -- the DHC intro / defeat scripts' NPCs and natives
  "src.zelda.tmc.SanctuaryScripts", -- Zelda's stone, the Sanctuary sequence
  "src.zelda.tmc.Ending",          -- the outro (garden, synced cutscene, Npc4E transitions)
  "src.zelda.tmc.DungeonFix27",    -- dungeon leftovers (heart container, throne, frozen Link...)
  "src.zelda.tmc.CoFRest27",       -- Cave of Flames cosmetics (steam overlay, Gleerok lava tiles)
  "src.zelda.tmc.CaveObjects",     -- caves / Royal Crypt / small dungeons: objects
  "src.zelda.tmc.CaveManagers",    -- caves / small dungeons: managers
  "src.zelda.tmc.Pot30",           -- round 30: pot tile / shatter / thrown-object shadow (ROM_RANGES only)
  "src.zelda.tmc.R31",             -- round 31: PL_FROZEN / PL_BURNING, CoF steam + lava tiles
  "src.zelda.tmc.Furniture32",     -- round 32: pushable furniture + its manager
  "src.zelda.tmc.Fusion32",        -- round 32: the world-event view after a fusion
  "src.zelda.tmc.R33",             -- round 33: LIGHT_RAY_MANAGER (Minish Woods / barrel house light rays)
  "src.zelda.tmc.R34",             -- round 34: beanstalks, dig caves, cloud overlay, room music, furniture push-out
  "src.zelda.tmc.R37",             -- round 37: Minish Paths / rafters parallax, rain, small objects, Armos interiors
  "src.zelda.tmc.Crypt73",         -- round 73: the Royal Crypt's room init, ENEMY_ITEM (Crypt73.lua)
  "src.zelda.tmc.Veil74",          -- round 74: Veil Falls' room init (the Wind Crest), the Source of the Flow's stones
  "src.zelda.tmc.Cloud75",         -- round 75: Cloud Tops' room code, the CLOUD object (bulges cleared, the great whirlwind)
  "src.zelda.tmc.Bell75",          -- round 75: WaitForPlayerNormal's framestates, the pause menu's gates, field82 pushes
  "src.zelda.tmc.WindTribe76",     -- round 76: the Wind Tribe tower's room code (roomInit.c sub_StateChange_WindTribeTower*)
  "src.zelda.tmc.Story90",         -- round 90: the Sanctuary's story panels (cutscene.c sub_080536B8 / sub_0805373C)
  "src.zelda.tmc.Exits90",         -- round 90: the Four Sword's exit lists (movement.c sub_080AF2E4 / sub_080AF284)
  "src.zelda.tmc.Legend94",        -- round 94: the new file's legend panels (cutscene.c sub_080536D4, Story90's panel code)
}

R.ROM_RANGES = {}

local loaded
local function mods()
  if loaded then return loaded end
  loaded = {}
  for _, name in ipairs(R.MODULES) do
    local ok, m = pcall(require, name)
    if ok then
      if type(m) == "table" then
        loaded[#loaded + 1] = m
        for k, v in pairs(m.ROM_RANGES or {}) do R.ROM_RANGES[k] = v end
      end
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

-- the sub-module that owns an enemy is kept on it (e.r27b)
function R.handles(e)
  if e.r27b ~= nil then return e.r27b ~= false end
  for _, m in ipairs(mods()) do
    if m.handles and m.handles(e) then e.r27b = m return true end
  end
  e.r27b = false
  return false
end
function R.update(E, e)
  local m = e.r27b
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

-- Field:update (after the fade / BG3 steps): true = this frame belongs to a
-- module's screen (the credits roll...), the rest of the field update stops
function R.frame(f, input)
  for _, m in ipairs(mods()) do
    if m.frame and m.frame(f, input) then return true end
  end
  return false
end
-- Field:draw, over the HUD and the pause menu, under the message box
function R.draw(f, font)
  for _, m in ipairs(mods()) do
    if m.draw then m.draw(f, font) end
  end
end
-- top of Player:update (after the item states): true = the module ran Link's
-- frame (PL_FROZEN...)
function R.playerFrame(p, input)
  for _, m in ipairs(mods()) do
    if m.playerFrame and m.playerFrame(p, input) then return true end
  end
  return false
end

mods() -- load now: the sub-modules register their script natives (Native.N) and ROM ranges
return R
