-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Fly/Dig's cleared picture box follows the native animation queue. Combat
-- owns invulnerable/hiddenAs; this latch owns only when that picture is seen.
local Version=require('src.core.GameVersion')
local M={}
local function side(b)return b.isPlayer and 'player' or 'enemy'end

local function vanished(b)
  return b and b.invulnerable and (b.hiddenAs=='air' or b.hiddenAs=='underground') or false
end
local function current(screen,b,p)
  return screen[side(b)]==b and b.mon==p.mon
    and not b.fainted and (b.mon.hp or 0)>0
end
local function queued(screen,row)
  for _,item in ipairs(screen.queue or {})do if item==row then return true end end
  return false
end
local function states(screen)
  screen._gen2VanishPictures=screen._gen2VanishPictures or {}
  return screen._gen2VanishPictures
end

function M.charge(screen,b,row)
  if not (Version.isGen2() and vanished(b))then return end
  states(screen)[side(b)]={battler=b,mon=b.mon,row=row,phase=row and 'charge' or 'hidden',hidden=not row}
end

-- Native resolution clears the charge flags before announcing the release.
-- Keep an already-cleared box until that row's SHOW_MON, not until its text.
function M.releasing(screen,b)
  if not Version.isGen2()then return end
  local all=screen._gen2VanishPictures
  local p=all and all[side(b)]
  if not p then return end
  if not (p.battler==b and current(screen,b,p) and p.hidden)then all[side(b)]=nil;return end
  p.phase,p.row,p.runner='release',nil,nil
end
function M.releaseRow(screen,b,row)
  local p=screen._gen2VanishPictures and screen._gen2VanishPictures[side(b)]
  if p and p.battler==b and p.phase=='release'then p.row=row end
end

function M.admitted(screen,row,runner)
  for key,p in pairs(screen._gen2VanishPictures or {})do
    local b=p.battler
    if p.row==row then
      p.row,p.runner=nil,runner
      if not runner then
        if p.phase=='charge' and vanished(b)then p.phase,p.hidden='hidden',true
        else screen._gen2VanishPictures[key]=nil end
      end
    end
  end
end

-- One observation after the native VM tick; reads and draws never call this.
function M.sync(screen)
  local all=screen._gen2VanishPictures
  for key,p in pairs(all or {})do
    local b=p.battler
    local remove=not current(screen,b,p)
    if p.phase=='hidden'then remove=remove or not vanished(b)
    elseif p.runner then
      local r=p.runner
      local ended=r~=screen.animPlayer.runtime or r.stopped
      if p.phase=='charge'then
        if ended then
          if vanished(b)then p.phase,p.hidden,p.runner='hidden',true,nil
          else remove=true end
        end
      elseif ended or r.bg.picSize[key]~=nil then remove=true end
    elseif not (p.row and queued(screen,p.row))then remove=true end
    if remove then all[key]=nil end
  end
end

function M.hidden(screen,b)
  local p=b and screen._gen2VanishPictures and screen._gen2VanishPictures[side(b)]
  return p and p.battler==b and current(screen,b,p) and p.hidden
    and (p.phase=='release' or vanished(b)) or false
end
function M.install(Screen)
  function Screen:isUnderground(side,mon)
    local b=(side=='player' or side=='enemy')and self[side]
    if not b or mon and mon~=b and mon~=b.mon then return false end
    return vanished(b) and M.hidden(self,b) or false
  end
  local hidden=Screen.fxHidden
  function Screen:fxHidden(b)
    return Version.isGen2() and M.hidden(self,b) or hidden(self,b)
  end
  local read=Screen.animPicState
  function Screen:animPicState(side)
    local state=read and read(self,side)
    local b=(side=='player' or side=='enemy')and self[side]
    if Version.isGen2() and M.hidden(self,b)then state=state or {};state.hidden=true end
    return state
  end
end
return M
