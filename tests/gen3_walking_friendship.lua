-- Executes the controller's actual completed-step friendship branch and
-- real Gen3Friendship routine. No cartridge, extracted data or renderer.
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local source=read('src/world/OverworldController.lua')
local first=assert(source:find('  self.todSteps = (self.todSteps or 0) + 1',1,true))
local last=assert(source:find('  -- re-evaluate day/night',first,true))
local V=require('src.core.GameVersion');local F=require('src.pokemon.Gen3Friendship')
local real=F.step;local calls,legacy=0,0
local Game={data={pokemon={TEST={friendship=70}}},save={}}
local native={['src.pokemon.Gen3Friendship']=F,
 ['src.world.PikachuFollower']={onStep=function()end},['src.world.HgssFollowMon']={onStep=function()end},
 ['src.pokemon.Gen2Friendship']={isVanilla=function()return false end},
 ['src.pokemon.Evolution']={changeHappiness=function()legacy=legacy+1 end}}
local chunk=assert(loadstring('return function(self)\n'..source:sub(first,last-1)..'end'))
setfenv(chunk,setmetatable({Game=Game,GameVersion=V,require=function(n)return assert(native[n],n)end},{__index=_G}))
local step=chunk();F.step=function(...)calls=calls+1;return real(...)end
local originalRandom=math.random;local editions=0
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald'}do
 if V.VERSIONS[edition] then
 editions=editions+1;V.set(edition)
 for _,coin in ipairs{0,1}do
  local mon={species='TEST',happiness=70};local egg={species='TEST',happiness=70,isEgg=true}
  Game.save={party={mon,egg}};local world={map={def={regionMapSection=5}}};calls,legacy=0,0
  math.random=function(a,b)assert(a==0 and b==65535);return coin end
  for i=1,256 do step(world);assert(Game.save.gen3FriendshipSteps==i%128)end
  assert(calls==256 and legacy==0,'Gen3 step omitted or used generic legacy friendship: '..edition)
  assert(mon.happiness==(coin==0 and 72 or 70)and egg.happiness==70)
 end
end end
assert(editions>=3)
math.random=originalRandom
print('PASS_GEN3_WALKING_FRIENDSHIP',editions,editions*512,'actual controller branch steps, both coin outcomes, eggs excluded')
