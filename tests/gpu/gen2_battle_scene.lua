-- Generated art, actual native BG/OAM scene composition and GPU readbacks.
local M={}
function M.run()
 local Version=require('src.core.GameVersion')
 local Palette=require('src.render.PaletteFX')
 local Player=require('src.battle.Gen2AnimPlayer')
 local Battle=require('src.battle.BattleState')
 local g=love.graphics
 local previous={version=Version.get(),mode=Palette.mode,ramp=Palette.customRamp()}
 local checks,frames=0,0
 local function check(ok,why)checks=checks+1;assert(ok,why)end
 local function pixel(image,x,y,wanted,label)
  local got={image:getPixel(x,y)}
  for n=1,4 do check(math.abs(got[n]-wanted[n])<2/255,label..' channel '..n)end
 end
 local art=love.image.newImageData(8,8,'rgba8')
 for y=0,7 do for x=0,7 do art:setPixel(x,y,2/3,2/3,2/3,1)end end
 local path='qa-native-scene-obj.png';art:encode('png',path);art:release()
 local canvas=g.newCanvas(304,144,{format='rgba8',dpiscale=1});M.image=canvas
 local sentinel=g.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){return Texel(t,uv)*c;}]])
 g.push('all')
 local ok,why=xpcall(function()
  for _,edition in ipairs({'gold','silver','crystal'})do
   Version.set(edition);Palette.setDisplay('gbc',nil)
   local player=Player.new({battle_anims={gen2=true,moveAnims={FIX_MOVE=1},
    scripts={[1]={entry=1,code={{op='obj',args={0,40,40,0}},{op='delay',frames=5},{op='ret'}}}},
    objects={[0]={oamFlags=0,fixY=255,frameset=0,fn=0,palette=4,gfx=0}},functions={[0]='Null'},
    framesets={[0]={frames={{oam=0,duration=20}},loop='hold'}},
    oam={[0]={tile=0,sprites={{x=0,y=0,tile=0,attr=0}}}},
    gfx={[0]={tiles=1,cols=1,image=path}},palettes={[2]={{255,255,255},{220,40,80},{70,160,30},{0,0,0}}}}})
   check(player:start('FIX_MOVE',true),'native scene animation did not start');player:update()
   local screen=setmetatable({frame=0,introSlide=0,fx={shakeX=3,shakeY=2},animPlayer=player,animPlaying=true,
    colorMode=function()return false end,worldBackdrop=function()return false end,
    drawPicsLayer=function()g.setColor(0,0,1,1);g.rectangle('fill',8,16,8,8)end,
    drawHUDs=function()g.setColor(1,0,0,1);g.rectangle('fill',0,0,8,8)end,
    drawTextArea=function()g.setColor(0,0,0,1);g.rectangle('fill',0,96,160,48)end},Battle)
   for _,case in ipairs({'native','replacement','wide','flash'})do
    g.setCanvas(canvas);g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha');g.clear(0,0,0,1)
    g.setShader(sentinel);g.setColor(.2,.3,.4,.5)
    local ticks,age=player.frames,player.objects[1].age
    local function panel()g.setShader();g.setColor(0,0,0,1);g.rectangle('fill',0,0,304,144)end
    if case=='native'then screen:drawSceneBody()
    elseif case=='replacement'then screen:drawSceneBody(panel)
    else
     screen.fx.flash=case=='flash'and 2 or nil
     screen:drawSceneBody(panel,function()g.push();g.translate(136,0);screen:drawAnimLayer(false);g.pop()end,304,144)
    end
    frames=frames+1
    check(g.getShader()==sentinel,'native scene lost caller shader')
    check(math.abs(select(4,g.getColor())-.5)<.001,'native scene lost caller tint')
    check(player.frames==ticks and player.objects[1].age==age,'scene rendering advanced native battle time')
    g.setCanvas();g.setShader();local image=g.readbackTexture(canvas)
    if case=='native'then pixel(image,12,19,{0,0,1,1},'native BG shake')end
    if case~='flash'then
     pixel(image,(case=='wide'and 168 or 32)+2,26,{220/255,40/255,80/255,1},'native OAM independent of BG shake')
    else pixel(image,300,100,{.85,.85,.85,1},'wide flash covers actual native surface')end
    image:release()
   end
   player:release()
  end
 end,debug.traceback)
 g.setCanvas();g.pop();sentinel:release()
 Version.set(previous.version);Palette.setDisplay(previous.mode,previous.ramp)
 if not ok then error(why,0)end
 return {passed=true,checks=checks,frames=frames,
  scope='Generated ROM-free Gold/Silver/Crystal native classic panel and real VM/OAM composition, replacement panel, translated wide OAM, full-width flash, state restoration and draw clock stability. Not full UI/art, scanline-effects, whole-mod or OS-window acceptance.'},canvas
end
return M
