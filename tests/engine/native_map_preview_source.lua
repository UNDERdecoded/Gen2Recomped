-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local M=require('src.ui.game3.map_preview_screen')
local Native=require('src.world.Gen3MapPreviewFRLG')
local original=package.loaded['src.core.Game']
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 require('src.core.GameVersion').set(edition)
 local g={data={},stack=setmetatable({},{__index=require('src.core.StateStack')})}
 g.stack:init();package.loaded['src.core.Game']=g
 local root={};g.stack:push(root)
 T.eq(M.isActive(),false);T.eq(M.dismiss(),false)
 local calls=0
 local preview=setmetatable({game=g,onDone=function()calls=calls+1 end},Native)
 g.stack:push(preview)
 T.eq(M.isActive(),true)
 local overlay={};g.stack:push(overlay)
 T.eq(M.dismiss(),false);T.eq(g.stack:top(),overlay);T.eq(calls,0)
 g.stack:pop()
 T.eq(M.dismiss(),true);T.eq(g.stack:top(),root);T.eq(calls,1)
 T.eq(M.reset(),false);T.eq(calls,1)
 local foreign=setmetatable({game={}},Native);g.stack:push(foreign)
 T.eq(M.isActive(),false);T.eq(M.dismiss(),false);T.eq(g.stack:top(),foreign)
end
package.loaded['src.core.Game']=original
T.finish('native map preview admission, covered dismissal and once-only continuation')
