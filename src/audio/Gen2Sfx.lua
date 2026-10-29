-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- GSC PlaySFX/PlayStereoSFX arbitration over the real native Sources. There
-- is no audio clock here: CheckSFX observes whether those Sources are playing.
local M={}
local Bus={};Bus.__index=Bus
local function native(def)
  return type(def)=='table' and (def.engine=='gen2' or def.generation==2)
end
local function sameHeader(a,b)
  return native(a) and native(b) and a.bank~=nil and a.address~=nil
    and a.bank==b.bank and a.address==b.address
end
local function validId(id)
  return type(id)=='number' and id==id and id>=0 and id<=65535 and id%1==0
end

-- The current importer supplies a sparse zero-based sfxIndex; original
-- source-native data supplies sfxOrder. Prefer an exact native label, then
-- the same aliased definition/header. Never guess an id from a sound's name.
function M.idFor(data,name,def)
  if not native(def)then return end
  local audio=data and data.audio or {}
  local exact,alias
  local function consider(id,label)
    if not validId(id)then return end
    if label==name then exact=math.max(exact or -1,id)
    else
      local other=audio.sfx and audio.sfx[label]
      if other==def or sameHeader(other,def)then alias=math.max(alias or -1,id)end
    end
  end
  if type(audio.sfxIndex)=='table'then
    for id,label in pairs(audio.sfxIndex)do consider(tonumber(id),label)end
  elseif type(audio.sfxOrder)=='table'then
    for index,label in ipairs(audio.sfxOrder)do consider(index-1,label)end
  end
  return exact or alias
end
function M.new(stop)
  return setmetatable({voices=setmetatable({},{__mode='k'}),current=0,stop=stop},Bus)
end
function Bus:clear()
  for source in pairs(self.voices)do self.stop(source);self.voices[source]=nil end
end
function Bus:reset()
  self:clear();self.current,self.audio=0,nil
end
function Bus:forget(name)
  if name==nil then return self:reset()end
  for source,row in pairs(self.voices)do if row.name==name then self.voices[source]=nil end end
end
function Bus:busy()
  local busy=false
  for source in pairs(self.voices)do
    local ok,playing=pcall(source.isPlaying,source)
    if ok and playing then busy=true else self.voices[source]=nil end
  end
  return busy
end
function Bus:play(data,name,def,stereo,mono,start)
  local id=M.idFor(data,name,def)
  if id==nil then return start()end
  if self.audio~=data.audio then self:reset();self.audio=data.audio end
  -- home/audio.asm:180-207 compares E with wCurSFX only while CheckSFX
  -- reports an active channel. PlayStereoSFX never writes that byte.
  if not stereo and self:busy() and self.current<id%256 then return end
  -- _PlaySFX clears all four SFX channels. PlayStereoSFX falls through to
  -- _PlaySFX in mono mode, but keeps the ungated entry and unchanged wCurSFX.
  if not stereo or mono then self:clear()end
  local source=start()
  if source then
    self.voices[source]={name=name,id=id}
    if not stereo then self.current=id%256 end
  end
  return source
end
return M
