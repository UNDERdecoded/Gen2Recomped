-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Gold/Silver/Crystal's native cast owns its rolled individual until the
-- verdict closes. Presentation consumers observe this state, never reroll it.
local M={CAST_FRAMES=40,BITE_FRAMES=40}
local Version=require('src.core.GameVersion')
local Runtime=require('src.mods.Runtime')
local rods={OLD_ROD=58,GOOD_ROD=59,SUPER_ROD=61,ITEM_058=58,ITEM_059=59,ITEM_061=61}
local delta={up={0,-1},down={0,1},left={-1,0},right={1,0}}
local active=setmetatable({},{__mode='k'})
local owners=setmetatable({},{__mode='k'})
local prepared=setmetatable({},{__mode='k'})
local admitting=setmetatable({},{__mode='k'})
local rolling=setmetatable({},{__mode='k'})

function M.isRod(id,items)
 local index=rods[id];local def=items and items[id]
 return index~=nil and not(def and def.index and def.index~=index)
end
local function context(world,game)
 if not(Version.isGen2() and game and game.overworld==world
  and game.data and game.save and world.map and world.player and game.stack
  and type(game.stack.top)=='function' and type(game.stack.push)=='function')then return false end
 if game.stack.worldOwner then
  return game.stack.worldState==world and game.world==world and game.phase=='play'
 end
 -- The upstream stack keeps the native field among its screens. A retired
 -- field cannot keep a cast alive merely because game.overworld names it.
 for _,state in ipairs(game.stack.states or{})do if state==world then return true end end
 return false
end
local function refs(world,game)
 return setmetatable({world=world,game=game,data=game.data,save=game.save,
  map=world.map,player=world.player,x=world.player.cellX,y=world.player.cellY,
  facing=world.player.facing},{__mode='v'})
end
local function valid(r,edition)
 local w,g=r and r.world,r and r.game
 return w and g and context(w,g) and Version.get()==edition
  and g.data==r.data and g.save==r.save and w.map==r.map and w.player==r.player
  and w.player.cellX==r.x and w.player.cellY==r.y and w.player.facing==r.facing
end
local function fieldReady(world,game,ignoreOverlay)
 if not context(world,game)then return false end
 if game.linkSession or game.linkNet and not game.linkNet.closed then return false end
 local p,map=world.player,world.map
 if type(p.cellX)~='number' or type(p.cellY)~='number' or p.cellX%1~=0 or p.cellY%1~=0
  or not map:inBounds(p.cellX,p.cellY)then return false end
 if world.battleActive or world:busy(ignoreOverlay) or p.moving or p.surfing or p.spinning
  or p.inputLocked or p.fieldMove or p.stairExit or world.iceSlide or world.mapSetup
  or world.headbutt or world.moveState or world.fieldMove or world._modScriptLock then return false end
 return true
end
function M.canUse(world,game,rod,ignoreOverlay)
 if admitting[world] or rolling[world] or not fieldReady(world,game,ignoreOverlay)
  or not M.isRod(rod,game.data.items)then return false end
 local p=world.player;local d=delta[p.facing or 'down'];if not d then return false end
 local x,y=p.cellX+d[1],p.cellY+d[2]
 return M.facingWater(world,x,y)
end

function M.facingWater(world,x,y)
 if world.map:inBounds(x,y)then return world.map:isWaterCell(x,y) and true or false end
 -- Read the same un-clamped native connection landing as movement. The rod
 -- stays in this map's coordinates and still uses this map's fish group.
 local dest,tileset,cx,cy=world:connectionLanding(world.player.facing)
 return dest~=nil and require('src.world.Map').defIsWaterCell(dest,tileset,cx,cy) and true or false
end

local function rollNative(world,game,rod,roll)
 if not context(world,game) or not M.isRod(rod,game.data.items) then return 'nowhere' end
 local p,map=world.player,world.map;local d=delta[p.facing or 'down']
 if type(p.cellX)~='number' or type(p.cellY)~='number' or p.cellX%1~=0 or p.cellY%1~=0
  or not map:inBounds(p.cellX,p.cellY)then return 'nowhere' end
 if p.surfing or not d then return 'nowhere' end
 local x,y=p.cellX+d[1],p.cellY+d[2]
 if not M.facingWater(world,x,y)then return 'nowhere' end
 local group=map.def and map.def.fishGroup
 if not group or group==0 or group=='FISHGROUP_NONE' then return 'nofish' end
 local tod=world.clockTimeOfDay and world.clockTimeOfDay() or world.tod
 local enc,handled,candidates,resolvedGroup=roll(game.data,rod,map.def,tod,game.save)
 if not handled then return 'nofish' end -- never substitute the Gen1 pond
 if Runtime.wantsHook('encounter.fishing')then
  enc=Runtime.call('encounter.fishing',function()return enc end,rod,map.id,candidates,
   {fishGroup=resolvedGroup or group,data=game.data,maps=game.data.maps,
    encounters=world.encounters,tod=tod,daytime=tod})
 end
 if enc==nil or enc==false then return 'nibble' end
 assert(type(enc)=='table' and (type(enc.species)=='string'or type(enc.species)=='number')and type(enc.level)=='number'
  and enc.level%1==0 and enc.level>=1 and enc.level<=100,'invalid native fishing encounter')
 -- The native constructor validates/resolves its own edition's species
 -- identity before drawing DVs. Do not copy a second naming registry here.
 local wild=require('src.pokemon.Pokemon').new(game.data,enc.species,enc.level)
 require('src.battle.BattleState').giveWildHeldItem(game.data,wild)
 prepared[wild]={refs=refs(world,game),edition=Version.get(),species=wild.species,level=wild.level}
 return 'battle',wild
