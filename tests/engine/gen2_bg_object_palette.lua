-- Real native OBP command -> OAM -> indexed shader uniforms. Device records
-- observe the native draw without replacing animation or palette owners.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Player=require('src.battle.Gen2AnimPlayer')
local Palette=require('src.render.Gen2PaletteDraw')
local Version=require('src.core.GameVersion')
local g=love.graphics
local shader,draw=g.newShader,g.draw
local previous=Version.get()
g.newShader=function()
  return {values={},send=function(self,name,value)self.values[name]=value end}
end
for _,edition in ipairs({'gold','silver','crystal'})do
  Version.set(edition)
  local A={{255,255,255},{201,53,71},{43,157,89},{0,0,0}}
  local B={{245,239,227},{31,97,193},{167,59,131},{7,13,19}}
  local C={{221,231,241},{71,81,91},{101,111,121},{11,21,31}}
  local data={battle_anims={gen2=true,moveAnims={PROBE=1},
    scripts={[1]={entry=1,code={{op='gfx',ids={1}},{op='obp0',args={0x1b}},
      {op='obj',args={0,64,48,0}},{op='obj',args={1,72,48,0}},
      {op='obj',args={2,80,48,0}},{op='delay',frames=2},{op='ret'}}}},
    objects={},functions={[0]='Null'},framesets={[0]={frames={{oam=0,duration=8}},loop='hold'}},
    oam={[0]={tile=0,sprites={{x=0,y=0,tile=0,attr=0}}}},
    gfx={[1]={tiles=1,cols=1,image='native-obj'}},palettes={[0]=A,[1]=B,[2]=C}}}
  for id=0,2 do data.battle_anims.objects[id]={fn=0,frameset=0,palette=id+2,gfx=1}end
  local p=Player.new(data);T.check(p:start('PROBE',true),'native object-palette program starts')
  p:update();T.eq(p.bg.obp0,0x1b,'native command owns the actual OBP0 register')
  local records={}
  g.draw=function()
    local active=g.getShader();local row={}
    for i=0,3 do row[i+1]={unpack(active.values['pal'..i])}end
    records[#records+1]=row
  end
  local external={};g.setShader(external)
  Palette.setBgp(0x00) -- the already-coloured BG register must not fade OBJs
  local frame=p.frames;p:draw()
  T.eq(#records,3,'all three actual native OAM objects are drawn')
  for index,colors in ipairs({A,B,C})do
    local expected=Palette.remap(Palette.resolve(colors),index<=2 and 0x1b or nil)
    for i=1,4 do
      T.same(records[index][i],{expected[i][1]/255,expected[i][2]/255,expected[i][3]/255},
        'only native gray/yellow OBJ slots consume OBP0, with exact RGB uniforms')
    end
  end
  T.eq(p.frames,frame,'OBJ palette drawing never advances the VM')
  T.eq(g.getShader(),external,'OBJ pass restores caller shader')
  Palette.setBgp(nil);g.setShader();p:release()
end
g.newShader,g.draw=shader,draw;Version.set(previous)
T.finish('native GSC OBP command, OAM palette selection and exact shader uniforms')
