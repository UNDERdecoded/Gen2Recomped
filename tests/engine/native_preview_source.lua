-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local M=require('src.ui.game3.map_preview_screen')
local Preview=require('src.world.Gen3MapPreviewFRLG')
local G=require('src.core.Game3')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 G.release()
 local f=require('tools.session-runtime.fixture').new(edition);local g=f.game
 g.data.constants.gen3FRLGMapPreviews={bySection={[8]={type='forest'},[9]={type='cave'}}}
 T.eq(M.isActive(),false);T.eq(M.mapsec(),nil)
 local state=setmetatable({game=g,section=8,t=15,phase='in',hold=40},Preview)
 g.stack:push(state)
 T.eq(M.isActive(),true);T.eq(M.isForestActive(),true);T.eq(M.mapsec(),8)
 Preview.update(state);T.eq(state.phase,'hold');T.eq(state.t,0,'one native clock advances the preview')
 state.section=9;T.eq(M.isForestActive(),false);T.eq(M.isActive(),true)
 g.stack:push({});T.eq(M.isActive(),true,'overlay does not hide an admitted preview')
 state.game={};T.eq(M.isActive(),false,'foreign preview is not admitted');state.game=g
 g.stack.states={f.world};T.eq(M.isActive(),false);T.eq(M.mapsec(),nil)
 g.stack.states={{game=g,section=8}};T.eq(M.isActive(),false,'lookalike states cannot claim a native preview')
 G.release()
end
T.finish('native preview admission and source observations')
