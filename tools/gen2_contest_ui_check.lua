love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen 2 contest UI functionality")
local Version=require("src.core.GameVersion")
local Battle=require("src.battle.BattleState")
local Start=require("src.ui.StartMenu")
local Contest=require("src.world.BugContest")
local Font=require("src.render.Font")
local Comparison=require("src.ui.Gen2ContestComparison")
require("src.render.Renderer").WIDTH=160
require("src.render.Renderer").HEIGHT=144
local text,boxes={},{ }
Font.draw=function(s,x,y) text[#text+1]={s,x,y} end
Font.drawBox=function(x,y,w,h) boxes[#boxes+1]={x,y,w,h} end
Font.drawCode=function() end
local function has(s,x,y)
  for _,r in ipairs(text) do if r[1]==s and r[2]==x and r[3]==y then return true end end
  return false
end
for _,version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local pokemon=assert(loadfile("G:/Gen2Recomped/"..version.."/data/generated/pokemon.lua"))()
  local key,pops,pushed,exits=nil,0,nil,0
  local game={data={pokemon=pokemon,field={}},save={party={{hp=20}},player={name="GOLD"},
    flags={EVENT_GOT_POKEGEAR=true},g2BugContest={active=true,balls=7}},
    input={wasPressed=function(_,k) return key==k end},
    stack={pop=function() pops=pops+1 end,push=function(_,s) pushed=s end},
    overworld={bugContestReturnToGate=function() exits=exits+1 end}}
  local menu=Start.new(game)
  local labels={"POKéMON","POKéGEAR","GOLD","QUIT","OPTION","EXIT"}
  T.eq(#menu.items,#labels,"native contest menu has no PACK SAVE or LINK")
  for i,label in ipairs(labels) do T.eq(menu.items[i].label,label,"native menu order") end
  T.eq(menu.ty,2,"native lowered contest menu")
  text={};boxes={};menu:draw()
  T.eq(boxes[1][3],19,"status interior 17 plus borders")
  T.eq(boxes[1][4],7,"status interior 5 plus borders")
  T.eq(has("None",64,8),true,"empty catch species row")
  T.eq(has("LEVEL",8,24),false,"no level for empty catch")
  T.eq(has("7",64,40),true,"status ball count is left aligned")
  menu.items[4].onSelect()
  T.eq(type(pushed.choice),"function","QUIT creates a confirmation")
  pushed.choice(false)
  T.eq(exits,0,"NO returns to start menu without ending contest")
  menu.items[4].onSelect();pushed.choice(true)
  T.eq(exits,1,"YES queues native judging flow")
  exits=0
  local before=pops;menu.index=6;key="a";menu:update(1/60);key=nil
  T.eq(pops,before+1,"EXIT closes start menu")
  T.eq(Contest.active(game.save),true,"EXIT does not retire from contest")
  T.eq(exits,0,"EXIT queues no judging")
  for _,answer in ipairs({"yes","no","b"}) do
    local stock={species="SPECIES_123",nickname="CUSTOM",level=14,maxHp=42}
    local candidate={species="SPECIES_127",level=15,maxHp=45}
    Contest.setCaught(game.save,stock)
    local battle=setmetatable({game=game,queue={},enemy={mon=candidate,name="PINSIR"},
      restoreMimicked=function() end},Battle)
    Battle.storeContestMon(battle)
    T.eq(battle.queue[1].text,"You already caught\na SCYTHER.","stock message uses species name")
    T.eq(battle.queue[2].ui~=nil,true,"comparison replaces generic text pages")
    table.remove(battle.queue,1)
    local ui=table.remove(battle.queue,1).ui()
    battle.nextInsert=0
    text={};boxes={};ui:draw()
    T.eq(has("SCYTHER",8,16),true,"stock name in upper panel")
    T.eq(has("PINSIR",8,64),true,"new catch name in lower panel")
    T.eq(has(" 42",88,32),true,"stock HEALTH is max HP")
    T.eq(has(" 45",88,80),true,"candidate HEALTH is max HP")
    T.eq(ui.choice.tx,14,"native YES NO column")
    T.eq(ui.choice.th,5,"native YES NO border height")
    if answer=="no" then key="down";ui:update(1/60) end
    key=answer=="b" and "b" or "a";ui:update(1/60);key=nil
    T.eq(Contest.caught(game.save),stock,"choice does not commit before hold ends")
    for frame=1,15 do ui:update(1/60) end
    T.eq(Contest.caught(game.save),answer=="yes" and candidate or stock,"YES replaces, NO/B retain")
    if answer=="yes" then T.eq(table.remove(battle.queue,1).text,"Caught PINSIR!","native kept catch text") end
    T.eq(#battle.queue,1,"decline adds no invented release message")
    table.remove(battle.queue,1).fn()
    T.eq(battle.result,"caught","every answer finishes battle")
    T.eq(battle.afterQueue,"finish","no looping back into catch selection")
  end
  for balls=0,20 do
    game.save.g2BugContest.balls=balls;text={};boxes={}
    local battle=setmetatable({game=game,data=game.data,bugContest=true,phase="menu",menuIndex=3},Battle)
    battle:drawTextAreaInner()
    T.eq(has(("%02d"):format(balls),104,128),true,"battle counts use leading zeros")
    T.eq(has("PARKBALL×",32,128),true,"native multiplication glyph")
  end
end
T.finish()
