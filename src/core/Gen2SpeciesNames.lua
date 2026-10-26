-- Copyright (c) 2026 Roxas2712. Contribution terms:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- G/S/C species identifiers used by the separate Gen1Recomp reference
-- 535a5ec0 (constant names only; no ROM bytes or artwork). Native SPECIES_nnn
-- records remain the only stored/iterated rows. Names are live lookup aliases.
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
local count = 0
for name in order:gmatch("%S+") do
  count = count + 1
  nativeByName[name] = string.format("SPECIES_%03d", count)
end
local states = setmetatable({}, {__mode="k"})
local function supported()
  local v = Version.get()
  return v == "gold" or v == "silver" or v == "crystal"
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
