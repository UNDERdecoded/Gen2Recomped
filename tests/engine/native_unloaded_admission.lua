-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local G=require('src.core.Game3')
local Field=require('src.core.game3.field_move_show_mon')
local Transition=require('src.compat.gen1.TransitionRuntime').new()
local Party=require('src.ui.game3.party_menu')
local modules={'src.world.Gen3FieldMove','src.render.BattleTransition','src.ui.Gen3PartyMenu'}
local saved={};for _,name in ipairs(modules)do saved[name]=package.loaded[name];package.loaded[name]=nil end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 G.release();local f=require('tools.session-runtime.fixture').new(edition);local g=f.game
 local plain={game=g,isMenu=true,subIndex=4}
 g.stack.states={f.world,plain}
 T.eq(Field.isActive(),false,'an unloaded native class cannot match a plain mod screen')
 T.eq(Field._fx,nil);T.eq(Field.draw(),false);T.eq(Field.reset(),false)
 T.eq(Transition:current(),nil);T.eq(Transition:observed(),nil)
 T.eq(Party.open,false);T.eq(Party._party,nil);T.eq(Party.ACTIONS,nil)
 T.eq(g.stack:top(),plain);T.eq(plain.subIndex,4,'observation cannot adopt or mutate a foreign screen')
end
for _,name in ipairs(modules)do package.loaded[name]=saved[name]end
Transition:release();G.release()
T.finish('unloaded native classes never admit plain mod or world states')
