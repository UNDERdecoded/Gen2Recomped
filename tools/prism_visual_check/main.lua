-- Run from the repository root: lovec.exe tools/prism_visual_check
local root=love.filesystem.getWorkingDirectory():gsub('\\','/')..'/'
local cache=(os.getenv('PRISM_CACHE') or 'G:/Gen2Recomped/prism/data/generated'):gsub('\\','/'):gsub('/+$','')
local gameRoot=cache:gsub('/data/generated$','')
local preview=root..'tmp/prism-visual-preview'
function love.load()
 local ok,why=xpcall(function()
  local f=assert(io.open(root..'pokeprism.gbc','rb'));local raw=f:read('*a');f:close()
  f=assert(io.open(root..'tools/rom_manifest_prism.json','rb'));local manifest=require('src.link.Json').decode(f:read('*a'));f:close()
  local C=require('src.import.CacheFs');local out=preview..'/output';C.root=function()return out end
  C.mkdirReal(root..'tmp');C.mkdirReal(preview)
  local E=require('src.import.RomExtractorGen2');local e=E.new(raw,'prism',manifest)
  e.readSourceTable=function(self,name)return assert(loadfile(root..self.sourceDir..'/'..name..'.lua'))()end
  local forms=assert(e:extractPrismPlayerForms());local cust=assert(e:gen2PlayerCustomization());local memory=assert(e:gen2MemoryGame())
  local cards=assert(e:gen2CardFlip())
  for _,id in ipairs({'p12','p13'})do
   local path=out..'/'..forms[id].back
   local f=assert(io.open(path,'rb'));local pixels=love.image.newImageData(love.filesystem.newFileData(f:read('*a'),path));f:close()
   assert(pixels:getWidth()==48 and pixels:getHeight()==48,'Patroller back sprite display is 6x6 tiles')
  end
  local D=require('src.core.Data')
  for _,key in ipairs({'font','charmap','sprites','text','palettes','pokemon','moves','type_chart','items','constants','maps','tilesets','audio'})do D[key]=assert(loadfile(cache..'/'..key..'.lua'))()end
  D.field={playerForms=forms,playerCustomization=cust,gen2MemoryGame=memory,gen2CardFlip=cards}
  require('src.core.GameVersion').set('prism')
  local Assets=require('src.render.Assets')
  local function pixels(path)
   local f=io.open(out..'/'..path,'rb') or assert(io.open(gameRoot..'/'..path,'rb'))
   local bytes=f:read('*a');f:close();return love.image.newImageData(love.filesystem.newFileData(bytes,path))
  end
  Assets.imageData=pixels;Assets.image=function(path)return love.graphics.newImage(pixels(path))end
  Assets.resolve=function(path)
   local file=io.open(out..'/'..path,'rb');if file then file:close();return out..'/'..path end
   return gameRoot..'/'..path
  end
  require('src.render.Font').load(D)
  local save={player={gender='p12',skinTone=3,clothes={r=31,g=0,b=0}},coins=100}
  local Palette=require('src.render.PlayerPalette')
  local front=assert(Palette.picture(forms.p12.intro,D,save));local back=assert(Palette.picture(forms.p12.back,D,save))
  local game={data=D,save=save,input={wasPressed=function()return false end},stack={pop=function()end}}
  local screen=require('src.ui.PrismMemoryGame').new(game);screen.stage='play';screen.shown[1]=true;screen.shown[2]=true
  local canvas=love.graphics.newCanvas(360,160,{dpiscale=1});love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(1,1,1,1)
  screen:draw();love.graphics.draw(front,190,12);love.graphics.draw(back,270,12)
  save.player.clothes={r=0,g=0,b=31}
  love.graphics.draw(assert(Palette.picture(forms.p12.intro,D,save)),190,90)
  love.graphics.draw(assert(Palette.picture(forms.p12.back,D,save)),270,90)
  local fullSave=require('src.core.SaveData').newGame();fullSave.player=save.player
  fullSave.party={require('src.pokemon.Pokemon').new(D,'SPECIES_152',10)};game.save=fullSave
  require('src.core.Game').save=fullSave
  local battle=require('src.battle.BattleState').newWild(game,'SPECIES_152',5)
  battle:enter()
  local colors=battle:sgbBattlePals()
  assert(colors and colors[2][3][3]==255,'actual battle palette reads saved blue outfit')
  assert(battle.playerBackPic:getWidth()==48,'actual battle loads the corrected patroller back')
  love.graphics.setCanvas();canvas:newImageData():encode('png'):getString()
  local f=assert(io.open(preview..'/preview.png','wb'));f:write(canvas:newImageData():encode('png'):getString());f:close()
  local cf=require('src.ui.Gen2CardFlip').new(game)
  cf.bgImg=Assets.image(cards.bg);cf.artLoaded=true;cf.quads={}
  local cardCanvas=love.graphics.newCanvas(160,144,{dpiscale=1})
  love.graphics.setCanvas({cardCanvas,stencil=true});cf:draw();love.graphics.setCanvas()
  f=assert(io.open(preview..'/cardflip.png','wb'));f:write(cardCanvas:newImageData():encode('png'):getString());f:close()
  print('PASS: p12/p13 native ROM pictures, memory/card-flip extraction and recolor preview')
 end,debug.traceback)
 if not ok then love.graphics.setCanvas();print(why)end;love.event.quit(ok and 0 or 1)
end
function love.errorhandler(m)print(debug.traceback(tostring(m)));return function()return 1 end end
