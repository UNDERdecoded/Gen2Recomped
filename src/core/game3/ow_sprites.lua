-- Original-order sprite interface backed by the native dataset. This facade
-- owns its resources and has no private actor, frame or extraction loop.
local Runtime=require('src.compat.gen1.SpriteRuntime')
local Pose=require('src.compat.gen1.SpritePose')
local Session=require('src.compat.gen1.NativeSession')
local Stream=require('src.core.game3.asset_stream')
local Assets=require('src.render.Assets')
local runtime=Runtime.new()
local S={}
Stream.register(runtime)
Assets.register(function()runtime:invalidate()end)
function S.install(cache)return runtime:install(cache)end
function S.invalidate()runtime:invalidate()end
function S.release()runtime:release()end
function S.ready()return runtime:ready()end
function S.get(id)return runtime:get(id)end
function S.getDraw(id)return runtime:getDraw(id)end
function S.getReflectionDraw(id)return runtime:reflection(id)end
function S.prefetch(id,priority)return runtime:prefetch(id,priority)end
function S.peekDraw(id)
  runtime:current();id=tonumber(id)
  if runtime.loaded[id]or runtime.overrides[id]then return runtime:getDraw(id)end
  runtime:prefetch(id,0);return nil
end
function S.setObjectPalette(id,key,colors,from)return runtime:setPalette(id,key,colors,from)end
function S.clearObjectPalette(id)return runtime:clearPalette(id)end
function S.objectPaletteKey(id)
  runtime:current();local o=runtime.overrides[tonumber(id)];return o and o.key
end
S.pose=Pose.pose
S.fieldMoveFrame=Pose.fieldMoveFrame
S.fishingFrame=Pose.fishingFrame
S.fishingAbsFrame=Pose.fishingAbsFrame
S.fishingOffset=Pose.fishingOffset
S.avatarState=Pose.avatarState
function S.avatars()local manifest=runtime:manifest();return manifest and manifest.avatars end
function S.avatarGraphicsId(state,female,avatars,who)return Pose.avatarGraphicsId(state,female,avatars or S.avatars(),who)end
function S.playerGraphicsId(game,provided)
  local native,why=Session.game(game);if game~=nil and not native then return nil,why end
  local _,world,player=Session.resolve(native)
  local observed=player and{
    fieldMoveAnim=player.fieldMove and 1 or 0,underwater=world.map.def.mapType=='UNDERWATER',
    fishing=player.fishing,surfing=player.surfing,dismounting=player.dismounting,flyRide=player.flyRide,
    biking=native.save and native.save.onBike,bikeType=player.acroBike and'acro'or native.save and native.save.bikeType,
    watering=player.watering,
  }or{}
  local source=provided or package.loaded['src.core.game3.player']
  local p=source and setmetatable({},{__index=function(_,key)
    local value=source[key];if value~=nil then return value end;return observed[key]
  end})or observed
  local session=type(game)=='table'and game.session
  local save=type(game)=='table'and game.save or native and native.save
  local gender=session and session.gender or save and(save.gender or save.player and save.player.gender)
  local female=gender==1 or gender=='female'or gender=='F'
  local avatars=S.avatars()
  if avatars then return Pose.avatarGraphicsId(Pose.avatarState(p),female,avatars)end
  -- FRLG's published interface uses these cartridge graphics constants when
  -- no avatar-state table exists. Hoenn always uses its imported state table.
  local c=runtime:current();if not c or(c.edition~='firered'and c.edition~='leafgreen')then return nil end
  local base=female and 7 or 0;local state=Pose.avatarState(p)
  if state=='FIELD_MOVE'then return base+(p.fieldMoveKind=='vs_seeker_bike'and 6 or 3)end
  return base+(({FISHING=4,SURFING=2,MACH_BIKE=1,ACRO_BIKE=1})[state]or 0)
end
function S.draw(id,px,py,camX,camY,facing,phase,flip,opts)
  local sprite=S.getDraw(id);if not sprite then return false end
  local frame,mirror=S.pose(sprite,facing,phase,flip,opts);local quad=sprite.quads[frame]
  if not quad then return false end
  local offX=sprite.drawOffX or 0;if mirror then offX=-offX end
  local x=px-camX+(16-sprite.width)/2+offX
  local y=py-camY+16-sprite.height+(sprite.drawOffY or 0)
  love.graphics.setColor(1,1,1,opts and opts.alpha or 1)
  love.graphics.draw(sprite.image,quad,x+(mirror and sprite.width or 0),y,0,mirror and -1 or 1,1)
  if opts and opts.alpha then love.graphics.setColor(1,1,1,1)end
  return true
end
-- Only the provider protocol is public. Its closure never exposes the native
-- game/dataset, owner sets or partially constructed GPU resources.
local stream={}
function stream:prefetch(id,priority)return S.prefetch(id,priority)end
function stream:get(id)return S.get(id)end
function stream:poll()runtime:poll()end
function stream:step(budget)runtime:step(budget)end
function stream:cancel(id)
  if id==nil then runtime:cancelPending();return true end
  local job=runtime.jobs[tonumber(id)];if not job then return false end;runtime:cancelJob(job);return true
end
function stream:retain(wanted)
  for id,job in pairs(runtime.jobs)do if not wanted[id]then runtime:cancelJob(job)end end
end
function stream:shutdown()S.release()end
setmetatable(stream,{__index=function(_,key)
  if key=='pending'then local out={};for id in pairs(runtime.jobs)do out[id]=true end;return out end
end})
setmetatable(S,{
  __index=function(_,key)
    runtime:current()
    if key=='_loaded'then return runtime.loaded end
    if key=='_overrides'then return runtime.overrides end
    if key=='_reflectionLoaded'then return runtime.reflections end
    if key=='_stream'then return stream end
    if key=='_manifest'then return runtime:manifest()end
    if key=='errors'then return runtime.errors end
    if key=='_cache'then local lease=runtime.providers[#runtime.providers];return lease and lease.cache end
    if key=='_root'then local c=runtime:current();return c and c.root end
  end,
  __newindex=function(t,key,value)
    if key=='_cache'then runtime:install(value)
    elseif key=='_loaded'then assert(value==nil or type(value)=='table','invalid sprite cache table');runtime:invalidate();runtime.loaded=value or{}
    else rawset(t,key,value)end
  end,
})
return S