end
function M.roll(world,game,rod,roll)
 if rolling[world]then return 'nowhere' end
 rolling[world]=true
 local ok,outcome,wild=pcall(rollNative,world,game,rod,roll)
 rolling[world]=nil
 if not ok then error(outcome,0)end
 return outcome,wild
end

-- Only a native individual made by the roll above may use the constructor's
-- no-reroll handoff. Consumed before any battle/stack/dex mutations.
function M.takePrepared(game,wild,species,level)
 local r=prepared[wild]
 assert(r and valid(r.refs,r.edition) and r.refs.game==game
  and r.species==species and r.level==level and wild.species==species
  and wild.level==level,'expired or invalid native fishing individual')
 prepared[wild]=nil
 return wild
end

local function clear(world,st,keepWild)
 local r=owners[st];owners[st]=nil
 if active[world]==st then active[world]=nil end
 if world.fishing==st then world.fishing=nil end
 local p=r and r.refs.player
 if p and p.fishingState==st then
  p.fishing=nil;p.fishingState=nil;p.spriteYOffset=0
 end
 if r and world.emote==r.bubble then world.emote=nil end
 if not keepWild and st.wild then prepared[st.wild]=nil end
end
function M.cancel(world)
 local st=active[world];if st then clear(world,st)end
end
local function finishBattle(world,game,wild)
 local ok,result=pcall(function()
  local battle=world:_beginFishingBattle(wild)
  assert(prepared[wild]==nil and battle and battle.enemy and battle.enemy.mon==wild,
   'native fishing battle must consume the exact individual')
  return battle
 end)
 prepared[wild]=nil
 if not ok then error(result,0)end
 return result
end
function M.begin(world,game,outcome,wild)
 if rolling[world] or not fieldReady(world,game)then return false end
 local p=world.player;local d=delta[p.facing or 'down']
 if not d or not M.facingWater(world,p.cellX+d[1],p.cellY+d[2])then return false end
 assert(outcome=='battle' or outcome=='nibble' or outcome=='nofish','invalid fishing outcome')
 if outcome=='battle'then
  local r=prepared[wild]
  assert(r and valid(r.refs,r.edition) and r.refs.world==world,'native fishing individual required')
 else assert(wild==nil,'empty fishing outcome cannot carry an individual')end
 local x,y=p.cellX+d[1],p.cellY+d[2]
 local st={phase='cast',timer=M.CAST_FRAMES,outcome=outcome,wild=wild,
  bobber={cellX=x,cellY=y,px=x*16,py=y*16},facing=p.facing or 'down'}
 owners[st]={refs=refs(world,game),edition=Version.get()};active[world]=st
 world.fishing=st;p.fishing=true;p.fishingState=st
 return st
end
function M.use(world,game,rod)
 if not M.canUse(world,game,rod)then return 'nowhere' end
 admitting[world]=true
 local wild
 local ok,result=pcall(function()
  local outcome;outcome,wild=world:rollFishing(rod)
  if outcome=='nowhere'then return outcome end
  world:beginFishing(outcome,wild)
  local st=active[world]
  if not(st and world.fishing==st and st.outcome==outcome and st.wild==wild)then return 'nowhere' end
  return outcome
 end)
 admitting[world]=nil
 if not ok or result=='nowhere'then
  if wild then prepared[wild]=nil end
  M.cancel(world)
 end
 if not ok then error(result,0)end
 return result
end
function M.try(world,game,rod)
 if not M.canUse(world,game,rod)then return 'nowhere' end
 admitting[world]=true
 local wild
 local ok,result=pcall(function()
  local outcome;outcome,wild=world:rollFishing(rod)
  if wild then finishBattle(world,game,wild)end
  return outcome
 end)
 admitting[world]=nil
 if not ok then if wild then prepared[wild]=nil end;error(result,0)end
 return result
end

function M.tick(world,game)
 local st=active[world];if not st then return end
 local r=owners[st]
 if not(r and valid(r.refs,r.edition)) or world.fishing~=st then clear(world,st);return end
 if game.stack:top() and game.stack:top()~=world then return end
 if st.phase=='done'then return end
 if st.timer>0 then
  st.timer=st.timer-1
  world.player.spriteYOffset=st.phase=='bite' and st.timer%2 or 0
  return
 end
 world.player.spriteYOffset=0
 if st.phase=='cast' and st.outcome=='battle'then
  st.phase='bite';st.timer=M.BITE_FRAMES
  r.bubble={npc=world.player,frames=M.BITE_FRAMES,totalFrames=M.BITE_FRAMES,bubble=1,age=0}
  world.emote=r.bubble
  return
 end
 st.phase='done'
 local Strings=require('src.core.Strings')
 local line=st.outcome=='battle' and Strings('Oh!\nA bite!') or Strings('Not even a nibble!')
 local ok,err=pcall(function()
  local box=require('src.render.TextBox').new(game,line,function()
   if not(owners[st]==r and valid(r.refs,r.edition) and world.fishing==st)then
    clear(world,st);return
   end
   clear(world,st,true)
   if st.wild then finishBattle(world,game,st.wild)end
  end)
  r.box=box;game.stack:push(box)
 end)
 if not ok then clear(world,st);error(err,0)end
end
function M.poll()
 for world,st in pairs(active)do
  local r=owners[st];local exists=true
  if r and r.box then
   exists=false
   for _,screen in ipairs(r.refs.game and r.refs.game.stack.states or{})do if screen==r.box then exists=true;break end end
  end
  if not(r and valid(r.refs,r.edition)) or world.fishing~=st or not exists then clear(world,st)end
 end
end
function M.release()
 for world,st in pairs(active)do clear(world,st)end
 prepared=setmetatable({},{__mode='k'})
end
return M
