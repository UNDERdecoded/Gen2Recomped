local Swarms={}
function Swarms.forMap(data,save,mapDef,mapId,ordinary)
  local version=require("src.core.GameVersion").get()
  if version~="gold" and version~="silver" and version~="crystal" then return ordinary end
  local tables=data.field and data.field.gen2Swarms
  local alternate=tables and tables.maps[mapDef and mapDef.label]
  if not (save and alternate) then return ordinary end
  local active=false
  if version=="crystal" then
    local Flags=require("src.script.Gen2Flags")
    for kind=0,1 do
      local target=save.g2Swarms and save.g2Swarms[kind]
      if not target and save.g2Swarm and save.g2Swarm.kind==kind then target=save.g2Swarm.map end
      local flag=tables.flags[kind]
      if target==mapId and flag and save.flags and save.flags[Flags.scriptFlag(flag)] then active=true end
    end
  else
    local stored=save.g2Swarm
    active=stored and (stored.map==mapId or (mapDef and mapDef.group==stored.kind and mapDef.number==stored.map))
  end
  if not active then return ordinary end
  local view={};for key,value in pairs(ordinary or {}) do view[key]=value end
  for key,value in pairs(alternate) do view[key]=value end
  return view
end
return Swarms
