-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- One admitted native presentation owner. This is not a second battle VM;
-- authored command/particle APIs are advertised only as they are integrated.
local Battle=require('src.core.game3.battle')
local Coords=require('src.core.game3.battle.anim_coords')
local Clock=require('src.battle.PresentationClock')
local Scope=require('src.render.GraphicsScope')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local Ids=require('src.compat.gen1.BattleIds')
local A={Coords=Coords,ENEMY_MON={x=176,y=40},PLAYER_MON={x=72,y=80}}
function A.stage()
 return require('src.core.game3.battle.stage').current(require('src.compat.gen1.SourceCall').owner(A,'stage'))
end
function A.drawParticles(lo,hi)
 return require('src.core.game3.battle.particle_pass').draw(lo,hi,require('src.compat.gen1.SourceCall').owner(A,'drawParticles'))
end
local current
local tweenOffers=require('src.compat.gen1.CoroutineScopes').new()
local numeric={ox=true,oy=true,alpha=true,scale=true,sx=true,sy=true,rotation=true,
  darken=true,flash=true,displayHp=true,displayMaxHp=true,displayLevel=true,displayExp=true}
local function retire()
  if current then
    local screen=current.screen[1]
    if screen and current.clip and screen.gen3Anim==current.clip.player
        and current.clip.serial==screen.gen3Anim.presentationSerial then
      screen.gen3Anim:release();screen.gen3AnimPlaying=false
    end
    current.clip=nil
    if current.effect then current.effect:release();current.effect=nil end
    current.tasks={};current.onEnd=nil;current.users={};current.overrides={}
    current.view=nil;current.screen[1]=nil
  end
  current=nil
end
local function context()
  local screen=Battle._screen();local view=Battle.getState()
  if not screen then retire();return end
  if not current or current.screen[1]~=screen or current.view~=view then
    retire()
    current={screen=setmetatable({screen},{__mode='v'}),view=view,present={},overrides={},
      tasks={},nextTask=0,users={},ids=Ids.new(screen.data)}
  end
  local facade=require('src.core.Game3');local owner=facade._callbackOwner()
  local host=package.loaded['src.mods.Runtime'];owner=host and host.currentMod or owner
  if owner then current.users[owner]=true end
  return current,screen
end
local function battler(screen,id)
  if id==0 then return screen.player elseif id==1 then return screen.enemy end
  return screen:battlerAt(id)
end
local function number(v)return type(v)=='number'and v==v and v~=math.huge and v~=-math.huge end
local function callback(fn,...)
  if fn then return require('src.core.Game3')._withCallbackOwner(fn.owner,fn.call,...)end
end
local function owned(fn)
  if fn==nil then return end
  assert(type(fn)=='function','presentation callback must be a function')
  local host=package.loaded['src.mods.Runtime']
  return{call=fn,owner=host and host.currentMod or require('src.core.Game3')._callbackOwner()}
end
local function read(d,id,key)
  local active,screen=context();if active~=d then return nil end
  local b=battler(screen,id);if not b then return nil end
  local p=d.overrides[id]
  if p[key]~=nil then return p[key]end
  if key=='id'then return id end
  if key=='side'then return Coords.sideOf(id)end
  local ball=(key=='visible'or key=='scale'or key=='oy')
    and screen.gen3BallFor and screen:gen3BallFor(b)or nil
  if key=='visible'then
    -- Before a ball exists, the native entry/switch flags already own the
    -- empty slot. A source capture must not expose the queued Pokemon while
    -- the trainer is still arriving or the send-out text is being printed.
    local hidden
    if id>=2 then hidden=screen:sideArriving(id%2==0,screen.introSlide)
    elseif b==screen.player then
      hidden=screen.showPlayerBack or screen.sendingOut or screen.safari
        or screen:demoHidesPlayer()
    else hidden=screen.showEnemyTrainer or screen.enemySendingOut or screen.enemyHidden end
    return not hidden and not b.fainted and not(ball and ball.monHidden)
      and not screen:fxHidden(b)and not screen:gen3AnimMonBgHidden(b)
  end
  if key=='invisible'or key=='battlerInvisible'then return screen:gen3AnimMonBgHidden(b)end
  if key=='ox'or key=='oy'then
    local x,y=screen:gen3AnimShake(b);local fx=screen.picFx and screen.picFx[b]
    return(key=='ox'and x+(fx and fx.ox or 0)or y+(fx and fx.oy or 0)+(ball and ball.monRise or 0))
  end
  if key=='scale'then return(screen:gen3AnimScale(b)or 1)*(ball and ball.monScale or 1)end
  if key=='sx'or key=='sy'then
    local x,y=screen:gen3AnimSquash(b);return(key=='sx'and x or y)or 1
  end
  if key=='rotation'then return screen:gen3AnimRotate(b)or 0 end
  if key=='alpha'then local fx=screen:gen3AnimSpecialMonState(b);return fx and fx.alpha or 1 end
  if key=='hFlip'then return false end
  if key=='darken'or key=='flash'then return 0 end
  if key=='displayHp'then return b.shownHP or b.mon.hp end
  if key=='displayMaxHp'then return b.mon.stats.hp end
  if key=='displayLevel'then return b.mon.level end
  if key=='displayStatus'then
    -- Logical status may already describe a queued future event. The native
    -- HUD owns the shown ailment; false is its explicit healthy sentinel.
    local status=b.shownStatus
    if not status then return false end
    if status=='SLP'then return 1 end
    return({PSN=8,BRN=16,FRZ=32,PAR=64,TOX=128})[status]or false
  end
  if key=='displayExp'then return screen:expFraction(b.mon)end
