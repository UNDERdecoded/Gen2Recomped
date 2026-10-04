love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen 2 fishing and swarms")
local OW=require("src.world.OverworldController")
local Version=require("src.core.GameVersion")
local Commands=require("src.script.Commands")
require("src.script.Gen2Commands")
require("src.script.Gen2Specials")
local Flags=require("src.script.Gen2Flags")
local Daily=require("src.script.Gen2Daily")
local function read(path)
  local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s
end
local files={gold="Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 silver="Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc",
 crystal="Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc"}
for _,version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local manifest=require("src.link.Json").decode(read("tools/rom_manifest_"..version..".json"))
  local ex=require("src.import.RomExtractorGen2").new(read(files[version]),version,manifest)
  local groups,times,swarms=ex:gen2Fishing()
  T.eq(swarms.dailyFlag,version=="crystal" and 82 or nil,"native version daily gating")
  local expectedRoutes={}
  local index=ex:symbol("GetFishGroupIndex")
  local offset=version=="crystal" and 10 or 1
  for i,name in ipairs({"qwilfish","remoraid"}) do
    local group=ex.rom:byte(index.bank,index.address+offset+(i-1)*4+1)
    local sym=assert(ex:symbol("GetFishGroupIndex."..name))
    local route={kind=ex.rom:byte(sym.bank,sym.address+4),group=ex.rom:byte(sym.bank,sym.address+8)}
    expectedRoutes[group]=route
    T.eq(swarms.routes[group] and swarms.routes[group].kind,route.kind,"swarm type read from cartridge")
    T.eq(swarms.routes[group] and swarms.routes[group].group,route.group,"swarm group read from cartridge")
  end
  local data={field={fishGroups=groups,timeFishGroups=times,fishSwarms=swarms}}
  data.field.gen2Swarms=ex:gen2SwarmTables()
  local root=(arg[1] or "G:/Gen2Recomped").."/"..version.."/data/generated/"
  data.maps=assert(loadfile(root.."maps.lua"))()
  data.encounters=assert(loadfile(root.."encounters.lua"))()
  local pool=assert(loadfile(root.."map_scripts.lua"))()
  ex.readSourceTable=function(_,name) return assert(loadfile(root..name..".lua"))() end
  local keys={};for key in pairs(data.maps) do keys[#keys+1]=key end
  ex:gen2ResolveScriptMapIds(data.maps,keys,pool)
  local announcements=0
  for label,rows in pairs(pool.scripts) do
    for _,row in ipairs(rows) do
      if row[1]=="swarm" then
        announcements=announcements+1
        local target=version=="crystal" and row[3] or row[2]
        T.eq(type(target),"string","actual phone swarm resolves native map operand")
        local save={flags={}}
        local ctx={save=save,game={data=data}}
        Commands.g2_swarm(ctx,row[2],row[3])
        local kind=version=="crystal" and row[2] or nil
        local flag=kind and data.field.gen2Swarms.flags[kind]
        if flag then save.flags[Flags.scriptFlag(flag)]=true end
        local def=data.maps[target]
        local ordinary=data.encounters[target]
        local expected=data.field.gen2Swarms.maps[def.label]
        local selected=require("src.world.Encounter").forMap(data,def,target,nil,save)
        T.eq(selected.grass,expected and expected.grass or ordinary.grass,"phone announcement activates grass swarm")
        T.eq(selected.water,expected and expected.water or ordinary.water,"water uses swarm only if table exists")
        local serializer=require("src.core.SaveSerializer")
        save=assert(serializer.decode(serializer.encode(save)))
        T.eq(require("src.world.Encounter").forMap(data,def,target,nil,save).grass,
          expected and expected.grass or ordinary.grass,"land swarm survives save/reload")
        if flag then
          save.flags[Flags.scriptFlag(flag)]=nil
          T.eq(require("src.world.Encounter").forMap(data,def,target,nil,save),ordinary,"Crystal flag disables grass swarm")
        end
        T.eq(require("src.world.Encounter").forMap(data,def,target),ordinary,"read-only lookup stays ordinary without save")
      end
    end
  end
  T.eq(announcements>0,true,"actual phone announcements tested")
  if version=="crystal" then
    local save={flags={}}
    local chosen={}
    for _,rows in pairs(pool.scripts) do for _,row in ipairs(rows) do
      if row[1]=="swarm" and not chosen[row[2]] then
        chosen[row[2]]=row[3]
        Commands.g2_swarm({save=save,game={data=data}},row[2],row[3])
        save.flags[Flags.scriptFlag(data.field.gen2Swarms.flags[row[2]])]=true
      end
    end end
    for _,target in pairs(chosen) do
      local def=data.maps[target]
      T.eq(require("src.world.Encounter").forMap(data,def,target,nil,save).grass,
        data.field.gen2Swarms.maps[def.label].grass,"Crystal keeps both independent swarm maps")
    end
    Daily.onNewDay(save)
    for _,target in pairs(chosen) do
      T.eq(require("src.world.Encounter").forMap(data,data.maps[target],target,nil,save),
        data.encounters[target],"Crystal daily reset expires land swarm")
    end
  end
  -- Verify every alternate row, including all three time periods.
  local mapIndex=ex:gen2MapIndex()
  for _,spec in ipairs({{"SwarmGrassWildMons","grass",47,7},{"SwarmWaterWildMons","water",9,3}}) do
    local sym=ex:symbol(spec[1]);local at=sym.address
    while ex.rom:byte(sym.bank,at)~=255 do
      local entry=mapIndex[ex.rom:byte(sym.bank,at)*256+ex.rom:byte(sym.bank,at+1)]
      local terrain=data.field.gen2Swarms.maps[entry.label][spec[2]]
      for time=0,(spec[2]=="grass" and 2 or 0) do
        local rows=time==0 and terrain.byTime and terrain.byTime.morn
          or time==2 and terrain.byTime.nite or terrain
        T.eq(rows.rate,ex.rom:byte(sym.bank,at+2+time),"alternate rate from native record")
        for i,slot in ipairs(rows.slots) do
          local start=at+(spec[2]=="grass" and 5+time*14 or 3)+(i-1)*2
          T.eq(slot.level,ex.rom:byte(sym.bank,start),"swarm slot level from ROM")
          T.eq(slot.species,string.format("SPECIES_%03d",ex.rom:byte(sym.bank,start+1)),"swarm slot species from ROM")
        end
      end
      at=at+spec[3]
    end
  end
  local fs=ex:symbol("FishGroups")
  for group=1,13 do
    local base=fs.address+(group-1)*7
    local chance=ex.rom:byte(fs.bank,base)
    T.eq(groups[group].chance,chance,"bite rate matches ROM")
    for r,rod in ipairs({"old","good","super"}) do
      local at=ex.rom:word(fs.bank,base+1+(r-1)*2)
      for _,tod in ipairs({"MORN","DAY","NITE","NIGHT"}) do
        for roll=0,255 do
          local slotAt=at
          while roll>ex.rom:byte(fs.bank,slotAt) do slotAt=slotAt+3 end
          local species=ex.rom:byte(fs.bank,slotAt+1)
          local level=ex.rom:byte(fs.bank,slotAt+2)
          if species==0 then
            local time=ex:symbol("TimeFishGroups")
            local night=(tod=="NITE" or tod=="NIGHT") and 2 or 0
            local timeAt=time.address+level*4+night
            species=ex.rom:byte(time.bank,timeAt);level=ex.rom:byte(time.bank,timeAt+1)
          end
          local calls=0
          love.math.random=function() calls=calls+1;return calls==1 and 0 or roll end
          local mon=OW.rollFishingForTest(data,rod:upper().."_ROD",{fishGroup=group},tod)
          T.eq(mon.species,string.format("SPECIES_%03d",species),"all slot bytes/time tables match ROM")
          T.eq(mon.level,level,"fishing level matches ROM")
        end
      end
      love.math.random=function() return chance end
      T.eq(OW.rollFishingForTest(data,rod:upper().."_ROD",{fishGroup=group},"DAY"),nil,"bite threshold exclusive")
    end
  end
  local save={flags={}}
  for kind=0,2 do
    local ctx={save=save,g2Var=kind}
    T.eq(Commands.g2_activate_fishing_swarm(ctx),nil,"special does not jump")
    T.eq(save.g2FishSwarm,kind,"special stores swarm type")
    for _,active in ipairs({false,true}) do
      if swarms.dailyFlag then save.flags[Flags.scriptFlag(swarms.dailyFlag)]=active or nil end
      for group=1,13 do
        local route=expectedRoutes[group]
        local selected=route and route.kind==kind and (active or version~="crystal") and route.group or group
        for _,rod in ipairs({"old","good","super"}) do
          for roll=0,255 do
            love.math.random=function(lo,hi) return roll end
            local expected=OW.rollFishingForTest({field={fishGroups=groups,timeFishGroups=times}},
              rod:upper().."_ROD",{fishGroup=selected},"DAY")
            local actual=OW.rollFishingForTest(data,rod:upper().."_ROD",{fishGroup=group},"DAY",save)
            T.eq(actual and actual.species,expected and expected.species,"swarm redirects only own fish group/type with native daily guard")
            T.eq(actual and actual.level,expected and expected.level,"swarm selected level")
          end
        end
      end
    end
  end
  save.g2FishSwarm=1
  if swarms.dailyFlag then save.flags[Flags.scriptFlag(swarms.dailyFlag)]=true end
  local serialized=require("src.core.SaveSerializer")
  save=assert(serialized.decode(serialized.encode(save)))
  T.eq(save.g2FishSwarm,1,"swarm selection survives save/reload")
  Daily.onNewDay(save)
  T.eq(save.g2FishSwarm,1,"daily reset does not clear stored swarm type")
  if swarms.dailyFlag then T.eq(save.flags[Flags.scriptFlag(swarms.dailyFlag)],nil,"Crystal daily reset disables outbreak") end
end
T.finish()
