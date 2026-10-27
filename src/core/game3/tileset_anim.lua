-- Animation observes the existing native clock. It never advances the game,
-- source scripts, RNG or a second terrain timer.
local A={_visible={}}
local function native()return require('src.core.game3.tileset_native')end
-- Metadata is derived from the admitted atlas, never from a second animation
-- scheduler. Detached decoders let renderers inspect every water frame without
-- rewinding the live sheet or changing the native clock.
local observed=setmetatable({},{__mode='k'})
local function waterBank(model,edition)
 local B=require('src.compat.gen1.MetatileBehavior')
 local decoder=model.decoder
 local water={[B.POND_WATER]=true,[B.OCEAN_WATER]=true,[B.DEEP_WATER]=true,
  [B.FAST_WATER]=true,[B.SHALLOW_WATER]=true}
 local relevant={}
 for _,mid in ipairs(decoder:animatedMetatiles())do
  local raw=decoder:sourceBehavior(mid)
  if raw~=nil and water[B.fromRaw(edition,raw)]then
   for _,part in ipairs(decoder:entries(mid))do
    for i,anim in ipairs(decoder:animations())do
     if part.tile>=anim.tile and part.tile<anim.tile+anim.count then relevant[i]=true end
    end
   end
  end
 end
 if not next(relevant)then return nil end
 local mids={}
 for _,mid in ipairs(model.mids)do
  local included=false
  for _,part in ipairs(decoder:entries(mid))do
   for i in pairs(relevant)do local anim=decoder:animations()[i]
    if part.tile>=anim.tile and part.tile<anim.tile+anim.count then included=true end
   end
  end
  if included then mids[#mids+1]=mid end
 end
 local function gcd(a,b)while b~=0 do a,b=b,a%b end;return a end
 local period=1
 for i in pairs(relevant)do local anim=decoder:animations()[i]
  local n=math.max(1,math.floor(anim.step))*#anim.frames
  period=period/gcd(period,n)*n
  if period>65536 then return nil,'native water animation period exceeds observation budget'end
 end
 local times={[0]=true}
 for i in pairs(relevant)do local step=math.max(1,math.floor(decoder:animations()[i].step))
  for tick=step,period-1,step do times[tick]=true end
 end
 local ticks={};for tick in pairs(times)do ticks[#ticks+1]=tick end;table.sort(ticks)
 if #ticks>256 or #ticks*#mids*1024>16*1024*1024 then return nil,'native water observation exceeds byte budget'end
 local snapshot=require('src.compat.gen1.AtlasPixels').new(
  {primary=decoder.primary,secondary=decoder.secondary},{tilesInPrimary=decoder.tilesInPrimary,
   metatilesInPrimary=decoder.metatilesInPrimary,palettesInPrimary=decoder.palettesInPrimary,metatileLayers=decoder.layers})
 local frames={}
 for _,tick in ipairs(ticks)do
  snapshot:update(tick)
  for _,mid in ipairs(mids)do frames[#frames+1]=snapshot.under[snapshot.midToSlot[mid]]end
 end
 return {mids=mids,frames=#ticks,rgba=table.concat(frames),ticks=ticks,period=period}
end
local function entry(name)
 local ts=native().get(name)
 if not(ts and ts._model and not ts._retired)then return nil end
 local prior=observed[ts]
 if not prior then
  local edition=require('src.core.GameVersion').get()
  -- The weak-key cache must not point strongly back to its key. Observing
  -- metadata cannot keep a trimmed native atlas (or its RGBA samples) alive.
  local reference=setmetatable({ts},{__mode='v'})
  prior=setmetatable({rse=edition~='firered'and edition~='leafgreen',banks={}},
   {__index=function(_,key)if key=='atlas'then return reference[1]end end})
  local water,why=waterBank(ts._model,edition)
  prior.banks.water,prior.unavailableReason=water,why
  observed[ts]=prior
 end
 return prior
end
A._pairs=setmetatable({},{__index=function(_,name)if type(name)=='string'then return entry(name)end end})
function A.install()A.invalidate()end
function A.invalidate()A._visible={};A._current=nil;A._pair=nil;observed=setmetatable({},{__mode='k'})end
function A.enterMap(pair)return A.bindPair(pair)end
function A.bindPair(pair,atlas)
 if type(pair)~='string'then return false end
 local owned=native().get(pair)
 if not owned or owned._retired or atlas~=nil and atlas~=owned then return false end
 A._current=pair;A._pair=pair;A._visible[pair]=true;return true
end
function A.unbindPair(pair)A._visible[pair]=nil;if A._pair==pair then A._pair=nil;A._current=nil end end
function A.setVisiblePairs(pairs)A._visible=pairs or{}end
function A.step()native().update()end
A.stepRse=A.step
A.release=A.invalidate
return A
