-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Menu=require('src.ui.game3.start_menu')
local Host=require('src.mods.Runtime')
local Stream=require('src.core.game3.asset_stream')
local G=require('src.core.Game3')
local nativeUpdate,nativeDraw=Menu.update,Menu.draw
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Stream.shutdown();G.release()
 local f=require('tools.session-runtime.fixture').new(edition);local game=f.game
 game.mods.mods={menu_owner={enabled=true},peer={enabled=true}}
 Host.currentMod='menu_owner'
 T.eq(Menu.isOpen(),false);T.eq(Menu.show({index=-1}),false)
 local menu=assert(Menu.show());T.eq(getmetatable(menu),require('src.ui.Gen3StartMenu'))
 T.eq(Menu.isOpen(),true);T.eq(Menu.open,true);T.eq(Menu.cursor,menu.index)
 T.eq(Menu.show(),false,'duplicate native menu refused')
 local before=menu.index;f.input.edges.down=true
 Menu.update=function()nativeUpdate();nativeUpdate()end
 game.stack:update(1/60)
 T.eq(menu.index,before%#menu.rows+1,'wrapped update consumes native input once')
 f.input.edges={};local draws=0
 Menu.draw=function()nativeDraw();nativeDraw()end
 Menu._draw(menu,function()draws=draws+1 end);T.eq(draws,1)
 nativeDraw();nativeUpdate();T.eq(draws,1,'out-of-phase calls cannot rerun a menu')
 Host.currentMod='peer';T.eq(Menu.close(),false);T.eq(game.stack:top(),menu)
 Stream.cancelOwner('peer');T.eq(game.stack:top(),menu,'foreign cleanup preserves the admitted menu')
 Host.currentMod='menu_owner';T.eq(Menu.close(),true);T.eq(Menu.isOpen(),false);T.eq(game.stack:top(),f.world)
 local second=assert(Menu.show());local flow=second.nativeUiFlow
 game.stack:pop();Stream.poll();T.eq(flow.retired,true,'native close releases an exhausted menu flow')
 T.eq(Menu.close(),false,'closing an absent menu cannot pop the world')
 Menu.update,Menu.draw=nativeUpdate,nativeDraw;Stream.shutdown();G.release();Host.currentMod=nil
end
T.finish('native START menu ownership, input/draw phases and exact close')
