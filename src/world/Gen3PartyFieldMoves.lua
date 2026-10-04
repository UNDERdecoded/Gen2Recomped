-- Reuse the cartridge's confirmed object-move branch for party-menu use.
-- This skips the overworld's badge/move lookup and Yes/No prompt; the party
-- screen has already checked the chosen member and supplies that member's slot.
local Field={}
local cache=setmetatable({}, {__mode="k"})
function Field.template(data,move,script)
  local cached=cache[data]
  if not cached then cached={};cache[data]=cached end
  local key=move..":"..tostring(script or "any")
  if cached[key] then return cached[key] end
  local gate=data.constants and data.constants.gen3FieldMoves
  local entry=gate and gate[move]
  if not entry then return nil end
  local property=move=="CUT" and "cuttable" or move=="ROCK_SMASH" and "smashable"
  if not property then return nil end
  local seen={}
  for _,map in pairs(data.maps or {}) do
    for _,object in ipairs(type(map)=="table" and map.objects or {}) do
      local at=tonumber(object.script)
      if object[property] and at and (not script or at==tonumber(script)) and not seen[at] then
        seen[at]=true
        local rows=require("src.script.Gen3ScriptVM").compile(data,("S%07X"):format(at))
        local checked,asked=false,false
        for i,row in ipairs(rows or {}) do
          if row[1]=="g3_check_party_move" and row[2]==entry.move then checked=true end
          if row[1]=="ask" then asked=true end
          if checked and asked and row[1]=="g3_field_effect"
              and rows[i-1] and rows[i-1][1]=="show_text"
              and rows[i+1] and rows[i+1][1]=="g3_wait_state"
              and rows[i+2] and rows[i+2][1]=="jump" then
            local tail={}
            -- Party callbacks begin at the effect, without interaction text.
            for n=i,#rows do tail[#tail+1]=rows[n] end
            cached[key]=tail
            return tail
          end
        end
      end
    end
  end
end
function Field.program(data,move,slot,script)
  local tail=Field.template(data,move,script)
  if not tail then return nil end
  local entry=data.constants.gen3FieldMoves[move]
  local out={{"g3_lock",true},{"g3_field_effect_arg",0,slot},
    {"g3_buffer",0,"party",slot},{"g3_buffer",1,"move",entry.move}}
  for _,row in ipairs(tail) do out[#out+1]=row end
  return out
end
function Field.target(ow,move)
  if not (ow and ow.player and ow.npcAtCell) then return nil end
  local x,y=ow.player:facingCell()
  local npc=ow:npcAtCell(x,y)
  local d=npc and npc.def
  local property=move=="CUT" and "cuttable" or move=="ROCK_SMASH" and "smashable"
  if not (d and property and d[property] and not npc.moving) then return nil end
  local a=tonumber(ow.player.elevation) or 0
  local b=tonumber(npc.elevation or d.elevation) or 0
  if a~=0 and b~=0 and a~=b then return nil end
  return npc
end
function Field.secretTarget(data,save,ow)
  local Base=require("src.world.Gen3SecretBase")
  local record=Base.record(data)
  if Base.mine(save) or not (record and ow and ow.player and ow.map)
      or ow.player.facing~="up" then return nil end
  local x,y=ow.player:facingCell()
  local kind=Base.kindOf(record,ow.map:cellBehaviour(x,y))
  local effect=({[1]=11,[5]=26,[6]=27})[kind]
  if not effect then return nil end
  for _,sign in ipairs(ow.map.def.signs or {}) do
    if sign.x==x and sign.y==y and (tonumber(sign.secretBaseId) or 0)>0 then
      return tonumber(sign.secretBaseId),effect
    end
  end
end
function Field.secretProgram(data,id,effect,slot)
  local record=require("src.world.Gen3SecretBase").record(data)
  if not (record and record.script) then return nil end
  local rows=require("src.script.Gen3ScriptVM").compile(data,record.script)
  local callback
  for i,row in ipairs(rows or {}) do
    if row[1]=="label" and rows[i+1] and rows[i+1][1]=="g3_lock"
        and rows[i+2] and rows[i+2][1]=="g3_field_effect"
        and rows[i+2][2]==effect then callback=row[2];break end
  end
  if not callback then return nil end
  local out={{"g3_setvar",0x8004,id},{"g3_special",21},
    {"g3_field_effect_arg",0,slot},{"jump",callback}}
  for _,row in ipairs(rows) do out[#out+1]=row end
  return out
end
return Field
