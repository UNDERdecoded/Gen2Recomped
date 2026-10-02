package.path='./?.lua;'..package.path
local rom=assert(require('src.import.NdsRom').open(arg[1]))
local arc=assert(require('src.import.NarcArchive').parse(rom:read('/data/mmodel/mmodel.narc')))
local F=require('src.import.Gen4Facings')
local sequence=F.read(arc).walk_and_run
local run=assert(F.facings(sequence,32,64))
local expected={up={8,9,12},down={13,14,16},left={17,18,20},right={21,23,25}}
local full=assert(F.cycles(sequence,64))
local Sprite=require('src.render.SpriteRenderer')
for _,sex in ipairs({'090','091'}) do
 local sprites=assert(loadfile('G:/Gen2Recomped/platinum/data/generated/sprites.lua'))()
 local walk=sprites['SPRITE_G4_'..sex]
 assert(walk.frames==32 and walk.facingSource:find('walk_and_run',1,true))
 for facing,frames in pairs(expected) do
  for i,v in ipairs(frames) do assert(run[facing][i]==v) end
  local def={walker=true,facings=run}
  assert(Sprite.facingFrames(def,facing,0,false)==frames[1])
  assert(Sprite.facingFrames(def,facing,1,false)==frames[2])
  assert(Sprite.facingFrames(def,facing,1,true)==frames[3])
  for phase=0,3 do assert(Sprite.facingFrames({fullCycle=true,facings=full},facing,phase,false)==F.textureAt(sequence,64+({up=0,down=1,left=2,right=3})[facing]*16+phase*4)) end
  assert(frames[2]~=walk.facings[facing][2],'run must have different artwork from walking')
 end
end
local Player=require('src.world.Player')
local runner={px=0,py=0,running=true,moving=true,facing='down',runSprite={def={fullCycle=true,facings=full}},sprite={},isUnderwater=function() return false end}
setmetatable(runner,{__index=Player})
for clock=0,15 do
 runner.animClock=clock
 local sprite,x,y,facing,phase=runner:pose()
 assert(sprite==runner.runSprite and phase==math.floor(clock/4),'player pose did not advance through the full running cycle')
end
runner.running=false
assert(runner:pose()==runner.sprite,'walking must restore the walking sheet')
assert(loadfile('src/world/Player.lua'));assert(loadfile('src/import/RomExtractorGen4.lua'))
rom:close()
print('Both Platinum protagonists: ROM run cycles, four facings, both stride poses and existing-cache compatibility passed')
