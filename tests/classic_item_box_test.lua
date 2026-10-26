-- Exercise the real installed host list controller; no duplicate test controller.
local root=arg[1]or'.';local calls,depth={},0;local gen=1;local buttons={}
local F={width=function(s)return #tostring(s)*8 end,draw=function(s,x,y)calls[#calls+1]={'text',s,x,y}end,drawCode=function(c,x,y)calls[#calls+1]={'code',c,x,y}end,drawBox=function(...)calls[#calls+1]={'box',...}end}
package.loaded['src.render.Font']=F
package.loaded['src.mods.Runtime']={wantsHook=function()return false end}
package.loaded['src.ui.Theme']={cursor=237,cursorHollow=236,moreArrow=238}
package.loaded['src.core.Strings']=function(s)return s=='CANCEL'and'ZURÜCK'or s end
package.loaded['src.core.GameVersion']={generation=function()return gen end,isGen2=function()return gen==2 end}
package.loaded['src.core.Sound']={play=function()end}
package.loaded['src.render.TextBox']={paginate=function(s)return{{s}}end}
love={graphics={push=function()depth=depth+1 end,pop=function()depth=depth-1 end,setColor=function()end,translate=function()end,scale=function()end,rectangle=function()error('Classic overlay erased its background')end}}
local List=dofile(root..'/src/ui/ListMenu.lua');package.loaded['src.ui.ListMenu']=List
local B=dofile(root..'/src/ui/ClassicItemBox.lua');package.loaded['src.ui.ClassicItemBox']=B
local game={data={items={POTION={key='POTION'},KEY={keyItem=true}}},input={wasPressed=function(_,k)return buttons[k]end,isDown=function()return false end}}
local pops,cancels=0,0;game.stack={top=function()return game.current end,pop=function()pops=pops+1;game.current=nil end}
local function press(l,key)buttons={[key]=true};l:update(1/60);buttons={}end
local function create(items,opts)
 opts=opts or{};opts.kind=opts.kind or'bag';opts.onCancel=opts.onCancel or function()cancels=cancels+1 end
 local l=List.new(game,'ITEMS',items,opts);game.current=l;return l
end
local function has(kind,value,x,y)
 for _,r in ipairs(calls)do if r[1]==kind and r[2]==value and(x==nil or r[3]==x)and(y==nil or r[4]==y)then return true end end
 return false
end
local items={{value='POTION',label='TRANK',right='x3'}};local l=create(items)
assert(l.isOpaque==false and l.sgbPalettes==false and l.rows==3)
l:draw();assert(depth==0 and l.items==items and #items==1)
assert(has('box',4,2,16)and has('text','TRANK',48,32)and has('text','×',112,40)and has('text','3',128,40)and has('text','ZURÜCK',48,48))
assert(not has('text','ITEMS'),'Full-screen title leaked into overlay')
press(l,'down');assert(l.index==2);press(l,'a');assert(pops==1 and cancels==1 and l.items==items and #items==1)
l=create({});calls={};l:draw();assert(has('text','ZURÜCK',48,32));press(l,'a');assert(pops==2 and cancels==2)
l=create({});press(l,'b');assert(pops==3 and cancels==3)
local rows={};for i=1,12 do rows[i]={label='Item'..i,value='POTION',right='x'..i}end
local selected,swaps=0,0;l=create(rows,{onChoose=function(row)selected=selected+1;assert(row==rows[1])end,onSelectKey=function()swaps=swaps+1 end})
for _=1,12 do press(l,'down')end
assert(l.index==13 and l.scroll==10 and l.items==rows and #rows==12)
press(l,'select');assert(swaps==0,'Virtual cancel was sent to native reorder callback')
for _=1,12 do press(l,'up')end;press(l,'select');assert(swaps==1);press(l,'a');assert(selected==1 and l.items==rows)
-- A native callback may remove rows in place or replace the whole table.
l=create({{label='one'},{label='two'}},{onChoose=function(_,self)self:removeCurrent()end});press(l,'a');assert(#l.items==1 and l.items[1].label=='two')
local replacement={{label='new'}};l=create({{label='old'}},{onChoose=function(_,self)self.items=replacement end});press(l,'a');assert(l.items==replacement)
local nativeCancel={label='native cancel',cancel=true};local originals={nativeCancel};local chosen=false
l=create(originals,{onChoose=function(r)chosen=r==nativeCancel end});press(l,'a');assert(chosen and l.items==originals,'Existing native cancel row was replaced')
l=create({{value='KEY',label='KEY',right='x99'}});calls={};l:draw();assert(not has('text','99')and not has('text','x99'),'Key item quantity must stay hidden')
l=create({{label='item'}},{onChoose=function()error('native failure')end});local original=l.items;local choose=l.onChoose;assert(not pcall(press,l,'a'));assert(l.items==original and l.onChoose==choose)
buttons={};local draw=F.draw;F.draw=function()error('render failure')end;assert(not pcall(l.draw,l));assert(depth==0);F.draw=draw
for _,g in ipairs{2,3}do gen=g;l=create({});assert(not l.__classicItemBox,'Changed another generation’s native bag')end
gen=1
local pc=List.new(game,'PC',{}, {kind='pc-items',messageBox=true});assert(pc.__classicItemBox and pc.isOpaque==false)
local unrelated=List.new(game,'DEX',{}, {kind='dex'});assert(not unrelated.__classicItemBox)
local modern=List.new(game,'ITEMS',{}, {kind='other'});modern.kind='bag';modern.itemBox=true;assert(B.attach(modern)==modern and not modern.__classicItemBox)
print('CLASSIC_ITEM_BOX_OK real native controller: cancel A/B, empty/long bags, scrolling, reorder guard, removal/refresh, key items, failure cleanup, GBC/GBA/modern forwarding')

assert(create({}).itemBox==true,"Advertise native itemBox support to compatibility mods")
