-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- G/S/C species identifiers used by the separate Gen1Recomp reference
-- 535a5ec0 (constant names only; no ROM bytes or artwork). Complete native
-- cartridges use named runtime identities; old SPECIES_nnn addresses remain
-- lookup aliases. Partial/authored datasets retain their existing identities.
local Version = require("src.core.GameVersion")
local M = {}
local order = [[
BULBASAUR IVYSAUR VENUSAUR CHARMANDER CHARMELEON CHARIZARD SQUIRTLE WARTORTLE
BLASTOISE CATERPIE METAPOD BUTTERFREE WEEDLE KAKUNA BEEDRILL PIDGEY
PIDGEOTTO PIDGEOT RATTATA RATICATE SPEAROW FEAROW EKANS ARBOK
PIKACHU RAICHU SANDSHREW SANDSLASH NIDORAN_F NIDORINA NIDOQUEEN NIDORAN_M
NIDORINO NIDOKING CLEFAIRY CLEFABLE VULPIX NINETALES JIGGLYPUFF WIGGLYTUFF
ZUBAT GOLBAT ODDISH GLOOM VILEPLUME PARAS PARASECT VENONAT
VENOMOTH DIGLETT DUGTRIO MEOWTH PERSIAN PSYDUCK GOLDUCK MANKEY
PRIMEAPE GROWLITHE ARCANINE POLIWAG POLIWHIRL POLIWRATH ABRA KADABRA
ALAKAZAM MACHOP MACHOKE MACHAMP BELLSPROUT WEEPINBELL VICTREEBEL TENTACOOL
TENTACRUEL GEODUDE GRAVELER GOLEM PONYTA RAPIDASH SLOWPOKE SLOWBRO
MAGNEMITE MAGNETON FARFETCH_D DODUO DODRIO SEEL DEWGONG GRIMER
MUK SHELLDER CLOYSTER GASTLY HAUNTER GENGAR ONIX DROWZEE
HYPNO KRABBY KINGLER VOLTORB ELECTRODE EXEGGCUTE EXEGGUTOR CUBONE
MAROWAK HITMONLEE HITMONCHAN LICKITUNG KOFFING WEEZING RHYHORN RHYDON
CHANSEY TANGELA KANGASKHAN HORSEA SEADRA GOLDEEN SEAKING STARYU
STARMIE MR__MIME SCYTHER JYNX ELECTABUZZ MAGMAR PINSIR TAUROS
MAGIKARP GYARADOS LAPRAS DITTO EEVEE VAPOREON JOLTEON FLAREON
PORYGON OMANYTE OMASTAR KABUTO KABUTOPS AERODACTYL SNORLAX ARTICUNO
ZAPDOS MOLTRES DRATINI DRAGONAIR DRAGONITE MEWTWO MEW CHIKORITA
BAYLEEF MEGANIUM CYNDAQUIL QUILAVA TYPHLOSION TOTODILE CROCONAW FERALIGATR
SENTRET FURRET HOOTHOOT NOCTOWL LEDYBA LEDIAN SPINARAK ARIADOS
CROBAT CHINCHOU LANTURN PICHU CLEFFA IGGLYBUFF TOGEPI TOGETIC
NATU XATU MAREEP FLAAFFY AMPHAROS BELLOSSOM MARILL AZUMARILL
SUDOWOODO POLITOED HOPPIP SKIPLOOM JUMPLUFF AIPOM SUNKERN SUNFLORA
YANMA WOOPER QUAGSIRE ESPEON UMBREON MURKROW SLOWKING MISDREAVUS
UNOWN WOBBUFFET GIRAFARIG PINECO FORRETRESS DUNSPARCE GLIGAR STEELIX
SNUBBULL GRANBULL QWILFISH SCIZOR SHUCKLE HERACROSS SNEASEL TEDDIURSA
URSARING SLUGMA MAGCARGO SWINUB PILOSWINE CORSOLA REMORAID OCTILLERY
DELIBIRD MANTINE SKARMORY HOUNDOUR HOUNDOOM KINGDRA PHANPY DONPHAN
PORYGON2 STANTLER SMEARGLE TYROGUE HITMONTOP SMOOCHUM ELEKID MAGBY
MILTANK BLISSEY RAIKOU ENTEI SUICUNE LARVITAR PUPITAR TYRANITAR
LUGIA HO_OH CELEBI
]]
local nativeByName = {}
local nameByNumber = {}
local count = 0
for name in order:gmatch("%S+") do
  count = count + 1
  nativeByName[name] = string.format("SPECIES_%03d", count)
  nameByNumber[count] = ({FARFETCH_D='FARFETCHD',MR__MIME='MR_MIME'})[name] or name
end
local states = setmetatable({}, {__mode="k"})
local function supported()
  local v = Version.get()
  return v == "gold" or v == "silver" or v == "crystal"
end

