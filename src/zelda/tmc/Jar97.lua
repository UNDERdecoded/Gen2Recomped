-- Round 97: an enemy the Gust Jar swallows dies, as on the cartridge.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc): an enemy with gustJarFlags 1 runs its OnGrabbed subaction 2 every frame of the
-- pull: `if (sub_0806F3E4(super))` -- it reached the jar's mouth and was swallowed (SFX_EF) -- then
--   * most enemies: GenericDeath (keese.c, rope.c, crow.c, dust.c, smallPesto.c, takkuri.c, wisp.c, gyorgChild.c ...);
--   * ghini.c / enemy50.c: CreateFx(FX_DEATH) first; enemy50.c's copies (type 1) are DeleteThisEntity'd, only the
--     type-0 Ghini dies (GenericDeath -- its FIGHT_MANAGER counts it);
--   * beetle.c: Beetle_OnDeath; helmasaur.c's mask: DeleteEntity (the port's onJarPull already handles those).
-- The port's GustJar.grabbedUpdate set jarSub 4 ("swallowed", SFX_EF) and then kept returning true: the enemy hung at
-- the mouth forever with its AI stopped ($88:0B's Ghinis).  Now jarSub 4 ends in the death (Enemies:kill: FX_DEATH,
-- the drop roll) or, for an ENEMY_50 copy, FX_DEATH and the entity gone.
-- No game data here (the enemy id is the engine's enum value).
--
-- Wraps GustJar.grabbedUpdate at require time (guard GustJar.jar97Installed); listed in R27A.MODULES.
local M = {}

M.ENEMY_50 = 0x50
M.SPECIAL_FX, M.FX_DEATH = 0x0F, 0x02

-- the swallowed enemy's end; true when handled
function M.swallowed(E, e)
  if not e or e.deleted or e.dying then return false end
  local f = E.field
  e.jarSub, e.spriteOX = nil, nil
  if e.id == M.ENEMY_50 and (e.form or 0) ~= 0 then
    if f.addFx then f:addFx(e.x, e.y, M.SPECIAL_FX, M.FX_DEATH) end
    e.deleted = true
    return true
  end
  if E.kill then E:kill(e) else e.deleted = true end
  return true
end

function M.install()
  local ok, GJ = pcall(require, "src.zelda.tmc.GustJar")
  if not ok or type(GJ) ~= "table" or GJ.jar97Installed then return end
  GJ.jar97Installed = true
  local upd0 = GJ.grabbedUpdate
  GJ.grabbedUpdate = function(E, e)
    local r = upd0(E, e)
    if e.jarSub == 4 then M.swallowed(E, e) return true end
    return r
  end
end
M.install()

return M
