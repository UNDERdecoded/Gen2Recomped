-- Owned, live observations of the native object pool. No second actor loop.
local Session = require('src.compat.gen1.NativeSession')
local Identity = require('src.compat.gen1.MapIdentity')
local Version = require('src.core.GameVersion')
local R = {}; R.__index = R
local directions = {up=true,down=true,left=true,right=true}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function integer(v,lo,hi) return finite(v) and v%1==0 and v>=lo and v<=hi end
local function copy(v,seen)
  if type(v)~='table' then
    if type(v)=='string' or type(v)=='number' or type(v)=='boolean' then return v end
    return nil
  end
  seen=seen or {}; if seen[v] then return seen[v] end
  local out={}; seen[v]=out
  for k,value in pairs(v) do if type(k)=='string' or type(k)=='number' then out[k]=copy(value,seen) end end
  return out
end
local fields={cellX='cellX',cellY='cellY',px='px',py='py',targetX='targetX',targetY='targetY',
  moving='moving',progress='progress',facing='facing',stepFlip='stepFlip',animClock='animClock',
  invisible='invisible',hidden='hidden',passable='passable',runtime='runtime',
  customFrame='fixedFrame',raiseX='shiftPx',homeX='roamOriginX',homeY='roamOriginY'}
local boolWrite={hidden='hidden',invisible='invisible',passable='passable'}
function R.new() return setmetatable({views=setmetatable({},{__mode='kv'}),records=setmetatable({},{__mode='kv'})},R) end
function R:release()
  if self.context then self.context.retired=true end
  self.context=nil
end
function R:current(game)
  local g,w,p=Session.resolve(game)
  local c=self.context
  if not g then self:release(); return nil,w end
  if c and (c.retired or c.game~=g or c.world~=w or c.player~=p or c.map~=w.map or c.def~=w.map.def or c.data~=g.data
      or c.maps~=g.data.maps or c.save~=g.save or c.loader~=g.mods or c.edition~=Version.get()
      or c.binding:legacyId(w.map.id)~=c.id) then
    self:release(); c=nil
  end
  if not c then
    c={game=g,world=w,player=p,map=w.map,def=w.map.def,data=g.data,maps=g.data.maps,
      save=g.save,loader=g.mods,edition=Version.get()}
    c.binding=Identity.bind(c.maps,c.edition)
    local why; c.id,why=c.binding:legacyId(w.map.id)
    if not c.id then return nil,why end
    self.context=c
  end
  return c
end
local function live(c)
  if c.retired then return false end
  local g,w,p=Session.resolve(c.game)
  if g~=c.game or w~=c.world or p~=c.player or w.map~=c.map or w.map.def~=c.def
      or g.data~=c.data or g.data.maps~=c.maps or g.save~=c.save or g.mods~=c.loader
      or Version.get()~=c.edition or c.binding:legacyId(c.map.id)~=c.id then c.retired=true; return false end
  return true
end
local function member(c,e,mapId)
  if not live(c) then return false end
  if mapId==c.map.id then
    for _,a in ipairs(c.world.npcs or c.world.entities or {}) do if a==e then return true end end
  else
    for _,nb in ipairs(c.world.neighbors or {}) do
      if nb.map and nb.map.id==mapId and c.maps[mapId]==nb.map.def then
        for _,a in ipairs(nb.peers or {}) do if a==e then return true end end
      end
    end
    for _,ghost in ipairs(c.world.ghosts or {}) do
      local map=ghost.nb and ghost.nb.map
      if map and map.id==mapId and c.maps[mapId]==map.def and ghost.npc==e then return true end
    end
  end
  return false