-- The original importer scaffold used numbered placeholders. Normal game
-- loads now publish one authoritative, named GSC graph before mods or game
-- objects are created. Old addresses remain lookup aliases, not extra rows.
-- A total conversion, partial fixture, authored lookup or identity collision
-- is not enough evidence to reinterpret its species numbering.
function M.canonicalize(data)
  local pokemon=type(data)=='table'and data.pokemon
  local prior=type(pokemon)=='table'and states[pokemon]
  if prior and prior.canonical then return getmetatable(pokemon)==prior.meta end
  if not supported()or type(pokemon)~='table'or getmetatable(pokemon)~=nil then return false end
  local constants=data.constants
  local species=constants and constants.speciesOrder
  if type(species)~='table'or #species~=251 then return false end
  local aliases={}
  for i=1,251 do
    local id=string.format('SPECIES_%03d',i)
    local def=rawget(pokemon,id)
    local name=nameByNumber[i]
    if species[i]~=id or type(def)~='table'or def.id~=id or def.index~=i or def.dex~=i
       or rawget(pokemon,name)~=nil then return false end
    aliases[id]=name
  end
  aliases.FARFETCH_D,aliases.MR__MIME='FARFETCHD','MR_MIME'
  -- Plan the complete graph transaction before changing any table. Exact
  -- identity tokens change; prose, filesystem paths and provenance do not.
  local literal={text=true,text_pointers=true,name=true,nickname=true,title=true,body=true,
    message=true,description=true,label=true,prompt=true,caption=true,source=true,
    sourceId=true,native=true,path=true,file=true,filename=true}
  local seen,plan={},{}
  local function visit(row)
    if type(row)~='table'or seen[row]then return true end
    seen[row]=true
    local targets={}
    for key,value in pairs(row)do
      if not literal[key]then
        local target=aliases[key]or key
        local replacement=type(value)=='string'and(aliases[value]or value)or value
        if target~=key then
          local existing=rawget(row,target)
          if existing~=nil and existing~=replacement then return false end
        end
        if targets[target]~=nil and targets[target]~=replacement then return false end
        targets[target]=replacement
        if target~=key or replacement~=value then
          plan[#plan+1]={row=row,key=key,target=target,value=replacement}
        end
        if not visit(value)then return false end
      end
    end
    return true
  end
  if not visit(data)then return false end
  for _,op in ipairs(plan)do
    if op.key~=op.target then op.row[op.key]=nil end
    op.row[op.target]=op.value
  end
  local meta={__index=function(t,id)
    if supported()then local name=aliases[id];if name then return rawget(t,name)end end
  end}
  states[pokemon]={aliases=aliases,meta=meta,canonical=true}
  setmetatable(pokemon,meta)
  constants.speciesIdentity='gsc-canonical-v1'
  return true
end

function M.fromNumber(data,index)
  index=math.floor(tonumber(index)or 0)
  local species=data and data.constants and data.constants.speciesOrder
  return species and species[index]or string.format('SPECIES_%03d',index)
end

function M.number(data,species)
  if type(species)=='table'then species=species.species end
  local def=data and data.pokemon and data.pokemon[species]
  return tonumber(def and def.index)or tonumber(species)
    or(type(species)=='string'and tonumber(species:match('^SPECIES_(%d+)$')))or 0
end

function M.same(data,a,b)
  local pokemon=data and data.pokemon
  return M.registryId(pokemon,a)==M.registryId(pokemon,b)
end

-- Save validation already owns the native Pokemon lists. Normalize their
-- identity when it scrubs them, and fold legacy Pokedex keys without losing
-- a previously true seen/owned bit. No save file is written here.
function M.normalizeDex(data,dex)
  local state=data and data.pokemon and states[data.pokemon]
  if not(supported()and state and state.canonical and type(dex)=='table')then return end
  for _,kind in ipairs{'seen','owned'}do
    local flags=dex[kind]
    if type(flags)=='table'then
      local changes={}
      for id,value in pairs(flags)do
        local target=state.aliases[id]
        if target then changes[#changes+1]={id,target,value}end
      end
      for _,entry in ipairs(changes)do
        flags[entry[2]]=flags[entry[2]]or entry[3]
        flags[entry[1]]=nil
      end
    end
  end
end

function M.publish(data)
  local pokemon = type(data) == "table" and data.pokemon
  if not supported() or type(pokemon) ~= "table" then return false end
  local previous = states[pokemon]
  if previous then return getmetatable(pokemon) == previous.meta end
  -- Authored dataset lookup behavior is never replaced or wrapped.
  if getmetatable(pokemon) ~= nil then return false end
  local nativeOrder = data.constants and data.constants.speciesOrder
  if type(nativeOrder) ~= "table" then return false end
  local aliases = {}
  for name, id in pairs(nativeByName) do
    local def = rawget(pokemon, id)
    local index = tonumber(id:match("(%d+)$"))
    if nativeOrder[index] == id and type(def) == "table" and def.id == id
       and def.dex == index and def.index == index
       and rawget(pokemon, name) == nil then
      aliases[name] = id
    end
  end
  if not next(aliases) then return false end
  local meta = {__index=function(t, name)
    if supported() then
      local id = aliases[name]
      if id then return rawget(t, id) end
    end
  end}
  states[pokemon] = {aliases=aliases, meta=meta}
  setmetatable(pokemon, meta)
  return true
end

-- The real Registry uses the same address for reads, edits, deletion,
-- conflicts and rollback. Explicit authored names always retain precedence.
function M.registryId(pokemon, id)
  if not supported() or type(pokemon) ~= "table" or rawget(pokemon, id) ~= nil then return id end
  local state = states[pokemon]
  if not state or getmetatable(pokemon) ~= state.meta then return id end
  return state.aliases[id] or id
end

function M.write(target, registry)
  local state = supported() and states[target]
  for id in pairs(registry.ops) do
    local value = registry:get(id)
    -- Full replacements addressed by a legacy name still carry a native id.
    if state and getmetatable(target) == state.meta and type(value) == "table"
       and state.aliases[value.id] == id then value.id = id end
    target[id] = value
  end
end
return M
