-- Round 89: a clone tile is free again once its clone has left it (src/object/playerClone.c).
--   PlayerClone_Init sets SPECIAL_TILE_22 on the clone's tile (no second clone there); PlayerClone_Action1 puts
--   TILE_TYPE_789 (the clone tile) back with CloneTile both when the split goes out (chargeState action 5: the clone
--   walks off with Link) and when the charge is lost before that (action != 4: the clone is deleted).
-- Port gap fixed: FourSword.lua marked a used tile in f.cloneTiles for the rest of the room visit, so a room allowed
--   ONE split per tile (the Gyorg female's back, where the split is made again for every eye pattern, became
--   unwinnable after the first round).  Here every clone still standing in its PlayerClone_Action1 (action 1) remembers
--   its tile; when it leaves action 1 (out with Link, or deleted) the tile's mark is cleared.
-- Port gap fixed (2): the clones' sword boxes (FourSword cloneSwords) always hit with the plain swing's hurtType
--   (Sword84.hurtOf) and left f.swordHurt31 unset, so the boss parts read HURT_SWORD: during a spin the clones' boxes
--   did nothing to the Gyorg female's eyes (their spin contacts $88-$8A).  playerClone.c's sword child
--   (sub_08077CF8 with Link's item field_0x68) does Link's move: M.cloneHurt gives the spin's hurtType
--   (SwordSkills.spinHurt of the charged sword) while Link spins, else the swing's (Sword84).
-- Hooked by wrapping FourSword.frame / FourSword.deleteClones (guard FourSword.tiles89Installed); listed in R27A.
local FS = require("src.zelda.tmc.FourSword")

local M = {}

local function key(c) return math.floor(c.x / 16) .. ":" .. math.floor(c.y / 16) end
M.key = key

-- the clones still in action 1 and their tiles
local function waiting(f)
  local t = {}
  local cl = rawget(f, "playerClones")
  if type(cl) == "table" then
    for _, c in ipairs(cl) do if c.action == 1 and not c.deleted then t[c] = key(c) end end
  end
  return t
end
M.waiting = waiting

-- clear the marks of the clones that left action 1
local function release(f, before)
  local used = rawget(f, "cloneTiles")
  if type(used) ~= "table" then return 0 end
  local n = 0
  for c, k in pairs(before) do
    if c.deleted or c.action ~= 1 then
      if used[k] then used[k] = nil; n = n + 1 end
    else
      local still = false
      for _, x in ipairs(rawget(f, "playerClones") or {}) do if x == c then still = true break end end
      if not still and used[k] then used[k] = nil; n = n + 1 end
    end
  end
  return n
end
M.release = release

function M.cloneHurt(f, p)
  local ss = p and p.ss
  if ss and ss.mode == "spin" then
    local S = require("src.zelda.tmc.SwordSkills")
    local item = ss.item
    if type(item) ~= "number" then item = f and f.equipped and f:equipped(ss.button or "b") end
    return S.spinHurt(item)
  end
  return require("src.zelda.tmc.Sword84").hurtOf(f, p)
end

function M.install()
  if FS.tiles89Installed then return end
  FS.tiles89Installed = true
  local frame0, del0 = FS.frame, FS.deleteClones
  FS.frame = function(p, input)
    local f = p and p.field
    local before = f and waiting(f) or {}
    local r = frame0(p, input)
    if f and next(before) then release(f, before) end
    return r
  end
  FS.deleteClones = function(f, fx)
    local before = f and waiting(f) or {}
    local r = del0(f, fx)
    if f and next(before) then
      for c in pairs(before) do c.deleted = true end
      release(f, before)
    end
    return r
  end
end
M.install()

return M
