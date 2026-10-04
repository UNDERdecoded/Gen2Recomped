love = require("tests.love_stub")
local T = require("tests.harness").suite("Gen 2 encounter rates and water levels")
local Version = require("src.core.GameVersion")
local Rules = require("src.world.Gen2EncounterRules")
local Contest = require("src.world.BugContest")
local Music = require("src.core.Music")
local OW = require("src.world.OverworldController")
local Game = require("src.core.Game")
for i=1,30 do
  local name=debug.getupvalue(OW.rollEncounter,i)
  if not name then break end
  if name=="Game" then debug.setupvalue(OW.rollEncounter,i,Game) end
end
local function read(path)
  local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s
end
local files={gold="Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 silver="Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 crystal="Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"}
local held = require("src.battle.HeldItems")
local originalEffect = held.effect
held.effect=function(_,mon) return mon.cleanse and held.EFFECT.CLEANSE_TAG or 0 end
local originalCurrent=Music.current
local song
Music.current=function() return song end
for _,version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local manifest=require("src.link.Json").decode(read("tools/rom_manifest_"..version..".json"))
  local ex=require("src.import.RomExtractorGen2").new(read(files[version]),version,manifest)
  local def=assert(ex:gen2EncounterRules())
  local data={field={gen2EncounterRules=def,gen2BugContest={mons={
    {rate=100,species="SPECIES_010",minLevel=10,maxLevel=10}}}},pokemon={}}
  T.eq(def.contestGrassRate,51,"ROM grass rate")
  T.eq(def.contestTallRate,102,"ROM tall rate")
  T.eq(def.superTallGrass[0x14],true,"first native tall class")
  T.eq(def.superTallGrass[0x1C],true,"second native tall class")
  for byte=0,255 do
    local level=5
    for _,threshold in ipairs(def.waterLevelThresholds) do
      if byte>=threshold then level=level+1 end
    end
    local enc={species="SPECIES_072",level=5}
    local actual=Rules.waterLevel(data,enc,function() return byte end)
    T.eq(actual.level,level,"all ROM water byte boundaries")
    T.eq(enc.level,5,"cached slot remains immutable")
    Game.data=data;Game.save={party={}}
    local n=0
    love.math.random=function() n=n+1;return n==3 and byte or 0 end
    local ow=setmetatable({map={id="test"},fieldWeather=function() return nil end},OW)
    local tableDef={grass={rate=20,bucketSpan=100,buckets={100},slots={enc}}}
    T.eq(OW.rollEncounter(ow,tableDef,"water").level,level,"walking uses water variation")
    T.eq(n,3,"walking spends exactly one water level roll")
    T.eq(OW.rollEncounter(ow,tableDef,"grass").level,5,"land keeps base level")
  end
  for _,music in ipairs({"none","Music_PokemonMarch","Music_RuinsOfAlphRadio","Music_PokemonLullaby"}) do
    song=music
    for _,cleanse in ipairs({false,true}) do
      local save={party={{hp=0,level=50},{hp=20,level=10,cleanse=cleanse}}}
      for rate=0,255 do
        local expected=rate
        if music=="Music_PokemonMarch" or music=="Music_RuinsOfAlphRadio" then expected=(rate*2)%256
        elseif music=="Music_PokemonLullaby" then expected=math.floor(rate/2) end
        if cleanse then expected=math.floor(expected/2) end
        T.eq(Rules.rate(data,save,rate,music),expected,"music before tag, with native byte wrap")
      end
      for _,tile in ipairs({0x10,0x14,0x1C}) do
        local base=def.superTallGrass[tile] and def.contestTallRate or def.contestGrassRate
        local expected=Rules.rate(data,save,base,music)
        for byte=0,255 do
          for _,leadLevel in ipairs({10,11}) do
            save.repelSteps=5;save.party[2].level=leadLevel
            local calls=0
            local enc=Contest.tryEncounter({data=data,save=save},tile,function()
              calls=calls+1;return calls==1 and byte or 0
            end)
            T.eq(enc~=nil,byte<expected and leadLevel<=10,"contest rate and first healthy Repel gate")
            T.eq(calls,byte<expected and 2 or 1,"failed rate does not choose a contest mon")
          end
        end
      end
    end
  end
end
Version.set("emerald")
local calls=0
T.eq(Rules.waterLevel({}, {species="x",level=5},function() calls=calls+1 end).level,5,"other generations unchanged")
T.eq(calls,0,"other generations spend no additional RNG")
held.effect=originalEffect;Music.current=originalCurrent
T.finish()
