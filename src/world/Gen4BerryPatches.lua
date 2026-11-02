-- Platinum's persistent berry patches. Durations, drainage and base yields
-- come from nuts_data; initial fruit and watch-map positions come from the ROM.
local B = {}
local function constants(game) return game and game.data and game.data.constants or {} end
local function duration(data,p)
  local minutes=data.stageHours*60
  if p.mulch==95 then minutes=math.floor(minutes*3/4)
  elseif p.mulch==96 then minutes=minutes+math.floor(minutes/2) end
  return minutes
end
local function clear(p)
  for key in pairs(p) do p[key]=nil end
  p.stage,p.item,p.mulch=0,0,0
end
local function drain(data,p,minutes)
  if p.stage==5 then return end
  local rate=data.drain
  if p.mulch==95 then rate=rate+math.floor(rate/2)
  elseif p.mulch==96 then rate=math.floor(rate/2) end
  local elapsed=(p.moistureMinutes or 0)+minutes
  local hours=math.floor(elapsed/60); p.moistureMinutes=elapsed%60
  local moisture=p.moisture or 0
  if moisture>=rate*hours then p.moisture=moisture-rate*hours; return end
  if moisture>0 and rate>0 then hours=hours-math.ceil(moisture/rate) end
  p.moisture=0; p.rating=math.max(0,(p.rating or 5)-hours)
end
function B.elapse(p,data,minutes)
  if not data or not p.growing or (p.stage or 0)==0 then return end
  while minutes>0 and p.stage>0 do
    local remaining=p.remaining or duration(data,p)
    local used=math.min(minutes,remaining)
    drain(data,p,used)
    p.remaining=remaining-used; minutes=minutes-used
    if p.remaining==0 then
      if p.stage==5 then
        p.replants=(p.replants or 0)+1
        if p.replants >= (p.mulch==98 and 15 or 10) then clear(p); break end
        p.stage,p.yield,p.rating=2,0,5
      else
        p.stage=p.stage+1
        if p.stage==5 then p.yield=math.max(2,data.baseYield*(p.rating or 0)) end
      end
      p.remaining=duration(data,p)*(p.stage==5 and (p.mulch==97 and 6 or 4) or 1)
    end
  end
end
function B.sync(game,now)
  if not (game and game.save and game.data and game.data.isGen4Cache) then return nil end
  local c=constants(game)
  if not c.gen4BerryGrowth or not c.gen4BerryInitial then return nil end
  now=now or os.time()
  local store=game.save.gen4BerryPatches
  if not store then
    store={patches={},clock=now}; game.save.gen4BerryPatches=store
    for id,initial in pairs(c.gen4BerryInitial) do
      local p={item=initial.item,stage=5,yield=initial.yield,rating=3,
        mulch=0,moisture=100,moistureMinutes=0,replants=0,growing=false}
      local data=c.gen4BerryGrowth[p.item]
      if data then p.remaining=duration(data,p)*4; store.patches[id]=p end
    end
  end
  local minutes=math.floor(math.max(0,now-(store.clock or now))/60)
  if minutes>0 then
    for _,p in pairs(store.patches) do B.elapse(p,c.gen4BerryGrowth[p.item],minutes) end
    store.clock=(store.clock or now)+minutes*60
  end
  return store.patches
end
function B.get(game,id,now)
  id=tonumber(id)
  if not id or id<0 or id>=128 then return nil end
  local patches=B.sync(game,now)
  if not patches then return nil end
  patches[id]=patches[id] or {stage=0,item=0,mulch=0}
  patches[id].growing=true
  return patches[id]
end
function B.target(ctx)
  local def=ctx.npc and (ctx.npc.def or ctx.npc)
  return def and B.get(ctx.game,def.berryPatch)
end
function B.plant(game,p,item)
  local data=constants(game).gen4BerryGrowth and constants(game).gen4BerryGrowth[item]
  if not p or p.stage~=0 or not data then return false end
  p.item,p.stage,p.yield,p.rating=item,1,0,5
  p.moisture,p.moistureMinutes,p.replants,p.growing=100,0,0,true
  p.remaining=duration(data,p)
  return true
end
function B.harvest(game,p)
  if not p or p.stage~=5 or (p.yield or 0)<1 then return false end
  if not require('src.inventory.Bag').add(game.save,p.item,p.yield,game.data) then return false end
  -- Platinum's Planting and Watering Show (BerryPatches_HarvestBerry)
  pcall(function() require('src.script.PtTvRecords').harvested(game.save,p.item,p.rating,p.yield) end)
  clear(p); return true
end
function B.observe(game)
  local ow=game and game.overworld
  if not (ow and ow.map and ow.map.def) then return end
  for _,object in ipairs(ow.map.def.objects or {}) do
    if object.berryPatch~=nil then B.get(game,object.berryPatch) end
  end
end
function B.ready(game,now)
  local patches=B.sync(game,now) or {}
  local positions=constants(game).gen4BerryPositions or {}
  local found,seen={},{}
  for id,p in pairs(patches) do
    local at=positions[id]
    if at and p.growing and p.stage==5 then
      local key=at.x..':'..at.y
      if not seen[key] then found[#found+1]=at; seen[key]=true end
    end
  end
  return found
end
function B.graphicsId(p)
  local stage=p and p.stage or 0
  if stage<2 then return nil end
  if stage==2 then return 4096 end
  local item=tonumber(p.item)
  if not item or item<149 or item>212 or stage>5 then return nil end
  return 4096+(item-149)*3+stage-2
end
function B.pose(game,npc,SpriteRenderer)
  local id=npc.def and npc.def.berryPatch
  if id==nil then return end
  local patches=game.save.gen4BerryPatches and game.save.gen4BerryPatches.patches
  local p=patches and patches[id]
  local gfx=B.graphicsId(p)
  npc.berryVisualEmpty=gfx==nil
  if not gfx or npc.berryGraphicsId==gfx then return end
  local name=require('src.import.Gen4ObjectGfx').name(gfx)
  local record=game.data.gen4_overworld and game.data.gen4_overworld.sprites[name]
  local key=record and record.member and ('SPRITE_G4_%03d'):format(record.member)
  local sheet=key and game.data.sprites and game.data.sprites[key]
  if sheet then
    npc.sprite=SpriteRenderer.new(sheet,npc.id)
    npc.berryGraphicsId=gfx
    npc.fixedFrame=nil
  end
end
return B
