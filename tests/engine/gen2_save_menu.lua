-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local original=V.get()
require('src.core.ModCompat').install()
local UI=require('src.ui.Gen2SaveMenu');local Box=require('src.render.TextBox')
local Stack=require('src.core.StateStack');local Screens=require('src.ui.Screens')
local Save=require('src.core.SaveData')
local function game(version)
 local g={data=T.fixtures.fresh(),save={version=version,player={name='QA'},flags={},options={textSpeed='fast'},party={},pokedex={owned={}},inventory={}},input={queue={}}}
 g.input.wasPressed=function(self,k)return self.queue[k]==true end
 g.input.isDown=function(self,k)return self.queue[k]==true end
 g.data.font.charmap={}
 for code=32,126 do g.data.font.charmap[#g.data.font.charmap+1]={seq=string.char(code),code=0x80+(code-32)} end
 g.data.font.charmap[#g.data.font.charmap+1]={seq='…',code=0xf0}
 require('src.render.Font').load(g.data)
 g.stack=setmetatable({}, {__index=Stack});g.stack:init()
 g.writeSave=function(self)self.writes=(self.writes or 0)+1;return self.result~=false end
 return g
end
local function tick(g,key,n)
 for _=1,n or 1 do g.input.queue=key and {[key]=true}or{};g.stack:update(1/60) end
 g.input.queue={}
end
local function wait(g,pred,label)
 for _=1,3000 do if pred() then return end;tick(g) end
 error('save flow did not reach '..label)
end
local function ready(g,ui)
 for _=1,3000 do
  if ui:yesNoVisible() then return end
  tick(g,ui.message.waiting and 'a' or nil)
 end
 error('save prompt never offered choices')
end
T.eq(require('src.ui.gen2.SaveMenu'),UI,'legacy class spelling resolves native save owner')
local pages=UI.pagesOf('A\nB\vC\fD\nE\nF')
T.eq(#pages,4,'paragraphs and scrolling retain independent visible pages')
T.eq(pages[2][1],'B','scroll retains previous visible lower line')
T.eq(pages[2][2],'C','scroll introduces next line')
T.eq(pages[2].scrolled,true,'scroll provenance is explicit')
T.eq(UI.pagesOf('')[1][1],'','empty prompt retains one visible page')
for _,edition in ipairs({'gold','silver','crystal'})do
 V.set(edition)
 local g=game(edition);local parent={};g.stack:push(parent)
 local done,n=nil,0
 local ui=Screens.push(g,'Gen2SaveMenu',{existed=false,onDone=function(saved)done=saved;n=n+1;g.stack:pop()end})
 T.eq(getmetatable(ui),UI,edition..' native screen registry fallback')
 T.eq(getmetatable(ui.message),Box,'actual native text printer retained')
 T.eq(g.stack:top(),ui,'embedded prompt cannot replace native menu')
 ui:accept();T.eq(ui.phase,'confirm','cannot accept before prompt finishes')
 ready(g,ui);tick(g,'b');T.eq(done,false,'B declines without writing')
 T.eq(g.writes,nil,'cancel cannot reach save writer');T.eq(g.stack:top(),parent,'exact parent restored')
 ui:finish(true);T.eq(n,1,'completion callback runs once')
 -- Existing file: two separate confirmations and original text scrolling.
 g=game(edition);n=0
 ui=Screens.push(g,'Gen2SaveMenu',{existed=true,onDone=function(saved)done=saved;n=n+1;g.stack:pop()end})
 ready(g,ui);tick(g,'a');T.eq(ui.phase,'overwrite','existing file requires independent overwrite answer')
 T.eq(g.writes,nil,'first YES does not write existing slot')
 ready(g,ui);T.eq(ui.message.lineIndex>=3,true,'overwrite scrolling finishes before YES/NO becomes active')
 T.eq(ui.page,2,'native text progress reaches public scrolled page')
 tick(g,'down');T.eq(ui.choice,2,'real menu input selects NO')
 tick(g,'a');T.eq(done,false,'overwrite NO returns cancellation');T.eq(g.writes,nil,'overwrite refusal preserves slot')
 -- No existing slot: fixed save delay and one authoritative write.
 g=game(edition);ui=Screens.push(g,'Gen2SaveMenu',{existed=false,onDone=function(saved)done=saved;g.stack:pop()end})
 ready(g,ui);tick(g,'a');T.eq(ui.phase,'saving','YES enters timed native save phase')
 T.eq(ui.message.textSpeed,3,'timed save message pins MID cadence')
 tick(g,'b',2);T.eq(ui.message.charIndex,0,'held B cannot accelerate timed save text')
 wait(g,function()return ui.message.done end,'saving text completion')
 tick(g,'b',UI.SAVING_FRAMES-1);T.eq(g.writes,nil,'B cannot skip pre-write delay')
 tick(g,'a');T.eq(g.writes,1,'sixteenth post-text frame writes exactly once')
 ui:writeNow();T.eq(g.writes,1,'duplicate direct write does not rewrite save')
 wait(g,function()return ui.finished end,'saved completion')
 T.eq(done,true,'actual successful writer reported');T.eq(g.writes,1,'all later timed frames keep one write')
 -- Failed and throwing writers cannot display a successful completion.
 for _,writer in ipairs({function()return false end,function()error('QA rejected write')end})do
  g=game(edition);ui=Screens.push(g,'Gen2SaveMenu',{existed=false,writer=writer,onDone=function(saved)done=saved;g.stack:pop()end})
  ready(g,ui);tick(g,'a');wait(g,function()return ui.finished end,'failed save completion')
  T.eq(done,false,'write failure reaches caller as false')
  T.eq(ui:promptText(),'Could not save.','failed writer never prints saved message')
 end
 -- START's ordinary native route uses this owner, rather than a substitute
 -- class offered only to optional consumers.
 g=game(edition);local start=Screens.push(g,'StartMenu');local row
 for i,item in ipairs(start.items)do if item.label=='SAVE' then row=i end end
 T.eq(type(row),'number','native START exposes SAVE')
 if start.list then start.list.index=row else start.index=row end;tick(g,'a')
 T.eq(getmetatable(g.stack:top()),UI,'actual START input enters native save screen')
end
V.set('red');local g=game('red');local start=Screens.push(g,'StartMenu');local row
for i,item in ipairs(start.items)do if item.label=='SAVE' then row=i end end
if start.list then start.list.index=row else start.index=row end;tick(g,'a');T.eq(getmetatable(g.stack:top()),Box,'Gen1 retains original save dialogue')
V.set(original)
-- This state must enter the real Game writer, retaining its capture and
-- metadata/resume work rather than calling a bare serializer in production.
V.set('crystal');g=game('crystal');g.writeSave=require('src.core.Game').writeSave
local captures,writes=0,0
g.overworld={captureSave=function(_,save)captures=captures+1;save.qaCaptured=true end}
local originalSave=Save.save
Save.save=function(save)writes=writes+1;T.eq(save.qaCaptured,true,'native overworld captured before write');T.eq(type(save.meta),'table','native writer stamps metadata');return true end
local ui=Screens.push(g,'Gen2SaveMenu',{existed=false})
ready(g,ui);tick(g,'a');wait(g,function()return ui.finished end,'native Game writer completion')
T.eq(captures,1,'actual native writer captures live state once');T.eq(writes,1,'actual native writer saves once')
local Runtime=require('src.mods.Runtime');local previousHooks=Runtime.hooks
local hooks=require('src.mods.Hooks').new();Runtime.hooks=hooks
hooks:wrap('save.write',function()return false end,0,'qa-save-veto')
ui=Screens.push(g,'Gen2SaveMenu',{existed=false})
ready(g,ui);tick(g,'a');wait(g,function()return ui.finished end,'native save hook veto')
T.eq(ui.saved,false,'native save veto cannot report success')
T.eq(captures,1,'veto runs before overworld mutation');T.eq(writes,1,'veto never reaches serializer')
Runtime.hooks=previousHooks
Save.save=originalSave;V.set(original)
T.finish('native Gen2 save menu')
