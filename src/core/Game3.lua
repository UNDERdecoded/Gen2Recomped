-- A distinct facade for source wrappers. The existing Game still owns every
-- simulation, frame and IO operation; requiring this cannot bootstrap it.
local Native=require('src.compat.gen1.NativeSession')
local Views=require('src.compat.gen1.SessionView')
local Version=require('src.core.GameVersion')
local G={}
local entries=setmetatable({},{__mode='k'})
local owners=setmetatable({},{__mode='k'})
local scopes={}
local bases={}
local bootLeases=setmetatable({},{__mode='k'})
local mouseBodies=setmetatable({},{__mode='k'})
local callbackOwners={}
local actorCallbackOwners={}
local callbackOwner
local unpack=table.unpack or unpack
local function pack(...)return {n=select('#',...),...}end
function G._callbackOwner()return callbackOwner end
function G._withCallbackOwner(owner,fn,...)
  local previous=callbackOwner;callbackOwner=owner
  local result=pack(pcall(fn,...))
  local views=package.loaded['src.compat.gen1.PokemonView']
  if result[1]and views then
    local ok,why=pcall(views.flush)
    if not ok then result={n=2,false,why}end
  end
  callbackOwner=previous
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
end
local function methodOwner(name)
  local seams=package.loaded['src.mods.ModSeams'];local journal=seams and seams._journal or{}
  for i=#journal,1,-1 do
    local change=journal[i]
    if change.tbl==G and change.key==name and change.after==G[name]then return change.owner end
  end
end
local function entry(view)
  local e=entries[view]
  assert(e and not e.retired,'native Game3 facade retired or unbound')
  return e
end
function G.native(value)
  if value==nil then return package.loaded['src.core.Game']end
  local e=entries[value]
  if e then return not e.retired and e.owner or nil end
  if type(value)=='table'and type(rawget(value,'game'))=='table'then return G.native(rawget(value,'game'))end
  return value
end
local function session(e)
  if e.session then
    local record=Views.record(e.session)
    if record and record:valid()then return e.session end
    Views.release(e.session);e.session=nil
  end
  e.session=Views.new(e.owner)
  return e.session
end
local function forward(view,name,...)
  local e=entry(view);local c=scopes[name]
  if c and c.view==view then
    if c.called then
      if c.failed then error(c.failure,0)end
      if c.result then return unpack(c.result,1,c.result.n)end
      return
    end
    c.called=true
    local result=pack(pcall(c.native,e.owner,...))
    if not result[1]then c.failed=true;c.failure=result[2];error(result[2],0)end
    c.result={n=result.n-1};for i=2,result.n do c.result[i-1]=result[i]end
    return unpack(c.result,1,c.result.n)
  end
  local method=e.owner[name]
  if type(method)~='function'then return nil,'native method unavailable: '..name end
  return method(e.owner,...)
end
for _,name in ipairs({'update','draw','keypressed','keyreleased','textinput','wheelmoved',
    'touchpressed','touchmoved','touchreleased','gamepadpressed','gamepadreleased','gamepadaxis',
    'joystickpressed','joystickreleased','joystickaxis','joystickhat','joystickremoved','focus','visible',
    'mousepressed','mousemoved','mousereleased','writeOptions','applyOptions','writeSave','returnToTitle',
    'logicSpeed','speedLocked','_resolveLogicSpeed','zoomStep',
    'returnToLauncher','restartWithMods'})do
  local key=name;G[key]=function(view,...)return forward(view,key,...)end;bases[key]=G[key]
end
function G.fixedUpdate(view,...)return forward(view,'_step',...)end
bases.fixedUpdate=G.fixedUpdate
function G.reset(view)
  local e=entry(view)
  local runtime=package.loaded['src.core.game3.runtime'];if runtime and runtime.release then runtime.release()end
  if e.session then Views.release(e.session);e.session=nil end
  e.overrides={};e.overridden={};e.bootEpoch={}
