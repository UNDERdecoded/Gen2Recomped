package.path='./?.lua;'..package.path
local PartyMenu=require('src.ui.Gen4PartyMenu')
local Summary=require('src.ui.Gen4SummaryMenu')
local mon={species=387,item='OLD',moves={}}
local game={data={constants={gen=4,gen4Bag={pockets={ITEM=1}}},items={NEW={pocket='ITEM'},OLD={pocket='ITEM'}}},
  save={party={mon},inventory={NEW=1},bagOrder={'NEW'}}}
local menu=PartyMenu.new(game)
assert(menu:giveHeld(mon,'NEW'))
assert(mon.item=='NEW' and game.save.inventory.OLD==1 and game.save.inventory.NEW==nil)
game.save.inventory.NEW=1;game.save.bagOrder={'OLD','NEW'};mon.item='OLD'
-- A stack at the cartridge maximum must leave both items untouched.
game.save.inventory.OLD=999
assert(not menu:giveHeld(mon,'NEW'))
assert(mon.item=='OLD' and game.save.inventory.NEW==1 and game.save.inventory.OLD==999)
assert(not menu:giveHeld(mon,'MISSING'))
menu:runAction('item');assert(menu.itemMenu and menu.submenu==1)
local actions=menu:actions();assert(actions[1]=='give' and actions[2]=='take' and actions[3]=='cancel')
menu:runAction('cancel');assert(not menu.itemMenu and menu.submenu==1)
assert(Summary.INFO_WINDOWS[6][2]==120 and Summary.INFO_WINDOWS[6][4]==136)
assert(Summary.INFO_WINDOWS[7][2]==152 and Summary.INFO_WINDOWS[7][4]==168)
assert(Summary.SKILL_WINDOWS[1][4]==32 and Summary.SKILL_WINDOWS[2][6]=='right')
game.data.gen4_dex={orders={sinnoh={387,390,393},national={1,387}}}
game.save.pokedex={national=false}
local summary=Summary.new(game,mon)
assert(summary:dexNumber()==1,'Sinnoh number must replace national species ID')
mon.species=1;assert(summary:dexNumber()==nil,'outside the regional dex must show unknown')
game.save.pokedex.national=true;assert(summary:dexNumber()==1)
local other={species=387};game.save.party={mon,other}
local cries=0
package.loaded['src.core.Sound']={playCry=function(_,id) assert(id==387);cries=cries+1 end}
summary:changePokemon(1);assert(summary.mon==other and cries==1)
local first={id=33,pp=14,ppUps=2};local second={id=110,pp=3,ppUps=1}
summary.mon.moves={first,second};summary.moveMode=true;summary.moveIndex=1
summary:selectMove();assert(summary.swapMove==1)
summary.moveIndex=2;summary:selectMove()
assert(summary.mon.moves[1]==second and summary.mon.moves[2]==first,'PP and PP Ups must travel with the move slot')
summary.moveIndex=3;summary:selectMove();assert(not summary.swapMove,'empty slots cannot be selected')
summary.moveIndex=1;summary:selectMove();summary:backFromMove()
assert(summary.moveMode and not summary.swapMove,'B cancels the reorder before exiting details')
summary.moveIndex=5;summary:selectMove();assert(not summary.moveMode)
package.loaded['src.render.Renderer']={uiPresentation={x=10,y=20,w=512,h=384,scaleX=2,scaleY=2}}
for i,page in ipairs(summary.pages) do if page.key=='moves' then summary.page=i end end
summary:mousepressed(10+180*2,20+40*2,1)
assert(summary.moveMode and summary.moveIndex==1)
summary:touchpressed('finger',10+180*2,20+40*2)
assert(summary.swapMove==1)
summary:touchpressed('finger',10+180*2,20+72*2)
assert(not summary.swapMove and summary.mon.moves[1]==first)
game.data.text=assert(loadfile('G:/Gen2Recomped/platinum/data/generated/text.lua'))()
local keys={'hp','attack','defense','speed','spAttack','spDefense'}
for stat,key in ipairs(keys) do
  for remainder=0,4 do
    summary.mon.ivs={[key]=25+remainder};summary.mon.personality=0
    local lines=summary:memoLines();local found
    for _,line in ipairs(lines) do if line.y==120 then found=line.text end end
    assert(found==game.data.text[('TEXT_B0455_%05d'):format(71+(stat-1)*5+remainder)])
  end
