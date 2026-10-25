package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local World=require('src.world.OverworldController')
local running=false
local w=setmetatable({runner={isRunning=function()return running end},scriptMoves={},player={}}, {__index=World})
T.eq(w:scriptRunning(),false,'idle script owner')
T.eq(w:busy(),false,'idle world not busy');T.eq(w:acceptsMenuInput(),true,'idle world accepts menu')
running=true;T.eq(w:scriptRunning(),true,'actual native runner owns script');T.eq(w:acceptsMenuInput(),false,'scripts block menu');running=false
for _,key in ipairs({'engaging','emote','teleportOut','whirlSpin','gen4Waterfall','transitioning','flyAnim','fishing'})do
 w[key]={};T.eq(w:busy(),true,key..' busy');T.eq(w:acceptsMenuInput(),false,key..' blocks menu');w[key]=nil
end
w.scriptMoves[1]={};T.eq(w:acceptsMenuInput(),false,'script movement blocks menu');w.scriptMoves={}
w.pendingScripts={{}};T.eq(w:acceptsMenuInput(),false,'pending map setup blocks menu');w.pendingScripts=nil
w.player.moving=true;T.eq(w:busy(),false,'ordinary step is not a script');T.eq(w:acceptsMenuInput(),false,'mid-step menu deferred');w.player.moving=nil
w.player.inputLocked=true;T.eq(w:acceptsMenuInput(),false,'input owner lock retained');w.player.inputLocked=nil
w.iceSlide='left';T.eq(w:acceptsMenuInput(),false,'ice slide blocks menu');w.iceSlide=nil
w.battleActive=true;T.eq(w:acceptsMenuInput(),false,'battle blocks world menus');w.battleActive=nil
T.eq(w:acceptsMenuInput(),true,'readiness recovers after owners release')
T.finish('native Gen2 menu readiness')
