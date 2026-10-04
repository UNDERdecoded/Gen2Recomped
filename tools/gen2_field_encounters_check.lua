love = require("tests.love_stub")
local T = require("tests.harness").suite("Gen 2 field encounters")
local Version = require("src.core.GameVersion")
local Commands = require("src.script.Commands")
require("src.script.Gen2Commands")
local VM = require("src.script.Gen2ScriptVM")
local Runner = require("src.script.ScriptRunner")
local Encounter = require("src.world.Encounter")
-- Ordinary walking still checks rate before choosing a slot in all formats.
for _,span in ipairs({100,180,256}) do
  local tableDef={rate=10,rateMax=span,bucketSpan=span,buckets={span},
    slots={{species="SPECIES_001",level=5}}}
  for roll=0,span-1 do
    local n=0
    local function random() n=n+1;return n==1 and roll or 0 end
    local mon=Encounter.rollTable(tableDef,random)
    T.eq(mon~=nil,roll<10,"walking rate retained across table formats")
    T.eq(n,roll<10 and 2 or 1,"walking rolls slot only after rate success")
    n=0;mon=Encounter.rollTable(tableDef,random,{2,1},5)
    T.eq(mon~=nil,roll<10,"rate override applied before modifier")
  end
end
local OW = require("src.world.OverworldController")
local Game = require("src.core.Game")
local Battle = require("src.battle.BattleState")
require("src.render.TextBox").new = function(_, text, done) return {text=text,onDone=done} end
for _, fn in ipairs({OW.gen2SweetScent, OW.gen2SweetScentEncounter}) do
  for i=1,30 do
    local name = debug.getupvalue(fn,i)
    if not name then break end
    if name=="Game" then debug.setupvalue(fn,i,Game) end
  end
end
Battle.newWild = function(_, species, level)
  return {species=species,level=level,makeBugContest=function(self) self.contest=true end}
end
local function read(path)
  local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s
end
local files={gold="Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 silver="Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 crystal="Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"}
local rng=math.random
local calls,starts=0,0
Commands.start_battle=function(ctx, kind, species, level)
  starts=starts+1;ctx.lastBattleResult="win"
  T.eq(kind,"wild","rock script starts wild battle")
  T.eq(species,ctx.expected.species,"script forwards selected species")
  T.eq(level,ctx.expected.level,"script forwards selected level")
end
-- UI/rock destruction acknowledged; VM control flow and WRAM use stay real.
for _, verb in ipairs({"show_text","g2_move","g2_hide_object","g2_earthquake",
  "g2_party_nickname","g2_reload_map_after_battle","play_sound","wait"}) do
  Commands[verb]=function() end
end
local resolve=Commands.resolve
Commands.resolve=function(...)
  calls=calls+1;assert(calls<150,"rock script loop")
  return resolve(...)
