local Breeding={}
local stats={"hp","attack","defense","speed","spatk","spdef"}
function Breeding.species(base,a,b,personality)
  if base=="WYNAUT" and a.item~="LAX_INCENSE" and b.item~="LAX_INCENSE" then return "WOBBUFFET" end
  if base=="AZURILL" and a.item~="SEA_INCENSE" and b.item~="SEA_INCENSE" then return "MARILL" end
  if personality and math.floor(personality/32768)%2==1 then
    if base=="NIDORAN" then return "NIDORAN_032" end
    if base=="ILLUMISE" then return "VOLBEAT" end
  end
  return base
end
function Breeding.inheritIVs(egg,a,b,rng)
  rng=rng or love.math.random
  local available={1,2,3,4,5,6}
  local selected,parents={},{}
  for i=1,3 do
    selected[i]=available[rng(0,#available-1)+1]
    -- Emerald removes the loop-index position, not the randomly selected
    -- position. Repeated stats and its HP/Defense bias are cartridge behavior.
    table.remove(available,i)
  end
  for i=1,3 do parents[i]=rng(0,1)==0 and a or b end
  for i=1,3 do
    local key=stats[selected[i]]
    local iv=parents[i].ivs and parents[i].ivs[key]
    if iv~=nil then egg.ivs[key]=iv end
  end
  return selected
end
function Breeding.inheritNature(data,egg,mother,a,b,rng)
  rng=rng or love.math.random
  local parent=mother
  if a.species=="DITTO" then parent=a elseif b.species=="DITTO" then parent=b end
  if not (parent and parent.item=="EVERSTONE" and parent.personality) or rng(0,65535)>=32767 then return false end
  local wanted=parent.personality%25
  for i=1,2401 do
    egg.personality=rng(0,65535)*65536+rng(0,65535)
    if egg.personality~=0 and egg.personality%25==wanted then break end
  end
  local order=(data.constants or {}).natureOrder
  if order then egg.nature=order[egg.personality%25+1] end
  return egg.personality%25==wanted
end
function Breeding.apply(data,save,egg,rng)
  local DayCare=require("src.pokemon.DayCare")
  local a,b=DayCare.pair(data,save)
  local mother=DayCare.parents(data,save)
  if not (a and b and mother) then return end
  Breeding.inheritNature(data,egg,mother,a,b,rng)
  local base=DayCare.eggSpecies(data,save)
  egg.species=Breeding.species(base,a,b,egg.personality)
  local def=data.pokemon[egg.species]
  local Pokemon=require("src.pokemon.Pokemon")
  egg.moves={}
  for _,id in ipairs(Pokemon.movesAtLevel(def,5)) do
    egg.moves[#egg.moves+1]={id=id,pp=data.moves[id] and data.moves[id].pp or 0}
  end
  egg.abilitySlot=def.abilities and def.abilities[2] and (egg.personality%2+1) or 1
  Breeding.inheritIVs(egg,a,b,rng)
  egg.stats=require("src.pokemon.Stats").calcGen3(def,5,egg.ivs,egg.evs,egg.nature)
  egg.hp=egg.stats.hp
end
function Breeding.voltTackle(data,save,egg)
  if egg.species~="PICHU" then return false end
  local a,b=require("src.pokemon.DayCare").pair(data,save)
  if not (a and b and (a.item=="LIGHT_BALL" or b.item=="LIGHT_BALL")) then return false end
  for _,move in ipairs(egg.moves) do if move.id=="VOLT_TACKLE" then return false end end
  local def=data.moves.VOLT_TACKLE
  if not def then return false end
  if #egg.moves>=4 then table.remove(egg.moves,1) end
  egg.moves[#egg.moves+1]={id="VOLT_TACKLE",pp=def.pp}
  return true
end
return Breeding
