-- Nintendo DS SSEQ transport over the ROM's SBNK/SWAR instruments.
-- PCM/ADPCM mixing is local; no replacement MIDI soundfont is used.
local FrameProfile = require("src.core.FrameProfile")
local Sdat=require('src.import.Gen4Sdat')
local Audio={};local Player={};Player.__index=Player
local archives,players={},setmetatable({}, {__mode="k"})
local RATE,BLOCK=32768,512
local function u8(s,o) return s:byte(o+1) end
local function u16(s,o) local a,b=s:byte(o+1,o+2);return b and a+b*256 end
local function u32(s,o) local a,b,c,d=s:byte(o+1,o+4);return d and a+b*256+c*65536+d*16777216 end
local function track(at) return {at=at,wait=0,program=0,volume=127,expression=127,pan=64,transpose=0,bend=0,bendRange=2,noteWait=true,calls={},loops={}} end
-- The imported SDAT, opened once per path and shared by every player (BGM and
-- each sound effect alike).
function Audio.archive(data)
 local path=assert(data and data.audio and data.audio.ndsArchive,'missing imported SDAT')
 local arc=archives[path]
 if not arc then
  local resolved=require('src.render.Assets').resolve(path)
  local bytes,why=love.filesystem.read(resolved)
  -- The game mounts the version cache over the read path; a tool run with
  -- POKEPORT_ASSET_ROOT has no mount and reads the cache folder directly.
  local root=not bytes and os.getenv('POKEPORT_ASSET_ROOT')
  if root then
   local f=io.open(root..'/'..resolved,'rb')
   if f then bytes=f:read('*a');f:close() end
  end
  arc=assert(Sdat.open(assert(bytes,why)));archives[path]=arc
 end
 return arc
end
function Audio.new(data,def)
 local arc=Audio.archive(data)
 local seq=assert(Sdat.sequence(arc,assert(def.nds)),'missing SDAT sequence')
 local at,size=Sdat.fileAt(arc,seq.file);local bytes=arc.data:sub(at+1,at+size)
 assert(bytes:sub(1,4)=='SSEQ','not a native SSEQ')
 local start=assert(u32(bytes,24),'truncated sequence')
 local self=setmetatable({arc=arc,seq=seq,bytes=bytes,start=start,tracks={[0]=track(start)},
  voices={},samples={},tempo=120,tickPhase=0,master=(seq.volume or 127)/127,
  queue=love.audio.newQueueableSource(RATE,16,2,4),looping=true,running=false},Player)
 players[self]=true
 return self
end
-- Sequence variables: 0-15 belong to the player and 16-31 are shared by
-- every player; each starts at SND_DEFAULT_VARIABLE (-1) and holds an s16.
-- The game only reads them back (pokeheartgold sub_02005B78 ->
-- NNS_SndPlayerReadVariable), so nothing outside the sequences writes them.
local globalVariables={}
function Player:variable(index)
 if index>=32 then return 0 end
 local v
 if index<16 then v=self.variables and self.variables[index] else v=globalVariables[index-16] end
 if v==nil then return -1 end;return v
end
function Player:setVariable(index,v)
 v=math.floor(v)%65536;if v>=32768 then v=v-65536 end
 if index<16 then self.variables=self.variables or {};self.variables[index]=v
 elseif index<32 then globalVariables[index-16]=v end
