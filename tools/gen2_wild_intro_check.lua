love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen 2 wild sleep and intros")
local Version=require("src.core.GameVersion")
local Battle=require("src.battle.BattleState")
local Pokemon=require("src.pokemon.Pokemon")
local Game=require("src.core.Game")
local OW=require("src.world.OverworldController")
local function read(path)
  local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s
end
local files={gold="Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 silver="Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 crystal="Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"}
local cryCount=0
require("src.core.Sound").playCry=function() cryCount=cryCount+1 end
for _,version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local manifest=require("src.link.Json").decode(read("tools/rom_manifest_"..version..".json"))
  local ex=require("src.import.RomExtractorGen2").new(read(files[version]),version,manifest)
  local trees=assert(ex:gen2TreeMons())
  local root=(arg[1] or "G:/Gen2Recomped").."/"..version.."/data/generated/"
  local data={constants={gen=2},field={gen2TreeMons=trees},type_chart={matchups={},types={}}}
  for _,name in ipairs({"pokemon","moves","text"}) do data[name]=assert(loadfile(root..name..".lua"))() end
  local player=Pokemon.new(data,"SPECIES_152",10)
  local game={data=data,save={party={player},flags={},inventory={},pokedex={seen={},owned={}},player={name="GOLD"}}}
  local expected={}
  if version=="crystal" then
    for key,suffix in pairs({MORN="Morn",DAY="Day",NITE="Nite"}) do
      local sym=assert(ex:symbol("AsleepTreeMons"..suffix));expected[key]={}
      for offset=0,63 do
        local species=ex.rom:byte(sym.bank,sym.address+offset)
        if species==255 then break end
        expected[key][species]=true
      end
    end
  else
    -- Gold/Silver's direct comparisons, verified against the ROM operands.
    local sym=assert(ex:symbol("LoadEnemyMon.TreeMon"))
    local species={}
    for _,offset in ipairs({3,7,11,15}) do
      T.eq(ex.rom:byte(sym.bank,sym.address+offset),0xFE,"native species compare opcode")
      species[#species+1]=ex.rom:byte(sym.bank,sym.address+offset+1)
    end
    expected.MORN={[species[1]]=true,[species[2]]=true}
    expected.DAY={[species[1]]=true,[species[2]]=true}
    expected.NITE={[species[3]]=true,[species[4]]=true}
  end
  local sleepSym=assert(ex:symbol(version=="crystal" and "LoadEnemyMon.TreeMon" or "LoadEnemyMon.sleeping"))
  local sleepOffset=version=="crystal" and 3 or 0
  T.eq(ex.rom:byte(sleepSym.bank,sleepSym.address+sleepOffset),0x3E,"native sleep duration opcode")
  local duration=ex.rom:byte(sleepSym.bank,sleepSym.address+sleepOffset+1)
  T.eq(trees.sleepTurns,duration,"duration extracted from own cartridge")
  local asleepSpecies=next(expected.DAY)
  local sleepBattle=Battle.newWild(game,string.format("SPECIES_%03d",asleepSpecies),10,
    {tree=true,timeOfDay="DAY"})
  local Status=require("src.battle.Status")
  for turn=1,duration do
    local canMove=Status.beforeMove(sleepBattle.enemy,sleepBattle.rng,sleepBattle)
    T.eq(canMove,false,"initial sleep blocks each native counter turn")
    T.eq(sleepBattle.enemy.sleepTurns,duration-turn,"initial sleep decrements normally")
    local expectedStatus
    if turn<duration then expectedStatus="SLP" end
    T.eq(sleepBattle.enemy.mon.status,expectedStatus,"wakes only at native duration")
  end
  T.eq(Status.beforeMove(sleepBattle.enemy,sleepBattle.rng,sleepBattle),true,"can move after waking")
  for _,tod in ipairs({"MORN","DAY","NITE"}) do
    game.overworld={timeOfDay=function() return tod end}
    for _,tree in ipairs({false,true}) do
      for number=1,251 do
        local species=string.format("SPECIES_%03d",number)
        local battle=Battle.newWild(game,species,10,{tree=tree,timeOfDay=tod})
        local asleep=expected[tod][number] and (tree or version~="crystal") or false
        T.eq(battle.enemy.mon.status,asleep and "SLP" or nil,version.." sleep species/time/battle type")
        T.eq(battle.enemy.sleepTurns,asleep and duration or nil,"sleep counter initialized")
        local silent=asleep and tree and version=="crystal"
        cryCount=0;battle:playEnemyIntroCry()
        T.eq(cryCount,silent and 0 or 1,"native version-specific opening cry")
        if tree then
          local text=data.text.PokemonFellFromTreeText:gsub("{RAM:wEnemyMonNickname}",battle.enemy.name)
          T.eq(battle.introText,text,"tree introduction uses ROM text")
        end
      end
    end
    local hooked=Battle.newWild(game,"SPECIES_129",5,{hooked=true})
    T.eq(hooked.introText,data.text.HookedPokemonAttackedText:gsub("{RAM:wEnemyMonNickname}",hooked.enemy.name),"fishing uses native text label")
  end
  -- Production overworld Headbutt forwards encounter kind and current clock.
  for i=1,30 do
    local name=debug.getupvalue(OW.gen2Headbutt,i)
    if not name then break end
    if name=="Game" then debug.setupvalue(OW.gen2Headbutt,i,Game) end
  end
  Game.data,Game.save=data,game.save
  local label=next(trees.maps)
  local ow={map={def={label=label}},timeOfDay=function() return "NITE" end,
    startDustAnim=function(_,_,_,done) done() end,pushBattle=function(self,b) self.battle=b end}
  local newWild=Battle.newWild
  Battle.newWild=function(_,species,level,opts)
    T.eq(opts.tree,true,"Headbutt passes tree encounter")
    T.eq(opts.timeOfDay,"NITE","Headbutt passes current time")
    return {species=species,level=level}
  end
  local random=math.random;math.random=function() return 0 end
  OW.gen2Headbutt(ow,1,1)
  math.random=random;Battle.newWild=newWild
  T.eq(ow.battle~=nil,true,"Headbutt starts battle after tree animation")
end
-- Other generations never receive Gold/Silver's ordinary-wild sleep quirk.
for _,version in ipairs({"emerald","platinum"}) do
  Version.set(version)
  local battle={data={field={gen2TreeMons={sleeping={day={SPECIES_163=true}},sleepTurns=7}}},
    enemy={mon={species="SPECIES_163"}},game={save={}}}
  require("src.battle.Gen2Wild").initialize(battle,{tree=true,timeOfDay="DAY"})
  T.eq(battle.enemy.mon.status,nil,"Gen2 initialization excluded from other generations")
end
T.finish()
