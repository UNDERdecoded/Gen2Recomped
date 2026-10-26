-- Synthetic data for exercising loader contracts without an imported cartridge.
-- Identifiers match consumer queries; records and art are test-owned stand-ins.
local M = {}
local function copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}; for k,v in pairs(value) do out[k]=copy(v) end; return out
end
function M.fresh()
  local data=require('tests.modkit.fixtures').fresh()
  local seed=data.pokemon.FIXMON_A
  for index,id in ipairs({'MEW','VENUSAUR','CHARIZARD','BLASTOISE','PIDGEY','RATTATA','SPEAROW','CHARMANDER'}) do
    local mon=copy(seed);mon.id=id;mon.name=id;mon.index=index;mon.dex=index
    data.pokemon[id]=mon
  end
  data.pokemon.MEW.dex=151
  for _,id in ipairs({'TACKLE','GROWL','QUICK_ATTACK','CUT','SURF'}) do
    data.moves[id]=copy(data.moves.FIX_TACKLE);data.moves[id].id=id
  end
  data.items.POTION={id='POTION',name='Potion',price=300,tossable=true}
  data.items.TM_TOXIC={id='TM_TOXIC',name='TM test',price=4000,machine={kind='TM',move='TACKLE'}}
  data.tilesets.OVERWORLD=copy(data.tilesets.FIX_OUT)
  for _,id in ipairs({'PALLET_TOWN','OAKS_LAB','ROUTE_1','VIRIDIAN_CITY','PEWTER_CITY'}) do
    local map=copy(data.maps.FIX_TOWN);map.id=id;map.tileset='OVERWORLD';map.objects={};map.warps={};map.connections={}
    data.maps[id]=map
  end
  data.encounters.ROUTE_1={grass={rate=10,slots={{level=3,species='PIDGEY'}}}}
  data.sprites.SPRITE_RED=copy(data.sprites.SPRITE_FIX_PLAYER)
  data.sprites.SPRITE_RED_BIKE=copy(data.sprites.SPRITE_RED)
  return data
end
return M
