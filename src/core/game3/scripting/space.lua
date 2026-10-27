-- Source-facing field scripts observe the existing native runner. Native map
-- callbacks open execution scopes; querying or rendering never ticks scripts.
local Runtime=require('src.compat.gen1.ScriptRuntime')
local Bundle=require('src.compat.gen1.ScriptBundle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local runtime=Runtime.new()
local Space={TEMP_FIELD_EVENT_FLAGS={0x807,0x842}}
local function current(game,world)return runtime:current(game,world)end
local function methodOwner(name)
  local seams=package.loaded['src.mods.ModSeams']
  for i=#(seams and seams._journal or{}),1,-1 do
    local change=seams._journal[i]
    if change.tbl==Space and change.key==name and change.after==Space[name]then return change.owner end
  end
end
local function attributed(name,fn,...)
  local game=package.loaded['src.core.Game3']
  if game and game._withCallbackOwner then return game._withCallbackOwner(methodOwner(name),fn,...)end
  return fn(...)
end
function Space.isActive()
  local c=current();return c~=nil and c.world~=nil and c.vm~=nil and not c.disabled
end
function Space.getVm()return Space.vm end
function Space.getStore()return Space.store end
function Space.persistSession()
  local c,why=current();if not c then return false,why end
  -- Writes already go through native commands into the native in-memory save.
  -- The normal save owner alone decides when to write a file.
  return not(c.preview.vmSet or c.preview.storeSet),'native save owner persists script state'
end
function Space.ensureBundle()return runtime:bundle()end
function Space.installLabels(bundle)
  bundle=bundle or Space.bundle
  return bundle and bundle.labels or nil
end
function Space.scriptKey(name)
  local c=current();if not c then return nil end
  local key=runtime:key(c,name);return key and Bundle.sourceKey(key)
end
function Space.attachEventsToMaps(maps,bundle)
  assert(type(maps)=='table','invalid source map views')
  local c=current();if not c then return 0 end
  assert(maps~=c.maps,'native map definitions cannot be replaced by source event views')
  bundle=bundle or Space.bundle;local n=0
  for id,ev in pairs(bundle and bundle.events or{})do
    local def=maps[id]
    if def then
      assert(def~=c.maps[c.binding:nativeId(id)],'native map definitions cannot be replaced by source event views')
      for _,key in ipairs({'objects','bgEvents','coordEvents','mapScripts'})do
        if ev[key]~=nil then def[key]=Bundle.copy(ev[key])end
      end
      if ev.music~=nil then def.music=ev.music end
      n=n+1
    end
  end
  return n
end
function Space.activate(_mod,mapId,game,world)
  local c,why=current(game,world)
  if not(c and c.vm)then return nil,why or'no native field runner'end
  if mapId and c.id~=mapId then return nil,'activation belongs to the native map transition'end
  c.disabled=nil;c.preview.disabled=nil;return Space.vm
end
Space.retarget=Space.activate
function Space.deactivate()
  local c=current()
  if c then
    c.disabled=true;c.preview.disabled=true
    c.preview.vm,c.preview.vmSet,c.preview.store,c.preview.storeSet=nil,nil,nil,nil
  end
end
function Space.onMapEnter(mod,mapId,game,world,opts)
  local vm,why=Space.activate(mod,mapId,game,world);if not vm then return nil,why end
  Space.runEnterScripts(mod,mapId,game,world,opts);return vm
end
function Space.runEnterScripts()return Boundary.invoke('runEnterScripts')end
function Space.runOnFrame()return Boundary.invoke('runOnFrame')end
function Space.runImmediately(key)return runtime:start(Space.scriptKey(key)or key)end
function Space.runOnResume(id)return runtime:request(5,id)end
function Space.runOnWarpIntoMap(id)return runtime:request(4,id)end
function Space.runOnReturnToField(id)return runtime:request(7,id)end
function Space.runOnDiveWarp(id)return runtime:request(6,id)end
function Space.runOnLoad(id)return runtime:request(1,id)end
function Space.returnToField(id)
  local a=Space.runOnResume(id);local b=Space.runOnReturnToField(id);return a or b
end
function Space.scheduleOnFrame()
  local c=current();if not(c and c.vm)then return false end
  c.pendingOnFrame=true;return true
end
local tempFlags={firered={0x807,0x842},leafgreen={0x807,0x842},
  emerald={0x8ad,0x8ae,0x889,0x8c1,0x880},ruby={0x84d,0x84e,0x829,0x861},sapphire={0x84d,0x84e,0x829,0x861}}
function Space.tempFieldEventFlags(session)
  local edition=session and session.edition or Version.get()
  return Bundle.copy(assert(tempFlags[edition],'no native GBA temporary field flags'))
end
function Space.clearTempFieldEventFlags()
  local store=Space.store;if not store then return false end
  for _,id in ipairs(Space.tempFieldEventFlags())do store.flags[id]=false end
  return true
end
function Space.objectVisible(obj)
  local id=tonumber(obj and(obj.flag or obj.flagId))
  if not id or id==0 or id==65535 then return true end
  local store=Space.store
  return store~=nil and store.flags[id]~=true
end
function Space.resolveObjectGraphicsId(obj,neighbor)
  if not obj then return nil end
  local c=current();if not c then return nil end
  local graphics=tonumber(obj.graphics or obj.graphicsId)
  local store=neighbor and neighbor.store or Space.store
  if not store then return nil end
  if obj.graphicsVar then
    local value=store.vars[obj.graphicsVar]
    if type(value)=='number'and value~=0 then graphics=value end
  end
  local slot=tonumber(obj.varSprite)
  if not slot and graphics and graphics>=240 and graphics<=255 then slot=graphics-240 end
  if slot then
    local value=store.vars[0x4010+slot]
    if value==nil then return nil end
    graphics=value%256
  end
  local meta=c.data.gen3_object_sheets
  if graphics and meta and graphics>=meta.count then
    return nil,'object graphics id outside the native cartridge catalogue'
  end
  return graphics
end
function Space.resolveObjectSprite(obj)
  if obj and type(obj.sprite)=='string'and obj.sprite~=''then return obj.sprite end
  local id=Space.resolveObjectGraphicsId(obj)
  return id and('SPRITE_G3_%03d'):format(id)
end
function Space.neighborObjectState(mapId)return runtime:neighbor(mapId)end
function Space.refreshObjectGraphics()
  local c=current();if not(c and c.world)then return false end
  if c.preview.vmSet or c.preview.storeSet then return false,'source preview lease is active'end
  if c.world.syncObjectVisibility then c.world:syncObjectVisibility()end
  local seen={}
  local function refresh(npc)
    if npc and not seen[npc]and npc.refreshSprite then seen[npc]=true;npc:refreshSprite(c.data)end
  end
  for _,npc in pairs(c.world.npcPool or{})do refresh(npc)end
  for _,npc in ipairs(c.world.npcs or{})do refresh(npc)end
  return true
end
function Space.startScript(key,localId,facing)
  local c=current();if not(c and c.world)then return false,'no native field runner'end
  facing=facing or c.world.player.facing
  return runtime:start(key,localId or 0,facing)
end
function Space.install(mod)
  local bundle,why=Space.ensureBundle();if not bundle then return nil,why end
  Space._mod=mod;return bundle
end
function Space.release()runtime:release()end
function Space.cancelOwner(who)runtime:cancelOwner(who)end
function Space._nativePhase(name,game,world,mapId,body)
  return runtime:phase(name,game,world,mapId,body,function(...)
    local c=current(game,world)
    if name=='runOnFrame'and c then c.pendingOnFrame=nil end
    return attributed(name,Space[name],...)
  end)
end
function Space._nativeTick(runner,body)return runtime:tick(runner,body)end
setmetatable(Space,{
  __index=function(_,key)
    local c=current();if not c then return key=='active'and false or nil end
    if key=='active'then return c.world~=nil and c.vm~=nil and not c.disabled end
    if key=='mapId'then return c.id end
    if key=='vm'then if c.disabled then return nil end;if c.preview.vmSet then return c.preview.vm end;return c.vm end
    if key=='store'then if c.preview.storeSet then return c.preview.store end;return c.store end
    if key=='bundle'then return c.dataset.override or c.bundle end
    if key=='_pendingOnFrame'then return c.pendingOnFrame==true end
  end,
  __newindex=function(t,key,value)
    if key=='vm'or key=='store'or key=='bundle'then
      local c,why=current();assert(c,why)
      assert(value==nil or type(value)=='table','invalid source script replacement')
      if key=='bundle'then
        assert(c.dataset.overrideOwner==nil or c.dataset.overrideOwner==runtime:owner(),'script bundle replacement belongs to another mod')
        c.dataset.override=value~=c.bundle and value or nil
        c.dataset.overrideOwner=c.dataset.override and runtime:owner()or nil
      else
        local who=runtime:owner()
        assert(c.preview[key..'Owner']==nil or c.preview[key..'Owner']==who,'script preview lease belongs to another mod')
        local original=c[key];c.preview[key]=value;c.preview[key..'Set']=value~=original
        c.preview[key..'Owner']=c.preview[key..'Set']and who or nil
      end
    elseif key=='_pendingOnFrame'then local c=current();if c then c.pendingOnFrame=value==true end
    elseif key=='active'or key=='mapId'then error('script field belongs to its native owner: '..key,2)
    else rawset(t,key,value)end
  end,
})
return Space
