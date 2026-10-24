package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Game=require('src.core.Game')
local Screens=require('src.ui.Screens')
local Save=require('src.core.SaveData')
local originalGet,originalLoad=Screens.get,Save.load
local calls={new=0,continued=0,restore=0};local slot,backup={},'backup-slot'
Screens.get=function()return{new=function(game,callbacks)return callbacks end}end
Save.load=function()return slot,backup end
local game={data={},newGame=function()calls.new=calls.new+1;return 'new' end,
 continueGame=function(_,loaded,recovered)calls.continued=calls.continued+1;T.eq(loaded,slot,'title forwards loaded save');T.eq(recovered,backup,'title retains recovery marker')end,
 restoreSave=function(_,loaded,recovered)calls.restore=calls.restore+1;T.eq(loaded,slot,'native continue delegates actual slot');T.eq(recovered,backup,'native continue retains recovery marker');return 'restored' end}
local title=Game.makeTitleState(game)
title.onNewGame();T.eq(calls.new,1,'title uses observable native newGame')
title.onContinue();T.eq(calls.continued,1,'title uses observable native continueGame')
T.eq(Game.continueGame(game,slot,backup),'restored','native migration path result retained')
T.eq(calls.restore,1,'actual restore called once')
T.eq(Game.continueGame(game,nil),'new','missing slot starts a new game')
T.eq(calls.new,2,'missing slot newGame called once')
Save.load=function()return nil end;title.onContinue();T.eq(calls.continued,1,'unreadable slot does not start continue')
Screens.get,Save.load=originalGet,originalLoad
T.finish('native game lifecycle entry points')
