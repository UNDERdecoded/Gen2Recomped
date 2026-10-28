-- Generated ROM-free art, real native BattleState -> VM -> OBJ GPU pixels.
local M={}
function M.run()
  local Version=require('src.core.GameVersion')
  local Palette=require('src.render.PaletteFX')
  local Registers=require('src.render.Gen2PaletteDraw')
  local Battle=require('src.battle.BattleState')
  local Assets=require('src.render.Assets')
  local Data=require('src.core.Data')
  local g=love.graphics
  local previous={version=Version.get(),mode=Palette.mode,ramp=Palette.customRamp()}
  local checks,cases=0,0
  local function check(ok,why)checks=checks+1;assert(ok,why)end
  local bg={32/255,64/255,128/255,1}
  local A={{255,255,255},{211,41,67},{29,173,101},{3,7,13}}
  local B={{255,255,255},{47,91,223},{193,131,53},{11,17,31}}
  local outer={{249,237,225},{191,149,107},{81,59,43},{19,13,7}}
  local custom={{247,233,219},{181,151,121},{103,73,43},{23,13,7}}
  local canvas=g.newCanvas(160,144,{format='rgba8',dpiscale=1});M.image=canvas
  local paths={}
  local function sample(kind,back,n,x,y)
    if kind=='rgb'then return {x%2==0 and 1 or .2,.4,y%2==0 and .7 or .1,.75}end
    if kind=='substitute'then
      local top=back and 32 or 40
      if x<16 or x>=32 or y<top or y>=top+16 then return {1,1,1,1}end
    elseif kind=='minimize'then
      local left,top=back and 24 or 24,back and 32 or 40
      if x<left or x>=left+8 or y<top or y>=top+8 then return {1,1,1,1}end
    end
    local shade=(math.floor(x/8)*3+math.floor(y/8)*2+x+2*y+(back and 1 or 0))%4
    local value=(3-shade)/3
    return {value,value,value,1},shade
  end
  for _,kind in ipairs{'normal','rgb','substitute','minimize'}do
    paths[kind]={}
    for _,back in ipairs{false,true}do
      for _,frontSize in ipairs{40,48,56}do
        local n=back and 48 or kind=='normal'and frontSize or 56
        local path='qa-row-'..kind..'-'..(back and 'back'or tostring(frontSize))..'.png'
        local pixels=love.image.newImageData(n,n,'rgba8')
        for y=0,n-1 do for x=0,n-1 do
          local rgba=sample(kind,back,n,x,y)
          pixels:setPixel(x,y,unpack(rgba))
        end end
        pixels:encode('png',path);pixels:release()
        paths[kind][back and 'back'or frontSize]=path
      end
    end
  end
  local function make(edition,rows,attacker,kind,frontSize)
    Version.set(edition);Assets.invalidate();Battle.invalidate()
    local data=require('tests.modkit.fixtures').fresh();data.constants.gen=2
    for name,def in pairs(data.pokemon)do
      def.palette=name=='FIXMON_A'and 'ROW_BACK'or 'ROW_FRONT'
      def.spriteFront=paths[kind][frontSize];def.spriteBack=paths[kind].back
      def.trueColor=kind=='rgb'or nil
    end
    data.palettes={palettes={ROW_BACK=B,ROW_FRONT=A,GRAYMON=A,MEWMON=A},
      pokemon={FIXMON_A='ROW_BACK',FIXMON_B='ROW_FRONT',FIXMON_C='ROW_FRONT'}}
    Data.publishGen2Palettes(data)
    data.constants.battleAnimGfxOrder={'BATTLE_ANIM_GFX_PLAYERHEAD','BATTLE_ANIM_GFX_ENEMYFEET'}
    local code={}
    if kind=='substitute'or kind=='minimize'then
      code[#code+1]={op=kind=='substitute'and 'raisesub'or 'minimizeopp'}
    end
    code[#code+1]={op=rows==2 and 'battlergfx_1row'or 'battlergfx_2row'}
    code[#code+1]={op='obj',args={0,76,40,0}}
    code[#code+1]={op='obj',args={1,40,100,0}}
    code[#code+1]={op='delay',frames=100};code[#code+1]={op='ret'}
    data.battle_anims={gen2=true,moveAnims={PROBE=1},scripts={[1]={entry=1,code=code}},
      functions={[0]='MoveFromUserToTarget'},objects={},framesets={},oam={}}
    if kind=='substitute'or kind=='minimize'then
      data.battle_anims.pictureArt={version=1,[kind]={
        enemy=paths[kind][frontSize],player=paths[kind].back}}
      -- The opposite battler remains a regular Pokemon. Give it generated
      -- native art too; the real command decides which picture is replaced.
      for _,def in pairs(data.pokemon)do
        def.spriteFront=paths.normal[frontSize];def.spriteBack=paths.normal.back
      end
    end
    for id=0,1 do
      data.battle_anims.objects[id]={oamFlags=1,fixY=255,fn=0,frameset=id,palette=id,gfx=id}
      data.battle_anims.framesets[id]={frames={{oam=id,duration=1}},loop='restart'}
      local sprites={}
      for tile=0,(id==0 and 7 or 6)*rows-1 do
        sprites[#sprites+1]={x=math.floor(tile/rows)*8,y=(tile%rows)*8,
          tile=tile,attr=(tile%4)*32}
      end
      data.battle_anims.oam[id]={tile=0,sprites=sprites}
    end
    local catalog=require('src.battle.Gen2AnimCatalog').compile(data.battle_anims,data.constants,edition)
    catalog.gen2,catalog.format,catalog.moveAnims,catalog.indices,catalog.misc=nil,nil,nil,nil,nil
    data.battle_anims=assert(loadstring(require('src.import.LuaWriter').encodeSplit(catalog)))()
    require('src.render.Font').load(data)
    local save=require('src.core.SaveData').newGame()
    save.party={require('src.pokemon.Pokemon').new(data,'FIXMON_A',30)}
    local screen=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
    screen.queue,screen.current,screen.waitFrames={},nil,nil
    check(screen:animForMove('PROBE',attacker),'native screen did not admit row animation')
    screen.animPlayer:update()
    return screen
  end
  g.push('all')
  local ok,why=xpcall(function()
    for ei,edition in ipairs{'gold','silver','crystal'}do
      local frontSize=32+ei*8
      for _,kind in ipairs{'normal','rgb','substitute','minimize'}do
        if kind=='normal'or kind=='rgb'or edition=='crystal'then
          for _,mode in ipairs(kind=='rgb'and {'gbc'}or {'gbc','dmg','custom'})do
            Palette.setDisplay(mode,mode=='custom'and custom or nil)
            for _,rows in ipairs{1,2}do for _,attacker in ipairs{'player','enemy'}do
              local screen=make(edition,rows,attacker,kind,frontSize)
              local player=screen.animPlayer;local runner=player.runtime
              local expected={}
              for _,obj in ipairs(runner:oam())do
                local entry
                for i=#runner.loaded,1,-1 do
                  local item=runner.loaded[i]
                  if obj.tile>=item.tile and obj.tile<item.tile+item.tiles then entry=item;break end
                end
                check(entry~=nil,'native OAM has no copied picture owner')
                local back=entry.battler=='player'
                local currentKind=kind
                if kind=='substitute'or kind=='minimize'then
                  local replaced=runner.picOverride[entry.battler]==kind
                  currentKind=replaced and kind or 'normal'
                end
                local n=back and 48 or currentKind=='normal'and frontSize or 56
                local col=math.floor((obj.tile-entry.tile)/rows)
                local row=(obj.tile-entry.tile)%rows
                local palette=Registers.resolve(back and B or A)
                for y=0,7 do for x=0,7 do
                  local xx=col*8+(math.floor(obj.attr/32)%2==1 and 7-x or x)
                  local yy=(back and 0 or 56-rows*8)+row*8+(math.floor(obj.attr/64)%2==1 and 7-y or y)
                  if not back and n<56 then xx=xx-8;yy=yy-(56-n)end
                  local raw,shade
                  if xx>=0 and yy>=0 and xx<n and yy<n then raw,shade=sample(currentKind,back,n,xx,yy)end
                  local dx,dy=obj.x-8+x,obj.y-16+y
                  if dx>=0 and dx<160 and dy>=0 and dy<144 and raw then
                    local alpha=currentKind=='rgb'and raw[4]or (shade and shade>0 and 1 or 0)
                    if alpha>0 then
                      local rgb=currentKind=='rgb'and raw or palette[shade+1]
                      local value={}
                      for channel=1,3 do
                        local component=currentKind=='rgb'and rgb[channel]or rgb[channel]/255
                        value[channel]=component*alpha+bg[channel]*(1-alpha)
                      end
                      value[4]=1;expected[dy*160+dx]=value
                    end
                  end
                end end
              end
              g.setCanvas(canvas);g.origin();g.setScissor();g.setBlendMode('alpha','alphamultiply')
              g.setShader();g.clear(unpack(bg));g.setColor(.2,.3,.4,.5)
              Registers.useRaw(outer);local external=g.getShader()
              Registers.setBgp(0) -- a BG fade cannot fade copied OBJ pixels
              local clock=player.frames
              player:draw()
              check(player.frames==clock,'GPU drawing advanced the VM')
              check(g.getShader()==external,'GPU OAM pass lost outer shader identity')
              check(math.abs(select(4,g.getColor())-.5)<1/255,'GPU OAM pass lost caller tint')
              -- Draw a four-pixel outer-palette probe after the actual OAM
              -- pass. This proves uniforms, not merely shader identity.
              local probe=love.image.newImageData(4,1,'rgba8')
              for x=0,3 do local gray=1-x/3;probe:setPixel(x,0,gray,gray,gray,1)end
              local image=g.newImage(probe);image:setFilter('nearest','nearest');probe:release()
              g.setColor(1,1,1,1);g.draw(image,0,140);image:release()
              for x=0,3 do expected[140*160+x]={outer[x+1][1]/255,outer[x+1][2]/255,outer[x+1][3]/255,1}end
              g.setCanvas();g.setShader();Registers.setBgp(nil)
              local pixels=g.readbackTexture(canvas)
              for y=0,143 do for x=0,159 do
                local got={pixels:getPixel(x,y)};local wanted=expected[y*160+x]or bg
                for channel=1,4 do check(math.abs(got[channel]-wanted[channel])<2/255,
                  edition..' '..kind..' '..mode..' rows'..rows..' '..attacker..' pixel '..x..','..y..' channel'..channel)end
              end end
              pixels:release();player:release();cases=cases+1
            end end
          end
        end
      end
    end
  end,debug.traceback)
  g.setCanvas();g.pop();Registers.setBgp(nil)
  Version.set(previous.version);Palette.setDisplay(previous.mode,previous.ramp)
  if not ok then error(why,0)end
  return {passed=true,checks=checks,cases=cases,
    scope='ROM-free real native BattleState/VM/OBJ GPU pixel equality: GSC, native 5/6/7-tile fronts, both attackers, one/two copied rows, flips, GBC/DMG/custom, RGB alpha, substitute/minimize, outer palette probe and stable draw clock. Generated test art; not unchanged-mod, OS-window, performance or release acceptance.'},canvas
end
return M
