-- Typed observations of one native GBA save, never another save/simulation.
-- Collection schemas (party, bag, script stores) have separate adapters; do
-- not lend differently shaped native tables under those source names.
local Native=require('src.compat.gen1.NativeSession')
local Identity=require('src.compat.gen1.MapIdentity')
local Version=require('src.core.GameVersion')
local ScriptStore=require('src.compat.gen1.ScriptStore')
local ScriptMap=require('src.compat.gen1.ScriptMap')
local Iteration=require('src.compat.gen1.TableIteration')
local M={}
local records=setmetatable({},{__mode='k'})
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function M.seconds(save)
  local value=save and save.playTime
  if type(value)=='table'then
    local function number(a,b)local n=tonumber(a)or tonumber(b)or 0;return finite(n)and n>=0 and n or 0 end
    return number(value.hours)*3600+number(value.minutes,value.mins)*60
      +number(value.seconds,value.secs)+number(value.frames,value.vblanks)/60
  end
  local n=tonumber(value);return finite(n)and n>=0 and n or 0
end
function M.new(game)
  local owner,why=Native.game(game);if not owner then return nil,why end
  local data,save,edition=owner.data,owner.save,Version.get()
  if type(data)~='table'or type(data.maps)~='table'or type(save)~='table'then return nil,'native save data unavailable'end
  if not Identity.lookup(edition,0,0)then return nil,'native source map catalogue unavailable'end
  local binding=Identity.bind(data.maps,edition)
  local record={owner=owner,data=data,save=save,edition=edition,maps=data.maps,clock={}}
  local scripts=assert(ScriptStore.new(owner))
  local flags,vars=ScriptMap.new(scripts,'flags'),ScriptMap.new(scripts,'vars')
  local view={}
  function record:valid()
    if self.retired then return false end
    if not scripts:valid()or Version.get()~=edition or owner.data~=data or owner.save~=save or data.maps~=self.maps then
      self.retired=true;scripts:release();return false
    end
    return true
  end
  function record:seconds()return M.seconds(save)end
  function record:world()
    if not self:valid()then return end
    local _,world,player=Native.resolve(owner);return world,player
  end
  function record:map()
    local world=self:world();local id=world and world.map.id or(save.player and save.player.map)
    return id and binding:legacyId(id)
  end
  local function current()
    if not record:valid()then return nil end
    return save.player or{},record:world()
  end
  setmetatable(view,{
    __index=function(_,key)
      local player,world,actor=current();if not player then return nil end
      if key=='version'then return edition end
      if key=='generation'then return 3 end
      if key=='flags'then return flags end
      if key=='vars'then return vars end
      if key=='engine'then return 'game3'end
      if key=='map'then return record:map()end
      if key=='x'or key=='y'then return actor and actor[key=='x'and'cellX'or'cellY']or player[key]end
      if key=='facing'then return actor and actor.facing or player.facing end
      if key=='name'then return player.name end
      if key=='rivalName'then return player.rival end
      if key=='trainerId'then return player.id end
      if key=='gender'then return player.gender end
      if key=='money'or key=='coins'or key=='modData'or key=='meta'or key=='options'then return save[key]end
      if key=='biking'then return save.onBike==true end
      if key=='bikeType'then return actor and actor.acroBike and'acro'or save.bikeType end
      if key=='surfing'then if actor then return actor.surfing==true end;return player.surfing==true end
      if key=='underwater'then return world and world.map.def.mapType=='UNDERWATER'or false end
      if key=='elevation'then return actor and actor.elevation or player.elevation end
      local seconds=record:seconds();local whole=math.floor(seconds)
      if key=='playTime'or key=='playtime'then
        local clock=record.clock
        clock.hours,clock.minutes,clock.seconds=math.floor(whole/3600),math.floor(whole/60)%60,whole%60
        clock.vblanks=math.floor((seconds-whole)*60+.000001)
        return clock
      end
      if key=='hours'or key=='playTimeHours'then return math.floor(whole/3600)end
      if key=='minutes'or key=='playTimeMinutes'then return math.floor(whole/60)%60 end
      if key=='seconds'or key=='playTimeSeconds'then return whole%60 end
    end,
    __newindex=function(t,key,value)
      assert(record:valid(),'native session view retired')
      local player=save.player
      if key=='money'or key=='coins'then
        assert(finite(value)and value>=0 and value%1==0 and value<4294967296,'invalid session '..key)
        save[key]=value
      elseif key=='flags'or key=='vars'then
        ScriptMap.replace(scripts,key,value)
      elseif key=='name'or key=='rivalName'then
        assert(player and type(value)=='string'and#value<=10 and not value:find('%c'),'invalid player name')
        player[key=='name'and'name'or'rival']=value
      elseif key=='gender'then
        assert(player and(value==0 or value==1),'invalid player gender');player.gender=value
      elseif key=='trainerId'then
        assert(player and finite(value)and value>=0 and value<=65535 and value%1==0,'invalid native trainer id');player.id=value
      elseif key=='biking'then
        assert(type(value)=='boolean','invalid bike state');save.onBike=value
      elseif key=='map'or key=='x'or key=='y'or key=='facing'or key=='elevation'or key=='surfing'
          or key=='version'or key=='generation'or key=='engine'or key=='options'or key=='modData'or key=='meta'
          or key=='playTime'or key=='playtime'or key=='hours'or key=='minutes'or key=='seconds'
          or key=='playTimeHours'or key=='playTimeMinutes'or key=='playTimeSeconds'then
        error('session '..key..' belongs to its native command owner',2)
      else
        -- Temporary presentation/preview fields stay detached. Persistence
        -- belongs to mod.save; this never adds fields to a player's save.
        rawset(t,key,value)
      end
    end,
  })
  record.scripts=scripts
  local fields={'version','generation','engine','map','x','y','facing','name','rivalName','trainerId','gender',
    'money','coins','modData','meta','options','biking','bikeType','surfing','underwater','elevation',
    'playTime','flags','vars'}
  Iteration.register(view,function(state,source)
    assert(state:valid(),'native session view retired')
    local out={}
    -- Include detached presentation fields without recursing through the
    -- registered iterator. No registry callback captures its own weak key.
    for k,v in Iteration.rawPairs(source)do out[k]=v end
    for _,key in ipairs(fields)do
      local v=source[key]
      if key=='flags'or key=='vars'then v=Iteration.snapshot(v)
      elseif key=='playTime'and v then
        v={hours=v.hours,minutes=v.minutes,seconds=v.seconds,vblanks=v.vblanks}
      end
      out[key]=v
    end
    return out
  end,record)
  records[view]=record
  return view,record
end
function M.record(view)return records[view]end
function M.release(view)
  local record=records[view]
  if record then record.retired=true;record.scripts:release()end
end
return M
