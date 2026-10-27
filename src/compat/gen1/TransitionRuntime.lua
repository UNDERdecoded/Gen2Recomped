-- Observe actual stack admissions; never create a parallel transition clock.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Catalog=require('src.compat.gen1.TransitionCatalog')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local R={};R.__index=R
local unpack=table.unpack or unpack
local function pack(...)return {n=select('#',...),...}end
local function copy(t,seen)
  if type(t)~='table'then
    if type(t)=='number'or type(t)=='string'or type(t)=='boolean'then return t end
    return nil
  end
  seen=seen or{};if seen[t]then return seen[t]end
  local out={};seen[t]=out
  for k,v in pairs(t)do if type(k)=='string'or type(k)=='number'then out[k]=copy(v,seen)end end
  return out
end
local function owner()
  local host=package.loaded['src.mods.Runtime'];local game=package.loaded['src.core.Game3']
  return host and host.currentMod or game and game._callbackOwner and game._callbackOwner()
end
local function cohort(c)
  return not c.invalidated and c.game.data==c.data and c.game.save==c.save and c.game.mods==c.loader and Version.get()==c.edition
end
local function member(c)
  if c.released or not cohort(c)or c.state.finished then return false end
  for _,state in ipairs(c.game.stack and c.game.stack.states or{})do if state==c.state then return true end end
  return false
end
local function releaseResource(r)if r and r.release then pcall(r.release,r)end end
function R.new()return setmetatable({records=setmetatable({},{__mode='kv'})},R)end
function R:notify(c,completed)
  if c.notified then return end;c.notified=true
  local ui=package.loaded['src.ui.game3.presentation']
  if ui and ui.notify then
    local ok,why=pcall(ui.notify,'battleTransitionEnd',{finished=completed})
    if not ok then
      c.presentationError=tostring(why)
      require('src.mods.Runtime').reportError(c.owner or 'compatibility-transition',c.presentationError)
    end
  end
end
function R:drop(c)
  if not c or c.released then return end
  c.released=true;releaseResource(c.canvas);releaseResource(c.input);c.canvas,c.input=nil,nil
end
function R:release()
  for _,c in pairs(self.records)do
    if c.state.onDone==c.installedCallback then c.state.onDone=c.original end
    c.invalidated=true;self:drop(c)
  end
  self.records=setmetatable({},{__mode='kv'});self.last=nil
end
function R:bind(state)
  local c=self.records[state];if c and cohort(c)then return c end
  if c then self:drop(c)end
  local game=Native.game(state.game)
  if not(game and game.data and game.save and game.stack and Catalog.family(Version.get()))then return nil end
  local own=state.cohort
  if own and(own.data~=game.data or own.save~=game.save or own.loader~=game.mods or own.edition~=Version.get())then return nil end
  c={state=state,game=game,data=game.data,save=game.save,loader=game.mods,edition=Version.get(),owner=owner()}
  c.catalog=Catalog.new(c.edition);c.options=copy(state.options or{})
  c.options.wild=not c.options.trainer;c.options.playerLevel=c.options.leadLevel
  c.options.terrain=c.options.mapTransitionType
  local chosen=Catalog.pick(c.edition,c.options,c.options.trainer)
  if c.catalog.styles[chosen]==state.style then c.id=chosen
  else for id,style in pairs(c.catalog.styles)do if style==state.style then c.id=id;break end end end
  local original=state.onDone
  c.original=original
  c.continue=function()
    if c.callbackError then error(c.callbackError,0)end
    if c.callbackResult then return unpack(c.callbackResult,1,c.callbackResult.n)end
    if not cohort(c)or not state.finished or state.phase~='done'then return false,'native transition has not completed'end
    c.callbackResult={n=0}
    local fn=original;original=nil;c.original=nil
    local result=pack(pcall(function()if fn then return fn()end end));fn=nil
    if not result[1]then c.callbackError=result[2];error(result[2],0)end
    c.callbackResult={n=result.n-1};for i=2,result.n do c.callbackResult[i-1]=result[i]end
    return unpack(c.callbackResult,1,c.callbackResult.n)
  end
  state.onDone=c.continue;c.installedCallback=c.continue;self.records[state]=c;self.last=c
  return c
end
function R:current()
  local game=Native.game();if not game then return nil end
  local class=package.loaded['src.render.BattleTransition']
  if not class then return nil end
  for i=#(game.stack and game.stack.states or{}),1,-1 do
    local state=game.stack.states[i]
    if getmetatable(state)==class and not state.finished then
      local c=self.records[state]
      if c and not cohort(c)then self:drop(c);return nil end
      return c or self:bind(state)
    end
  end
end
function R:observed()
  local c=self:current()or self.last
  if c and cohort(c)then return c end
  if c then self:drop(c);self.last=nil end
