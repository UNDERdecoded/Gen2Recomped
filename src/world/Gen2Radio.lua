-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Station identities/MapRadio numbers are shared by both native radio UIs.
-- Program text stays in the existing native Pokegear implementation.
local Copy = require("src.mods.Merge").deepCopy
local R = {}
local literal=setmetatable({},{__mode="k"})
local WALL = {
  "OAKS_POKEMON_TALK", "POKEDEX_SHOW", "POKEMON_MUSIC", "LUCKY_CHANNEL",
  "UNOWN_RADIO", "PLACES_AND_PEOPLE", "LETS_ALL_SING", "ROCKET_RADIO",
}
local NAMES = {
  OAKS_POKEMON_TALK="OAK'S POKéMON TALK", POKEDEX_SHOW="POKéDEX SHOW",
  POKEMON_MUSIC="POKéMON MUSIC", LUCKY_CHANNEL="LUCKY CHANNEL",
  UNOWN_RADIO="UNOWN RADIO", PLACES_AND_PEOPLE="PLACES & PEOPLE",
  LETS_ALL_SING="LET'S ALL SING", ROCKET_RADIO="ROCKET RADIO",
  POKE_FLUTE_RADIO="POKé FLUTE", EVOLUTION_RADIO="EVOLUTION RADIO",
  BUENAS_PASSWORD="BUENA'S PASSWORD",
}
local GEAR = { "OAKS_POKEMON_TALK", "POKEDEX_SHOW", "POKEMON_MUSIC",
  "LUCKY_CHANNEL", "BUENAS_PASSWORD", "PLACES_AND_PEOPLE" }

function R.defaults()
  local rows={}
  for id,name in pairs(NAMES)do rows[id]={name=name} end
  for channel,id in ipairs(WALL)do rows[id].channel=channel end
  return rows
end

function R.records(data)
  local rows=data and data.gen2RadioChannels
  -- An explicitly empty mounted table is authoritative, including removals.
  return type(rows)=="table" and rows or R.defaults()
end

function R.literalState(data)return data and literal[data]end
function R.setLiteralState(data,state)if data then literal[data]=state end end
function R.isLiteral(data,id)
  local state=data and literal[data]
  return state and state[id]==true or state==nil and data and type(data.gen2RadioChannels)=="table"
end

function R.channelRecord(data,channel)
  local ids={}
  for id,row in pairs(R.records(data))do
    if type(row)=="table" and row.channel==channel then ids[#ids+1]=id end
  end
  table.sort(ids)
  local id=ids[1]
  return id and Copy(R.records(data)[id]),id
end

function R.stationName(data,id)
  local row=R.records(data)[id]
  if type(row)~="table" then return nil end
  return row.name or NAMES[id] or id
end

function R.resolve(data,channel,map,tod)
  if channel~=0 then
    local _,id=R.channelRecord(data,channel)
    if id then return id end
  else
    local maps=data and data.maps or {}
    local pallet=maps.PALLET_TOWN
    local boundary=tonumber(pallet and pallet.landmark)
      or (require("src.core.GameVersion").get()=="crystal" and 0x2f or 0x2e)
    if tonumber(map and map.landmark) and tonumber(map.landmark)>=boundary then
      return R.stationName(data,"PLACES_AND_PEOPLE") and "PLACES_AND_PEOPLE"
    end
    if tod=="MORNING" or tod=="MORN" then
      return R.stationName(data,"POKEDEX_SHOW") and "POKEDEX_SHOW"
    end
  end
  return R.stationName(data,"OAKS_POKEMON_TALK") and "OAKS_POKEMON_TALK"
end

function R.gearList(data,save,programs,expn)
  local rows=R.records(data)
  local list={}
  for i,id in ipairs(GEAR)do
    if type(rows[id])=="table" then
      local entry=Copy(programs[i] or {})
      entry.id,entry.name,entry.nameLiteral=id,R.stationName(data,id),R.isLiteral(data,id)
      list[#list+1]=entry
    end
  end
  if expn and type(rows.POKE_FLUTE_RADIO)=="table" then
    list[#list+1]={id="POKE_FLUTE_RADIO",name=R.stationName(data,"POKE_FLUTE_RADIO"),nameLiteral=R.isLiteral(data,"POKE_FLUTE_RADIO"),
      knob=78,lines={"Playing the","POKé FLUTE...","A soothing melody.","..."},flute=true}
  end
  return list
end

function R.notify(data,id,channel,source)
  local name=id and R.stationName(data,id)
  local Runtime=require("src.mods.Runtime")
  if name and Runtime.wants("radio.channel") then
    Runtime.emit("radio.channel",{station=id,channel=channel,name=name,source=source})
  end
end

R.STATIONS=WALL
return R
