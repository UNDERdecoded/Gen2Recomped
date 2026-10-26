-- Actual RS cartridge action records; no assets or generated cache written.
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local bytes=read(assert(arg[1]));local m=require('src.link.Json').decode(read(assert(arg[2])))
local X=require('src.import.RomExtractorGen3');local config=assert(m.rsItemMenu)
local function extract(manifest)
 local x=X.new(bytes,'rs-item-menu-regression',manifest);local c={};x:itemMenuActions(c);return c.gen3ItemMenu
end
local menu=assert(extract(m));assert(menu.columns==2 and menu.blank==9 and menu.cancel==3 and menu.register==4 and not menu.deselect)
local names={'USE','TOSS','CANCEL','REGISTER','USE','CANCEL','GIVE','CHECK TAG','','CONFIRM'}
local kinds={'use','toss','cancel','register','use','cancel','give','checkTag','blank','other'}
for i=1,10 do assert(menu.labels[i]==names[i],i..': '..tostring(menu.labels[i]));assert(menu.kinds[i]==kinds[i])end
local expected={ITEM={1,7,2,3},BALL={7,9,2,3},TM_HM={1,7,9,3},BERRY={8,9,1,7,2,3},KEY_ITEM={1,4,9,3}}
local checked=0
for key,list in pairs(expected)do
 assert(#menu.pockets[key]==#list)
 for i,v in ipairs(list)do assert(menu.pockets[key][i]==v,key..' position '..i);checked=checked+1 end
 -- Independent raw ROM check: source index is column*rows+row.
 local spec=config.pockets[key];local rows=spec.count/2
 for row=0,rows-1 do for col=0,1 do
  local value=bytes:byte(config.choices+spec.row*6+col*rows+row+1)+1
  assert(menu.pockets[key][row*2+col+1]==value)
 end end
end
local old={};for k,v in pairs(m)do old[k]=v end;old.rsItemMenu=nil
assert(not extract(old),'Legacy Emerald scanner unexpectedly recognized RS fixed-stride actions')
local bad={};for k,v in pairs(m)do bad[k]=v end
bad.rsItemMenu={};for k,v in pairs(config)do bad.rsItemMenu[k]=v end;bad.rsItemMenu.sourceOrder='row-major'
assert(not pcall(extract,bad),'Unknown source grid order was accepted')
-- Feed the actual extracted cartridge items into the unchanged native
-- consumer and grid navigator. This is CPU evidence, not a rendered run.
local x=X.new(bytes,'rs-item-menu-consumer',m);local items
x.write=function(_,name,value)if name=='items'then items=value end end
x:extractItems();assert(items and items.REPEL and items.MACH_BIKE)
local Bag=require('src.ui.Gen3BagMenu');local Action=require('src.ui.Gen3ItemMenu')
local game={data={items=items,constants={gen3ItemMenu=menu}},save={inventory={REPEL=2},bagOrder={'REPEL'}}}
local bag=Bag.new(game,{});assert(bag:selected().id=='REPEL')
local selectedByPocket={ITEM='REPEL',BALL='POKE_BALL',TM_HM='TM01',BERRY='CHERI_BERRY',KEY_ITEM='MACH_BIKE'}
local nativeCells=0
for key,id in pairs(selectedByPocket)do
 local entries=assert(bag:actionsFor(id));assert(entries.columns==2)
 local got;local action=Action.new(game,{entries=entries.entries,columns=entries.columns,onPick=function(kind)got=kind end})
 game.stack={pop=function()end}
 for i,cell in ipairs(expected[key])do assert(action.entries[i].kind==kinds[cell]);nativeCells=nativeCells+1 end
 if key=='BALL'then action:keypressed('down');assert(action.index==3);action:keypressed('right');assert(action.index==4)
 elseif key=='BERRY'then action:keypressed('down');assert(action.index==3);action:keypressed('right');assert(action.index==4)
 elseif key=='KEY_ITEM'then action:keypressed('right');assert(action.index==2)end
 action:keypressed('a');assert(got==action.entries[action.index].kind)
end
assert(Bag.canRegister(game,'MACH_BIKE')and not Bag.canRegister(game,'REPEL'))
print('PASS_RS_ITEM_MENU actual 10 labels/handlers, '..checked..' raw pocket positions; '..nativeCells..' actual native consumer cells/grid/callbacks; legacy/unknown-order negatives')