end
function R:configure(c,id,opts,callback)
  assert(member(c),'native transition admission retired')
  opts=opts or{}
  assert(type(opts)=='table','invalid transition options')
  if id~=nil then
    assert(type(id)=='number'and id%1==0 and c.catalog.names[id],'invalid transition id')
    if id~=c.id then
      local style=assert(c.catalog.styles[id],'native transition effect is not implemented')
      local def=c.data.transitions and c.data.transitions[style]or require('src.render.BattleTransition').STYLES[style]
      assert(def,'native transition style is not registered')
      c.state.style,c.state.def,c.state.wipeLen=style,def,def.frames;c.id=id
    end
  end
  if callback~=nil then
    assert(type(callback)=='function','invalid transition completion');c.state.onDone=callback;c.installedCallback=callback
  end
  if opts.skipIntro then c.state.phase='wipe';c.state.t=0 end
  c.options=copy(opts)
  if opts.headless then return self:complete(c,true)end
  return true
end
function R:phase(c,name,body,fn,...)
  if not member(c)then return false,'native transition admission retired'end
  local result=pack(Boundary.dispatch('transition.'..name,body,fn,...))
  if c.callbackError then error(c.callbackError,0)end
  return unpack(result,1,result.n)
end
function R:complete(c,completed)
  if not c or not member(c)then return false,'native transition admission retired'end
  local who=owner()
  if c.owner and who and c.owner~=who then return false,'native transition belongs to another mod'end
  if c.game.stack:top()~=c.state then return false,'native transition is covered by another state'end
  self:notify(c,completed)
  local result=c.state:complete(completed)
  if c.callbackError then error(c.callbackError,0)end
  return result
end
function R:start(id,opts,callback)
  local game,why=Native.game();if not(game and game.data and game.save and game.stack)then return false,why or'no native transition owner'end
  if self:current()then return false,'native transition is busy'end
  local catalogue=Catalog.new(Version.get());id=id or catalogue.ID.SLICE
  local style=catalogue.styles[id]
  if not style then return false,'native transition effect is not implemented'end
  local args=copy(opts or{});args.style=style
  local state=require('src.render.BattleTransition').new(game,callback,args)
  local c=self:bind(state)
  if c.catalog.styles[id]==state.style then c.id=id end
  c.options=copy(opts or{});c.sourceStarted=true
  game.stack:push(state)
  return true
end
function R:exit(state)
  local c=self.records[state];if not c then return end
  self:notify(c,state.finished and state.phase=='done')
  self:drop(c)
end
function R:cancelOwner(who)
  local c=self:current()
  if c and c.sourceStarted and c.owner==who and c.game.stack:top()==c.state then
    self:notify(c,false);c.state:complete(false)
  end
end
function R:drawWorld(c,canvas,w,h)
  if not c or not member(c)then return false end
  if c.options.overUi then return false end
  if c.state.def.draw then return false,'native foreground transition owns its UI draw'end
  assert(canvas and canvas.getDimensions,'invalid transition canvas')
  local cw,ch=canvas:getDimensions();w,h=w or cw,h or ch
  assert(cw==w and ch==h and w>0 and h>0,'transition view dimensions differ')
  local g=love.graphics
  if c.input and(c.input:getWidth()~=w or c.input:getHeight()~=h)then releaseResource(c.input);c.input=nil end
  c.input=c.input or g.newCanvas(w,h,{dpiscale=canvas:getDPIScale()})
  c.input:setFilter('nearest','nearest')
  g.push('all')
  local ok,why=pcall(function()
    g.origin();g.setCanvas(c.input);g.setShader();g.setScissor();g.setDepthMode();g.setColor(1,1,1,1)
    g.setBlendMode('replace','premultiplied');g.draw(canvas,0,0)
  end)
  g.pop();if not ok then error(why,0)end
  local drawn=c.state:drawInto(canvas,w,h,c.input)
  if drawn then c.worldDrawn=true end
  return drawn
end
function R:composite(renderer,fn)
  local c=self:current();if not c or c.options.overUi or not renderer.worldOverride then return false end
  if c.state.def.draw then return false end
  local source=renderer.worldOverride
  local ok,w,h=pcall(source.getDimensions,source);if not ok then return false end
  local g=love.graphics
  if c.canvas and(c.canvas:getWidth()~=w or c.canvas:getHeight()~=h)then releaseResource(c.canvas);c.canvas=nil end
  c.canvas=c.canvas or g.newCanvas(w,h,{dpiscale=source:getDPIScale()});c.canvas:setFilter('nearest','nearest')
  g.push('all')
  local success,drawn=pcall(function()
    g.origin();g.setCanvas(c.canvas);g.setShader();g.setScissor();g.setDepthMode();g.setColor(1,1,1,1)
    g.setBlendMode('replace','premultiplied')
    if renderer.worldOverrideMirrored then g.draw(source,0,h,0,1,-1)else g.draw(source,0,0)end
    return fn(c.canvas,w,h)
  end)
  g.pop();if not success then error(drawn,0)end
  if drawn then
    if renderer.worldOverride==source then renderer:setWorldOverride(c.canvas,{worldOrientation='native'})end
    if renderer.battleWipe and renderer.battleWipe.transition==c.state then renderer.battleWipe=nil end
    local veil=renderer.nativeTransitionVeil
    if veil and veil.state==c.state and veil.value==renderer.screenVeil then renderer.screenVeil=nil end
  end
  return drawn
end
R.copy=copy
return R
