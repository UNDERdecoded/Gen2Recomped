-- Session/lifecycle seam over native owners. No copied field, battle, audio,
-- RTC or playtime loop: only Game:_step can service a deferred callback batch.
local Native=require('src.compat.gen1.NativeSession')
local Views=require('src.compat.gen1.SessionView')
local Version=require('src.core.GameVersion')
local R={}
local current,boundary,tombstone
local queueInfo=setmetatable({},{__mode='k'})
local function same(c,game)
  return c and c.owner==game and game.data==c.data and game.save==c.save
    and c.edition==Version.get()and game.data and game.data.maps==c.maps and c.loader==game.mods
end
local function retire(c)
  if c then c.retired=true;c.queue=nil;c.ui=nil;c.override=nil;c.overrideSet=nil end
end
local function observe(game)
  local owner=Native.game(game)
  if not(owner and type(owner.data)=='table'and type(owner.data.maps)=='table'and type(owner.save)=='table')then
    retire(current);current=nil;return nil
  end
  if not same(current,owner)then
    retire(current)
    local facade=require('src.core.Game3').forNative(owner)
    local view=facade and facade.session;local record=view and Views.record(view)
    if not record then current=nil;return nil end
    current={owner=owner,data=owner.data,maps=owner.data.maps,save=owner.save,
      edition=Version.get(),facade=facade,view=view,record=record,serial=0,loader=owner.mods,
      stopped=same(tombstone,owner)}
    if not current.stopped then tombstone=nil end
  end
  return current
end
local function world(c)
  if not c or c.stopped or c.retired or not c.record:valid()then return end
  local _,w,p=Native.resolve(c.owner);return w,p
end
local function active(game)
  local c=observe(game);return world(c)and c or nil
end
local function queue(c)
  if not c.queue then c.queue={};queueInfo[c.queue]={context=c,owners={}}end
  return c.queue,queueInfo[c.queue]
end
function R.log(message)
  require('src.core.Logger').info('[game3] %s',tostring(message))
end
function R.isActive()return active()~=nil end
function R.getSession()
  local c=active();if not c then return nil end
  if c.overrideSet then return c.override end
  return c.view
end
function R.defer(fn)
  if type(fn)~='function'then return false end
  local c=active();if not c then return false end
  local q,info=queue(c);local i=#q+1;q[i]=fn
  local facade=package.loaded['src.core.Game3']
  info.owners[i]=require('src.mods.Runtime').currentMod or(facade and facade._callbackOwner())
  return true
end
function R.drainDeferred()
  local b=boundary
  if not b or b.draining or b.drained or not same(b.context,b.context.owner)then return 0 end
  b.drained=true
  local c=b.context;local q=c.queue;if not q then return 0 end
  c.queue=nil;b.draining=true
  local info=queueInfo[q];local count=0
  for i=1,#q do
    if c.retired or c.stopped or not same(c,c.owner)or current~=c or Native.game()~=c.owner then break end
    local owner=info and info.owners[i]
    local facade=package.loaded['src.core.Game3']
    local ok,why=xpcall(function()
      if facade and facade._withCallbackOwner then return facade._withCallbackOwner(owner,q[i])end
      return q[i]()
    end,debug.traceback);count=count+1
    if not ok then
      require('src.mods.Runtime').reportError(owner,'deferred call failed: '..tostring(why))
      R.log('deferred call failed: '..tostring(why))
    end
  end
  b.draining=false
  return count
