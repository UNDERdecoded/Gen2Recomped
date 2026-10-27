-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Game=require('src.core.Game')
local Version=require('src.core.GameVersion')
local Screens=require('src.ui.Screens')
local World=require('src.world.OverworldController')
local Save=require('src.core.SaveData')
local oldVersion,oldPush,oldNew,oldGet=Version.get(),Screens.push,Save.newGame,Screens.get
Screens.get=function()return{new=function(_,callbacks)return callbacks end}end
local function newGame(g)return Game.makeTitleState(g).onNewGame()end
local function session(screen)
 local g={save={player={name='OLD'}},data={},draws=0}
 g.bootConfig=function()return {screens={newGame=screen}}end
 g.data.field={boot={screens={newGame=screen}}}
 g.adoptSave=function(self,s)T.eq(self.save,s,'save adopted before intro')end
 g.applyOptions=function()end
 g.stack={top=function()end,clearWorld=function()g.world=nil end,
  push=function(_,state,map,x,y,facing)
   T.eq(state,World,'native world owner created')
   g.draws=g.draws+1;g.world={map={id=map},x=x,y=y,facing=facing}
  end}
 return g
end
Save.newGame=function()return {player={map='HOME',x=3,y=3,facing='down',gender='boy'},options={}}end
local intro
Screens.push=function(g,id,done)intro={game=g,id=id,done=done};return intro end
for _,edition in ipairs({'gold','silver','crystal'})do
 Version.set(edition)
 local g=session('OakSpeech');newGame(g)
 T.eq(g.world,nil,edition..' has no map while clock/name screen owns input')
 T.eq(g.draws,0,edition..' destination preparation cannot see a premature world')
 T.eq(intro.id,'OakSpeech',edition..' keeps configured real introduction')
 -- Answers belong to the adopted save; world creation reads their final values.
 g.save.player.gender='girl';g.save.player.x=4
 intro.done();T.eq(g.draws,1,edition..' completion starts actual world once')
 T.eq(g.world.x,4,edition..' final introduction position reaches world')
 intro.done();T.eq(g.draws,1,edition..' duplicate completion is harmless')
 g=session('OakSpeech');newGame(g);local stale=intro.done
 newGame(g);stale();T.eq(g.world,nil,edition..' retired save cannot start a world')
 intro.done();T.eq(g.draws,1,edition..' replacement introduction owns destination')
 g=session(false);newGame(g)
 T.eq(g.draws,1,edition..' no-intro datasets retain immediate world creation')
end
Version.set('red');local g=session('OakSpeech');newGame(g)
T.eq(g.draws,1,'Gen1 retains world beneath its introduction')
intro.done();T.eq(g.draws,1,'Gen1 callback does not create another world')
Screens.push,Save.newGame,Screens.get=oldPush,oldNew,oldGet;Version.set(oldVersion)
T.finish('native Gen2 new-game lifecycle')
