-- Copyright (c) 2026 Roxas2712. See the offered PR contribution permission in docs/native-gen2-phone-book.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
local Book=require('src.world.Gen2PhoneBook')
local Calls=require('src.script.Gen2Commands')
local Gear=require('src.ui.PokegearMenu')
local function data()
 local d=T.fixtures.fresh();d.map_scripts={phone={},scripts={STUB={{'end'}}}}
 for id=1,24 do d.map_scripts.phone[id]={name='CONTACT'..id,class=1,trainer=1,
   receive='STUB',receiveTime=7,call='STUB',callTime=7,group=1,number=1} end
 d.map_scripts.phone[1]={name='MOM',contactNumber=1}
 d.map_scripts.phone[4]={name='ELM',contactNumber=4}
 return d
end
local function same(actual,expected,label)
 T.eq(#actual,#expected,label..' length')
 for i,id in ipairs(expected) do T.eq(actual[i],id,label..' slot'..i) end
end
for _,version in ipairs({'gold','silver','crystal'}) do
 V.set(version);local d,save=data(),{}
 local label=version..': '
 T.eq(Book.remainingSlots(d,save,2),8,label..' absent permanent numbers reserve two slots')
 T.eq(Book.remainingSlots(d,save,1),9,label..' a permanent number does not reserve against itself')
 T.eq(Book.has(save,0),true,label..' native empty-byte membership semantics retained')
 local trainerIds={2,3,5,6,7,8,9,10}
 for _,id in ipairs(trainerIds) do T.eq(Book.add(d,save,id),true,label..' ordinary number admitted within unreserved run') end
 T.eq(Book.add(d,save,11),false,label..' ninth trainer cannot consume missing permanent slots')
 T.eq(Book.add(d,save,1),true,label..' Mom can occupy her reserved slot')
 T.eq(Book.add(d,save,4),true,label..' Elm can occupy his reserved slot')
 same(Book.contacts(save),{2,3,5,6,7,8,9,10,1,4},label..' insertion order reaches all ten slots')
 T.eq(Book.has(save,0),false,label..' full native array contains no empty byte')
 local ok,why=Book.add(d,save,2);T.eq(ok,false,label..' duplicate refused');T.eq(why,'already',label..' duplicate reason retained')
 T.eq(Book.add(d,save,0),false,label..' zero never becomes a registered contact')
 T.eq(Book.add(d,save,255),false,label..' absent contact cannot become callable')
 T.eq(Book.canDelete(d,1),false,label..' Mom is permanent in the native UI')
 T.eq(Book.canDelete(d,4),false,label..' Elm is permanent in the native UI')
 T.eq(Book.canDelete(d,2),true,label..' trainer number is deletable')
 T.eq(Book.remove(save,5),true,label..' script deletion succeeds')
 T.eq(Book.contacts(save)[3],0,label..' script deletion leaves a physical hole')
 T.eq(Book.contacts(save)[4],6,label..' script deletion does not reorder later slots')
 T.eq(Book.add(d,save,11),true,label..' next addition occupies the first hole')
 T.eq(Book.contacts(save)[3],11,label..' reusing a hole keeps remaining order')
 T.eq(Book.deleteAt(save,2),true,label..' Pokegear deletion succeeds')
 same(Book.contacts(save),{2,11,6,7,8,9,10,1,4,0},label..' only Pokegear deletion compacts')
 T.eq(save.g2Phone[3],nil,label..' deletion updates the existing numeric set')
 local detached=Book.contacts(save);detached[1]=24
 T.eq(Book.contacts(save)[1],2,label..' returned slot arrays are detached')
 save.g2Phone[23]=true
 T.eq(Book.contacts(save)[10],23,label..' old/native set writes are adopted without reordering')
 save.g2Phone[11]=nil
 T.eq(Book.contacts(save)[2],0,label..' external native deletion is not resurrected')
 local selected=Calls.availableCallers(d,save,{group=2,number=2},'DAY')
 same(selected,{2,6,7,8,9,10,23},label..' actual incoming selector walks physical registration order')
 -- Actual imported-opcode compiler and native ScriptRunner, including the
 -- askforphonenumber result branches. Only the yes/no prompt is an IO seam.
 local fresh={};local game={data=d,save=fresh,overworld={}}
 local serial=0
 local function run(rows)
  serial=serial+1;local key='BOOK'..serial
  d.map_scripts.scripts[key]=rows
  local lowered=assert(require('src.script.Gen2ScriptVM').compile(d,key))
  local runner=require('src.script.ScriptRunner').new(game,game.overworld);runner:run(lowered)
  T.eq(runner:isRunning(),false,label..' native book script returns')
  return runner.ctx
 end
 local ctx=run({{'addcellnum',7},{'checkcellnum',7},{'end'}})
 T.eq(ctx.g2Var,1,label..' actual native add/check writes the book')
 T.eq(Book.contacts(fresh)[1],7,label..' VM and UI share native slot ownership')
 ctx=run({{'delcellnum',7},{'checkcellnum',7},{'end'}})
 T.eq(ctx.g2Var,0,label..' actual native delete clears membership')
 ctx=run({{'checkcellnum',0},{'end'}})
 T.eq(ctx.g2Var,1,label..' actual native checkcellnum sees an empty slot')
 local Commands=require('src.script.Commands');local ask=Commands.ask
 local accepted=true;Commands.ask=function(c)c.lastCheck=accepted end
 ctx=run({{'askforphonenumber',8},{'end'}})
 T.eq(ctx.g2Var,0,label..' actual accepted ask returns CONTACT_GOT')
 ctx=run({{'askforphonenumber',8},{'end'}})
 T.eq(ctx.g2Var,1,label..' actual duplicate ask returns CONTACTS_FULL')
 accepted=false;ctx=run({{'askforphonenumber',9},{'end'}})
 T.eq(ctx.g2Var,2,label..' actual refused ask returns CONTACT_REFUSED')
 T.eq(fresh.g2Phone[9],nil,label..' refusal does not mutate native membership')
 Commands.ask=ask
end
V.set('crystal')
do
 local d=data();d.map_scripts.phone[1]={class=1,name='TRAINER1'}
 d.map_scripts.phone[4]={class=1,name='TRAINER4'}
 d.map_scripts.phone[12]={name='AUTHORED MOM',contactNumber=1}
 d.map_scripts.phone[14]={name='AUTHORED ELM',contactNumber=4}
 T.eq(Book.canDelete(d,1),true,'native trainer identity wins over the old Mom slot')
 T.eq(Book.canDelete(d,4),true,'native trainer identity wins over the old Elm slot')
 T.eq(Book.canDelete(d,12),false,'explicit relocated Mom identity is permanent')
 T.eq(Book.canDelete(d,14),false,'explicit relocated Elm identity is permanent')
 d.constants.phoneContactOrder={};d.map_scripts.phone[1]={name='CUSTOM'}
 T.eq(Book.canDelete(d,1),true,'authored empty identity metadata does not receive retail guesses')
end
do
 local d=data();local save={g2Phone={[7]=true,[2]=true,[5]=true}}
 same(Book.contacts(save),{2,5,7,0,0,0,0,0,0,0},'legacy set receives deterministic initial slot order')
 save.g2PhoneSlots={7,2,2,0,0,0,0,0,0,0}
 same(Book.contacts(save),{7,2,5,0,0,0,0,0,0,0},'stored order survives and duplicate slots are repaired')
 local gear=setmetatable({game={data=d,save=save},contact=1},{__index=Gear})
 local rows=gear:contacts();T.eq(#rows,10,'actual native card exposes ten physical slots')
 T.eq(rows[1].id,7,'actual native card does not sort away registration order')
 T.eq(rows[4].id,0,'empty native row is not callable')
 T.eq(rows[4].name,'----------','empty native row is displayed explicitly')
 local empty=setmetatable({game={data=d,save={}}},{__index=Gear}):contacts()
 T.eq(empty[1].id,0,'empty book cannot invent a Mom registration')
 T.eq(empty[4].id,0,'empty book cannot invent an Elm registration')
 local key;gear.cards={{id='PHONE'}};gear.index=1;gear.blink=0
 gear.game.input={wasPressed=function(_,value)return key==value end}
 gear.game.stack={pop=function()end}
 local Sound=require('src.core.Sound');local sound=Sound.play;Sound.play=function()end
 gear.contact=4;key='a';gear:update(0)
 T.eq(gear.phoneSubmenu,nil,'real native A input cannot call an empty slot')
 gear.contact=2;key='a';gear:update(0);key='down';gear:update(0);key='a';gear:update(0)
 T.eq(save.g2Phone[2],nil,'real native DELETE input removes the selected physical slot')
 same(Book.contacts(save),{7,5,0,0,0,0,0,0,0,0},'real Pokegear delete compacts the shared book')
 Sound.play=sound
end
do
 local d=data();local save={g2Phone={},g2PhoneSlots={2,3,5,6,7,8,9,10,1,4}}
 for _,id in ipairs(save.g2PhoneSlots)do save.g2Phone[id]=true end
 local gear=setmetatable({game={data=d,save=save},contact=10,gfx={}},{__index=Gear})
 local drawn={};gear.drawStrip=function()end;gear.textbox=function()end
 gear.printBoxText=function()end;gear.drawModeArrow=function()end
 gear.text=function(_,name,_,y)drawn[name]=y end
 local Font=require('src.render.Font');local old={Font.draw,Font.drawCode,Font.beginTint,Font.endTint}
 local graphics=love.graphics;love.graphics={setColor=function()end,rectangle=function()end}
 Font.draw=function(name,_,y)drawn[name]=y/8 end
 Font.drawCode=function()end;Font.beginTint=function()end;Font.endTint=function()end
 gear:drawPhone()
 T.eq(drawn.ELM,11,'actual native drawing keeps selected slot ten visible')
 T.eq(drawn.MOM,10,'actual native drawing retains slot nine beside it')
 T.eq(drawn.CONTACT2,nil,'scrolling does not draw hidden slot one')
 Font.draw,Font.drawCode,Font.beginTint,Font.endTint=unpack(old);love.graphics=graphics
end
V.set(original)
T.finish('native ordered phone slots, permanent reservations, actual VM and Pokegear')
