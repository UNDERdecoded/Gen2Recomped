-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Synthetic full native identity table; contains no cartridge data/artwork.
local F={}
function F.new()
  local data=require('tests.modkit').fixtures.fresh()
  local copy=require('src.mods.Merge').deepCopy
  local prototype=data.pokemon.FIXMON_A
  data.pokemon={};data.constants.speciesOrder={}
  for index=1,251 do
    local id=string.format('SPECIES_%03d',index)
    local def=copy(prototype)
    def.id,def.index,def.dex,def.name=id,index,index,'Localized display name'
    def.source='ROM:'..id
    def.evolutions={};def.eggGroups={'FIELD'};def.genderRatio=127
    data.pokemon[id]=def;data.constants.speciesOrder[index]=id
  end
  return data
end
return F
