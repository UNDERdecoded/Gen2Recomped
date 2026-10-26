-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Menu=require('src.ui.game3.start_menu')
local Window=require('src.ui.game3.window')
local Native=require('src.ui.Gen3StartMenu')
local Host=require('src.mods.Runtime')
local Font=require('src.render.Font')
local G=require('src.core.Game3')
local Stream=require('src.core.game3.asset_stream')
local template=Menu.contentTemplate
T.eq(Menu._game,nil);T.eq(#Menu.ENTRIES,0);T.eq(Menu.contentTemplate(),nil)
T.eq(Window.CURSOR_WIDTH,Native.CURSOR_WIDTH)
local rect=Window.template(3,2,8,5);T.eq(rect.tilemapLeft,3);T.eq(rect.w,8)
local box,labels,cursor
local saved={Font.drawBox,Font.draw,Font.drawCode}
Font.drawBox=function(...)box={...}end
Font.draw=function(text,x,y)labels[#labels+1]={text,x,y}end
Font.drawCode=function(code,x,y)cursor={x,y}end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Stream.shutdown();G.release();Host.currentMod='menu_owner'
 local f=require('tools.session-runtime.fixture').new(edition);local g,w=f.game,f.world
 g.mods.mods={menu_owner={enabled=true}}
 local frlg=edition=='firered'or edition=='leafgreen'
 g.data.constants=g.data.constants or{};g.data.constants.gen3StartMenu={layout=frlg and'frlg'or'rs'}
 local menu=assert(Menu.show());labels={}
 local base=menu:nativeContentTemplate()
 T.eq(G.native(Menu._game),g);T.eq(#Menu.ENTRIES,#menu.rows)
 for i,row in ipairs(menu.rows)do T.eq(Menu.ENTRIES[i].id,row.id or row.key);T.eq(row.id,row.key)end
 local detached=Menu.ENTRIES;detached[1].label='CHANGED';T.eq(menu.rows[1].label~='CHANGED',true)
 local layout=Menu.contentTemplate();layout.width=100;T.eq(Menu.contentTemplate().width,base.width)
 menu:draw()
 T.eq(box[1],base.left-1);T.eq(box[2],base.top-1);T.eq(box[3],base.width+2);T.eq(box[4],base.height+2)
 T.eq(labels[1][2],frlg and base.left*8+Window.CURSOR_WIDTH or base.left*8)
 T.eq(cursor[1],frlg and base.left*8 or(base.left-1)*8+2)
 -- An installed source wrapper changes the rectangle the native painter uses.
 Menu.contentTemplate=function()
  local t=template();T.eq(G.native(Menu._game),g);T.eq(t.left,base.left)
  return Window.template(2,2,12,base.height)
 end
 labels={};menu:draw();T.eq(box[1],1);T.eq(box[2],1);T.eq(box[3],14)
 T.eq(labels[1][2],frlg and 24 or 16);T.eq(labels[1][3]>=16,true)
 -- Invalid returns and wrapper errors preserve the real native geometry.
 for _,value in ipairs{{left=-1,top=1,width=12,height=3},{left=0,top=1,width=0/0,height=3},{left=1,top=1,width=31,height=3},false}do
  Menu.contentTemplate=function()return value end
  local t=menu:contentTemplate();T.eq(t.left,base.left);T.eq(t.width,base.width)
 end
 Menu.contentTemplate=function()error('layout failure')end
 T.eq(menu:contentTemplate().width,base.width)
 local chosen=0;local key=menu.rows[1].key
 menu.rows[#menu.rows+1]={id='source_action',label='ACTION',onSelect=function(game,row)T.eq(game,g);T.eq(row.id,'source_action');chosen=chosen+1 end}
 menu:choose(menu.rows[#menu.rows]);T.eq(chosen,1);T.eq(menu.rows[1].key,key,'source IDs preserve native action keys')
 Menu.contentTemplate=template;Menu.close();T.eq(Menu._game,nil);T.eq(#Menu.ENTRIES,0)
 Stream.shutdown();G.release();Host.currentMod=nil
end
Font.drawBox,Font.draw,Font.drawCode=unpack(saved)
T.finish('native START content geometry and source observations')
