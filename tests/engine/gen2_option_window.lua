-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local before=Version.get()
local Menu=require('src.ui.OptionsMenu')
local UI=require('src.render.ScreenSpaceUI')
local Stack=require('src.core.StateStack')
local Save=require('src.core.SaveData')
require('src.render.Font').load(T.fixtures.fresh())
for _,edition in ipairs({'gold','silver','crystal','red','emerald'})do
 Version.set(edition)
 local game={data=T.fixtures.fresh(),save=Save.newGame()}
 game.stack=setmetatable({},{__index=Stack});game.stack:init()
 local menu=Menu.new(game);game.stack:push(menu)
 local gen2=Version.isGen2()
 T.eq(menu:drawsWidescreen(),gen2,edition..' window drawing is edition scoped')
 T.eq(menu:wantsFillScale(),gen2,edition..' fill contract is edition scoped')
 T.eq(UI.select(game.stack,{states={menu}},1),gen2 and menu or nil,edition..' actual compositor selects declared owner')
 if gen2 then
  local glyphs=0;local draw=love.graphics.draw;local wide=Menu.drawWidescreen
  love.graphics.draw=function(...)glyphs=glyphs+1;return draw(...)end
  Menu.drawWidescreen=function(self,w,h)
   self.windowReceipt={w,h};return wide(self,w,h)
  end
  UI.draw(menu,{}, {width=800,height=720},nil,false)
  love.graphics.draw=draw;Menu.drawWidescreen=wide
  T.same(menu.windowReceipt,{800,720},edition..' provider wrapper receives actual window dimensions')
  T.check(glyphs>0,edition..' fallback renders native panel glyphs')
 end
end
Version.set(before)
T.finish('native Gen2 options window presentation')
