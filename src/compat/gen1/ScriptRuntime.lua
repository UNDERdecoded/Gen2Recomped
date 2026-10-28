-- Source scripting observations and commands over the existing native runner.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Identity=require('src.compat.gen1.MapIdentity')
local Store=require('src.compat.gen1.ScriptStore')
local Maps=require('src.compat.gen1.ScriptMap')
local Bundle=require('src.compat.gen1.ScriptBundle')
local Iteration=require('src.compat.gen1.TableIteration')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local R={};R.__index=R
local function owner()
  local runtime=package.loaded['src.mods.Runtime'];local g=package.loaded['src.core.Game3']
  return runtime and runtime.currentMod or g and g._callbackOwner and g._callbackOwner()
end
function R.new()return setmetatable({},R)end
function R:owner()return owner()end
function R:cancelOwner(who)
  local c=self.context
  if c then
    for _,key in ipairs({'vm','store'})do
      if c.preview[key..'Owner']==who then
        c.preview[key],c.preview[key..'Set'],c.preview[key..'Owner']=nil,nil,nil
      end
    end
  end
  if self.dataset and self.dataset.overrideOwner==who then self.dataset.override,self.dataset.overrideOwner=nil,nil end
end
function R:retireContext()
  local c=self.context
  if c then c.life.retired=true;c.backend:release()end
  self.context=nil
end
function R:release()
  self:retireContext()
  if self.dataset then self.dataset.life.retired=true end
  self.dataset=nil
end
function R:current(game,world)
  local g,why=Native.game(game);if not g then self:release();return nil,why end
  if not world then local _,w=Native.resolve(g);world=w end
  if world and not(type(world)=='table'and world.isOverworld and world.player and world.map
      and g.data and g.data.maps and g.data.maps[world.map.id]==world.map.def)then world=nil end
  if not(g.data and type(g.data.maps)=='table'and type(g.save)=='table')then
    self:release();return nil,'native script dataset unavailable'
  end
  local c=self.context;local map=world and world.map
  if c and(c.game~=g or c.world~=world or c.map~=map or c.data~=g.data or c.maps~=g.data.maps
      or c.save~=g.save or c.loader~=g.mods or c.pool~=g.data.map_scripts or c.edition~=Version.get()
      or c.life.runner~=(world and world.runner))then self:retireContext();c=nil end
  local dataset=self.dataset
  if dataset and(dataset.game~=g or dataset.data~=g.data or dataset.maps~=g.data.maps or dataset.save~=g.save
      or dataset.loader~=g.mods or dataset.pool~=g.data.map_scripts or dataset.edition~=Version.get())then
    dataset.life.retired=true;self.dataset=nil;dataset=nil
  end
  if not dataset then
    dataset={game=g,data=g.data,maps=g.data.maps,save=g.save,loader=g.mods,pool=g.data.map_scripts,edition=Version.get()}
    local held={};for k,v in pairs(dataset)do held[k]=v end;dataset.life=held
    dataset.bundle,dataset.error=Bundle.new(g.data,dataset.edition,function()
      return not held.retired and held.data==g.data and held.maps==g.data.maps and held.save==g.save
        and held.loader==g.mods and held.pool==g.data.map_scripts and held.edition==Version.get()
    end)
    self.dataset=dataset
  end
  if not c then
    c={game=g,world=world,map=map,data=g.data,maps=g.data.maps,save=g.save,loader=g.mods,pool=g.data.map_scripts,edition=Version.get()}
    c.binding=Identity.bind(c.maps,c.edition);c.id=map and c.binding:legacyId(map.id)
    c.backend=assert(Store.new(g))
    local life={game=g,data=c.data,maps=c.maps,save=c.save,loader=c.loader,pool=c.pool,edition=c.edition,
      world=world,map=map,runner=world and world.runner}
    c.life=life
    local function valid()
      local _,observed=Native.resolve(g)
      return not life.retired and g.data==life.data and g.save==life.save
        and g.mods==life.loader and g.data.maps==life.maps and g.data.map_scripts==life.pool and Version.get()==life.edition
        and(not life.world or observed==life.world and life.world.map==life.map and life.world.runner==life.runner)
    end
    c.valid=valid;c.preview={};self.context=c
    local backend,preview=c.backend,c.preview
    local guarded=setmetatable({},{__index=function(_,key)
      local fn=backend[key]
      if type(fn)~='function'then return fn end
      return function(_,...)
        assert(valid(),'native script view retired')
        if key=='setFlag'or key=='setVar'or key=='clearVar'then
          assert(not(preview.vmSet or preview.storeSet or preview.disabled),'native commands suspended by source preview lease')
        end
        return fn(backend,...)
      end
    end})
    local flags,vars=Maps.new(guarded,'flags'),Maps.new(guarded,'vars')
    c.store=setmetatable({},{__index=function(_,key)
      assert(valid(),'native script view retired')
      if key=='flags'then return flags elseif key=='vars'then return vars end
    end,__newindex=function(_,key,value)
      assert(key=='flags'or key=='vars','invalid script store field')
      Maps.replace(guarded,key,value)
    end})
    Iteration.register(c.store,function(s)
      assert(s.valid(),'native script view retired');return s.backend:snapshot()
    end,{valid=valid,backend=backend})
    c.dataset=dataset;c.bundle,c.bundleError=dataset.bundle,dataset.error
    if world and world.runner and c.bundle then c.vm=self:vm(c)end
  end
  return c