end
bases.reset=G.reset
function G._handleBootAction(view,action)
  local e=entry(view);local lease=type(action)=='table'and bootLeases[action]
  if not lease or lease.view~=view or lease.epoch~=e.bootEpoch or action.action~=lease.kind then
    return nil,'boot action belongs to a retired or absent native title callback'
  end
  if lease.failed then error(lease.failed,0)end
  if lease.done then return unpack(lease.result,1,lease.result.n)end
  if lease.owner.data~=lease.data or lease.owner.save~=lease.save or lease.owner.mods~=lease.loader then
    return nil,'native title callback retired'
  end
  if not lease.done then
    lease.done=true
    local ok,why=xpcall(function()lease.result=pack(lease.callback())end,debug.traceback)
    if not ok then lease.failed=why;error(why,0)end
  end
  return unpack(lease.result,1,lease.result.n)
end
bases._handleBootAction=G._handleBootAction
function G._bootAction(owner,action,callback)
  if Version.generation()~=3 or G._handleBootAction==bases._handleBootAction then return callback()end
  local view=G.forNative(owner);if not view then return callback()end
  local e=entries[view]
  bootLeases[action]={view=view,owner=owner,data=owner.data,save=owner.save,loader=owner.mods,
    epoch=e.bootEpoch,kind=action.action,callback=callback}
  return G._dispatch('_handleBootAction',owner,function()return bases._handleBootAction(view,action)end,action)
end
function G.stepGC()if collectgarbage then return collectgarbage('step',1)end end
function G._stepGC()
  if Version.generation()~=3 then return false end
  G.stepGC();return true
end
function G.forNative(value)
  local native=G.native(value)
  if value~=nil and native==nil then return nil,'native Game3 facade retired'end
  local owner,why=Native.game(native);if not owner then return nil,why end
  local existing=owners[owner]
  if existing and not entries[existing].retired then
    local e=entries[existing]
    if e.loader==owner.mods or e.resetting then return existing end
    G._notifyReset(owner);e.retired=true;if e.session then Views.release(e.session)end
  end
  local view={};local e={owner=owner,overrides={},overridden={},loader=owner.mods,bootEpoch={}};entries[view]=e;owners[owner]=view
  setmetatable(view,{
    __index=function(_,key)
      if G[key]~=nil then return G[key]end
      if e.retired then return nil end
      if e.overridden[key]then return e.overrides[key]end
      if key=='mods'then return e.loader end
      if key=='generation'then return 3 end
      if key=='session'or key=='save'then return session(e)end
      if key=='phase'then return Native.resolve(owner)and'field'or'boot'end
      if key=='options'then return owner.save and owner.save.options end
      if key=='data'then
        if e.dataset~=owner.data then
          e.dataset=owner.data
          local dataset=e.dataset
          e.dataView=setmetatable({}, {__index=function(_,field)
            if owner.data~=dataset then return nil end
            if field=='maps'then return require('src.core.game3.map').definitions(owner)end
            return dataset and dataset[field]
          end})
        end
        return e.dataView
      end
      local value=owner[key]
      if type(value)~='function'then return value end
    end,
    __newindex=function(t,key,value)
      assert(not e.retired,'native Game3 facade retired')
      if key=='data'or key=='generation'or key=='phase'then error('Game3 '..key..' belongs to its native owner',2)end
      if key=='speedOverride'then
        assert(value==nil or value==false or(type(value)=='number'and value>0 and value<math.huge),'invalid native speed override')
        owner.speedOverride=value;return
      end
      -- Source previews lease their own session/save/options and methods.
      -- Such replacements must never overwrite the native Game or save.
      if key=='session'or key=='save'or key=='options'or key=='stack'then
        assert(value==nil or type(value)=='table','invalid Game3 '..key);e.overrides[key]=value;e.overridden[key]=true
      else rawset(t,key,value)end
    end,
  })
  return view
end
function G.new(owner)
  if owner==nil then return nil,'native game creation belongs to the host'end
  return G.forNative(owner)
end
function G._dispatch(name,owner,native,...)
  local sourceName=name=='_step'and'fixedUpdate'or name
  if mouseBodies[owner]and(name=='touchpressed'or name=='touchmoved'or name=='touchreleased')
      and select(1,...)=='mouse'then return native(owner,...)end
  if Version.generation()~=3 or G[sourceName]==bases[sourceName]or scopes[name]then return native(owner,...)end
  local view=G.forNative(owner);if not view then return native(owner,...)end
  local previous=scopes[name];local c={view=view,native=native};scopes[name]=c
  local args=pack(...);local result
  local ok,why=xpcall(function()
    result=pack(G._withCallbackOwner(methodOwner(sourceName)or callbackOwner,G[sourceName],view,unpack(args,1,args.n)))
  end,debug.traceback)
  scopes[name]=previous
  if c.failed then error(c.failure,0)end
  if not ok then error(why,0)end
  return unpack(result,1,result.n)