end
function Player:setVolume(v) self.queue:setVolume(v) end
-- A playback-rate factor over every voice (sound-effect pitch shifts).
function Player:setPitch(v) self.pitch=tonumber(v) or 1 end
function Player:getPitch() return self.pitch or 1 end
function Player:getVolume() return self.queue:getVolume() end
function Player:setFilter(...) return self.queue:setFilter(...) end
function Player:setLooping(v) self.looping=v end
function Player:isPlaying() return self.running and (not self.ended or #self.voices>0 or self.queue:isPlaying()) end
function Player:stop() self.running=false;self.queue:stop();self.voices={} end
function Player:pause() self.paused=true;self.queue:pause() end
function Player:play()
 if self.paused then self.paused=false;self.queue:play();return end
 self.queue:stop();self.tracks={[0]=track(self.start)};self.voices={};self.tickPhase=1;self.variables={}
 self.ended=false;self.running=true;self:update();self.queue:play()
end
local function signed(v) return v>=128 and v-256 or v end
function Player:note(t,note,velocity,duration)
 note=note+t.transpose
 local ins=Sdat.instrument(self.arc,self.seq.bank,t.program,note)
 if not ins then return end
 local key=ins.kind..':'..tostring(ins.archive)..':'..tostring(ins.wave)
 local sample=self.samples[key]
 if not sample then
  if ins.kind==1 then
   local list=Sdat.samples(self.arc,ins.archive)
   local swav=list and list[(ins.wave or 0)+1]
   local pcm,loop=Sdat.pcm(self.arc,swav)
   if pcm and #pcm>0 then sample={pcm=pcm,loop=swav.loop,loopAt=loop,rate=swav.rate};self.samples[key]=sample end
  elseif ins.kind==2 or ins.kind==3 then
   local pcm={};local period=ins.kind==2 and 8 or 32767;local lfsr=32767
   for i=1,period do
    if ins.kind==2 then pcm[i]=i<=((ins.wave or 3)+1) and 0.5 or -0.5
    else local bit=(lfsr%2+math.floor(lfsr/2)%2)%2;lfsr=math.floor(lfsr/2)+bit*16384;pcm[i]=lfsr%2==0 and -0.3 or 0.3 end
   end
   sample={pcm=pcm,loop=true,loopAt=0,rate=440*period};self.samples[key]=sample
  end
 end
 if not sample then return end
 if #self.voices>=32 then table.remove(self.voices,1) end
 local root=ins.kind==1 and ins.root or 69
 local pan=math.max(0,math.min(127,t.pan+ins.pan-64))/127
 self.voices[#self.voices+1]={sample=sample,pos=0,step=sample.rate/RATE*2^((note-root+t.bend*t.bendRange/128)/12),
  ticks=math.max(1,duration),gain=velocity/127*t.volume/127*t.expression/127*self.master*0.35,
  left=math.sqrt(1-pan),right=math.sqrt(pan),release=0}
end
function Player:events(t)
 local b=self.bytes
 local function read() local v=assert(u8(b,t.at),'sequence overrun');t.at=t.at+1;return v end
 local function word() local a,c=read(),read();return a+c*256 end
 local function address() local a,c,d=read(),read(),read();return self.start+a+c*256+d*65536 end
 local function variable() local v=0;for _=1,5 do local c=read();v=v*128+c%128;if c<128 then return v end end;error('invalid sequence variable') end
 local function s16(v) v=v%65536;return v>=32768 and v-65536 or v end
 for _=1,2048 do
  if t.done or t.wait>0 then return end
  local op=read()
  -- The NitroSDK sequencer's three prefixes, in any order: 0xA2 runs the
  -- next command only while the track's compare flag is set (the args are
  -- still read), 0xA0 / 0xA1 replace its last argument with a random value
  -- (s16 min, s16 max) or a sequence variable (u8 index). The argument is
  -- read where the command reads it, so `A1 B0 var idx` takes its variable
  -- number first. HEARTGOLD / SOULSILVER's battle themes open on
  -- `B0 00 00 00` (setvar): unhandled, it raised on the first tick and
  -- NitroAudio.update stopped the player -- the silent battle.
  local run,argType=true,nil
  while op==160 or op==161 or op==162 do
   if op==162 then run=t.cmp~=false else argType=op end
   op=read()
  end
  local function parameter(fn)
   if argType==160 then
    local lo,hi=s16(word()),s16(word());argType=nil
    return math.random(math.min(lo,hi),math.max(lo,hi))
   elseif argType==161 then
    argType=nil;return self:variable(read())
   end
   return fn()
  end
  if op<128 then
   local velocity=read();local duration=parameter(variable)
   if run then
    self:note(t,op,velocity,duration)
    if t.noteWait then t.wait=duration end
   end
  elseif op==128 then local v=parameter(variable);if run then t.wait=v end
  elseif op==129 then local v=parameter(variable);if run then t.program=v%128 end
  elseif op==147 then local id=read();local dest=address();if run then self.tracks[id]=track(dest) end
  elseif op==148 then local dest=address();if run then if not self.looping and dest<t.at then t.done=true else t.at=dest end end
  elseif op==149 then local dest=address();if run then assert(#t.calls<16,'sequence call overflow');t.calls[#t.calls+1]=t.at;t.at=dest end
  elseif op>=176 and op<=189 then
   -- variable arithmetic and compares (u8 variable, s16 argument)
   local index=read();local v=parameter(function() return s16(word()) end)
   if run then
    local cur=self:variable(index)
    if op==176 then self:setVariable(index,v)
    elseif op==177 then self:setVariable(index,cur+v)
    elseif op==178 then self:setVariable(index,cur-v)
    elseif op==179 then self:setVariable(index,cur*v)
    elseif op==180 then if v~=0 then local q=cur/v;self:setVariable(index,q<0 and math.ceil(q) or math.floor(q)) end
    elseif op==181 then self:setVariable(index,v>=0 and cur*2^v or math.floor(cur/2^(-v)))
    elseif op==182 then local r=math.random(0,math.abs(v));self:setVariable(index,v<0 and -r or r)
    elseif op==184 then t.cmp=cur==v elseif op==185 then t.cmp=cur>=v
    elseif op==186 then t.cmp=cur>v elseif op==187 then t.cmp=cur<=v
    elseif op==188 then t.cmp=cur<v elseif op==189 then t.cmp=cur~=v end
   end
  elseif not run and (op==252 or op==253 or op==255) then
   -- a skipped loop end / return / fin
  elseif not run and op==254 then word()
  elseif op==253 then t.at=table.remove(t.calls);if not t.at then t.done=true end
  elseif op==254 then word()
  elseif op==255 then t.done=true
  elseif op==252 then
   local loop=t.loops[#t.loops];if loop then
    loop.count=loop.count-1
    if loop.forever and self.looping or loop.count>0 then t.at=loop.at else table.remove(t.loops) end
   end
  elseif not run and (op>=192 and op<=223) then parameter(read)
  elseif not run and (op==224 or op==225 or op==227) then parameter(word)
  elseif op>=192 and op<=223 then
   local v=parameter(read)
   if op==192 then t.pan=v elseif op==193 then t.volume=v elseif op==194 then self.master=v/127
   elseif op==195 then t.transpose=signed(v) elseif op==196 then t.bend=signed(v)
   elseif op==197 then t.bendRange=v elseif op==199 then t.noteWait=v~=0
   elseif op==212 then t.loops[#t.loops+1]={at=t.at,count=v,forever=v==0}
   elseif op==213 then t.expression=v end
  elseif op==224 or op==227 then parameter(word)
  elseif op==225 then self.tempo=math.max(1,parameter(word))
  else error(('unsupported SSEQ command %02X at %X'):format(op,t.at-1)) end
 end
 error('sequence failed to yield')
end
function Player:tick()
 local live=false
 for _,t in pairs(self.tracks) do
  if not t.done then t.wait=math.max(0,t.wait-1);self:events(t);live=live or not t.done end
 end
 self.ended=not live
 for _,v in ipairs(self.voices) do v.ticks=v.ticks-1;if v.ticks<=0 and v.release==0 then v.release=math.floor(RATE*0.04) end end
end
function Player:render()
 local closeRender=FrameProfile.section("  audio: Nitro render")
 local sound=love.sound.newSoundData(BLOCK,RATE,16,2)
 for i=0,BLOCK-1 do
  self.tickPhase=self.tickPhase+self.tempo*48/60/RATE
  while self.tickPhase>=1 do self.tickPhase=self.tickPhase-1;self:tick() end
  local left,right=0,0
  for n=#self.voices,1,-1 do
   local v=self.voices[n];local s=v.sample;local pcm=s.pcm
   if v.pos>=#pcm then
    if s.loop and #pcm>s.loopAt then v.pos=s.loopAt+(v.pos-s.loopAt)%(#pcm-s.loopAt)
    else table.remove(self.voices,n);v=nil end
   end
   if v then
    local index=math.floor(v.pos)+1;local gain=v.gain
    if v.release>0 then gain=gain*v.release/(RATE*0.04);v.release=v.release-1;if v.release==0 then table.remove(self.voices,n) end end
    local value=(pcm[index] or 0)*gain
    left=left+value*v.left;right=right+value*v.right;v.pos=v.pos+v.step*(self.pitch or 1)
   end
  end
  sound:setSample(i,1,math.max(-1,math.min(1,left)))
  sound:setSample(i,2,math.max(-1,math.min(1,right)))
 end
 closeRender()
 return sound
end
function Player:update()
 if not self.running or self.paused then return end
 if self.ended and #self.voices==0 then
  if not self.queue:isPlaying() then self.running=false end
  return
 end
 while self.queue:getFreeBufferCount()>0 do self.queue:queue(self:render());if self.ended and #self.voices==0 then break end end
 if not self.queue:isPlaying() then self.queue:play() end
end
function Audio.update()
 for p in pairs(players) do
  if p.running then
   local ok,why=pcall(p.update,p)
   if not ok then p:stop();require('src.core.Logger').warn('DS audio: %s',tostring(why)) end
  end
  -- Music keeps its Source and may replay it after a pause; do not evict it.
 end
end
return Audio
