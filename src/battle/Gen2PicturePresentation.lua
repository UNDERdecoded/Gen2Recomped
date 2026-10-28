-- Picture identity follows the existing GSC animation VM, not the earlier
-- native damage/effect calculation. No combat value or saved mon is delayed.
local Version=require('src.core.GameVersion')
local M={}

local function side(b) return b.isPlayer and 'player' or 'enemy' end
local function current(screen,p)
  return screen[side(p.b)]==p.b and p.b.mon==p.mon
end
local function commit(p)
  if p.kind=='transform' then
    p.b.species=p.species
    p.b.picAnim=p.picAnim
  end
end
local function remove(screen,index,apply)
  local p=table.remove(screen._gen2PictureChanges,index)
  if apply and current(screen,p) then commit(p) end
end
local function pending(screen,b,kind)
  for _,p in ipairs(screen._gen2PictureChanges or {})do
    if p.b==b and p.mon==b.mon and (not kind or p.kind==kind)then return p end
  end
end
local function mark(screen,b,kind)
  local row=screen.moveAnimRow
  local player=screen.animPlayer
  if not (Version.isGen2() and row and screen:animationsOn() and player and player.anims.gen2
      and player:scriptFor(row.anim))then return end
  local queued=false
  for _,item in ipairs(screen.queue or {})do if item==row then queued=true;break end end
  if not queued then return end
  local p={b=b,mon=b.mon,row=row,kind=kind}
  screen._gen2PictureChanges=screen._gen2PictureChanges or {}
  table.insert(screen._gen2PictureChanges,p)
  return p
end

function M.transform(screen,b,target)
  local function resolved(who)
    local species=who.species or who.mon.species
    for _,p in ipairs(screen._gen2PictureChanges or {})do
      if p.b==who and p.mon==who.mon and p.kind=='transform'then species=p.species end
    end
    return species
  end
  local species,before=resolved(target),resolved(b)
  -- Front entrance frames belong to this battler, never the target's live
  -- runner. A back picture has no front entrance animation to borrow.
  local animation=not b.isPlayer and require('src.pokemon.PicAnim').new(screen.data,species) or nil
  local p=mark(screen,b,'transform')
  if p then
    p.beforeSprite,p.beforeSpecies=b.sprite,before
    p.species,p.picAnim=species,animation
  end
  b.sprite=screen:speciesSprite(species,b.isPlayer) or b.sprite
  if not p then commit({kind='transform',b=b,species=species,picAnim=animation})end
end

function M.substitute(screen,b)
  if Version.isGen2() then mark(screen,b,'substitute') end
end

-- Native row admission binds the one actual VM (or selects the normal
-- disabled/missing-data fallback), never a parallel animation owner.
function M.admitted(screen,row,runner)
  local i=1
  while i<=#(screen._gen2PictureChanges or {})do
    local p=screen._gen2PictureChanges[i]
    if p.row==row then
      if runner then p.runner=runner;i=i+1 else remove(screen,i,true)end
    else i=i+1 end
  end
end

-- Called after the native VM tick, before an after-animation replaces it.
-- Drawing only reads; it cannot advance this owner.
function M.sync(screen)
  local i=1
  while i<=#(screen._gen2PictureChanges or {}) do
    local p=screen._gen2PictureChanges[i]
    local discard,apply=false,true
    if not current(screen,p)then discard,apply=true,false
    elseif p.runner then
      local value=p.runner.picOverride[side(p.b)]
      discard=p.runner~=screen.animPlayer.runtime or p.runner.stop or value==p.kind
    else
      local queued=false
      for _,row in ipairs(screen.queue or {})do if row==p.row then queued=true;break end end
      discard=not queued
    end
    if discard then remove(screen,i,apply)else i=i+1 end
  end
end

function M.override(screen,b)
  local overrides=screen.anim and screen.anim.picOverride
  local value=overrides and overrides[side(b)]
  -- false is an explicit dropsub, distinct from an unmodified tilemap.
  if value~=nil then return value end
  if pending(screen,b,'substitute')then return false end
  return b.substituteHP and 'substitute' or nil
end

function M.species(screen,b)
  if not Version.isGen2()then return b.species or b.mon.species end
  local p=pending(screen,b,'transform')
  if p then return p.beforeSpecies end
  local value=M.override(screen,b)
  if type(value)=='table' and value.kind=='beatup' then
    -- The wire parameter is wCurPartySpecies, not an index into the party.
    -- Keep the pinned VM's public `slot` field for compatibility.
    local catalog=screen.data.pokemon
    local cached=screen._gen2BeatUpIdentity
    if not(cached and cached.value==value and cached.catalog==catalog and cached.index==value.slot)then
      cached={value=value,catalog=catalog,index=value.slot}
      for name,def in pairs(catalog or {})do
        if type(def)=='table' and def.index==value.slot then cached.species=name;break end
      end
      screen._gen2BeatUpIdentity=cached
    end
    if cached.species then return cached.species end
  end
  return b.species or b.mon.species
end

function M.sprite(screen,b)
  if not Version.isGen2()then return b.sprite end
  local p=pending(screen,b,'transform')
  if p then return p.beforeSprite end
  local species=M.species(screen,b)
  if species~=(b.species or b.mon.species)then
    return screen:speciesSprite(species,b.isPlayer) or b.sprite
  end
  return b.sprite
end

function M.install(Screen)
  local sprite=Screen.pictureSprite
  function Screen:pictureSprite(b)
    if Version.isGen2()then return M.sprite(self,b)end
    return sprite(self,b)
  end
  local pic=Screen.battlerPic
  function Screen:battlerPic(b)
    if Version.isGen2() and (pending(self,b,'transform') or M.sprite(self,b)~=b.sprite)then
      return self:pictureStill(b)
    end
    return pic(self,b)
  end
  local visible=Screen.substituteVisible
  function Screen:substituteVisible(b)
    if Version.isGen2() and b then return M.override(self,b)=='substitute'end
    return visible(self,b)
  end
  local read=Screen.animPicState
  function Screen:animPicState(which)
    local state=read and read(self,which)
    if Version.isGen2() and self[which]then
      state=state or {};state.pic=M.override(self,self[which])
    end
    return state
  end
end
return M
