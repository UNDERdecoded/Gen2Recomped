package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Emerald reported issues")
local root = "G:/Gen2Recomped/emerald/data/generated/"
local data = {}
for _, key in ipairs({"constants","pokemon","moves","items","maps","tilesets","map_tilesets"}) do
  data[key] = assert(loadfile(root .. key .. ".lua"))()
end
require("src.core.GameVersion").set("emerald")
require("src.pokemon.Growth").setTables(data.constants.experienceTables)
local Pokemon = require("src.pokemon.Pokemon")
local Evolution = require("src.pokemon.Evolution")
local Stats = require("src.pokemon.Stats")
local Commands = require("src.script.Gen3Commands")
local SB = require("src.world.Gen3SecretBase")
local Battle = require("src.battle.BattleState")
local Experience = require("src.battle.Experience")
local function game()
  return {data=data,save={party={},inventory={},flags={},player={name="BRENDAN"},pokedex={seen={},owned={}}},
    stack={states={},push=function(_,s) if s.onDone then s.onDone() end end,pop=function() end}}
end
local g = game()
g.save.gen3SecretBase = {id=0,map="MAP_G00_N09"}
T.eq(SB.mine(g.save),nil,"zero ID is no base")
local mapId, sign
for id,def in pairs(data.maps) do
  for _, row in ipairs(def.signs or {}) do
    if row.secretBaseId then mapId,sign=id,row;break end
  end
  if sign then break end
end
-- The specials must retain the entrance ID after party selection overwrites 8004.
local record = data.constants.gen3SecretBases
local chosen = 10
local def = data.maps["MAP_G00_N22"] or {regionMapSection=32}
local ctx={game=g,save=g.save,overworld={map={id="MAP_G00_N22",def=def,
  cellBehaviour=function() return 0x90 end},player={cellX=4,cellY=5,facingCell=function() return 4,4 end}}}
