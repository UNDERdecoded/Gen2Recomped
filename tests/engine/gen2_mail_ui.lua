-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local original=V.get()
V.set('crystal')
local data=T.fixtures.fresh()
require('src.render.Font').load(data)
data.items.ITEM_158={id='ITEM_158',key='FLOWER_MAIL',name='Letter',pocket='ITEM'}
local Mail=require('src.pokemon.Gen2Mail');Mail.load(data)
local Pokemon=require('src.pokemon.Pokemon')
local function mon()
  return Pokemon.new(data,T.fixtures.ids.species[1],5,function(lo)return lo end)
end
local game={data=data,save={},stack={states={}}}
function game.stack:push(screen)self.states[#self.states+1]=screen;if screen.enter then screen:enter()end end
function game.stack:pop()return table.remove(self.states)end
function game.stack:top()return self.states[#self.states]end
local function press(screen,key)
  game.input={wasPressed=function(_,k)return k==key end,isDown=function()return false end}
  screen:update(1/60)
end
local function reset()
  game.save={party={mon(),mon()},player={name='AUTHOR',id=17},inventory={ITEM_158=2},bagOrder={'ITEM_158'}}
  game.stack.states={{parent=true}}
end
local Compose=require('src.ui.Gen2MailCompose')
reset()
local parent=game.stack:top();local inv,order=game.save.inventory,game.save.bagOrder
local cancelled=0
local screen=Compose.new(game,{mon=game.save.party[1],item='ITEM_158',onCancel=function()cancelled=cancelled+1 end})
game.stack:push(screen);screen.text='UNSENT';press(screen,'select')
T.eq(game.stack:top(),parent,'SELECT cancels the actual keyboard')
T.eq(game.save.inventory.ITEM_158,2,'cancel does not consume stationery')
T.eq(game.save.party[1].item,nil,'cancel leaves the held item unchanged')
T.eq(game.save.mail,nil,'cancel creates no pending letter')
T.eq(cancelled,1,'cancel callback runs once')
local completed=0
screen=Compose.new(game,{mon=game.save.party[1],item='ITEM_158',onDone=function()completed=completed+1 end})
game.stack:push(screen);screen.text=string.rep('X',33)
T.eq(#screen.glyphs,32,'actual native keyboard caps the message at 32 glyphs')
press(screen,'start')
T.eq(completed,0,'START selects END before completing the letter')
press(screen,'a')
T.eq(completed,1,'A on END completes once')
T.eq(game.stack:top(),parent,'composition closes its own screen exactly once')
T.eq(game.save.inventory,inv,'composition preserves live inventory identity')
T.eq(game.save.bagOrder,order,'composition preserves live acquisition order identity')
T.eq(game.save.inventory.ITEM_158,1,'composition consumes one stationery')
T.eq(game.save.party[1].item,'ITEM_158','composition gives the actual native held item')
T.eq(game.save.mail.party[1].message,string.rep('X',32),'actual keyboard result becomes the native letter')
T.eq(game.save.mail.party[1].authorId,17,'composition records the real trainer ID')
local Bag=require('src.inventory.Bag')
T.eq(Bag.takeHeld(game.save,game.save.party[1],data),nil,'ordinary take cannot destroy a held letter')
T.eq(game.save.mail.party[1].message,string.rep('X',32),'refused take keeps message')
reset()
local held='PREVIOUS_ITEM';data.items[held]={id=held,name='Held item',pocket='ITEM'}
game.save.party[1].item=held;game.save.inventory[held]=99
local before=require('src.core.SaveData').encode(game.save)
T.eq(Mail.attachFromBag(game.save,1,'ITEM_158','FAIL',data),false,'full previous-item stack refuses the exchange')
T.eq(require('src.core.SaveData').encode(game.save),before,'failed exchange changes no persisted fields')
game.save.inventory[held]=98
T.check(Mail.attachFromBag(game.save,1,'ITEM_158','SWAP',data),'previous held item can return to bag')
T.eq(game.save.inventory[held],99,'previous held item is returned exactly once')
reset()
local gone=game.save.party[1]
screen=Compose.new(game,{mon=gone,item='ITEM_158'});game.stack:push(screen)
game.save.party[1]=mon();screen.text='STALE';press(screen,'start');press(screen,'a')
T.eq(game.save.inventory.ITEM_158,2,'stale keyboard target consumes no stationery')
T.eq(game.save.party[1].item,nil,'stale target cannot affect a replacement mon')
T.eq(game.save.mail,nil,'stale target creates no letter')

-- Native party switches keep letters pinned to their actual carriers.
reset()
local PartyMenu=require('src.ui.PartyMenu')
local carrier=game.save.party[1];carrier.item='ITEM_158'
Mail.set(game.save,1,Mail.entry('ITEM_158','CARRIER'))
local partyScreen=PartyMenu.new(game,{})
game.stack:push(partyScreen);partyScreen.swapFrom=1;partyScreen.index=2;press(partyScreen,'a')
T.eq(game.save.party[2],carrier,'actual party screen reorders the carrier')
T.eq(game.save.mail.party[2].message,'CARRIER','actual party screen moves its letter')
T.eq(game.save.mail.party[1],nil,'actual party screen clears the old mail slot')

-- Mailbox actions use the same save and preserve entries on failed moves.
local Mailbox=require('src.ui.Gen2MailboxMenu')
reset();game.save.mail={party={},box={Mail.entry('ITEM_158','ONE','A'),Mail.entry('ITEM_158','TWO','B'),Mail.entry('ITEM_158','THREE','C')}}
local list=Mailbox.new(game);game.stack:push(list);list.index=2
list:attachMail()
local picker=game.stack:top();press(picker,'a')
T.eq(game.save.mail.party[1].message,'TWO','real mailbox GIVE attaches the selected letter')
T.eq(game.save.mail.box[2].message,'THREE','real mailbox compacts after middle deletion')
T.eq(list:selected().message,'THREE','native cursor follows the compacted mailbox index')
game.stack.states={parent,list};list.message=nil;list.index=2;list:attachMail()
picker=game.stack:top();press(picker,'a')
T.eq(#game.save.mail.box,2,'occupied target preserves the mailbox')
T.eq(game.save.mail.party[1].message,'TWO','failed mailbox attachment preserves held letter')
game.stack.states={parent,list};list.message=nil;list.index=2;list:putInPack()
press(list,'b')
T.eq(#game.save.mail.box,2,'declining message loss retains mailbox contents')
T.eq(game.save.inventory.ITEM_158,2,'declining message loss adds no stationery')

-- The compatibility PC's dismissal is caller-owned; its close callback may
-- pop exactly one screen, as existing Gen2 hosts do.
require('src.core.ModCompat').install()
local BoxMenu=require('src.ui.gen2.BoxMenu')
T.eq(BoxMenu,require('src.ui.Gen2BoxMenu'),'legacy Gen2 PC namespace reaches the actual native factory')
reset();parent=game.stack:top();local calls=0;local pc
pc=BoxMenu.new(game,{onClose=function()
  calls=calls+1;T.eq(game.stack:top(),pc,'PC remains on stack during caller-owned close');game.stack:pop()
end})
game.stack:push(pc);press(pc,'b')
T.eq(calls,1,'PC B invokes one close callback')
T.eq(game.stack:top(),parent,'PC does not pop the parent below its caller')
T.eq(pc.save,game.save,'native PC exposes the actual save required by Gen2 hosts')
local alternate={party={mon(),mon()}}
pc=BoxMenu.new(game,{save=alternate})
T.eq(pc.save,alternate,'alternate-save native PC uses the supplied save')
T.eq(pc.game.writeSave,false,'alternate-save native PC cannot write the live profile')

-- Unknown carriers are quarantined by the production save validator. Their
-- detached letters survive the real codec without duplicating stationery.
reset();local unknown=mon();unknown.species='REMOVED_MOD_SPECIES';unknown.item='ITEM_158'
game.save.party[2]=unknown
Mail.set(game.save,2,Mail.entry('ITEM_158','KEEP','MOD',9,unknown.species))
local Save=require('src.core.SaveData')
local report=Save.validate(game.save,data)
T.eq(game.save.mail.box[1].message,'KEEP','missing-carrier letter is retained in native mailbox')
T.eq(unknown.item,nil,'quarantined carrier cannot duplicate detached stationery')
T.eq(#report.restoredMail,1,'mail recovery is reported')
T.eq(assert(Save.decode(Save.encode(game.save))).mail.box[1].message,'KEEP','quarantined letter survives actual save encoding')
local recovered={orphaned={mail={Mail.entry('ITEM_158','RECOVER')}}}
Mail.validate(recovered,{})
T.eq(recovered.mail.box[1].message,'RECOVER','pending letters reclaim even when no live mail table exists')

local run=T.sdk.loadMods({'mods/mail_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/mail_probe/manifest.json']='{"id":"mail_probe","name":"Mail probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/mail_probe/main.lua']=[[
    local mod=...
    mod.exports.reads=0;mod.exports.writes=0
    mod.events:on("mail.read",function(e)mod.exports.reads=mod.exports.reads+1;mod.exports.message=e.message end)
    mod.events:on("mail.written",function(e)mod.exports.writes=mod.exports.writes+1 end)
  ]],
})})
T.eq(#run.errors,0,'actual SDK mail event subscriptions load')
reset();Mail.load(data);Mail.compose(game.save,1,'PUBLIC',game.save.party[1],'ITEM_158')
Mail.lines(Mail.get(game.save,1));Mail.lines(game.save.mail.party[1])
local exports=run.loader.exports.mail_probe
T.eq(exports.writes,1,'public SDK receives the native write once')
T.eq(exports.reads,1,'public SDK receives the native read once, not every redraw')
T.eq(exports.message,'PUBLIC','public SDK receives actual letter contents')
run.release()
V.set(original);Mail.load(nil)
T.finish('native GSC mail keyboard, mailbox, party and PC menu transactions')
