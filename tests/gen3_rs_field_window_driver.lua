-- Native RS field layout/input fixture; no mod and no story-completion claim.
return function(game)
 io.stdout:setvbuf('no');local fs=love.filesystem
 assert(fs.getIdentity():match('^gen2recomp%-qa%-')or fs.getIdentity():match('^oasc%-gen2recomp%-qa%-full109%-'))
 local U=require('tests.drivers.util');local V=require('src.core.GameVersion');local edition=V.get()
 assert(edition=='ruby'or edition=='sapphire');assert(not require('src.core.SaveData').saveFileExists(edition),'Fresh QA unexpectedly loaded a save')
 local J=require('src.link.Json');local Font=require('src.render.Font');local Theme=require('src.ui.Theme')
 local TextBox=require('src.render.TextBox');local Choice=require('src.ui.ChoiceBox')
 local w=assert(game.data.constants.gen3FieldMessageWindow)
 assert(w.left==2 and w.top==15 and w.width==26 and w.height==4)
 assert(not game.data.constants.gen3MessageWindow,'RS field record became an Emerald battle-window anchor')
 assert(game.data.font and #game.data.font.pages.normal.widths==254,'RS font is not its own extracted 254-character face')
 local bw,bh=Theme.uiSize();assert(bw==240 and bh==160,'RS field dialogue still uses Game Boy dimensions')
 local t=Theme.textBox;assert(t.tx==1 and t.ty==14 and t.tw==28 and t.th==6 and t.maxCols==26)
 local Cache=require('src.import.CacheFs');local Importer=require('src.import.RomImporter')
 assert(Cache.rootReport().kind~='portable','QA must not purge a portable user cache')
 assert(Importer.readyReport(edition).ok,'Fresh RS cache is not ready')
 local raw=assert(fs.read(edition..'/rom-cache.complete'));assert(raw:find('rs%-item%-menu%-v4:'))
 local old,n=raw:gsub('rs%-item%-menu%-v4:','rs-field-window-v3:',1);assert(n==1)
 local read=Cache.read;Cache.read=function(path,...)if path=='rom-cache.complete'then return old end;return read(path,...)end
 local ok,report=pcall(Importer.readyReport,edition);Cache.read=read
 assert(ok and report.ok==false,'Old RS cache was accepted without current action metadata');assert(Importer.readyReport(edition).ok)
 U.teleport(game,'MAP_G00_N16',10,12,'up');local world=game.stack:top()
 local function press(key)game.input:overlayPressed(key);U.wait(1);game.input:overlayReleased(key);U.wait(1)end
 local function until_(fn,seconds,label)local endAt=love.timer.getTime()+seconds;repeat U.wait(1);assert(love.timer.getTime()<endAt,label)until fn()end
 -- Explicit width fixture, not a natural story quote: long native glyphs
 -- fit the real field printer but exceed the old 18-column default.
 local line='W';while Font.width(line..'W')<=208 do line=line..'W'end
 assert(Font.width(line)>144 and Font.width(line)<=208)
 local text=line..'\n'..line;local legacy=TextBox.paginate(text,18)
 assert(#legacy==1 and #legacy[1]>2,'Old narrow-wrap negative did not reproduce')
 local done=0;local box=TextBox.new(game,text,function()done=done+1 end);game.stack:push(box)
 assert(box.maxCols==26 and #box.pages==1 and #box.pages[1]==2 and box.pages[1][1]==line and box.pages[1][2]==line)
 until_(function()return box.done and #box.shown==2 end,10,'Native wide dialogue did not finish')
 local function shot(name,state)
  local g=love.graphics;local canvas=g.newCanvas(240,160,{dpiscale=1});local depth=g.getStackDepth()
  g.push('all');local ok,why=xpcall(function()g.setCanvas(canvas);g.origin();g.setShader();g.setScissor();g.clear(0,0,0,0);state:draw()end,debug.traceback)
  while g.getStackDepth()>depth do g.pop()end;assert(ok,why)
  local image=canvas:newImageData();assert(fs.write(name..'.png',image:encode('png')));image:release();canvas:release()
 end
 shot('rs-field-window-dialogue',box);press('a');assert(done==1 and game.stack:top()==world,'Native dialogue completion/input changed')
 local picked;local choice=Choice.new(game,function(yes)picked=yes end,{noSound=true});game.stack:push(choice)
 press('down');assert(choice.index==2);shot('rs-field-window-choice',choice);press('a')
 until_(function()return picked~=nil end,3,'Native choice callback did not return');assert(picked==false and game.stack:top()==world)
 assert(fs.write('edition-result.json',J.encode({status='pass',edition=edition,nativeNoMods=true,
  fieldWindow={width=bw,height=bh,tx=t.tx,ty=t.ty,tw=t.tw,th=t.th,maxCols=t.maxCols},
  nativeFontCharacters=254,explicitWidthFixturePixels=Font.width(line),oldNarrowFixtureLines=#legacy[1],newFixtureLines=2,
  actualDialogueInput=true,actualChoiceInput=true,oldCacheRevisionRejected=true,freshCacheReady=true,
  fieldMetadataSeparateFromBattle=true,originalRSDialogueFrameArtPorted=false,fullRSUI=false,fullStory=false,physicalIOSDeviceTested=false})))
 print('PASS_NATIVE_RS_FIELD_WINDOW '..edition);love.event.quit(0)
end
