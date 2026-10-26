-- Compatibility facade over native NPCs; all motion stays on the native queue.
local Runtime=require('src.compat.gen1.ObjectRuntime')
local Identity=require('src.compat.gen1.MapIdentity')
local Player=require('src.core.game3.player')
local runtime=Runtime.new()
local Objects={PLAYER_LOCAL_ID=0xFF}
function Objects.isPlayer(id) id=tonumber(id); return id==0xFF or id==0x800F end
function Objects.find(id)
  if Objects.isPlayer(id) then return runtime:current() and Player or nil end
  for _,view in ipairs(runtime:pool() or {}) do if view.localId==tonumber(id) then return view end end
end
function Objects.findObjectByLocalIdAndMap(id,group,number)
  if group==nil and number==nil or Objects.isPlayer(id) then return Objects.find(id) end
  local c=runtime:current(); if not c then return nil end
  local mapId=Identity.lookup(c.edition,tonumber(group),tonumber(number))
  if not mapId then return nil end
  for _,view in ipairs(runtime:pool(mapId) or {}) do if view.localId==tonumber(id) then return view end end
end
function Objects.layoutBounds(def)
  local l=def and def.midLayout
  if l and (l.width or 0)>0 and (l.height or 0)>0 then return {w=l.width,h=l.height} end
end
function Objects.offMap(bounds,eo)
  return bounds~=nil and (eo.cellX<0 or eo.cellY<0 or eo.cellX>=bounds.w or eo.cellY>=bounds.h) or false
end
function Objects.forDraw()
  local out={}; local list,c=runtime:pool(); if not list then return out end
  for _,v in ipairs(list) do
    -- The source follower has its own actor/presentation contract. Keep its
    -- native NPC available to current/find and the native update lists, but
    -- do not emit it again as ordinary map artwork (or as a player fallback).
    local actor=runtime:actor(v)
    if actor and actor.optionalFollower~=true and v.visible and not(v.hidden or v.invisible)
        and (v.moving or v.scriptBusy or c.map:inBounds(v.cellX,v.cellY)) then out[#out+1]=v end
  end
  return out
end
function Objects.listActive(_mod,game,mapId)
  local ids={}
  for _,v in ipairs(runtime:pool(mapId,game) or {}) do if v.visible and not v.hidden then ids[#ids+1]=v.localId end end
  return ids
end
function Objects.at(x,y)
  if not(Runtime.integer(x,-16777216,16777216) and Runtime.integer(y,-16777216,16777216)) then return nil end
  for _,v in ipairs(runtime:pool() or {}) do
    if v.visible and not v.hidden and (v.moving and v.targetX or v.cellX)==x
        and (v.moving and v.targetY or v.cellY)==y then return v end
  end
end
function Objects.elevationsCompatible(a,b) a,b=tonumber(a) or 0,tonumber(b) or 0; return a==0 or b==0 or a==b end
function Objects.blocks(x,y,except,elevation)
  for _,v in ipairs(runtime:pool() or {}) do
    if v.localId~=tonumber(except) and v.visible and not(v.hidden or v.passable)
        and Objects.elevationsCompatible(elevation,v.currentElevation) then
      if v.cellX==x and v.cellY==y or v.moving and v.targetX==x and v.targetY==y then return true end
    end
  end
  return false
end
function Objects.playerBlocks(x,y,elevation)
  local c=runtime:current(); local p=c and c.player
  return p~=nil and Objects.elevationsCompatible(elevation,p.elevation)
    and (p.cellX==x and p.cellY==y or p.moving==true and p.targetX==x and p.targetY==y) or false
end
function Objects.walkPhase(view) return view==Player and Player.walkPhase() or runtime:walkPhase(view) end
function Objects.scriptFace(view,dir)
  if not Runtime.directions[dir] then return false end
  if view==Player then if not runtime:current() then return false end; Player.facing=dir; return true end
  local e=runtime:actor(view); if not e or e.facingLocked then return false end
  e.facing=dir; return true
end
function Objects.turnObject(id,dir)
  dir=({[1]='down',[2]='up',[3]='left',[4]='right'})[dir] or dir
  return Objects.scriptFace(Objects.find(id),dir)
end
function Objects.hideObjectAt(id,g,n)
  local v=Objects.findObjectByLocalIdAndMap(id,g,n); if not v then return false end
  v.visible=false; return true
end
function Objects.showObjectAt(id,g,n)
  local v=Objects.findObjectByLocalIdAndMap(id,g,n); if not v then return false end
  v.visible=true; return true
end
function Objects.hideObject(id) return Objects.hideObjectAt(id) end
function Objects.showObject(id) return Objects.showObjectAt(id) end
function Objects.freeze(id)
  local v=Objects.find(id); if not v or v==Player then return false end; v.frozen=true; return true
end
function Objects.unfreeze(id)
  local v=Objects.find(id); if not v or v==Player then return false end; v.frozen=false; return true
end
function Objects.setMovementType(id,mt)
  local v=Objects.find(id); local e,c=runtime:actor(v)
  if not e or not Runtime.integer(mt,0,255) or not(c.data.constants.gen3MovementTypes or {})[mt] then return false end
  return e:setMovementType(c.data,mt)
end
function Objects.facePlayer(id)
  local e,c=runtime:actor(Objects.find(id)); if not e then return false end
  e:facePlayer(c.player); return true
end
function Objects.updateElevation(view)
  local e,c,mapId=runtime:actor(view); if not e then return false end
  local map=mapId==c.map.id and c.map
  if not map then for _,nb in ipairs(c.world.neighbors or {}) do if nb.map.id==mapId then map=nb.map; break end end end
  if not map then return false end; e:updateElevation(map); return true
end
function Objects.loadMap(game,mapId)
  local c,why=runtime:current(game); if not c then return nil,why end
  if mapId~=c.id then return nil,'object loading belongs to the native map transition' end
  local list,why=runtime:pool(mapId,game)
  if not list then return nil,why end
  return list
end
function Objects.clear() runtime:release() end
Objects.reset=Objects.clear
Objects.release=Objects.clear
-- Internal shared observer for the separate, map-local neighbour facade.
function Objects._pool(mapId)
  local list,why=runtime:pool(mapId)
  if not list then return nil,why end
  return list
end
setmetatable(Objects,{__index=function(_,key)
  if key=='_mapId' then local c=runtime:current(); return c and c.id end
  if key=='_byId' or key=='_order' then
    local byId,order={},{}
    for _,v in ipairs(runtime:pool() or {}) do byId[v.localId]=v; order[#order+1]=v.localId end
    return key=='_byId' and byId or order
  end
end})
return Objects