end
summary.mon.ivs={hp=31,attack=31,defense=31,speed=31,spAttack=31,spDefense=31}
summary.mon.personality=3
local found
for _,line in ipairs(summary:memoLines()) do if line.y==120 then found=line.text end end
assert(found=='Alert to sounds.','personality chooses the first tied IV in cyclic stat order')
summary.moveMode=nil
local pressed='a'
game.input={wasPressed=function(_,key) return key==pressed end}
summary:update();assert(summary.moveMode and summary.moveIndex==1)
summary.readOnlyMoves=true;summary:selectMove();assert(not summary.swapMove)
pressed='b';summary:update();assert(not summary.moveMode)
-- before the Contest Hall (FLAG_CONTEST_HALL_VISITED) the contest pages are
-- skipped: MOVES -> EXIT
pressed='right';local before=summary.page;summary:update()
assert(summary.pages[summary.page].key=='exit' and #summary:visiblePages()==5)
summary.page=before;game.save.flags={FLAG_G4_0978=true}
summary:update()
assert(summary.page==before%#summary.pages+1)
summary.mon.ribbons={[0]=true,[32]=true,['32']=true,[53]=1,[900]=true,[1]=false}
local ribbons=summary:ribbonList()
assert(#ribbons==3 and ribbons[1]==0 and ribbons[2]==32 and ribbons[3]==53)
local R=require('src.ui.Gen4RibbonData')
assert(R[32].art=='summary/sinnoh_champion' and R[37].palette==1)
assert(game.data.text[('TEXT_B0535_%05d'):format(R[32].name)]=='Sinnoh Champ Ribbon')
summary.mon.contest={cool=255,beauty=0,cute=0,smart=0,tough=0,sheen=0}
local vertices=summary:conditionVertices()
assert(vertices[1]>180 and vertices[1]<182 and vertices[2]>56 and vertices[2]<59)
assert(vertices[4]>90 and vertices[4]<93,'zero beauty must stay near graph center')
local old=vertices[2];summary.mon.contest.cool=0
vertices=summary:conditionVertices();assert(vertices[2]>old+25)
for i,page in ipairs(summary.pages) do if page.key=='ribbons' then summary.page=i end end
summary:touchpressed('finger',10+132*2,20+56*2)
assert(summary.ribbonMode and summary.ribbonIndex==1)
pressed='right';summary:update();assert(summary.ribbonIndex==2)
pressed='b';summary:update();assert(not summary.ribbonMode)
print('Platinum menu checks passed: transactional held-item swaps, full/missing-item rejection, nested cancel and ROM summary windows')
summary.mon.hp=1
for status,index in pairs({PAR=1,FRZ=2,SLP=3,PSN=4,TOX=4,BRN=5}) do
 summary.mon.status=status;assert(summary:statusIndex()==index,status)
end
summary.mon.status=nil;assert(summary:statusIndex()==nil)
summary.mon.hp=0;summary.mon.status='PSN';assert(summary:statusIndex()==6,'fainting takes priority')
local closed=0
summary.close=function() closed=closed+1 end
pressed='a'
for i,page in ipairs(summary.pages) do
 if page.key=='info' or page.key=='memo' or page.key=='skills' or page.key=='condition' then
  summary.page=i;summary:update();assert(closed==0,'A must not close '..page.key)
 end
end
summary.mon.ribbons={}
for i,page in ipairs(summary.pages) do if page.key=='ribbons' then summary.page=i end end
summary:update();assert(not summary.ribbonMode,'empty ribbon list must not enter detail mode')
for i,page in ipairs(summary.pages) do if page.key=='exit' then summary.page=i end end
summary:update();assert(closed==1,'A on the Exit page must close')
pressed='b';summary.page=1;summary:update();assert(closed==2,'B must close ordinary pages')
local tabs=summary:pageTabs()
assert(tabs[1].width==24 and tabs[2].width==16)
-- x is the tab SPRITE's anchor (sprites.c UpdatePageTabSprites): eight
-- visible pages put the first at 188 - (24 + 7*16)/2 = 120; the cells reach
-- 8 left of their anchor, so the strip ends at the last anchor + 8
assert(#tabs==8 and tabs[1].x==120 and tabs[#tabs].x+8==248,'tabs must sit where CalcPageTabsBaseXPos puts them')
summary:touchpressed('finger',10+(tabs[2].x+4)*2,20+24*2)
assert(summary.page==2,'touch must select the displayed tab through presentation scaling')
summary:mousepressed(10+(tabs[3].x+4)*2,20+24*2,1)
assert(summary.page==3,'mouse must select the displayed tab')
local egg={species=387,isEgg=true,eggCycles=5,ivs={hp=31},personality=3}
local eggSummary=Summary.new(game,egg)
assert(eggSummary.pages[eggSummary.page].key=='memo')
assert(#eggSummary:pageTabs()==2,'eggs only have Memo and Exit tabs')
eggSummary:changePage(1);assert(eggSummary.pages[eggSummary.page].key=='exit')
eggSummary:changePage(1);assert(eggSummary.pages[eggSummary.page].key=='memo')
for _,test in ipairs({{5,105},{6,106},{10,106},{11,107},{40,107},{41,108}}) do
 egg.eggCycles=test[1]
 local lines=eggSummary:memoLines()
 assert(#lines==4 and lines[1].text=='“The Egg Watch”')
 assert(lines[4].text==game.data.text[('TEXT_B0455_%05d'):format(test[2])]:match('([^\n]+)$'))
end
game.data.gen4_species_sprites={forms={
 ['000_egg_base']={front='ordinary-egg'},['000_egg_manaphy']={front='manaphy-egg'}}}
eggSummary.image=function(_,path) return path end
local art,flip=eggSummary:pictureArt();assert(art=='ordinary-egg' and not flip)
egg.species=490;art,flip=eggSummary:pictureArt();assert(art=='manaphy-egg' and not flip)
egg.eggLocation='T01';egg.eggDate={year=2026,month=10,day=1}
game.data.maps={T01={name='Twinleaf Town'}}
local originLines=eggSummary:memoLines()
assert(originLines[1].text=='Oct. 1, 2026')
assert(originLines[4].text=='Twinleaf Town.')
for _,line in ipairs(originLines) do assert(not line.text:find('{STRVAR',1,true),'unresolved egg memo placeholder') end
summary.mon.metDate={year=26,month=10,day=1}
local sawDate=false
for _,line in ipairs(summary:memoLines()) do if line.y==56 then sawDate=line.text=='Oct. 1, 2026' end end
assert(sawDate,'normal memo date must use the ROM date template')
game.save.player={id=123};summary.mon.otId=456;summary.mon.metLevel=5
local function memoText()
 local text={}
 for _,line in ipairs(summary:memoLines()) do
  assert(line.y<192 and not line.text:find('{STRVAR',1,true),'memo overflow or unresolved placeholder')
  text[#text+1]=line.text
 end
 return table.concat(text,'\n')
end
assert(memoText():find('Apparently met at\nLv. 5.',1,true))
summary.mon.fatefulEncounter=true
assert(memoText():find('Apparently had a\nfateful encounter at\nLv. 5.',1,true))
summary.mon.otId=123
assert(memoText():find('Had a fateful encounter\nat Lv. 5.',1,true))
summary.mon.hatched=true;summary.mon.eggDate={year=26,month=9,day=30}
summary.mon.eggLocation='Day-Care Couple';summary.mon.metLocation='Route 209';summary.mon.metLevel=0
local history=memoText()
assert(history:find('Sep. 30, 2026',1,true) and history:find('Egg hatched.',1,true))
assert(history:find('Fateful encounter.',1,true) and not history:find('Met at Lv. 0.',1,true))