end
function A.idOf(key)
  if key=='attacker_side'then
    local _,screen=context();local anim=screen and screen.gen3Anim
    return anim and anim.attackerPosition or 0
  end
  return Coords.idOf(key)
end
A.sideOf,A.isDouble,A.setDouble=Coords.sideOf,Coords.isDouble,Coords.setDouble
A.coords,A.subpriority,A.bgPriorityRank=Coords.coords,Coords.subpriority,Coords.bgPriorityRank
A.monDrawOrder,A.particleBand,A.battlerIds=Coords.monDrawOrder,Coords.particleBand,Coords.ids
function A.x(value)
  local _,screen=context();local anim=screen and screen.gen3Anim
  value=tonumber(value)or 0
  return anim and anim.attackerIsPlayer==false and -value or value
end
function A.present(key)
  local d,screen=context();local id=A.idOf(key)
  if not d or id==nil or id>=2 and not Coords.isDouble(d.view)or not battler(screen,id)then return nil end
  if not d.present[id]then
    d.overrides[id]={}
    d.present[id]=setmetatable({},{__index=function(_,k)return read(d,id,k)end,
      __newindex=function(_,k,v)
        assert(context()==d,'native battle presentation retired')
        assert(k~='id'and k~='side','native battler identity is read-only')
        if v~=nil and(numeric[k]or type(v)=='number')then assert(number(v),'invalid presentation number')end
        d.overrides[id][k]=v
      end})
  end
  return d.present[id]
end
function A.battlerCenter(key)
  local p=A.present(key);local base=Coords.coords(nil,A.idOf(key))
  if not p or not base then return nil end
  return base.x+(p.ox or 0),base.y+(p.oy or 0)
end
function A.shownBattler(key,fallback)local p=A.present(key);return p and p.shown or fallback end
function A.setShown(key,value)local p=A.present(key);if p then p.shown=value;return true end;return false end
function A.ballIdOf(key)
  local d,screen=context();local id=A.idOf(key);local b=d and id and battler(screen,id)
  if not b then return nil end
  return require('src.battle.Gen3BallAnim').ballIndex(screen.data,b.mon.ball or'POKE_BALL',screen.data.items)
end
function A.displayHpRatio(key,fallback)
  local p=A.present(key);local mon=fallback and fallback.mon
  local hp=p and p.displayHp or mon and mon.hp or 0
  local maximum=math.max(1,p and p.displayMaxHp or mon and mon.maxHp or 1)
  return math.max(0,math.min(1,hp/maximum)),hp,maximum
end
function A.displayExpRatio(key,fallback)
  local p=A.present(key or'player')
  return p and p.displayExp or 0,p and p.displayLevel or fallback and fallback.mon and fallback.mon.level or 1
end
function A.hpTweening()
  local _,screen=context();if not screen then return false end
  for _,id in ipairs(Coords.ids())do
    local b=battler(screen,id)
    if b and b.shownHP and(b.shownHP~=b.mon.hp or b.draining or(b.drainHold or 0)>0)then return true end
  end
  return false
end
local function effect()
  local d=context();if not d then return end
  if not d.effect then d.effect=require('src.render.BattleScreenEffect').new()end
  return d.effect
