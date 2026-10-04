love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen 2 friendship and medicines")
local Version=require("src.core.GameVersion")
local Friendship=require("src.pokemon.Gen2Friendship")
local Breeding=require("src.pokemon.Gen2Breeding")
local Items=require("src.inventory.ItemEffects")
local Pokemon=require("src.pokemon.Pokemon")
local Game=require("src.core.Game")
local OW=require("src.world.OverworldController")
local Battle=require("src.battle.BattleState")
local TextBox=require("src.render.TextBox")
TextBox.new=function(_,text,done) return {text=text,onDone=done} end
require("src.core.Sound").play=function() end
local function bind(fn)
  for i=1,30 do
    local name=debug.getupvalue(fn,i)
    if not name then break end
    if name=="Game" then debug.setupvalue(fn,i,Game) end
  end
end
bind(OW.stepEggs);bind(OW.applyFieldPoison)
local function read(path)
  local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s
end
local files={gold="Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 silver="Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 crystal="Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"}
local reasons={LEVELUP=1,VITAMIN=2,XITEM=3,GYMBATTLE=4,LEARNMOVE=5,
 FAINT=6,POISONFAINT=7,STRONGFOE=8,BITTERPOWDER=15,ENERGYROOT=16,REVIVALHERB=17}
for _,version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local manifest=require("src.link.Json").decode(read("tools/rom_manifest_"..version..".json"))
  local ex=require("src.import.RomExtractorGen2").new(read(files[version]),version,manifest)
  local symbol=assert(ex:symbol("HappinessChanges"))
  reasons.LEVELUPATHOME=version=="crystal" and 19 or nil
  local rows=ex.rom:bytes(symbol.bank,symbol.address,version=="crystal" and 57 or 54)
  for reason,index in pairs(reasons) do
    for h=0,255 do
      local band=h<100 and 1 or h<200 and 2 or 3
      local delta=rows[(index-1)*3+band];if delta>=128 then delta=delta-256 end
      local mon={happiness=h}
      Friendship.change(mon,reason)
      T.eq(mon.happiness,math.max(0,math.min(255,h+delta)),version.." "..reason.." uses ROM band/clamp")
      mon={happiness=h,isEgg=true};Friendship.change(mon,reason)
      T.eq(mon.happiness,h,version.." eggs excluded from "..reason)
    end
  end
  local root=(arg[1] or "G:/Gen2Recomped").."/"..version.."/data/generated/"
  local data={constants={gen=2}}
  for _,name in ipairs({"pokemon","moves","items","text"}) do data[name]=assert(loadfile(root..name..".lua"))() end
  require("src.core.Data").items=data.items;require("src.core.Data").moves=data.moves
  local function mon(h)
    local m=Pokemon.new(data,"SPECIES_152",5);m.happiness=h or 70;return m
  end
  local save={party={mon(70),mon(200),mon(255),{happiness=20,isEgg=true,eggSteps=999999}},
    player={name="GOLD",id=42},flags={}}
  Game.data,Game.save=data,save
  Game.stack={push=function() end}
  -- Production overworld entry point: first 256-cycle toggles only, the
  -- second gives exactly one point to every real mon, including fainted ones.
  save.party[2].hp=0
  for step=1,512 do
    T.eq(OW.stepEggs({}),false,version.." no premature hatch")
    T.eq(save.party[1].happiness,step==512 and 71 or 70,version.." +1 only on step 512")
    if step==300 then
      local serializer=require("src.core.SaveSerializer")
      save=assert(serializer.decode(serializer.encode(save)));Game.save=save
      T.eq(save.g2EggCycleStep,44,version.." shared step phase survives save/reload")
      T.eq(save.g2HappinessStepCount,1,version.." alternate cycle survives save/reload")
    end
  end
  T.eq(save.party[2].happiness,201,version.." fainted mon gains walking happiness")
  T.eq(save.party[3].happiness,255,version.." walking caps at 255")
  T.eq(save.party[4].happiness,20,version.." walking leaves egg counter separate")
  save.party[1]=mon(99);save.party[2]=mon(199);save.party[3]=mon(200)
  save.party[2].hp=0
  Friendship.gymBattle(save)
  T.eq(save.party[1].happiness,102,version.." healthy party Gym bonus")
  T.eq(save.party[2].happiness,199,version.." fainted party misses Gym bonus")
  T.eq(save.party[3].happiness,201,version.." high-band Gym bonus")
  for _,diff in ipairs({29,30,31}) do
    local m=mon(200);m.hp=0
    local battler={isPlayer=true,mon=m,name="CHIKORITA"}
    local battle={game=Game,enemy={mon={level=m.level+diff}},queue={},
      actNext=function() end,act=function() end,sayNext=function() end,isDouble=function() return false end}
    Battle.onFaint(battle,battler)
    T.eq(m.happiness,diff<30 and 199 or 190,version.." battle faint level boundary")
    Battle.onFaint(battle,battler)
    T.eq(m.happiness,diff<30 and 199 or 190,version.." queued faint penalizes once")
  end
  local poison=mon(200);poison.hp=1;poison.status="PSN"
  save.party={poison,mon(70)}
  save.poisonSteps=3
  OW.applyFieldPoison({})
  T.eq(poison.hp,0,version.." field poison faints")
  T.eq(poison.status,nil,version.." field poison clears status")
  T.eq(poison.happiness,190,version.." field poison penalty reaches Gen 2 mon")
  local byKey={};for id,def in pairs(data.items) do byKey[def.key]=id end
  local function use(key,target,battle)
    return Items.use(data,save,assert(byKey[key],key),target,battle)
  end
  local m=mon(99)
  T.eq(use("PROTEIN",m),"consumed",version.." vitamin succeeds")
  T.eq(m.happiness,104,version.." successful vitamin adds happiness")
  m.statExp.attack=25600
  T.eq(use("PROTEIN",m),"failed",version.." capped vitamin refused")
  T.eq(m.happiness,104,version.." capped vitamin no friendship")
  m=mon(99)
  T.eq(use("RARE_CANDY",m),"consumed",version.." candy succeeds")
  T.eq(m.happiness,104,version.." candy level adds happiness")
  m.level=100
  T.eq(use("RARE_CANDY",m),"failed",version.." level 100 candy refused")
  T.eq(m.happiness,104,version.." refused candy no friendship")
  data.maps={HOMETOWN={landmark=17}};save.player.map="HOMETOWN"
  m=mon(200);m.caughtData=0xAC91
  T.eq(use("RARE_CANDY",m),"consumed",version.." candy in caught location")
  T.eq(m.happiness,version=="crystal" and 204 or 202,version.." Crystal caught-landmark bonus")
  m=mon(200);m.caughtData=18
  use("RARE_CANDY",m)
  T.eq(m.happiness,202,version.." different landmark ordinary level bonus")
  save.player.map=nil
  for _,key in ipairs({"X_ATTACK","X_DEFEND","X_SPEED","X_SPECIAL"}) do
    m=mon(99)
    local b={player={mon=m,stages={},name="CHIKORITA"}}
    T.eq(use(key,nil,b),"consumed",version.." X stat consumed")
    T.eq(m.happiness,100,version.." X stat friendship")
  end
  for _,key in ipairs({"POTION","FULL_HEAL","REVIVE"}) do
    m=mon(70);m.hp=key=="REVIVE" and 0 or 1;m.status="PSN"
    T.eq(use(key,m),"consumed",version.." ordinary medicine works")
    T.eq(m.happiness,70,version.." ordinary medicine gives no Gen 2 friendship")
  end
  for _,key in ipairs({"X_ACCURACY","DIRE_HIT","GUARD_SPEC"}) do
    m=mon(70);local b={player={mon=m,name="CHIKORITA"}}
    T.eq(use(key,nil,b),"consumed",version.." battle flag item initially works")
    T.eq(use(key,nil,b),"failed",version.." duplicate battle flag item not consumed")
    T.eq(m.happiness,70,version.." flag item has no X-stat friendship bonus")
  end
  for _,key in ipairs({"ENERGYPOWDER","ENERGY_ROOT","HEAL_POWDER","REVIVAL_HERB"}) do
    m=mon(200);m.hp=key=="REVIVAL_HERB" and 0 or 1;m.status="PSN"
    local kind,lines=use(key,m)
    T.eq(kind,"consumed",version.." herbal medicine works")
    T.eq(m.happiness,key=="REVIVAL_HERB" and 180 or key=="ENERGY_ROOT" and 185 or 190,version.." herbal penalty")
    T.eq(lines[#lines],data.text._ItemLooksBitterText,version.." extracted bitter text")
    T.eq(m.hp,key=="HEAL_POWDER" and 1 or m.stats.hp,version.." herbal HP effect")
    if key=="HEAL_POWDER" then T.eq(m.status,nil,version.." powder cures status") end
    m=mon(200)
    T.eq(use(key,m),"failed",version.." unneeded herb not consumed")
    T.eq(m.happiness,200,version.." unused herb has no penalty")
    m.isEgg=true;m.hp=1
    T.eq(use(key,m),"failed",version.." egg rejects medicine")
    T.eq(m.hp,1,version.." egg HP unchanged")
  end
  for _,entry in ipairs({{"ENERGYPOWDER",50},{"ENERGY_ROOT",200}}) do
    m=mon(70);m.stats.hp=500;m.hp=1
    T.eq(use(entry[1],m),"consumed",version.." herb on larger HP pool")
    T.eq(m.hp,1+entry[2],version.." exact herbal heal amount")
  end
  for _,key in ipairs({"FULL_HEAL","HEAL_POWDER","ANTIDOTE"}) do
    m=mon(70);m.hp=0;m.status="PSN"
    T.eq(use(key,m),"failed",version.." status cure refuses fainted target")
    T.eq(m.status,"PSN",version.." refused cure leaves status")
    T.eq(m.happiness,70,version.." refused cure leaves friendship")
  end
end
for _,v in ipairs({"yellow","emerald","platinum","prism"}) do
  Version.set(v)
  local m={happiness=70};T.eq(Friendship.change(m,"VITAMIN"),false,v.." keeps its own rules")
  T.eq(m.happiness,70,v.." no Gen 2 side effect")
end
T.finish()
