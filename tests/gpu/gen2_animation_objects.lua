-- Native Gen2 OAM/view pixels. All texture bytes below are generated test art.
local M={}
function M.run()
  local Version=require('src.core.GameVersion')
  local Palette=require('src.render.PaletteFX')
  local Player=require('src.battle.Gen2AnimPlayer')
  local g=love.graphics
  local before={version=Version.get(),mode=Palette.mode,ramp=Palette.customRamp()}
  local checks,frames=0,0
  local function check(ok,why)checks=checks+1;assert(ok,why)end
  local colors={{255,255,255},{220,40,80},{70,160,30},{0,0,0}}
  local custom={{240,230,220},{180,150,120},{100,70,40},{20,10,5}}
  local atlas=love.image.newImageData(16,8,'rgba8')
  for y=0,7 do for x=0,15 do
    local shade=(x+2*y)%4
    local gray=(3-shade)/3
    atlas:setPixel(x,y,gray,gray,gray,shade==0 and 0 or 1)
  end end
  local path='qa-native-oam.png';atlas:encode('png',path);atlas:release()
  local canvas=g.newCanvas(160,144,{format='rgba8',dpiscale=1});M.image=canvas
  local sentinel=g.newShader([[vec4 effect(vec4 tint,Image image,vec2 uv,vec2 screen){return Texel(image,uv)*tint;}]])
  g.push('all')
  local ok,why=xpcall(function()
    for _,edition in ipairs({'gold','silver','crystal'})do
      Version.set(edition)
      for _,mode in ipairs({'gbc','dmg','custom'})do
        -- Each case owns both settings: setMode intentionally retains a saved
        -- custom ramp, which would leak the previous edition's custom case.
        Palette.setDisplay(mode,mode=='custom'and custom or nil)
        local expected=mode=='gbc'and colors or mode=='custom'and custom or Palette.GRAYS
        for _,enemy in ipairs({false,true})do for _,flip in ipairs({0,32,64,96})do
          local xf,yf=flip%64>=32,flip>=64
          local data={battle_anims={gen2=true,moveAnims={FIX_MOVE=1},
            scripts={[1]={entry=1,code={{op='obj',args={0,40,40,0}},{op='delay',frames=5},{op='ret'}}}},
            objects={[0]={oamFlags=1,fixY=255,frameset=0,fn=0,palette=4,gfx=2}},functions={[0]='Null'},
            framesets={[0]={frames={{oam=0,duration=20,xflip=xf,yflip=yf}},loop='hold'}},
            oam={[0]={tile=0,sprites={{x=0,y=0,tile=0,attr=0},{x=8,y=0,tile=1,attr=32}}}},
            gfx={[2]={tiles=2,cols=2,image=path}},palettes={[2]=colors}}}
          local player=Player.new(data);check(player:start('FIX_MOVE',not enemy),'native VM start failed')
          player:update();frames=frames+1
          g.setCanvas(canvas);g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
          g.clear(.125,.25,.5,1);g.setColor(.1,.2,.3,.4);g.setShader(sentinel)
          local clock,age=player.frames,player.objects[1].age
          player:draw()
          check(g.getShader()==sentinel,'native object pass lost caller shader')
          local tint={g.getColor()};check(math.abs(tint[1]-.1)<.001 and math.abs(tint[4]-.4)<.001,'object pass lost caller tint')
          check(player.frames==clock and player.objects[1].age==age,'object drawing advanced the native animation')
          g.setCanvas();g.setShader()
          local image=g.readbackTexture(canvas)
          local ax,ay=enemy and 140 or 40,enemy and 80 or 40
          for tile=0,1 do
            local left=ax+(xf and -tile*8-8 or tile*8)-8
            local top=ay+(yf and -8 or 0)-16
            local spriteXFlip=xf~=(tile==1)
            for y=0,7 do for x=0,7 do
              local sourceX=tile*8+(spriteXFlip and 7-x or x)
              local sourceY=yf and 7-y or y
              local shade=(sourceX+2*sourceY)%4
              local got={image:getPixel(left+x,top+y)}
              local wanted=shade==0 and {.125,.25,.5}or expected[shade+1]
              for channel=1,3 do
                local value=shade==0 and wanted[channel]or wanted[channel]/255
                check(math.abs(got[channel]-value)<2/255,
                  edition..' '..mode..' native OAM flip/position/palette mismatch')
              end
              check(math.abs(got[4]-1)<2/255,'native OAM lost destination alpha')
            end end
          end
          image:release();player:release()
        end end
      end
    end
  end,debug.traceback)
  g.setCanvas();g.pop();sentinel:release()
  Version.set(before.version);Palette.setDisplay(before.mode,before.ramp)
  if not ok then error(why,0)end
  return {passed=true,checks=checks,frames=frames,
    scope='Generated ROM-free native VM/OAM/object renderer pixels: Gold/Silver/Crystal, both sides, all object flip combinations, per-sprite XOR, GBC/DMG/custom palettes, alpha and caller graphics state. Not whole-mod or OS-window acceptance.'},canvas
end
return M
