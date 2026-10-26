-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local original=V.get()
local Mom=require('src.world.Gen2MomShopping');local Native=require('src.world.Gen2Decorations')
local Flags=require('src.script.Gen2Flags');local Runner=require('src.script.ScriptRunner')
local W=require('src.world.OverworldController');local Stack=require('src.core.StateStack')
local Map=require('src.world.Map');local Pokemon=require('src.pokemon.Pokemon')
local Battle=require('src.battle.BattleState');local S=require('src.save_convert.Gen2Save')
local E=require('src.import.RomExtractorGen2');local J=require('src.link.Json')
local Sound=require('src.core.Sound');local oldSound=Sound.play;Sound.play=function()end -- audio device IO
local slot,oldGame
for i=1,100 do local name,value=debug.getupvalue(W.afterBattle,i);if name=='Game'then slot=i;oldGame=value;break end end
assert(slot)
local function data()
 local d=T.fixtures.fresh()
 d.items.ITEM_017={id='ITEM_017',index=17,name='SYNTHETIC A',pocket='ITEM'}
 d.items.ITEM_018={id='ITEM_018',index=18,name='SYNTHETIC B',pocket='ITEM'}
 d.map_scripts={momShopping={complete=true,step=17,
  random={{trigger=0,cost=3,kind=1,item=17},{trigger=0,cost=5,kind=1,item=18}},
  ladder={{trigger=100,cost=20,kind=1,item=17},{trigger=200,cost=70,kind=2,item=14},{trigger=500,cost=30,kind=1,item=18}},
  programs={item='ITEM_PHONE',doll='DOLL_PHONE'},rewardTexts={[0]='REWARD0',[1]='REWARD1',[2]='REWARD2',[3]='REWARD3'}},
  phone={[3]={class=0,contactNumber=1,name='SYNTHETIC MOM'}},
  decorations={[14]={type=1,name='SYNTHETIC DOLL',action='SET_UP_DOLL',flag=900,sprite=18}},
  decorationInfo={complete=true},scripts={BANK={{'special',0,'BankOfMom'},{'end'}},ITEM_PHONE={{'setevent',901},{'end'}},DOLL_PHONE={{'setevent',902},{'end'}}}}
 d.text={REWARD0='SYNTHETIC {PLAYER} TOTAL {NUM}',REWARD1='SYNTHETIC SOME {PLAYER} TOTAL {NUM}',
  REWARD2='SYNTHETIC HALF {PLAYER} TOTAL {NUM}',REWARD3='SYNTHETIC ALL {PLAYER} TOTAL {NUM}'}
 return d
end
local function save(balance)
 return{flags={},money=0,g2MomMoney=balance or 0,inventory={},pcItems={},party={},player={name='QA'},pokedex={seen={},owned={}}}
end
local function buy(d,s,opts)
 opts=opts or{};opts.phoneService=opts.phoneService~=false;return Mom.tryBuy(d,s,opts)
