-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Actual native HP queue and HUD tile rendering on each GPU backend.
-- The atlas below is generated test art, not cartridge or mod content.
local M={}
function M.run()
  local Version=require('src.core.GameVersion')
  local Data=require('src.core.Data')
  local Hud=require('src.render.HudTiles')
  local Palette=require('src.render.PaletteFX')
  local Hp=require('src.battle.Gen2HpPresentation')
  local Battle=require('src.battle.BattleState')
  local g=love.graphics
  local before={version=Version.get(),font=Data.font,mode=Palette.mode}
  local checks,frames=0,0
  local function check(ok,why)checks=checks+1;assert(ok,why)end
  local colors={GREENBAR={0,189,0},YELLOWBAR={239,181,0},REDBAR={223,37,19}}
  local data={palettes={palettes={}}}
  for name,color in pairs(colors)do
    data.palettes.palettes[name]={{255,255,255},{170,170,170},color,{0,0,0}}
  end
  local atlas=love.image.newImageData(32*8,8,'rgba8')
  for tile=0,31 do
    local code=0x62+tile
    for y=0,7 do for x=0,7 do
      local value=1
      if code>=0x63 and code<=0x6b then
        if y==1 or y==5 then value=0
        elseif y>=2 and y<=4 and x<code-0x63 then value=1/3 end
      end
      atlas:setPixel(tile*8+x,y,value,value,value,1)
    end end
  end
  local path='qa-native-hp-tiles.png';atlas:encode('png',path);atlas:release()
  local pages={}
  for _,id in ipairs({'font_battle_extra','battle_hud_1','battle_hud_2','battle_hud_3','exp_bar'})do
    pages[id]={image=path,base=0x62}
  end
  local canvas=g.newCanvas(80,8,{format='rgba8',dpiscale=1})
  local sheet=g.newCanvas(80,32,{format='rgba8',dpiscale=1});M.image=sheet
  g.push('all')
  local ok,why=xpcall(function()
    g.origin();g.setShader();g.setBlendMode('replace','premultiplied')
    g.setCanvas(sheet);g.clear(1,1,1,1);g.setCanvas()
    for _,edition in ipairs({'gold','silver','crystal'})do
      Version.set(edition);Palette.setMode('gbc');Data.font={pages=pages};Hud.invalidate()
      for _,gray in ipairs({false,true})do
        for _,case in ipairs({{19,16,19},{48,0,48},{0,48,48},{383,190,383}})do
          local enemy={mon={hp=case[2],stats={hp=case[3]}},shownHP=case[1],isPlayer=false}
          local screen=setmetatable({enemy=enemy,data=data,game={data=data},
            queue={{drain=true,battler=enemy}}},Battle)
          Hp.bind(screen);check(screen:updateQueue(),'native queue did not dispatch real HP row')
          local ticks=0;local busy
          repeat
            busy=screen:updateQueuePresentation();ticks=ticks+1;frames=frames+1
            check(ticks<300,'native HP queue did not finish')
            local pixels=screen:hudHpPixels(enemy.mon,'enemy')
            local name=Palette.barPalName(screen:hudHp(enemy.mon,'enemy'),case[3],pixels)
            local color=gray and {85,85,85}or colors[name]
            g.setCanvas(canvas);g.origin();g.setShader();g.clear(1,1,1,1);g.setColor(1,1,1,1)
            Hud.drawHPBar(data,0,0,{hp=screen:hudHp(enemy.mon,'enemy'),stats=enemy.mon.stats},nil,gray,nil,pixels)
            g.setCanvas()
            local image=g.readbackTexture(canvas)
            for x=0,47 do
              local got={image:getPixel(16+x,3)}
              for channel=1,3 do
                local wanted=x<pixels and color[channel]/255 or 1
                check(math.abs(got[channel]-wanted)<2/255,
                  edition..' native GPU HP pixel '..x..' frame '..ticks..' channel '..channel)
              end
              check(math.abs(got[4]-1)<2/255,'native HP output lost opaque alpha')
            end
            image:release()
            check(enemy.mon.hp==case[2],'GPU drawing changed resolved damage')
            if edition=='crystal' and not gray and ticks==1 then
              local row=case[1]==19 and 0 or case[1]==48 and 8 or case[1]==0 and 16 or 24
              g.setCanvas(sheet);g.origin();g.setColor(1,1,1,1);g.draw(canvas,0,row);g.setCanvas()
            end
          until not busy
          check(screen.hpAnim==nil and enemy.shownHP==case[2],'native HP owner did not retire at its target')
        end
      end
    end
  end,debug.traceback)
  g.setCanvas();g.pop()
  Data.font=before.font;Hud.invalidate();Version.set(before.version);Palette.setMode(before.mode)
  if not ok then error(why,0)end
  return {passed=true,checks=checks,frames=frames,
    scope='ROM-free real GPU readback of native HP queue, pixel-stepped HUD tiles and palette transitions; generated test atlas, color and grayscale, Gold/Silver/Crystal. Not whole-mod or OS-window acceptance.'},sheet
end
return M