end
function G._pointer(name,owner,native,...)
  local function body(game,...)
    local previous=mouseBodies[game];mouseBodies[game]=(previous or 0)+1
    local args=pack(...);local result
    local ok,why=xpcall(function()result=pack(native(unpack(args,1,args.n)))end,debug.traceback)
    mouseBodies[game]=previous
    if not ok then error(why,0)end
    return unpack(result,1,result.n)
  end
  return G._dispatch(name,owner,body,...)
end
function G.release()
  for view,e in pairs(entries)do e.retired=true;if e.session then Views.release(e.session)end end
  owners=setmetatable({},{__mode='k'})
  callbackOwners={}
  actorCallbackOwners={}
end
function G._observeActorMod(owner)if type(owner)=='string'then actorCallbackOwners[owner]=true end end
function G._observeMod(owner)if type(owner)=='string'then callbackOwners[owner]=true end end
function G._retireMod(owner)callbackOwners[owner]=nil;actorCallbackOwners[owner]=nil end
function G._usesCallbacks(owner)return (callbackOwners[owner]==true or actorCallbackOwners[owner]==true) and Version.generation()==3 end
local function callbackGame(owner)
  if not callbackOwners[owner]or Version.generation()~=3 then return end
  local native=package.loaded['src.core.Game'];if type(native)~='table'then return end
  return native,G.forNative(native)
end
function G._event(owner,name,payload)
  if not G._usesCallbacks(owner)or type(payload)~='table'or name:match('^mod%.[%w_%-]+%.')then return payload end
  local native=package.loaded['src.core.Game'];if type(native)~='table'then return payload end
  local rawGame=rawget(payload,'game')
  local saveEvent=name=='save.created'or name=='save.loaded'or name=='save.writing'or name=='save.loading'
  if payload~=native and rawGame~=native and not saveEvent then return payload end
  local view=G.forNative(native);if not view then return payload end
  if payload==native then return view end
  local out={};for k,v in pairs(payload)do out[k]=v end
  if rawGame==native then out.game=view;setmetatable(out,{__index=view});entries[out]=entries[view]end
  if saveEvent then
    for _,key in ipairs({'save','raw'})do
      local raw=rawget(payload,key)
      if type(raw)=='table'then
        if raw==native.save then out[key]=view.session
        else out[key]=Views.new({data=native.data,save=raw})end
      end
    end
  end
  return out
end
function G._invokeEvent(owner,name,callback,payload)
  return G._withCallbackOwner(owner,callback,G._event(owner,name,payload))
end
function G._invokeHook(owner,callback,nextFn,...)
  local native,view=callbackGame(owner)
  if not view then return G._withCallbackOwner(owner,callback,nextFn,...)end
  local function public(values)
    for i=1,values.n do if values[i]==native then values[i]=view end end
    return values
  end
  local function raw(values)
    for i=1,values.n do local e=entries[values[i]];if e then values[i]=not e.retired and e.owner or nil end end
    return values
  end
  local function nextPublic(...)
    local args=raw(pack(...))
    local result=public(pack(G._withCallbackOwner(nil,nextFn,unpack(args,1,args.n))))
    return unpack(result,1,result.n)
  end
  local args=public(pack(...))
  local result=raw(pack(G._withCallbackOwner(owner,callback,nextPublic,unpack(args,1,args.n))))
  return unpack(result,1,result.n)
end
function G._notifyReset(owner)
  if Version.generation()~=3 then return false end
  local view=owners[owner];local e=view and entries[view]
  if not e or e.retired or e.resetNotified then return false end
  e.resetNotified=true;e.resetting=true
  local ok,why=xpcall(function()G.reset(view)end,debug.traceback)
  if not ok then
    bases.reset(view)
    require('src.mods.Runtime').reportError('compatibility','reset failed: '..tostring(why))
    require('src.core.Logger').warn('compatibility reset failed: %s',tostring(why))
  end
  e.resetting=nil
  return true
end
return G