Commands.setVar(g.save,0x8004,chosen)
Commands.SPECIALS[21](ctx)
Commands.setVar(g.save,0x8004,0)
Commands.SPECIALS[6](ctx)
T.eq(SB.mine(g.save).id,chosen,"party slot does not replace entrance ID")
T.eq(Commands.getVar(g.save,0x4026),def.regionMapSection,"base route is saved")
Commands.SPECIALS[281](ctx)
T.eq(g.stringBuffers[1],data.constants.gen3MapSections[def.regionMapSection],"nearby route text")
SB.giveUp(g.save);Commands.setVar(g.save,0x8004,20);Commands.SPECIALS[21](ctx)
Commands.setVar(g.save,0x8004,2);Commands.SPECIALS[6](ctx)
T.eq(SB.mine(g.save).id,20,"moving base selects new entrance")
T.check(SB.roomFor(record,20)~=nil,"new entrance resolves native room")
-- Run the actual extracted creation/relocation script, accepting its prompts.
data.map_scripts=assert(loadfile(root.."map_scripts.lua"))()
data.text=assert(loadfile(root.."text.lua"))()
local ScriptRunner=require("src.script.ScriptRunner")
local rows=require("src.script.Gen3ScriptVM").compile(data,record.script)
for _, previous in ipairs({0,10,20}) do
  g=game()
  g.save.party={Pokemon.new(data,"MUDKIP",15)}
  g.save.party[1].moves={{id="SECRET_POWER",pp=20}}
  if previous>0 then SB.claim(g.save,previous,"MAP_G00_N22",4,5) end
  local pending, warps, prompts = {}, {}, 0
  g.stack.push=function(_,screen) pending[#pending+1]=screen end
  local ow={map={id="MAP_G00_N22",def=def,cellBehaviour=function() return 0x90 end},
    player={cellX=4,cellY=5,facing="up",facingCell=function() return 4,4 end}}
  ow.startWarpTo=function(_,id,x,y,facing,done)
    warps[#warps+1]={map=id,x=x,y=y};pending[#pending+1]={onDone=done}
  end
  Commands.setVar(g.save,0x8004,30)
  local runner=ScriptRunner.new(g,ow)
  runner:run(rows)
  local ticks=0
  while runner:isRunning() and ticks<1000 do
    ticks=ticks+1
    local screen=table.remove(pending,1)
    if screen then
      if screen.choice then prompts=prompts+1;screen.choice(true)
      elseif screen.onDone then screen.onDone() end
    end
    if ow.fadeOverlay then ow.fadeOverlay:update(1/60) end
    runner:update()
  end
  if ticks>=1000 then print("parked",runner.lastRow,runner.waitingFrames,runner.waitingCheck) end
  T.check(ticks<1000,"Secret Power script terminates, previous "..previous)
  T.eq(SB.mine(g.save) and SB.mine(g.save).id,30,"script creates requested base, previous "..previous)
  T.check(#warps>0,"creation warps into base, previous "..previous)
  T.eq(warps[1] and warps[1].map,SB.roomFor(record,30).map,"native base room")
  T.check(prompts>0,"creation asks for confirmation")
end
for count=1,6 do
  g=game()
  local mon=Pokemon.new(data,"NINCADA",20)
  mon.item="ORAN_BERRY";mon.markings=7;mon.ribbons={champion=true};mon.status="poison"
  g.save.party[1]=mon
  for i=2,count do g.save.party[i]=Pokemon.new(data,"RALTS",4) end
  Evolution.apply(g,mon,"NINJASK","LEVEL")
  T.eq(mon.stats.hp,Stats.calcGen3(data.pokemon.NINJASK,20,mon.ivs,mon.evs,mon.nature).hp,"evolved IV stats")
  -- The queued move text completes immediately in this headless stack.
  Evolution.learnEvolutionMoves(g,mon)
  T.eq(#g.save.party,count<6 and count+1 or 6,"Shedinja party capacity "..count)
  if count<6 then
    local extra=g.save.party[count+1]
    T.eq(extra.species,"SHEDINJA","bonus species")
    T.eq(extra.hp,1,"Shedinja fixed HP")
    T.eq(extra.item,nil,"does not copy held item")
    T.eq(extra.status,nil,"healthy Shedinja")
    T.eq(extra.personality,mon.personality,"personality copied")
    T.eq(extra.moves[#extra.moves].id,mon.moves[#mon.moves].id,"post-evolution moves copied")
    T.check(extra.ivs~=mon.ivs and extra.moves~=mon.moves,"independent copied tables")
    T.check(g.save.pokedex.owned.SHEDINJA,"dex registered")
    T.eq(g.save.inventory.POKE_BALL,nil,"Emerald needs no spare ball")
    Evolution.learnEvolutionMoves(g,mon)
    T.eq(#g.save.party,count+1,"no duplicate after move callback")
  end
end
local Collision=require("src.world.Collision")
local map={inBounds=function() return true end,isWalkableCell=function() return true end,
  runningBlockedAt=function() return true end}
local p={cellX=0,cellY=0,onBike=true}
local can,why=Collision.canMove(map,{},p,"right")
T.eq(can,false,"bike cannot enter long grass")
p.onBike=false
T.check(Collision.canMove(map,{},p,"right"),"walking can enter long grass")
-- Find real long-grass cells and exercise the production map behavior lookup.
local Map=require("src.world.Map")
local checkedGrass=0
for id,mapDef in pairs(data.maps) do
  local ts=data.tilesets[mapDef.tileset]
  if ts and ts.behaviourBytes and ts.noRunBehaviours then
    local real=Map.new(mapDef,ts)
    for y=0,mapDef.height-1 do for x=1,mapDef.width-1 do
      if real:cellBehaviour(x,y)==3 and real:isWalkableCell(x,y) then
        local rider={cellX=x-1,cellY=y,onBike=true}
        T.eq(Collision.canMove(real,{},rider,"right"),false,"native long grass blocks bike")
        rider.onBike=false
        T.check(Collision.canMove(real,{},rider,"right"),"native long grass allows walker")
        checkedGrass=checkedGrass+1
        if checkedGrass>=20 then break end
      end
    end if checkedGrass>=20 then break end end
  end
  if checkedGrass>=20 then break end
end
T.check(checkedGrass>0,"real Emerald long grass found")
g=game();g.save.party={Pokemon.new(data,"RALTS",4),Pokemon.new(data,"MUDKIP",10)}
local b=setmetatable({game=g,data=data,participants={},sides={{battlers={}}},
  player={mon=g.save.party[1]},kind="wild"},Battle)
-- Intro has not called syncSides yet. It must record the initial lead.
b:markParticipant();T.check(b.participants[g.save.party[1]],"lead counted before side initialization")
b.player={mon=g.save.party[2]};b:markParticipant()
T.check(b.participants[g.save.party[2]],"switch-in counted")
local count=0;for _ in pairs(b.participants) do count=count+1 end
T.eq(count,2,"two EXP participants")
local before1,before2=g.save.party[1].exp,g.save.party[2].exp
b.enemy={mon={level=5},def=data.pokemon.POOCHYENA}
b.sayNext=function() end;b.expBarNext=function() end;b.drainNext=function() end
b:awardExp()
local expected=math.floor(math.floor(data.pokemon.POOCHYENA.baseExp*5/7)/2)
T.eq(g.save.party[1].exp-before1,expected,"switched-out Ralts gains half EXP")
T.eq(g.save.party[2].exp-before2,expected,"finishing Mudkip gains half EXP")
for level=1,30 do for split=1,6 do
  local foe=data.pokemon.POOCHYENA
  T.eq(Experience.gainFor(foe,level,false,split,false,data.constants),
    math.max(1,math.floor(math.floor(foe.baseExp*level/7)/split)),"Emerald EXP arithmetic")
end end
local Naming=require("src.ui.NamingScreen")
g=game();local pressed,completed
g.input={wasPressed=function(_,key) return key==pressed end}
local naming=Naming.new(g,{title="NICKNAME?",maxLen=10,kind="mon",species="MUDKIP",
  onDone=function(name) completed=name end})
local function key(k) pressed=k;naming:update(1/60);pressed=nil end
for row=1,4 do
  naming.row,naming.col=row,8;key("right")
  T.eq(naming.row,({5,6,6,7})[row],"right enters native button column "..row)
  key("left");T.eq(naming.col,8,"left leaves button column at final key")
end
naming.row,naming.col=1,1;key("up");T.eq(naming.row,4,"key column wraps upwards")
naming.row,naming.col=5,1;key("up");T.eq(naming.row,7,"button column wraps upwards")
naming.row,naming.col=1,1;key("a");T.eq(naming.glyphs[1],"A","native letter inserts")
key("select");T.eq(naming.pages[naming.page].name,"lower","SELECT cycles lower")
key("select");T.eq(naming.pages[naming.page].name,"symbols","SELECT cycles symbols")
key("select");T.eq(naming.pages[naming.page].name,"upper","SELECT cycles upper")
naming.row,naming.col=6,1;key("a");T.eq(#naming.glyphs,0,"BACK deletes")
naming.row,naming.col=1,1;key("a");key("start")
T.eq(naming.row,7,"START selects OK");T.eq(completed,nil,"START does not confirm")
key("a");T.eq(completed,"A","OK completes nickname")
T.finish()
