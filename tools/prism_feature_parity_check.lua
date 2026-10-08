love=love or require('tests.love_stub')
local T=require('tests.harness').suite('Prism gifts, text, trees and cards')
local D=require('src.core.Data')
local cache=os.getenv('PRISM_CACHE') or 'G:/Gen2Recomped/prism/data/generated/'
for _,key in ipairs({'maps','tilesets','sprites','field','pokemon','moves','items','constants','text','palettes','map_scripts','type_chart','trainers','trainer_headers','charmap','font','audio'})do
 D[key]=assert(loadfile(cache..key..'.lua'))()
end
require('src.core.GameVersion').set('prism')
local Save=require('src.core.SaveData');local C=require('src.script.Commands');require('src.script.Gen2Commands');require('src.script.Gen2Specials')
local f=assert(io.open('pokeprism.gbc','rb'));local raw=f:read('*a');f:close()
f=assert(io.open('tools/rom_manifest_prism.json','rb'));local manifest=assert(require('src.link.Json').decode(f:read('*a')));f:close()
local E=require('src.import.RomExtractorGen2');local e=E.new(raw,'prism',manifest)
e.readSourceTable=function(self,name)return assert(loadfile(self.sourceDir..'/'..name..'.lua'))()end
local game={data=D,save=Save.newGame(),stack={push=function()end,pop=function()end}}
local ctx={game=game,save=game.save}
-- Decode the affected scripts from this ROM, including menus, local jumps
-- and inline callasm operands, then drive their actual compiled execution.
local pool={scripts={},movements={},queue={},instructions=0,desyncs=0,failures=0}
local adoption=e:gen2QueueScript(23,0x7099,pool)
local prize=e:gen2QueueScript(27,0x6D2A,pool)
e:gen2DrainScripts(pool)
local fresh={scripts=pool.scripts,movements=pool.movements}
T.eq(#fresh.scripts[adoption][5][2],5,'actual ROM adoption menu has all choices')
T.eq(fresh.scripts[adoption][5][2][1],'Chikorita    100','adoption menu decodes its ROM label and price')
local oldScripts=D.map_scripts;D.map_scripts=fresh
local VM=require('src.script.Gen2ScriptVM')
local Runner=require('src.script.ScriptRunner')
local originalShow,originalAsk,originalMenu,originalYes=C.show_text,C.ask,C.g2_verticalmenu,C.g2_yesno
local menuCalls=0
C.show_text=function()end;C.ask=function(c)c.lastCheck=false end
C.g2_verticalmenu=function(c)menuCalls=menuCalls+1;c.g2Var=menuCalls==1 and 1 or 5;c.lastCheck=true end
C.g2_yesno=function(c)c.g2Var=1;c.lastCheck=true end
local runner=Runner.new(game,{map={id='ORPHANAGE',def={label='Orphanage'}}})
game.save.g2OrphanPoints=100
runner:run(assert(VM.compile(D,adoption)))
T.check(not runner:isRunning(),'fresh ROM adoption script reaches its exit')
T.eq(#game.save.party,1,'fresh ROM adoption actually grants one Pokemon')
T.eq(game.save.party[1].species,'SPECIES_152','fresh ROM adoption chooses Chikorita')
T.eq(game.save.g2OrphanPoints,0,'fresh ROM adoption deducts 100 points')
game.save=Save.newGame();game.save.coins=3000
runner=Runner.new(game,{map={id='SPURGE_GAME_CORNER',def={label='SpurgeGameCorner'}}})
runner:run(assert(VM.compile(D,prize)))
T.check(not runner:isRunning(),'fresh ROM prize script reaches its exit')
T.eq(#game.save.party,1,'fresh ROM prize gives exactly one Pokemon')
T.eq(game.save.party[1].species,'SPECIES_133','fresh ROM prize grants Eevee')
T.eq(game.save.coins,0,'fresh ROM prize actually takes 3000 coins')
C.show_text,C.ask,C.g2_verticalmenu,C.g2_yesno=originalShow,originalAsk,originalMenu,originalYes
D.map_scripts=oldScripts;game.save=Save.newGame();ctx.save=game.save
local built=e:gen2CustomArgsCommand('45 3 0 1 0 0')
T.eq(built.command,'givepoke','ordinary orphanage gift blob decodes without absent OT pointers')
T.eq(#built.args,4,'four ordinary gift operands')
local offers={{152,10,100,64},{133,15,250,65},{175,15,500,66},{213,15,1000,67}}
local bytes={};for _,o in ipairs(offers)do for _,n in ipairs({o[1],o[2],o[3]%256,math.floor(o[3]/256),o[4],0})do bytes[#bytes+1]=n end end
ctx.save.g2OrphanPoints=2000
for i,o in ipairs(offers)do
 ctx.g2Var=i-1;C.g2_loadarray(ctx,{size=6,bytes=bytes})
 C.g2_readarrayhalfword(ctx,4);C.g2_halfword_event(ctx,'check');T.eq(ctx.g2Var,0,'adoption initially available '..i)
 C.g2_readarrayhalfword(ctx,2);C.g2_check_orphan_points(ctx,65535);T.check(ctx.g2Var~=2,'actual halfword price affordable '..i)
 C.g2_cmd_array_args(ctx,built)
 local mon=ctx.save.party[i];T.eq(mon.species,('SPECIES_%03d'):format(o[1]),'adopted species '..i);T.eq(mon.level,o[2],'adopted level '..i)
 T.eq(ctx.g2Var,0,'party gift returns native zero '..i)
 C.g2_readarrayhalfword(ctx,4);C.g2_halfword_event(ctx,'set');C.g2_halfword_event(ctx,'check');T.eq(ctx.g2Var,1,'individual adoption becomes unavailable '..i)
 C.g2_readarrayhalfword(ctx,2);C.g2_take_orphan_points(ctx,65535)
end
T.eq(ctx.save.g2OrphanPoints,150,'all four exact prices deducted')
local Pokemon=require('src.pokemon.Pokemon')
while #ctx.save.party<6 do ctx.save.party[#ctx.save.party+1]=Pokemon.new(D,'SPECIES_152',10) end
ctx.g2Var=133;C.g2_give_poke(ctx,0,20,0)
T.eq(ctx.g2Var,1,'full party gift returns native boxed result')
local boxed=0;for _,box in ipairs(ctx.save.boxes)do for _,mon in ipairs(box)do if mon.species=='SPECIES_133' then boxed=boxed+1 end end end
T.eq(boxed,1,'gift deposited into PC exactly once')
local Boxes=require('src.pokemon.Boxes');local current=Boxes.ensure(ctx.save)[ctx.save.currentBox]
while #current<Boxes.capacity()do current[#current+1]=Pokemon.new(D,'SPECIES_152',10)end
ctx.g2Var=133;C.g2_give_poke(ctx,0,20,0)
T.eq(ctx.g2Var,2,'full active Gen2 box refuses a gift')
T.eq(#ctx.save.boxes[2],0,'Gen2 gift cannot silently switch to another box')
game.save=Save.newGame();ctx.save=game.save;ctx.save.coins=3000;ctx.g2Var=133
C.g2_give_poke(ctx,0,20,0);C.g2_give_coins(ctx,-3000)
T.eq(ctx.save.party[1].species,'SPECIES_133','Game Corner variable species resolved');T.eq(ctx.save.coins,0,'prize cost deducted')
ctx.save.party[1].happiness=211;C.g2_first_happiness(ctx)
T.eq(ctx.g2Var,211,'happiness special returns actual value')
local shown
local TB=require('src.render.TextBox');local old=TB.new
TB.new=function(_,text)return {text=text}end
game.stack.push=function(_,screen)shown=screen.text end
ctx.runner={yield=function()end,resume=function()end}
C.show_text(ctx,'Your {RAM:wStringBuffer3} scored {RAM:hScriptVar}/255.')
T.check(shown:find('211/255',1,true)~=nil,'happiness number substituted before drawing')
T.check(not shown:find('{RAM:',1,true),'no raw text tokens remain')
TB.new=old;ctx.runner=nil
local trees=e:gen2FruitTrees();T.eq(#trees,29,'all apricorn and berry rows extracted')
D.field.gen2FruitTrees=trees
local originalText=C.show_text;C.show_text=function()end
for tree=19,29 do
 local item=trees[tree];local before=(ctx.save.inventory[item] or 0)
 C.g2_fruittree(ctx,tree);T.eq(ctx.save.inventory[item],before+1,'berry tree grants item '..tree)
 C.g2_fruittree(ctx,tree);T.eq(ctx.save.inventory[item],before+1,'tree cannot be harvested twice '..tree)
end
C.show_text=originalText
-- Use the ROM's name-rater dialogue and actual command workflow.
for key,label in pairs({Hello='intro_text',WhichMon='select_mon_text',BetterName='offer_name_change_text',WhatName='ask_new_name_text',Named='confirm_new_name_text',Finished='after_renaming_text',SameName='same_name_text',Egg='egg_text',PerfectName='traded_text',ComeAgain='cancel_text'})do
 local s=assert(e:symbol('NameRater.'..label));D.text['_NameRater'..key..'Text']=e:decodeGen2TextAt(s.bank,s.address,D.charmap,true)
end
local texts={};TB.new=function(_,text)return {text=text}end
local Screens=require('src.ui.Screens');local push=Screens.push
Screens.push=function(_,id,opts) if id=='PartyMenu' then opts.onSwitch(ctx.save.party[1]) end end
local Naming=require('src.ui.NamingScreen');local namingNew=Naming.new
Naming.new=function(_,opts)return {naming=opts}end
game.stack.push=function(_,screen) if screen.naming then screen.naming.onDone('SUNNY') else texts[#texts+1]=screen.text end end
local ask=C.ask;C.ask=function(c,text)C.show_text(c,text);c.lastCheck=true end
ctx.runner={yield=function()end,resume=function()end};ctx.save.party[1].nickname='BUD'
game.stringBuffers[1]='STALE';C.g2_name_rater(ctx)
T.eq(ctx.save.party[1].nickname,'SUNNY','name-rater workflow actually renames the selected Pokemon')
T.eq(game.stringBuffers[1],'SUNNY','name-rater updates the named buffer')
for _,text in ipairs(texts)do T.check(not text:find('{RAM:',1,true),'ROM name-rater dialogue has no unresolved buffer') end
C.ask=ask;TB.new=old;Screens.push=push;Naming.new=namingNew;ctx.runner=nil
local dist=e:symbol('MemoryGame_GetDistributionOfTiles.distributions');local reward=e:symbol('GameCornerMemoryGame.items')
D.field.gen2MemoryGame={distributions={e.rom:bytes(dist.bank,dist.address,8)},rewards=e.rom:bytes(reward.bank,reward.address,8),image='unused.png'}
local Screen=require('src.ui.PrismMemoryGame');game.input={wasPressed=function(_,key)return key=='a'end};game.save.coins=100
local finished;local s=Screen.new(game,function(m)finished=m end)
T.eq(#s.cards,45,'ROM board has 45 cards');s:update(0);T.eq(game.save.coins,75,'25 coins charged once')
s:update(0);T.eq(game.save.coins,75,'playing does not charge a second entry fee')
for turn=1,5 do
 local a,b
 for i=1,45 do if not s.removed[i] then for j=i+1,45 do if not s.removed[j] and s.cards[i]==s.cards[j] then a,b=i,j;break end end end;if a then break end end
 s:pick(a);s:pick(a);T.eq(s.second,nil,'same card cannot pair with itself')
 s:pick(b);s:update(2);T.eq(#s.matches,turn,'matching cards produce reward '..turn)
end
T.eq(s.stage,'reveal','five attempts end the round');s:update(0);T.eq(#finished,5,'matched rewards returned to script')
ctx.g2MemoryMatches={1,8};C.g2_memory_reward_next(ctx);T.eq(ctx.g2Var,D.field.gen2MemoryGame.rewards[1],'first ROM item reward');C.g2_memory_reward_next(ctx);T.eq(ctx.g2Var,D.field.gen2MemoryGame.rewards[8],'second ROM item reward');C.g2_memory_reward_next(ctx);T.eq(ctx.g2Var,0,'reward loop terminates')
T.finish()
