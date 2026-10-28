-- Counterexample through the native player's actual OAM consumer. The old
-- archetype interpolator produces different pixels and retires at 48 frames.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Player=require('src.battle.Gen2AnimPlayer')
local previous=Version.get()
for _,edition in ipairs({'gold','silver','crystal'})do
 Version.set(edition)
 for _,player in ipairs({true,false})do
  local data={battle_anims={gen2=true,moveAnims={PROBE=1},
   scripts={[1]={entry=1,code={{op='gfx',ids={1}},
    {op='obj',args={0,64,96,4}},{op='delay',frames=200},{op='ret'}}}},
   objects={[0]={oamFlags=1,fixY=255,frameset=0,fn=0,palette=2,gfx=1}},
   functions={[0]='MoveFromUserToTarget'},
   framesets={[0]={frames={{oam=0,duration=1}},loop='restart'}},
   oam={[0]={tile=0,sprites={{x=0,y=0,tile=0,attr=0}}}},
   gfx={[1]={tiles=1,cols=1,image='native-motion'}}}}
  local p=Player.new(data);T.check(p:start('PROBE',player))
  for frame=1,30 do
   p:update()
   local x=math.min(132,64+4*frame)
   local y=96-math.min(17,frame)*2
   local row=p:oam()[1]
   T.eq(row and row.x,player and x or 180-x,'actual cartridge X step and stop threshold')
   T.eq(row and row.y,player and y or 40+y,'actual cartridge half-speed Y step')
  end
  for _=31,60 do p:update()end
  T.eq(#p:oam(),1,'restarting object remains visible after 48 frames')
  for _=61,202 do p:update()end
  T.eq(p:isDone(),true,'full wait followed by return has no synthetic tail')
  T.eq(#p:oam(),0,'normal top-level return immediately clears OAM')
  local terminal=p.frames
  for _=1,20 do p:update()end
  T.eq(p.frames,terminal,'no clocks run after terminal return')
  p:release()
 end
end
Version.set(previous)
T.finish('native GSC actual object pixels, cartridge lifetime and terminal timing')