end
function A.setScreenEffect(opts)local e=effect();return e and e:set(opts)or false end
function A.screenEffect()local e=effect();return e and e.value end
function A.beginScreenEffect()local e=effect();return e and e:begin()or false end
function A.endScreenEffect()local e=effect();return e and e:finish()or false end
function A.busy()
  local d,screen=context()
  local sendout=package.loaded['src.core.game3.battle.sendout_tween']
  return d~=nil and(screen.gen3AnimPlaying==true or screen.gen3BallPlaying==true
    or A.hpTweening()or screen.expFilling==true or next(d.tasks)~=nil
    or sendout and sendout._busy(screen))or false
end
function A.setSeqBusy(value)local d=context();if d then d.seqBusy=value==true end end
function A.seqBusy()local d=context();return d and d.seqBusy==true or false end
local function tweenStage(frames,onStep,onComplete)
  local offer=tweenOffers:find('native.sendout.tween')
  if offer then return offer.value(frames,onStep,onComplete)end
  local d=context();if not d then return nil,'no admitted native battle'end
  assert(number(frames)and frames>=0,'invalid presentation duration')
  d.nextTask=d.nextTask+1
  local task={id=d.nextTask,frames=0,total=math.max(1,math.ceil(frames)),step=owned(onStep),done=owned(onComplete)}
  d.tasks[task.id]=task
  return task
end
A.tweenStage=tweenStage
function A._nativeSendOut(screen,anim,row)
  if A.tweenStage==tweenStage then return false end
  local _,actual=context();if actual~=screen then return false end
  return require('src.core.game3.battle.sendout_tween')._begin(screen,anim,row,A.tweenStage,
    function()return A.tweenStage end,function(configure,frames,step,complete)
      local offer=tweenOffers:push('native.sendout.tween',configure)
      local values={pcall(Call.call,A,'tweenStage',frames,step,complete)}
      local retired=offer.closed;tweenOffers:close(offer)
      if retired then error('native send-out tween offer retired',0)end
      if not values[1]then error(values[2],0)end
      return values[2]
    end)
end
function A._nativeStep(screen,dt)
  if not Clock.active(screen)then return false,'animation update belongs to its native battle phase'end
  local d,actual=context();if actual~=screen or screen.game.stack:top()~=screen then return false end
  return Clock.once(screen,'source.presentation',function()
    local clip=d.clip
    if clip then
      if clip.player~=screen.gen3Anim or clip.serial~=screen.gen3Anim.presentationSerial then
        d.clip,d.onEnd=nil,nil
      elseif screen.gen3AnimPlaying then
        require('src.core.Game3')._withCallbackOwner(nil,screen.updateMovePresentation,screen)
      end
    end
    -- Snapshot the IDs: a callback may schedule another tween, which starts
    -- next frame, or retire the admission, which cancels the remaining work.
    local ids={};for id in pairs(d.tasks)do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids)do
      if context()~=d or screen.game.stack:top()~=screen then return false end
      local task=d.tasks[id]
      if task then
        task.frames=task.frames+1
        callback(task.step,math.min(1,task.frames/task.total),task)
        if context()~=d then return false end
        if task.frames>=task.total then d.tasks[id]=nil;callback(task.done)end
      end
    end
    if context()==d and screen.game.stack:top()==screen and d.onEnd and not screen.gen3AnimPlaying then
      local done=d.onEnd;d.onEnd,d.clip=nil,nil;callback(done)
    elseif context()==d and not screen.gen3AnimPlaying then d.clip=nil
    end
    return true
  end)
end
function A._holdsNativeQueue(screen)
  local sendout=package.loaded['src.core.game3.battle.sendout_tween']
  if sendout and sendout._holds(screen)then return true end
  local d,actual=context();local clip=d and d.clip
  return actual==screen and clip~=nil and clip.player==screen.gen3Anim
    and clip.serial==screen.gen3Anim.presentationSerial and screen.gen3AnimPlaying==true
end
local publicUpdateStep='source.animation.public'
local function update(dt)
  if Boundary.active('battle.animation.update')then return Boundary.invoke('battle.animation.update')end
  local _,screen=context()
  if not screen or not Clock.active(screen)then return false,'animation update belongs to its native battle phase'end
  if screen.game.stack:top()~=screen then return false,'native battle is covered by another state'end
  return Clock.once(screen,publicUpdateStep,function()
    A._nativeStep(screen,Clock.delta(screen))
    if Battle._screen()~=screen or screen.game.stack:top()~=screen then return false,'native battle admission retired'end
    -- Explicit source holds and the native body share the same display steps.
    require('src.core.Game3')._withCallbackOwner(nil,screen.updatePresentation,screen,Clock.delta(screen))
    return true
  end)