end
function R:bundle()
  local c,why=self:current();if not c then return nil,why end
  return c.dataset.override or c.bundle,c.bundleError
end
function R:key(c,key)
  local native=Bundle.nativeKey(key)
  local labels=c.dataset.override and c.dataset.override.labels or c.bundle and c.bundle.labels
  if labels and labels[key]then native=Bundle.nativeKey(labels[key])end
  if c.pool and c.pool.scripts and c.pool.scripts[native]then return native end
end
function R:start(key,localId,facing)
  local c,why=self:current();if not(c and c.world and c.vm)then return false,why or'no native field runner'end
  if c.disabled or c.preview.vmSet or c.preview.storeSet then return false,'native commands are suspended by a source preview lease'end
  local runner=c.world.runner
  if runner:isRunning()then return false,'native field runner is busy'end
  local intact,reason=Bundle.validate(c.dataset.override or c.bundle)
  if not intact then return false,reason end
  local native=self:key(c,key);if not native then return false,'native script label unavailable'end
  local rows=require('src.script.Gen3ScriptVM').compile(c.data,native)
  if not rows then return false,'native script did not compile'end
  for _,row in ipairs(rows)do
    if row[1]=='g3_unimplemented'or row[1]=='g3_unimplemented_result'then
      return false,'native script command unavailable: '..tostring(row[2])
    end
  end
  local npc
  if localId then
    assert(type(localId)=='number'and localId%1==0 and localId>=0 and localId<=255,'invalid script local id')
    for _,n in ipairs(c.world.npcs or{})do if n.def and n.def.index==localId then npc=n;break end end
  end
  if facing then
    facing=({down=1,up=2,left=3,right=4})[facing]or facing
    assert(type(facing)=='number'and facing%1==0 and facing>=1 and facing<=4,'invalid script facing')
  end
  if localId then c.backend:setVar(0x800f,localId)end
  if facing then c.backend:setVar(0x800c,facing)end
  local who=owner();c.started={runner=runner,key=native,owner=who}
  runner:run(rows,{npc=npc,mapId=c.map.id,source={modId=who,mapId=c.map.id,hook='source script',strict=true}})
  c.started.context=runner.ctx
  return true