end
local function nativeTop(c)
  local stack=c and c.owner.stack
  if stack and type(stack.active)=='function'then return stack:active()end
  if stack and type(stack.top)=='function'then return stack:top()end
  local states=stack and stack.states;return states and states[#states]
end
function R.uiBusy()
  local c=active();local w=world(c);if not w then return false end
  if c.ui then return true end
  local top=nativeTop(c)
  return (top~=nil and top~=w)or w.battleActive==true
    or(type(w.busy)=='function'and w:busy()==true)or false
end
function R.setUi(top)
  local c=observe();if c then c.ui=top or nil end
end
function R.fieldScreenOpen(menuOpen)
  local c=active();if not c then return false end
  local top=nativeTop(c);local w=world(c)
  if menuOpen==nil then menuOpen=c.ui~=nil or(top~=nil and top~=w)end
  if not menuOpen then return false end
  local layers=package.loaded['src.ui.game3.stack']
  if layers and layers.depth and layers.has and layers.has('start')then
    local n=layers.depth();if n==1 or(n==2 and layers.has('save'))then return false end
  end
  local id=top and(top.screenId or top.id)
  if not c.ui and(id=='StartMenu'or id=='SaveMenu')then return false end
  return true
end
function R.noteFieldFocus(open)
  local c=active();if not c then return false end
  local was=c.menuFocus==true;c.menuFocus=open==true
  if open and not was then
    local lighting=package.loaded['src.core.game3.league_lighting']
    if lighting and lighting.stop then lighting.stop()end
  end
  if open or not was then return false end
  local w=world(c);if w.battleActive or(type(w.busy)=='function'and w:busy())then return false end
  local space=package.loaded['src.core.game3.scripting.space']
  if not(space and space.active and space.vm and type(space.returnToField)=='function')then return false end
  if space.vm.isRunning and space.vm:isRunning()then return false end
  if space._immediateVm and space._immediateVm.isRunning and space._immediateVm:isRunning()then return false end
  local ok,ran=pcall(space.returnToField);return ok and ran==true
end
function R.pumpRtc()
  local view=R.getSession();return view and view.playtime or nil
end
function R.tickVblank()
  local c=active();return c and c.serial or 0
end
function R.update()
  if not boundary then return nil,'runtime updates belong to the native fixed-step phase'end
  if boundary.called then return false end
  boundary.called=true
  boundary.context.serial=boundary.context.serial+1
  local count=R.drainDeferred()
  if not same(boundary.context,boundary.context.owner)then return count end
  R.noteFieldFocus(R.fieldScreenOpen())
  return count
end
local baseUpdate=R.update
function R._fixedBoundary(game,dt)
  local c=active(game);if not c then return true end
  if boundary then return true end
  local b={context=c};boundary=b
  local ok,why=xpcall(function()R.update(dt)end,debug.traceback)
  boundary=nil
  if not ok then error(why,0)end
  return not c.retired and not c.stopped and same(c,game)and(R.update==baseUpdate or b.called==true)
end
function R.start(mod,game,session,opts)
  local c=observe(game);if not c then return false,'native session unavailable'end
  local _,w=Native.resolve(c.owner)
  if not w or(session~=nil and session~=c.view)then return false,'session adoption requires its native map command'end
  c.stopped=false;c.mod=mod;c.queue=nil;c.menuFocus=false;tombstone=nil
  return true
end
function R.stop()
  local c=observe();if c then c.stopped=true;c.queue=nil;c.ui=nil;c.override=nil end
end
function R.ensureActiveForMap(mod,game,id)
  local c=observe(game)
  if not c or c.record:map()~=id then return false,'native map is not the requested source map'end
  if not c.stopped and world(c)then return true end
  return R.start(mod,c.owner,c.view,{alreadyOnMap=true})
end
function R.install(mod)
  local c=observe();if c then c.mod=mod end
  return c~=nil
end
function R.release()
  if current then tombstone=current end
  retire(current);current=nil
end
setmetatable(R,{
  __index=function(_,key)
    local c=observe()
    if key=='active'then return world(c)~=nil end
    if key=='session'then return R.getSession()end
    if key=='_game'then return c and not c.stopped and c.facade or nil end
    if key=='_mod'then return c and c.mod or nil end
    if key=='_deferred'then return c and c.queue or nil end
    if key=='_menuFocus'then return c and c.menuFocus==true or false end
    if key=='_ui'then return c and c.ui end
    if key=='_vblankCounter'then return c and c.serial or 0 end
    if key=='_playTimeAcc'then local n=c and c.record:seconds()or 0;return n-math.floor(n)end
    if key=='_fieldLocked'then local w=world(c);return w and type(w.busy)=='function'and w:busy()==true or false end
  end,
  __newindex=function(t,key,value)
    local c=observe()
    if key=='session'then
      assert(value==nil or type(value)=='table','invalid runtime session lease')
      if c then c.override=value;c.overrideSet=value~=c.view end
    elseif key=='_deferred'then
      assert(value==nil or type(value)=='table','invalid deferred callback lease')
      if c then
        local info=value and queueInfo[value]
        assert(not info or info.context==c,'deferred callback lease belongs to a retired session')
        if value and not info then queueInfo[value]={context=c,owners={}}end
        c.queue=value
      end
    elseif key=='active'then
      assert(type(value)=='boolean','invalid runtime active state');if c then c.stopped=not value end
    elseif key=='_playTimeAcc'or key=='_vblankCounter'or key=='_game'then
      error('runtime '..key..' belongs to its native owner',2)
    else rawset(t,key,value)end
  end,
})
return R