end
A.update=update
-- Native frames also notify decoration-only wrappers. If a source update
-- already called its base, do not invoke the public wrapper a second time.
-- A wrapper's base here borrows completed presentation work, never another
-- native frame or command queue.
function A._nativeAfterUpdate(screen)
  if A.update==update or not Clock.active(screen)or Clock.called(screen,publicUpdateStep)then return end
  local _,actual=context()
  if actual~=screen or screen.game.stack:top()~=screen then return end
  return Clock.once(screen,publicUpdateStep,function()
    return Boundary.dispatch('battle.animation.update',function()
      if Battle._screen()~=screen or screen.game.stack:top()~=screen then return false,'native battle admission retired'end
      A._nativeStep(screen,Clock.delta(screen));return true
    end,function()return Call.call(A,'update',Clock.delta(screen))end)
  end)
end
function A.launchMove(moveId,opts)
  opts=opts or{};local d,screen=context()
  if not d then return false,'no admitted native battle'end
  if screen.game.stack:top()~=screen then return false,'native battle is covered by another state'end
  if screen.gen3AnimPlaying then return false,'native animation is already active'end
  local native=d.ids:native('moves',moveId);local anim=screen.gen3Anim
  if not native or not anim or not anim:has(native,opts)then return false,'no native animation record'end
  if opts.miss then return false,'native miss presentation requires its authored command'end
  local attacker=A.idOf(opts.attackerId or opts.attackerSide or'player')
  local target=A.idOf(opts.targetId or opts.targetSide or'enemy')
  if attacker==nil or target==nil or not battler(screen,attacker)or not battler(screen,target)then
    return false,'animation requires admitted native battlers'
  end
  local done=owned(opts.onEnd)
  if not require('src.core.Game3')._withCallbackOwner(nil,anim.start,anim,native,attacker%2==0,attacker,target,opts,screen)then return false end
  screen.gen3AnimPlaying=true;d.onEnd=done;d.clip={player=anim,serial=anim.presentationSerial}
  return true
end
function A.reset()
  local sendout=package.loaded['src.core.game3.battle.sendout_tween']
  if sendout then sendout._cancel()end
  retire();Coords._service.release();return true
end
function A._nativeExit(screen)
  if current and current.screen[1]==screen then A.reset()end
end
-- Applied around the existing native sprite draw, preserving its scanlines,
-- tints, substitutes and affine effects. Only source overrides compose here;
-- querying present() never feeds native effects back into themselves.
function A._drawBattler(screen,b,body,...)
  local d,actual=context();local id=b.position or(b.isPlayer and 0 or 1)
  local p=d and actual==screen and d.overrides[id]
  if not p or next(p)==nil then return body(screen,b,...)end
  if p.visible==false or p.invisible or p.battlerInvisible or p.blinkHidden then return end
  if not(p.hFlip or(p.ox or 0)~=0 or(p.oy or 0)~=0 or(p.rotation or 0)~=0
      or(p.scale or 1)~=1 or(p.sx or 1)~=1 or(p.sy or 1)~=1 or(p.alpha or 1)~=1)then
    return body(screen,b,...)
  end
  local args={...};local x,y,scale=args[1],args[2],args[3]or 1
  local img=screen:battlerPic(b);local w,h=img:getDimensions()
  local cx,cy=x+w*scale/2,y+h*scale/2
  local ok,result=Scope.call(function()
    local g=love.graphics
    g.translate(cx+(p.ox or 0),cy+(p.oy or 0));g.rotate(p.rotation or 0)
    g.scale((p.scale or 1)*(p.sx or 1)*(p.hFlip and -1 or 1),(p.scale or 1)*(p.sy or 1))
    g.translate(-cx,-cy)
    local r,green,blue,a=g.getColor();g.setColor(r,green,blue,a*(p.alpha or 1))
    return body(screen,b,x,y,scale)
  end)
  if not ok then error(result,0)end
  return result
end
A._service={release=A.reset,poll=function()context()end,releaseOwner=function(_,owner)
  if current and current.users[owner]then A.reset()end
end}
require('src.core.game3.asset_stream').register(A._service)
return A
