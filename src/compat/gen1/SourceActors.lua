-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Draw-only actors join native sorting, never NPC updates or collision pools.
local Native=require('src.compat.gen1.NativeSession')
local Scope=require('src.render.GraphicsScope')
local M={}
local bindings=setmetatable({},{__mode='kv'})
function M.bind(actor,record)bindings[actor]=record end
function M.renderer(actor)
 local r=bindings[actor]
 if not r or r.retired or not r.presentationSet then return nil,false end
 if r.view.localId==nil then return nil,false end
 return r.extras.sprite,true
end
function M.releaseOwner(_,who)
 for actor,r in pairs(bindings)do if r.presentationOwner==who then
  r.presentationSet=nil;r.extras.sprite=nil;bindings[actor]=nil
 end end
end
function M.release()
 for actor,r in pairs(bindings)do r.presentationSet=nil;r.extras.sprite=nil;bindings[actor]=nil end
end
require('src.core.game3.asset_stream').register(M)
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function M.collect(actors)
 assert(type(actors)=='table','actor collection required')
 local g,w=Native.resolve();if not g then return actors end
 local refs=setmetatable({game=g,world=w,map=w.map,save=g.save,data=g.data},{__mode='v'})
 local edition=require('src.core.GameVersion').get()
 local function valid()
  local owner,current=Native.resolve()
  return owner~=nil and owner==refs.game and current==refs.world and current.map==refs.map and owner.save==refs.save
   and owner.data==refs.data and require('src.core.GameVersion').get()==edition
 end
 for i,r in ipairs(w.ripples or{})do
  local row={kind='native_ripple',i=i,x=r.px,y=r.py,sortY=r.py,elevation=0,_nativeEffect=true}
  local observed=setmetatable({r},{__mode='v'})
  row.draw=function(_,cx,cy)
   if not valid()then return false end
   local world,ripple=refs.world,observed[1];if not ripple then return false end
   local exists=false;for _,v in ipairs(world.ripples or{})do if v==ripple then exists=true end end
   if not exists then return false end
   local sprite=world:rippleSprite();if sprite then world:drawRippleRing(sprite,ripple,cx,cy);return true end;return false
  end
  actors[#actors+1]=row
 end
 return actors
end
function M.withActors(game,world,body)
 local source=package.loaded['src.core.game3.field_effects']
 if not(source and source.collectActors)or source._hasActorExtensions and not source._hasActorExtensions()then return body()end
 local rows={};local nativeRows={}
 -- Native effect records remain identifiable even if a mod removes flags.
 M.collect(rows);for _,row in ipairs(rows)do nativeRows[row]=true end
 local boundary=require('src.compat.gen1.ScriptBoundary')
 local base=function(target)
  if target~=rows then return M.collect(target)end
  return rows
 end
 boundary.dispatch('field.collectActors',function()return base(rows)end,function()
  return require('src.compat.gen1.SourceCall').call(source,'collectActors',rows,world.camera and world.camera.x or 0,world.camera and world.camera.y or 0)
 end)
 local additions={};local open=true
 for _,row in ipairs(rows)do if not nativeRows[row]then
  assert(type(row)=='table'and finite(row.x)and finite(row.y)and finite(row.sortY or row.y),'invalid field actor position')
  assert(type(row.draw)=='function'or type(row.renderer)=='table'and type(row.renderer.draw)=='function','field actor needs a renderer')
  local e={px=row.x,py=row.sortY or row.y,cellX=math.floor(row.x/16),cellY=math.floor(row.y/16),
   elevation=row.elevation or 0,gen3Elevation=row.elevation or 0,facing=row.facing or'down',passable=true,def={passable=true},customSourceActor=true}
  function e:pose()return row.renderer,row.x,row.y,self.facing,row.walkPhase or 0,false,false end
  function e:draw(cx,cy)
   if not open then return false end
   if row.draw then return row:draw(cx,cy)end
   return row.renderer:draw(row.x,row.y,cx,cy,self.facing,row.walkPhase or 0,row.stepFlip==true)
  end
  additions[#additions+1]=e
 end end
 if #additions==0 then return body()end
 local original=world.entities;local combined={}
 for i,e in ipairs(original or{})do combined[i]=e end
 for _,e in ipairs(additions)do combined[#combined+1]=e end
 world.entities=combined
 local ok,result=Scope.call(body);open=false;world.entities=original
 if not ok then error(result,0)end
 return result
end
return M
