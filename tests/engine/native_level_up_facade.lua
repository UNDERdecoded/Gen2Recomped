-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Battle=require('src.core.game3.battle')
local Layer=require('src.core.game3.battle.level_up_streaks')
local G=require('src.core.Game3')
local original=package.loaded['src.core.Game'];local base=Layer.draw
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition);local game=f.game
 package.loaded['src.core.Game']=game
 T.eq(base(),false,'source draw cannot invent a native admission')
 local battle=f.fresh('TACKLE').battle;battle.enter=false;game.stack:push(battle)
 local frame=battle.frame;local calls=0
 Layer.draw=function(st)
  T.eq(st,Battle.getState());base(st);base(st)
  return false,nil,'source result'
 end
 local a,b,c=Layer._nativeDraw(battle,function(owner)T.eq(owner,battle);calls=calls+1 end)
 T.eq(a,false);T.eq(b,nil);T.eq(c,'source result');T.eq(calls,1,'native layer is borrowed once')
 T.eq(battle.frame,frame,'capture does not advance the native clock')
 local depth=love.graphics.getStackDepth and love.graphics.getStackDepth()
 Layer.draw=function()love.graphics.push('all');error('level-up source error')end
 T.raises(function()Layer._nativeDraw(battle,function()end)end,'level-up source error')
 if depth then T.eq(love.graphics.getStackDepth(),depth,'callback error unwinds leaked graphics pushes')end
 Layer.draw=function()game.stack:push({});local ok,why=base();game.stack:pop();return ok,why end
 calls=0
 local ok,why=Layer._nativeDraw(battle,function()calls=calls+1 end)
 T.eq(ok,false);T.eq(why,'native level-up presentation admission changed');T.eq(calls,0)
 local seams=require('src.mods.ModSeams');local previous=G._callbackOwner()
 Layer.draw=function()T.eq(G._callbackOwner(),'level_owner');return base()end
 seams._journal[#seams._journal+1]={tbl=Layer,key='draw',after=Layer.draw,owner='level_owner'}
 Layer._nativeDraw(battle,function()return true end)
 T.eq(G._callbackOwner(),previous,'attribution restores caller owner');table.remove(seams._journal)
 Layer.draw=base
 local releases=0;battle._levelUpBlend={release=function()releases=releases+1 end}
 game.stack:pop();T.eq(releases,1,'real native battle exit retires its owned alpha buffers')
 T.eq(battle._levelUpBlend,nil);T.eq(base(),false,'retired native battle cannot paint')
 Battle._service.release();f.close();G.release()
end
Layer.draw=base;package.loaded['src.core.Game']=original
T.finish('native level-up draw admission, once-only borrowing and graphics ownership')