end
for _, version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local manifest=require("src.link.Json").decode(read("tools/rom_manifest_"..version..".json"))
  local ex=require("src.import.RomExtractorGen2").new(read(files[version]),version,manifest)
  local trees=assert(ex:gen2TreeMons())
  local sets=ex:symbol("TreeMons")
  local maxSet=version=="crystal" and 7 or 3
  T.eq(#trees.sets,maxSet,version.." own supported set count")
  for set=1,maxSet do
    local at=ex.rom:word(sets.bank,sets.address+set*2)
    for _,kind in ipairs({"common","rare"}) do
      if not (set==maxSet and kind=="rare") then
        local rows=trees.sets[set][kind]
        for _,row in ipairs(rows) do
          T.eq(row.chance,ex.rom:byte(sets.bank,at),"tree chance matches ROM")
          T.eq(row.species,string.format("SPECIES_%03d",ex.rom:byte(sets.bank,at+1)),"version-specific tree species")
          T.eq(row.level,ex.rom:byte(sets.bank,at+2),"tree level matches ROM")
          at=at+3
        end
        T.eq(ex.rom:byte(sets.bank,at),255,"tree table stops at terminator")
        at=at+1
      end
    end
  end
  local index=ex:gen2MapIndex()
  local sym=assert(ex:symbol("RockMonMaps"))
  local n=0
  for at=sym.address,sym.address+192,3 do
    local group=ex.rom:byte(sym.bank,at);if group==255 then break end
    local entry=assert(index[group*256+ex.rom:byte(sym.bank,at+1)])
    T.eq(trees.rockMaps[entry.label],ex.rom:byte(sym.bank,at+2),version.." rock map/set from ROM")
    n=n+1
  end
  local count=0;for _ in pairs(trees.rockMaps) do count=count+1 end
  T.eq(count,n,version.." no extra rock maps")
  T.eq(trees.wildSpeciesAddress,ex:symbol("wTempWildMonSpecies").address,version.." WRAM address")
  local root=(arg[1] or "G:/Gen2Recomped").."/"..version.."/data/generated/"
  local data={field={gen2TreeMons=trees},text={}}
  data.map_scripts=assert(loadfile(root.."map_scripts.lua"))()
  local entry
  for label,rows in pairs(data.map_scripts.scripts) do
    for _,row in ipairs(rows) do
      if row[1]=="callasm" and row[2]=="RockMonEncounter" then entry=label end
    end
  end
  local script=assert(VM.compile(data,assert(entry)))
  local found=false
  for _,row in ipairs(script) do if row[1]=="g2_rock_encounter" then found=true end end
  T.eq(found,true,version.." actual rock bytecode lowers encounter")
  local label,set=next(trees.rockMaps)
  local rows=trees.sets[set].common
  for rateRoll=0,9 do
    for slotRoll=0,99 do
      local expected
      if rateRoll<4 then
        local pick=slotRoll
        for _,row in ipairs(rows) do pick=pick-row.chance;if pick<0 then expected=row;break end end
      end
      math.random=function(lo,hi) return hi==9 and rateRoll or slotRoll end
      local game={data=data,save={flags={},g2Wram={[trees.wildSpeciesAddress]=99}},stack={push=function() end}}
      local ow={map={def={label=label}},player={}}
      local runner=Runner.new(game,ow)
      -- Run the production command then the ROM tail from callasm onward.
      local ctx={game=game,save=game.save,overworld=ow,g2Wild={species="STALE"},g2Trainer={}}
      T.eq(Commands.g2_rock_encounter(ctx),nil,"encounter cannot jump script")
      T.eq(ctx.g2Wild and ctx.g2Wild.species,expected and expected.species,"40% rate/weighted slot")
      T.eq(ctx.g2Trainer,nil,"clears stale trainer")
      Commands.g2_readmem(ctx,trees.wildSpeciesAddress)
      T.eq(ctx.lastCheck,expected~=nil,"readmem branches on fresh species byte")
      local tail={};local active=false
      for _,row in ipairs(script) do
        if row[1]=="g2_rock_encounter" then active=true end
        if active then tail[#tail+1]=row end
      end
      starts,calls=0,0
      game.expected=expected
      -- Runner exposes its context to commands; supply expected there.
      local start=Commands.start_battle
      Commands.start_battle=function(c,... ) c.expected=expected;return start(c,...) end
      runner:run(tail)
      Commands.start_battle=start
      T.eq(runner:isRunning(),false,"ROM rock tail terminates")
      T.eq(starts,expected and 1 or 0,"ROM starts exactly one battle or none")
    end
  end
  math.random=function() error("unlisted rock map must not roll") end
  local game={data=data,save={}}
  local ctx={game=game,save=game.save,overworld={map={def={label="UNLISTED"}}},g2Wild={}}
  Commands.g2_rock_encounter(ctx);T.eq(ctx.g2Wild,nil,"unlisted map cannot spawn rock mon")
  math.random=rng
  data.encounters=assert(loadfile(root.."encounters.lua"))()
  data.text=assert(loadfile(root.."text.lua"))()
  data.field.gen2BugContest=assert(ex:gen2BugContest())
  local id,encDef
  for key,value in pairs(data.encounters) do if value.grass and value.grass.rate>0 then id,encDef=key,value;break end end
  local grass,water,ice=true,false,false
  local tod="DAY"
  local ow={player={cellX=1,cellY=1},map={id=id,def={environment=2}},timeOfDay=function() return tod end,
    gen2IsIce=function() return ice end,gen2SweetScentEncounter=OW.gen2SweetScentEncounter,
    pushBattle=function(self,b) self.battle=b end}
  ow.map.isGrassCell=function() return grass end;ow.map.isWaterCell=function() return water end
  Game.data=data;Game.save={repelSteps=999,party={{heldItem="CLEANSE_TAG",level=100}}}
  local box;Game.stack={push=function(_,b) box=b end}
  love.math.random=function(lo,hi) T.eq(hi,255,"Sweet Scent rolls slot only");return hi end
  OW.gen2SweetScent(ow,{nickname="SCENT"})
  T.eq(ow.battle,nil,"used text precedes encounter")
  T.eq(type(box.onDone),"function","used text resumes field move")
  box.onDone()
  T.eq(ow.battle.species,Encounter.chooseTable(encDef.grass,function(_,hi)return hi end).species,"guaranteed last slot ignores walking rate/repel")
  for _,time in ipairs({"MORN","NITE"}) do
    tod=time;OW.gen2SweetScentEncounter(ow)
    T.eq(ow.battle.species,Encounter.chooseTable(Encounter.atTime(encDef.grass,time),function(_,hi)return hi end).species,"Sweet Scent selects current time table")
  end
  tod="DAY"
  for _,case in ipairs({{false,false,2},{true,true,2},{false,false,4},{false,true,4}}) do
    grass,ice,ow.map.def.environment=case[1],case[2],case[3];ow.battle=nil
    OW.gen2SweetScentEncounter(ow)
    T.eq(ow.battle~=nil,case[3]==4 and not ice,"grass/cave eligibility excludes road and ice")
  end
  grass,ice=true,false;ow.map.def.environment=2
  local rate=encDef.grass.rate;encDef.grass.rate=0;ow.battle=nil
  OW.gen2SweetScentEncounter(ow);T.eq(ow.battle,nil,"zero-rate map refuses Sweet Scent")
  encDef.grass.rate=rate
  ow.map.id="UNLISTED";ow.battle=nil
  OW.gen2SweetScentEncounter(ow);T.eq(ow.battle,nil,"no encounter table refuses safely")
  -- Surfing chooses water slots rather than the land table.
  data.encounters.TEST_WATER={grass=encDef.grass,water={rate=1,slots={{species="SPECIES_129",level=7}},buckets={256}}}
  ow.map.id="TEST_WATER";water=true;ow.player.surfing=true
  OW.gen2SweetScentEncounter(ow);T.eq(ow.battle.species,"SPECIES_129","surfing uses water table")
  water=false;ow.player.surfing=false
  grass,ice=true,false;ow.map.id=require("src.world.BugContest").contestMap()
  Game.save.g2BugContest={active=true}
  love.math.random=function() return 0 end
  OW.gen2SweetScentEncounter(ow)
  T.eq(ow.battle.contest,true,"Sweet Scent enters contest battle rules")
  T.eq(ow.battle.species,data.field.gen2BugContest.mons[1].species,"Sweet Scent uses contest table")
end
math.random=rng
T.finish()