end
local function game(d,s)
 local def={id='QA_MOM',generation=2,width=2,height=2,blocks={1,1,1,1},warps={},mapPalette=1,phoneService=true}
 local ts={id='FLOOR',blockCells=2,collision={255,255,255,255,0,0,0,0},walkable={0},grassTiles={},waterTiles={}}
 d.maps.QA_MOM=def
 local w=setmetatable({map=Map.new(def,ts),player={cellX=0,cellY=0,facing='down'},scriptMoves={},pendingScripts={},npcs={}},{__index=W})
 local stack=setmetatable({states={w}},{__index=Stack}) -- world already entered in this fixture
 local g={data=d,save=s,stack=stack,world=w,overworld=w,input={wasPressed=function()return false end}};w.runner=Runner.new(g,w)
 debug.setupvalue(W.afterBattle,slot,g);return g,w
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 for mode=0,3 do
  for _,coin in ipairs({1,2})do
   local s=save(100);s.money=10;s.g2MomSavingMode=mode
   local quarters=({[0]=0,1,2,4})[mode];local award=Mom.reward(s,900*coin)
   T.eq(s.g2MomMoney,100+225*coin*quarters,version..' native mode '..mode..' sends actual quarters to Mom')
   T.eq(s.money,10+225*coin*(4-quarters),version..' wallet receives only its actual share')
   T.eq(award.total,900*coin,version..' displayed total remains complete prize')
   T.eq(award.mode,mode,version..' native text uses actual savings mode')
  end
 end
 local s=save(999999);s.g2MomSaving=true
 T.eq(Mom.reward(s,900).mode,0,version..' maxed savings disables skimming')
 T.eq(s.money,900,version..' maxed savings sends all quarters to wallet')
 s=save(999998);s.g2MomSaving=true;s.money=999998
 Mom.reward(s,900)
 T.eq(s.g2MomMoney,999999,version..' near-cap Mom account saturates')
 T.eq(s.money,999999,version..' wallet saturates separately')
 s=save();s.g2MomSaving=true;s.flags.ENGINE_MOM_SAVING_MONEY=false
 T.eq(Mom.mode(s),0,version..' explicit native flag overrides legacy saving boolean')
 s.g2MomSavingMode=2;T.eq(Mom.mode(s),2,version..' HALF bit survives an unset SOME bit')
 s.flags.ENGINE_MOM_SAVING_MONEY=true;T.eq(Mom.mode(s),3,version..' native setflag changes only bit zero')
 Mom.setSaving(s,false);T.eq(Mom.mode(s),0,version..' bank stop clears saving mode')
 Mom.openBank(s);Mom.setSaving(s,true)
 T.eq(s.flags.ENGINE_MOM_ACTIVE,true,version..' bank opening reaches native active flag')
 T.eq(s.flags.ENGINE_MOM_SAVING_MONEY,true,version..' bank start reaches native SOME flag')
 local previous=save();previous.g2MomBankOpen=true;previous.g2MomSaving=true
 Mom.prepareBank(previous)
 T.eq(previous.flags.ENGINE_MOM_ACTIVE,true,version..' earlier native preview account migrates to active flag')
 T.eq(previous.flags.ENGINE_MOM_SAVING_MONEY,true,version..' earlier native preview saving choice migrates to native flag')
 previous.flags.ENGINE_MOM_ACTIVE=false;Mom.prepareBank(previous)
 T.eq(previous.g2MomBankOpen,nil,version..' explicit native reset overrides legacy open boolean')
 local legacy=data();legacy.map_scripts.phone[3].contactNumber=nil;legacy.map_scripts.phone[3].trainer=1
 T.eq(Mom.caller(legacy),3,version..' original non-trainer contact byte remains supported')
 local d=data();s=save()
 local bankGame,bankWorld=game(d,s)
 local bank=Runner.new(bankGame,bankWorld);bank:run(assert(require('src.script.Gen2ScriptVM').compile(d,'BANK')))
 local box=bankGame.stack:top();box.done=true;box:update(0)
 local yes=bankGame.stack:top();bankGame.input={wasPressed=function(_,key)return key=='a'end};yes.index=1;yes:update(0);bankGame.input={wasPressed=function()return false end};for _=1,20 do if bankGame.stack:top()==yes then yes:update(0)end end
 local feedback=bankGame.stack:top();feedback.done=true;bankGame.input={wasPressed=function(_,key)return key=='a'end};feedback:update(0)
 T.eq(bank:isRunning(),false,version..' actual BankOfMom UI completes first saving choice')
 T.eq(s.flags.ENGINE_MOM_SAVING_MONEY,true,version..' actual BankOfMom UI writes native SOME flag')
 T.eq(s.flags.ENGINE_MOM_ACTIVE,true,version..' actual BankOfMom UI opens native account')
 T.eq(Mom.mode(s),1,version..' actual BankOfMom UI affects reward allocation mode')
 local d=data();s=save(100)
 local purchase=buy(d,s)
 T.eq(purchase.kind,1,version..' first ladder purchase is native item')
 T.eq(s.pcItems.ITEM_017,1,version..' native item byte resolves current dataset')
 T.eq(s.g2MomMoney,80,version..' price deducted once')
 T.eq(s.g2MomShopping.whichItem,1,version..' ladder advances only on delivery')
 T.eq(s.g2MomShopping.whichSet,0,version..' ladder uses native zero set')
 T.eq(purchase.caller,3,version..' Mom caller is current native contact identity')
 s.g2MomMoney=200;purchase=buy(d,s)
 T.eq(s.flags[Flags.eventFlag(900)],true,version..' doll purchase grants actual ownership flag')
 T.eq(s.g2MomMoney,130,version..' doll price is deducted')
 T.eq(s.g2MomShopping.whichItem,2,version..' doll advances ladder once')
 T.eq(s.decorations,nil,version..' doll ownership does not place it in the room')
 local g,w=game(d,s);local r=Runner.new(g,w);r:run(purchase.script)
 T.eq(s.flags[Flags.eventFlag(902)],true,version..' doll notification runs native compiled role')
 s=save(101);purchase=buy(d,s)
 T.check(purchase~=nil,version..' ladder takes precedence over random threshold')
 s=save(34);s.g2MomShopping={whichItem=255,triggerBalance=17}
 local called=0;purchase=buy(d,s,{random=function(n)called=called+1;return n-1 end})
 T.eq(purchase.item,18,version..' exact multiple selects current random table row')
 T.eq(called,1,version..' random purchase consumes one bounded roll')
 T.eq(s.g2MomShopping.triggerBalance,51,version..' consumed exact threshold advances once')
 T.eq(s.g2MomShopping.whichSet,2,version..' native random set is selected row plus one')
 T.eq(s.g2MomShopping.whichItem,255,version..' random buy cannot consume ladder index')
 T.eq(s.g2MomMoney,29,version..' random purchase deducts its own price')
 s=save(35);s.g2MomShopping={whichItem=255,triggerBalance=17}
 T.eq(buy(d,s),nil,version..' overshot multiple cannot buy')
 T.eq(s.g2MomShopping.triggerBalance,51,version..' overshot threshold advances above current balance')
 s=save(100);d.field.pcItemCap=1;s.pcItems.ITEM_018=99
 T.eq(buy(d,s),nil,version..' full PC rejects new stack')
 T.eq(s.g2MomMoney,100,version..' refusal does not spend money')
 T.eq(s.g2MomShopping.whichItem,0,version..' refusal does not advance ladder')
 s.pcItems={ITEM_017=98};T.check(buy(d,s)~=nil,version..' existing stack with room accepts purchase')
 T.eq(s.pcItems.ITEM_017,99,version..' item reaches last slot in actual stack')
 s=save(100);s.pcItems.ITEM_017=99
 T.eq(buy(d,s),nil,version..' a full same-item stack needs another native PC stack')
 s=save(200);s.g2MomShopping={whichItem=1,triggerBalance=17};s.pcItems.ITEM_018=99
 T.check(buy(d,s)~=nil,version..' doll ownership is independent of PC capacity')
 s=save(100);T.eq(buy(d,s,{phoneService=false}),nil,version..' no reception suppresses purchase')
 T.eq(s.g2MomShopping,nil,version..' no reception cannot consume threshold or initialize purchase state')
 T.eq(buy(d,s,{queued=true}),nil,version..' occupied native map-reentry queue suppresses purchase')
 T.eq(s.g2MomShopping,nil,version..' occupied queue cannot mutate purchase state')
 d.map_scripts.scripts.ITEM_PHONE=nil
 T.eq(buy(d,s),nil,version..' missing original phone program cannot grant a silent purchase')
 T.eq(s.pcItems.ITEM_017,nil,version..' missing native program leaves inventory unchanged')
 -- Actual battle win uses this account split and the cartridge-selected text.
 d=data();require('src.battle.TypeChart').load(d);s=save(10)
 s.party={Pokemon.new(d,'FIXMON_A',10)};s.g2MomSavingMode=1
 g,w=game(d,s)
 local battle=Battle.newTrainer(g,'OPP_FIX_YOUNGSTER',1);battle.participants={}
 for _,mon in ipairs(battle.enemyParty)do mon.hp=0 end
 battle.enemyIndex=#battle.enemyParty;battle.enemy.mon=battle.enemyParty[battle.enemyIndex]
 battle:enemyMonFainted()
 T.eq(battle.result,'win',version..' real battle native win branch completes')
 T.check(s.g2MomMoney>10,version..' real battle win actually increases Mom account')
 T.eq(battle.g2MomAward.mode,1,version..' real battle records applied savings mode')
 local found=false
 for _,row in ipairs(battle.queue)do if row.text and row.text:find('SYNTHETIC SOME QA TOTAL ',1,true)then found=true end end
 T.check(found,version..' real battle presents actual imported SOME reward text')
 -- Actual world post-battle path commits once and waits behind native dialogue.
 d=data();s=save(200);s.party={Pokemon.new(d,'FIXMON_A',10)}
 s.g2MomShopping={whichItem=1,triggerBalance=17};g,w=game(d,s)
 battle={kind='trainer',leveledUp={}}
 w:afterBattle('win',battle)
 T.eq(s.g2MomMoney,130,version..' actual trainer return purchases eligible doll')
 T.check(w.g2MomCallPending~=nil,version..' actual trainer return defers original notification')
 w:afterBattle('win',battle);T.eq(s.g2MomMoney,130,version..' repeated callback cannot buy twice')
 w.pendingScripts={{script={{'end'}}}}
 T.eq(w:checkMomShoppingCall(),false,version..' trainer after-dialogue queue keeps phone waiting')
 w.pendingScripts={};w.player.moving=true
 T.eq(w:checkMomShoppingCall(),false,version..' native phone does not interrupt a partial movement')
 w.player.moving=false;g.stack:push({name='dialogue'})
 T.eq(w:checkMomShoppingCall(),false,version..' actual overlay owner keeps phone waiting')
 g.stack:pop();T.eq(w:checkMomShoppingCall(),true,version..' idle native world queues original doll script')
 T.eq(s.g2CurCaller,3,version..' deferred native call sets actual caller')
 T.eq(w:checkMomShoppingCall(),false,version..' notification queues once')
 local entry=w.pendingScripts[1];T.check(entry~=nil,version..' actual native FIFO receives notification')
 if entry then w.runner:run(entry.script,entry.extra)end
 T.eq(s.flags[Flags.eventFlag(902)],true,version..' actual queued original role executes')
 T.eq(s.g2CurCaller,nil,version..' completed native call releases caller')
 T.eq(s.g2CallCycles,0,version..' completed native call resets receive timer')
 -- Physical SRAM offsets checked against the independent shipped symbols.
 S.setLayout(version);S.setCharmap({['128']='A'})
 s.g2MomMoney=123456;s.g2MomSavingMode=2;s.g2MomSaving=true;s.g2MomBankOpen=true
 s.flags.ENGINE_MOM_SAVING_MONEY=false;s.flags.ENGINE_MOM_ACTIVE=true
 s.g2MomShopping={whichItem=2,whichSet=1,triggerBalance=98765}
 local bytes=S.encode(s,d);local f=assert(io.open('tools/rom_manifest_'..version..'.json','rb'));local manifest=assert(J.decode(f:read('*a')));f:close()
 local anchor=version=='crystal'and 0xd47b or 0xd1a1
 local function offset(key)return 0x2009+manifest.symbols[key][2]-anchor end
 local function three(at)local a,b,c=bytes:byte(at+1,at+3);return a*65536+b*256+c end
 T.eq(three(offset('wMomsMoney')),123456,version..' Mom account uses actual three-byte SRAM field')
 T.eq(bytes:byte(offset('wMomSavingMoney')+1),130,version..' saving mode and active bit preserve native byte')
 T.eq(bytes:byte(offset('wWhichMomItem')+1),2,version..' native ladder index exports at independent address')
 T.eq(three(offset('wMomItemTriggerBalance')),98765,version..' native threshold exports at independent address')
 local back=S.decode(bytes,d)
 T.eq(back.g2MomMoney,123456,version..' native balance round-trips')
 T.eq(Mom.mode(back),2,version..' HALF mode round-trips without becoming SOME')
 T.eq(back.g2MomBankOpen,true,version..' bank active state round-trips')
 T.eq(back.g2MomShopping.whichItem,2,version..' ladder progress round-trips')
 T.eq(back.g2MomShopping.whichSet,1,version..' random row round-trips')
 T.eq(back.g2MomShopping.triggerBalance,98765,version..' threshold progress round-trips')
 local again=S.encode(back,d,bytes);local decoded=S.decode(again,d)
 local good=true;for _,warning in ipairs(decoded.warnings)do if warning:find('checksum')then good=false end end
 T.check(good,version..' Mom fields remain covered by valid native checksum')
end
for _,version in ipairs({'red','emerald','prism','polishedcrystal'})do
 V.set(version);local s=save(10);T.eq(Mom.reward(s,900),nil,version..' native GSC account split is isolated')
 T.eq(Mom.tryBuy(data(),s,{phoneService=true}),nil,version..' foreign edition cannot buy retail GSC gifts')
 S.setLayout(version);T.eq(S.OFFSETS.momMoney,nil,version..' unreviewed SRAM layout has no guessed Mom fields')
end
Sound.play=oldSound;debug.setupvalue(W.afterBattle,slot,oldGame);V.set(original);S.setLayout(original)
T.finish('native GSC Mom accounts, purchases, trainer return, phone queue and SRAM')
