-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Actual native owners, registry construction and the shared save stores.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local old=Version.get()
require('src.core.ModCompat').install()
local Screens=require('src.ui.Screens');local Stack=require('src.core.StateStack')
local Bag=require('src.inventory.Bag');local Mail=require('src.pokemon.Gen2Mail')
local Storage=require('src.pokemon.Boxes');local Font=require('src.render.Font')
local function game(version)
 local data=T.fixtures.fresh()
 data.items.POTION={name='POTION',pocket='ITEM',canToss=true}
 data.items.ANTIDOTE={name='ANTIDOTE',pocket='ITEM',canToss=true}
 data.items.POKE_BALL={name='POKé BALL',pocket='BALL',canToss=true}
 data.items.FLOWER_MAIL={name='FLOWER MAIL',pocket='ITEM'}
 data.font.charmap={}
 for n=32,126 do data.font.charmap[#data.font.charmap+1]={seq=string.char(n),code=n} end
 Font.load(data);Mail.load(data);Storage.load(nil)
 local g={data=data,input={key=nil},save={version=version,flags={},inventory={POTION=5,ANTIDOTE=2,POKE_BALL=3},
   pcItems={POTION=2},options={},player={name='QA'},party={},pokedex={seen={},owned={}}}}
 function g.input:wasPressed(key)return self.key==key end
 function g.input:isDown(key)return self.key==key end
 g.stack=setmetatable({},{__index=Stack});g.stack:init();g.overworld={};g.stack:push(g.overworld)
 return g
end
local function tick(g,key)g.input.key=key;g.stack:update(1/60);g.input.key=nil end
for _,version in ipairs({'gold','silver','crystal'}) do
 Version.set(version);local g=game(version)
 for _,name in ipairs({'PcMenu','CenterPcMenu','ItemPcMenu','MailboxMenu','DecorationMenu','PackMenu','BoxMenu','MailRead'}) do
  local owner=require('src.ui.Gen2'..name)
  T.eq(require('src.ui.gen2.'..name),owner,'public spelling retains '..name..' class identity')
  local before=#g.stack.states
  local instance=Screens.build(g,'Gen2'..name)
  T.eq(getmetatable(instance),owner,'factory builds actual '..name..' state')
  T.eq(instance.screenId,'Gen2'..name,'resolved owner ID is available before stack insertion')
  T.eq(#g.stack.states,before,'embedded construction never pushes '..name)
 end
 local Item=require('src.ui.Gen2ItemPcMenu')
 g.data.items.KEY={name='KEY',pocket='KEY_ITEM',keyItem=true,cantToss=true,registerable=true}
 g.data.items.HM={name='HM01',pocket='TM_HM',machine={kind='HM',number=1,move='CUT'}}
 g.data.items.TM={name='TM02',pocket='TM_HM',machine={kind='TM',number=2,move='MOVE_001'}}
 local pack=require('src.ui.Gen2PackMenu').new(g)
 T.eq(pack:moveOf('HM'),'CUT','pack reads imported native machine records')
 T.eq(pack:moveOf('TM'),'MOVE_001','TM uses native move identity')
 T.eq(table.concat(pack:submenuRows('KEY'),','),'use,sel,quit','native CANT_TOSS/CAN_SELECT bits govern key-item actions')
 T.check(Item.new(g):cantToss('HM'),'PC cannot toss an imported HM')
 T.check(Item.new(g):cantToss('KEY'),'PC cannot toss an imported key item')

 local pc=Screens.push(g,'Gen2ItemPcMenu')
 T.eq(getmetatable(pc),Item,'ordinary PC push uses its native owner')
 pc:enterDeposit()
 T.eq(getmetatable(pc.pack),require('src.ui.Gen2PackMenu'),'deposit embeds an actual pack without a second stack state')
 T.eq(g.stack:top(),pc,'embedded PACK leaves PC as stack owner')
 pc:deposit('POTION','POTION',2)
 T.eq(g.save.inventory.POTION,3,'deposit removes the real bag quantity')
 T.eq(g.save.pcItems.POTION,4,'deposit grows the canonical PC store')
 pc:withdraw({id='POTION',name='POTION'},1)
 T.eq(g.save.inventory.POTION,4,'withdraw returns real items to the bag')
 T.eq(g.save.pcItems.POTION,3,'withdraw debits the same PC store')
 pc:leaveDeposit();pc:close();T.eq(g.stack:top(),g.overworld,'PC default close returns to the world')
 local s=g.save;s.bagOrder={'POTION','POKE_BALL','ANTIDOTE'}
 T.check(Bag.move(s,'POTION','ITEM',2,g.data),'SELECT reorders inside its pocket')
 T.eq(table.concat(s.bagOrder,','),'ANTIDOTE,POKE_BALL,POTION','another pocket keeps its global acquisition position')
 T.eq(Bag.move(s,'POKE_BALL','ITEM',1,g.data),false,'cross-pocket move is refused')
 T.eq(Bag.move(s,'MISSING','ITEM',1,g.data),false,'unknown rows never create items')
 T.eq(s.inventory.POTION,4,'reorder never changes quantities')
 local Rating=require('src.core.Gen2PokedexRating')
 s.pokedex={seen={A=true,B=true},owned={A=true}}
 local seen,owned=Rating.dexCounts(s)
 T.eq(seen,2,'Oak counts the native seen map');T.eq(owned,1,'Oak counts native owned rather than a second caught map')
 T.eq(Rating.findOakRating(9).max,9,'rating covers its upper boundary')
 T.eq(Rating.findOakRating(10).max,19,'rating advances past the boundary')
 local letter=Mail.entry('FLOWER_MAIL','ONE\nTWO','SENDER',123)
 s.mail={party={},box={letter}};s.party={{species=T.fixtures.ids.species[1],hp=10,moves={},stats={hp=10}}}
 local mailbox=Screens.push(g,'Gen2MailboxMenu');mailbox:attachMail()
 local party=g.stack:top();T.eq(party.pickOnly,true,'native mailbox requests actual party selection')
 tick(g,'a')
 T.eq(g.stack:top(),mailbox,'party selection pops exactly one state')
 T.eq(s.party[1].item,'FLOWER_MAIL','attachment retains stationery ID')
 T.eq(s.mail.party[1],letter,'attachment retains the exact letter')
 T.eq(#s.mail.box,0,'attachment removes only the selected mailbox entry')
 mailbox:close();T.eq(g.stack:top(),g.overworld,'mailbox close leaves the underlying world intact')
 local pcmon=require('src.ui.Gen2PcMenu').new(g,{saveExists=false,writer=function()return false end})
 s.currentBox=1;pcmon:beginChangeBox(2);pcmon:writeChangeBox()
 T.eq(pcmon.saved,false,'failed change-box persistence is reported')
 T.eq(s.currentBox,1,'failed write restores the live current-box selection')
 local Pokemon=require('src.pokemon.Pokemon')
 local species=T.fixtures.ids.species[1]
 local function mon()return Pokemon.new(g.data,species,5,function(lo)return lo end)end
 local a,b,c=mon(),mon(),mon();s.party={a,b,c};s.mail={party={},box={}}
 local box=Screens.build(g,'Gen2BoxMenu',{mode='deposit'})
 box:doDeposit()
 T.eq(#s.party,2,'native deposit screen removes one party member')
 T.eq(require('src.pokemon.Gen2Boxes').box(s,1)[1],a,'deposit screen stores the exact selected member')
 local withdrawal=Screens.build(g,'Gen2BoxMenu',{mode='withdraw'})
 withdrawal:doWithdraw()
 T.eq(s.party[3],a,'native withdrawal screen returns the actual stored member')
 T.eq(require('src.pokemon.Gen2Boxes').count(s,1),0,'withdraw screen empties the source slot')
 local move=Screens.build(g,'Gen2BoxMenu',{mode='move'})
 move.boxIndex=0;move.index=1;move:beginMove()
 T.eq(move.phase,'insert','party move admits a valid destination chooser')
 move:stepBox(1);move:insertMon()
 T.eq(require('src.pokemon.Gen2Boxes').box(s,1)[1],b,'move screen inserts the selected live mon into its destination')
 T.eq(#s.party,2,'cross-list move retains party cardinality')
 T.eq(s.party[1],c,'cross-list move compacts the party in order')
 local alternate={version=version,party={},inventory={},player={}}
 local alternatePC=require('src.ui.Gen2PcMenu').new(g,{save=alternate,saveExists=false})
 alternatePC:beginChangeBox(2);alternatePC:writeChangeBox()
 T.eq(alternatePC.saved,false,'alternate PC never falls back to the live profile writer')
end
Version.set('red');local g=game('red');local value={}
g.data.screens={Probe={new=function(_,a,b)T.eq(a,11,'build preserves first positional argument');T.eq(b,value,'build preserves trailing argument');return {}end}}
Screens.invalidate();local state=Screens.build(g,'Probe',11,value)
T.eq(g.stack:top(),g.overworld,'registry build leaves stack untouched')
T.eq(state.screenId,'Probe','registry build records resolved identity')
T.eq(Screens.push(g,'Probe',11,value),g.stack:top(),'push uses the same construction policy before insertion')
Version.set(old)
T.finish('native Gen2 PC owners')
