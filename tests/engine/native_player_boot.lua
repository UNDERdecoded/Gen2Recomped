-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Player=require('src.core.game3.player')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 require('src.core.Game3').release()
 local f=require('tools.session-runtime.fixture').new(edition);local g=f.game
 f.map.def.width,f.map.def.height=20,20
 g.stack.states={{isIntro=true}};g.save.player.x,g.save.player.y=7,9
 T.eq(Player.px,112);T.eq(Player.py,144);T.eq(Player.cellX,7);T.eq(Player.cellY,9)
 T.eq(Player.facing,g.save.player.facing);T.eq(Player.running,false)
 T.raises(function()Player.px=0 end,'no active native player')
 T.eq(g.save.player.x,7,'boot reads cannot change the native spawn')
 g.stack.states={f.world};T.eq(Player.px,f.player.px);T.eq(Player.py,f.player.py)
 T.neq(Player.px,112,'live actor takes precedence over saved spawn cells')
 g.stack.states={{isIntro=true}};g.save.player.map='UNIMPORTED';T.eq(Player.px,nil)
 g.save.player.map='TEST'
 for _,bad in ipairs{-1,20,math.huge,0/0,.5,'7'}do g.save.player.x=bad;T.eq(Player.px,nil)end
 Player.release();require('src.core.Game3').release()
end
T.finish('native pending spawn observation before actor admission')