end
function R:view(c,e,mapId)
  local class=package.loaded['src.world.NPC']
  if type(class)~='table' or getmetatable(e)~=class or type(e.def)~='table'
      or not integer(e.def.index,1,65535) then return nil,'unsupported native object identity' end
  local id,why=c.binding:legacyId(mapId); if not id then return nil,why end
  local record=self.views[e]
  if record and record.context==c and record.mapId==mapId and not record.retired then return record.view end
  record={context=c,actor=e,mapId=mapId,extras={},definition=copy(e.def)}
  record.definition.localId=e.def.index
  local function valid()
    if record.retired then return false end
    if not member(c,e,mapId) or c.binding:legacyId(mapId)~=id then record.retired=true; return false end
    return true
  end
  local function read(_,key)
    if not valid() then return nil end
    if key=='passable' then return e.passable==true or e.def.passable==true end
    if key=='runtime' then return e.def.runtime==true end
    if fields[key] then return e[fields[key]] end
    if key=='def' then return record.definition end
    if key=='localId' or key=='originLocalId' then return e.def.index end
    if key=='id' then return e.id end
    if key=='originMapId' then return id end
    if key=='originMapGroup' then return c.maps[mapId].group end
    if key=='originMapNum' then return c.maps[mapId].number end
    if key=='graphicsId' then
      -- The extractor preserves the cartridge row on the actual sprite.
      -- Variable sprites resolve to a different sheet without changing def.
      local sprite=e.sprite and e.sprite.def
      local key=type(sprite)=='table' and sprite.id
      return type(key)=='string' and tonumber(key:match('^SPRITE_G3_(%d+)$')) or e.def.graphicsId
    end
    if key=='visible' then return not(e.hidden or e.visible==false or e.berryVisualEmpty) end
    if key=='currentElevation' or key=='elevation' then return e.elevation or e.gen3Elevation or e.def.elevation or 0 end
    if key=='stepFrames' then return e.scriptStepLen or e.stepFrames or 16 end
    if key=='raiseY' then
      local observed={}; for k,v in pairs(e) do observed[k]=v end
      setmetatable(observed,class)
      local _,_,py=class.pose(observed)
      return e.py-py
    end
    if key=='movementType' then return e.gen3MovementType or e.def.movementType end
    if key=='frozen' then return e.frozen==true or e.gen3ScriptFrozen==true end
    if key=='scriptBusy' then
      for _,mv in ipairs(c.world.scriptMoves or {}) do if mv.entity==e then return true end end
      return false
    end
    return record.extras[key]
  end
  local function write(_,key,value)
    assert(valid(),'native object view retired')
    if boolWrite[key] then
      assert(type(value)=='boolean','invalid object boolean'); e[boolWrite[key]]=value
    elseif key=='visible' then
      assert(type(value)=='boolean','invalid object visibility'); e.hidden=not value; e.visible=value
    elseif key=='facing' then
      assert(directions[value],'invalid object facing'); e.facing=value
    elseif key=='raiseX' then
      assert(finite(value) and math.abs(value)<=16777216,'invalid object offset'); e.shiftPx=value
    elseif key=='customFrame' then
      local frames=e.sprite and e.sprite.def and math.max(e.sprite.def.frames or 1,e.sprite.def.poseFrames or 1) or 1
      assert(value==nil or integer(value,0,frames-1),'invalid object frame'); e.fixedFrame=value
    elseif key=='frozen' then
      assert(type(value)=='boolean','invalid object freeze'); e.gen3ScriptFrozen=value or nil
    elseif fields[key] or key=='def' or key=='localId' or key=='graphicsId' or key=='id'
        or key=='currentElevation' or key=='elevation' or key=='stepFrames' or key=='movementType'
        or key=='scriptBusy' or key=='raiseY' or type(key)=='string' and key:match('^origin') then
      error('object '..key..' requires a native command owner',2)
    else record.extras[key]=value end
  end
  record.view=setmetatable({},{__index=read,__newindex=write})
  self.views[e]=record
  self.records[record.view]=record
  return record.view
end
function R:actor(view)
  local r=view and self.records[view]
  if r then
    if not r.retired and r.view.localId~=nil then return r.actor,r.context,r.mapId end
    r.retired=true; return nil,'native object view retired'
  end
  return nil,'foreign object view'
end
function R:pool(mapId,game)
  local c,why=self:current(game); if not c then return nil,why end
  local nativeId=c.map.id
  if mapId then
    nativeId=c.binding:nativeId(mapId)
    if not nativeId then
      -- Registries can acquire authored maps without replacing data.maps.
      -- Re-index on a miss; never fall back to the current map's objects.
      c.binding=Identity.bind(c.maps,c.edition)
      nativeId=c.binding:nativeId(mapId)
    end
    if not nativeId then return nil,'unknown object map' end
  end
  local list,seen,ids={},{},{}
  local function add(e)
    if seen[e] then return true end
    local view,err=self:view(c,e,nativeId); if not view then return nil,err end
    if ids[view.localId] then return nil,'ambiguous native object local ID' end
    seen[e]=true; ids[view.localId]=true; list[#list+1]=view
    return true
  end
  if nativeId==c.map.id then
    for _,e in ipairs(c.world.npcs or c.world.entities or {}) do
      if e~=c.player then local ok,err=add(e); if not ok then return nil,err end end
    end
  else
    for _,nb in ipairs(c.world.neighbors or {}) do
      if nb.map and nb.map.id==nativeId then
        for _,e in ipairs(nb.peers or {}) do local ok,err=add(e); if not ok then return nil,err end end
      end
    end
    for _,ghost in ipairs(c.world.ghosts or {}) do
      if ghost.nb and ghost.nb.map and ghost.nb.map.id==nativeId then
        local ok,err=add(ghost.npc); if not ok then return nil,err end
      end
    end
  end
  return list,c
end
function R:walkPhase(view)
  local e=self:actor(view)
  return e and not e.sliding and e:walkPhase() or 0
end
R.integer=integer
R.copy=copy
R.directions=directions
return R