end
function R:halt()
  local c=self:current();local run=c and c.started
  if not run or c.world.runner~=run.runner or run.runner.ctx~=run.context or run.owner~=owner()then return false,'native script belongs to another owner'end
  local runner=run.runner
  if not runner:isRunning()then return true end
  local states=c.game.stack and c.game.stack.states
  if states and states[#states]~=c.world then return false,'native script UI must finish before cancellation'end
  if #(c.world.scriptMoves or{})>0 then return false,'native script movements must finish before cancellation'end
  -- Reuse the native cancellation cleanup, including locks/fades and the
  -- script-ended notification; do not replace another runner's coroutine.
  return runner:cancelOwned(run.context,runner.co)
end
function R:vm(c)
  local runtime=self;local vm={}
  local special=setmetatable({},{
    __index=function(_,id)
      assert(c.valid(),'native script view retired');id=tonumber(id)
      if not id or id%1~=0 or not c.backend:isSpecial(id)then return nil end
      return c.backend:varValue(id)
    end,
    __newindex=function(_,id,value)
      assert(c.valid(),'native script view retired');id=tonumber(id)
      assert(not(c.preview.vmSet or c.preview.storeSet or c.disabled),'native commands suspended by source preview lease')
      assert(id and id%1==0 and c.backend:isSpecial(id),'invalid native special variable')
      if value==nil then c.backend:clearVar(id)else c.backend:setVar(id,value)end
    end})
  Iteration.register(special,function(s)
    assert(s.valid(),'native script view retired');local out={}
    local high=(s.edition=='firered'or s.edition=='leafgreen')and 0x8014 or 0x8015
    for id=0x8000,high do out[id]=s.backend:varValue(id)end
    return out
  end,{valid=c.valid,backend=c.backend,edition=c.edition})
  local ctx=setmetatable({specialVars=special},{__index=function(_,key)
    assert(c.valid(),'native script view retired');local native=c.world.runner.ctx
    if key=='status'then return c.world.runner:isRunning()and'running'or'stopped'end
    local value=native and native[key]
    if type(value)~='table'and type(value)~='function'and type(value)~='userdata'then return value end
  end,__newindex=function()error('script context writes require their native command',2)end})
  function vm:isRunning()return c.valid()and c.world.runner:isRunning()or false end
  function vm:start(key)assert(c.valid(),'native script view retired');return runtime:start(key)end
  function vm:startTalk(key,id,facing)assert(c.valid(),'native script view retired');return runtime:start(key,id,facing)end
  function vm:tick()assert(c.valid(),'native script view retired');return Boundary.invoke('tick')end
  function vm:halt()assert(c.valid(),'native script view retired');return runtime:halt()end
  function vm:getText(key)
    assert(c.valid(),'native script view retired');local b=runtime:bundle()
    if not(b and b.text)then return nil,'source text control-code projection is not available'end
    return b.text[key]
  end
  return setmetatable(vm,{__index=function(_,key)
    assert(c.valid(),'native script view retired')
    if key=='ctx'then return ctx end
    if key=='store'then return c.preview.storeSet and c.preview.store or c.store end
    if key=='scripts'or key=='text'or key=='movements'then local b=runtime:bundle();return b and b[key]end
  end})
end
function R:phase(name,game,world,mapId,body,source)
  return Native.withWorld(game,world,function()
    local c=self:current(game,world)
    if not c or c.id==nil or not c.vm then return body()end
    if c.disabled or c.preview.vmSet or c.preview.storeSet then return body()end
    local intact,reason=Bundle.validate(c.dataset.override or c.bundle)
    assert(intact,reason)
    local facade=require('src.core.Game3');local observed=assert(facade.forNative(game))
    return Boundary.dispatch(name,function()
      if name=='runEnterScripts'then
        c.entered=true;c.requests=c.requests or{}
        local r=package.loaded['src.core.game3.runtime'];local serial=r and r.tickVblank()or 0
        local entry=c.pool.maps and c.pool.maps[c.map.id]
        for _,cb in ipairs(entry and entry.callbacks or{})do c.requests[cb.type]=serial end
      end
      return body()
    end,source,nil,c.id,observed,world)
  end)
end
function R:tick(runner,body)
  local c=self:current()
  if not(c and c.vm and c.world.runner==runner)then return body(runner)end
  -- A detached preview does not take ownership of the live game's clock.
  if c.preview.vmSet or c.preview.storeSet then return body(runner)end
  return Boundary.dispatch('tick',function()return body(runner)end,function()return c.vm:tick()end)
end
function R:request(kind,mapId)
  local c,why=self:current()
  if not(c and c.world and c.bundle)then return false,why or'no native field script space'end
  if mapId and mapId~=c.id then return false,'native map is not the requested source map'end
  if c.preview.vmSet or c.preview.storeSet then return false,'source preview lease is active'end
  local intact,reason=Bundle.validate(c.dataset.override or c.bundle)
  if not intact then return false,reason end
  if kind==1 or kind==3 then return c.entered==true,'native map-entry phase owns this callback'end
  local rows={}
  local entry=c.pool and c.pool.maps and c.pool.maps[c.map.id]
  for _,cb in ipairs(entry and entry.callbacks or{})do if cb.type==kind then rows[#rows+1]=cb.script end end
  if kind==4 then
    for _,tbl in ipairs(entry and entry.tables or{})do if tbl.type==kind then
      for _,row in ipairs(tbl.rows or{})do
        if c.backend:getVar(row.var)==c.backend:getVar(row.value or 0)then rows[#rows+1]=row.script;break end
      end
    end end
  end
  local r=package.loaded['src.core.game3.runtime'];local serial=r and r.tickVblank()or 0
  c.requests=c.requests or{}
  if c.requests[kind]==serial then return true,'native callback already requested'end
  local compiler=require('src.script.Gen3ScriptVM');local compiled={}
  for _,key in ipairs(rows)do
    local code=compiler.compile(c.data,key)
    if code then
      for _,row in ipairs(code)do
        if row[1]=='g3_unimplemented'or row[1]=='g3_unimplemented_result'then return false,'native callback command unavailable: '..tostring(row[2])end
      end
      compiled[#compiled+1]=code
    end
  end
  if #compiled==0 then return false,'native callback is absent'end
  assert(type(c.world.queueScript)=='function','native script queue unavailable')
  c.requests[kind]=serial
  for _,code in ipairs(compiled)do c.world:queueScript(code,{mapId=c.map.id})end
  return true
end
function R:neighbor(mapId)
  local c,why=self:current();if not(c and c.world and c.bundle)then return nil,why end
  local id=c.binding:nativeId(mapId)
  if not id or id==c.map.id then return nil,'not a native neighbour map'end
  local found=false
  for _,row in ipairs(c.world.neighbors or{})do if row.map and row.map.id==id then found=true;break end end
  if not found then return nil,'requested map is not in the native connection world'end
  if c.preview.vmSet or c.preview.storeSet then return nil,'source preview lease is active'end
  -- Recompute from current native variables: transitions may have changed a
  -- gating var without changing maps or the identity of its store.
  return require('src.compat.gen1.ScriptPreview').run(c,id)
end
return R
