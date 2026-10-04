-- Headless Day Care parity checks with each game's extracted Pokemon data.
love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen 2 Day Care")
local Version=require("src.core.GameVersion")
local DC=require("src.pokemon.DayCare")
local G2=require("src.script.Gen2Commands")
local C=require("src.script.Commands")
local Growth=require("src.pokemon.Growth")
local Pokemon=require("src.pokemon.Pokemon")
require("src.core.Sound").playCry=function() end
local function read(path)
  local file=assert(io.open(path,"rb"));local bytes=file:read("*a");file:close();return bytes
end
local asks,lines,answers={},{},{}
C.ask=function(ctx,text,subs)
  asks[#asks+1]={text=text,subs=subs};ctx.lastCheck=table.remove(answers,1)
end
C.show_text=function(_,text) lines[#lines+1]=text end
for _,version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local files={gold="Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
    silver="Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
    crystal="Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"}
  local manifest=require("src.link.Json").decode(read("tools/rom_manifest_"..version..".json"))
  local ex=require("src.import.RomExtractorGen2").new(read(files[version]),version,manifest)
  local symbol=assert(ex:symbol("DayCareStep.check_egg"))
  local bytes=ex.rom:bytes(symbol.bank,symbol.address,100)
  local raw=string.char(unpack(bytes))
  for _,pattern in ipairs({{0xfe,230,0x06,80},{0xfe,170,0x06,40},{0xfe,110,0x06,30},{0x06,10}}) do
    T.eq(raw:find(string.char(unpack(pattern)),1,true)~=nil,true,version.." ROM egg-roll threshold")
  end
  local root=(arg[1] or "G:/Gen2Recomped").."/"..version.."/data/generated/"
  local data={text={}}
  for _,name in ipairs({"pokemon","moves","text"}) do
    data[name]=assert(loadfile(root..name..".lua"))()
  end
  -- The real extracted text cache can be namespaced; use explicit token
  -- fixtures to prove both numeric substitutions rather than fallback text.
  data.text._AreWeGeniusesText="See {RAM:NAME}?"
  data.text._YourMonHasGrownText="Grew {NUM:GROWTH}; fee {NUM:PRICE}"
  data.text._BackAlreadyText="Back already"
  data.text._NotEnoughMoneyText="NOT_ENOUGH"
  data.text._HaveNoRoomText="NO_ROOM"
  local function mon(species,level,attack,defense,special,ot)
    return {species=species,level=level,exp=Growth.expForLevel(data.pokemon[species].growthRate,level),
      hp=1,status="POISON",dvs={hp=0,attack=attack,defense=defense,speed=7,special=special},
      moves={{id="TACKLE",pp=0,ppUps=2}},otId=ot,nickname="TEST"}
  end
  for _,which in ipairs({DC.MAN,DC.LADY}) do
    for _,grown in ipairs({false,true}) do
      local save={flags={},money=10000,party={{species="SPECIES_152",hp=20}}}
      local m=mon("SPECIES_152",5,8,3,7,1)
      m.exp=m.exp+10
      local slot=DC.deposit(save,which,m)
      if grown then slot.steps=Growth.expForLevel(data.pokemon[m.species].growthRate,8)-m.exp+17 end
      asks,lines,answers={},{},{true,true}
      local ctx={save=save,game={save=save,data=data}}
      G2.dayCareWithdraw(ctx,which)
      local level=grown and 8 or 5
      T.eq(m.level,level,version.." retrieves correct level")
      T.eq(m.hp,m.stats.hp,version.." retrieval restores full HP")
      T.eq(m.status,nil,version.." retrieval clears status")
      T.eq(m.moves[1].pp,35+2*7,version.." retrieval restores PP Ups")
      T.eq(m.exp,Growth.expForLevel(data.pokemon[m.species].growthRate,level),version.." ROM EXP rounding")
      T.eq(save.money,10000-(100+(level-5)*100),version.." charges correct fee")
      T.eq(DC.mon(save,which),nil,version.." pen emptied after retrieval")
      T.eq(#save.party,2,version.." appends returned Pokemon once")
      T.eq(#asks,grown and 2 or 1,version.." correct confirmation count")
      if grown then
        T.eq(asks[1].text,"See {RAM:NAME}?",version.." show growth first")
        T.eq(asks[2].subs["NUM:GROWTH"],"3",version.." growth token independent of price")
        T.eq(asks[2].subs["NUM:PRICE"],"400",version.." fee token independent of growth")
      end
    end
    for _,reason in ipairs({"decline_first","decline_fee","money","party"}) do
      local save={flags={},money=reason=="money" and 0 or 10000,party={}}
      if reason=="party" or reason=="money" then for i=1,6 do save.party[i]={hp=20} end end
      local m=mon("SPECIES_152",5,8,3,7,1)
      local slot=DC.deposit(save,which,m);slot.steps=1000
      asks,lines,answers={},{},reason=="decline_first" and {false} or reason=="decline_fee" and {true,false} or {true,true}
      local before=save.money
      G2.dayCareWithdraw({save=save,game={save=save,data=data}},which)
      T.eq(DC.mon(save,which),m,version.." failed retrieval retains pen")
      T.eq(save.money,before,version.." failed retrieval takes no money")
      T.eq(m.status,"POISON",version.." declined retrieval does not mutate mon")
      if reason=="money" then T.eq(lines[#lines],"NOT_ENOUGH",version.." checks money before party capacity") end
    end
  end
  local random,new=math.random,Pokemon.new
  Pokemon.new=function(_,species,level) return {species=species,level=level,moves={}} end
  local function pair(tier)
    local a=mon("SPECIES_152",5,1,3,7,1) -- female
    local b=mon((tier==1 or tier==3) and "SPECIES_001" or "SPECIES_152",5,15,4,6,
      (tier==3 or tier==4) and 2 or 1)
    if tier==5 then b.dvs.defense=3;b.dvs.special=15 end
    local save={flags={}};DC.deposit(save,1,a);DC.deposit(save,2,b)
    return save
  end
  for tier=1,5 do
    local save=pair(tier)
    T.eq(DC.compatibility(data,save),tier,version.." correct pair tier "..tier)
    local successes=0
    for byte=0,255 do
      local s=pair(tier);DC.store(s,false).stepsToEgg=1
      local calls=0
      math.random=function() calls=calls+1;return calls==1 and 0 or byte end
      if DC.step(data,s) then successes=successes+1 end
      if tier~=5 then T.eq(DC.store(s,false).stepsToEgg,256,version.." zero countdown wraps") end
    end
    T.eq(successes,({10,40,30,80,0})[tier],version.." exhausts all 256 egg rolls "..tier)
  end
  local s=pair(4)
  math.random=function(low) return low end
  for i=1,149 do T.eq(DC.step(data,s),false,version.." waits initial 150 steps") end
  T.eq(DC.step(data,s),true,version.." first egg attempt at 150 steps")
  local related=pair(5)
  DC.mon(related,2).species="SPECIES_132"
  T.eq(DC.compatibility(data,related),5,version.." matching Ditto DVs also rejected")
  T.eq(DC.step(data,related),false,version.." matching Ditto pair cannot produce egg")
  for _,full in ipairs({false,true}) do
    local state=pair(4);state.party={}
    if full then for i=1,6 do state.party[i]={hp=20} end end
    local breed=DC.store(state,false)
    breed.egg={species="SPECIES_152",isEgg=true};breed.stepsToEgg=80
    local egg=breed.egg
    asks,lines,answers={},{},{true}
    local ctx={save=state,game={save=state,data=data}}
    C.g2_daycare_outside(ctx)
    T.eq(ctx.g2Var,full and 1 or 0,version.." full-party egg handover result")
    T.eq(breed.egg,full and egg or nil,version.." pending egg retained only when full")
    if not full then
      T.eq(breed.stepsToEgg,nil,version.." accepted egg starts a fresh countdown")
      T.eq(state.party[1],egg,version.." accepted egg transferred once")
    end
  end
  -- Matching-DV pairs, including Ditto, print the rejection line and cannot
  -- produce eggs. Normal best pairs print care, not the brimming line.
  data.text._BreedBrimmingWithEnergyText="BRIMMING"
  data.text._BreedAppearsToCareForText="CARE"
  data.text._BreedNoInterestText="NO_INTEREST"
  local cry=require("src.core.Sound").playCry
  local cries=0;require("src.core.Sound").playCry=function() cries=cries+1 end
  for _,case in ipairs({{5,"BRIMMING"},{4,"CARE"}}) do
    local state=pair(case[1]);lines={}
    G2.dayCareYardMon({save=state,game={save=state,data=data}},1)
    T.eq(lines[#lines],case[2],version.." correct yard compatibility dialogue")
  end
  T.eq(cries,2,version.." yard Pokemon plays cry")
  require("src.core.Sound").playCry=cry
  math.random,Pokemon.new=random,new
end
T.finish()
