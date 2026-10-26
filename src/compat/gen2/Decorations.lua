-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Legacy argument/result contracts over the native cartridge and placed bytes.
-- No fallback catalogue, ownership bitfield or second decoration save exists.
local Native=require('src.world.Gen2Decorations')
local Version=require('src.core.GameVersion')
local Flags=require('src.script.Flags')
local Gen2Flags=require('src.script.Gen2Flags')
local Copy=require('src.mods.Merge').deepCopy
local M={SLOTS=Copy(Native.slots),OBJECT_SLOTS=Copy(Native.objectSlots),ACTIONS={},
 EVENT_PLAYERS_ROOM_POSTER=716,DECOFLAG_GOLD_TROPHY_DOLL=43,DECOFLAG_SILVER_TROPHY_DOLL=44,
 DESC_SLOTS={DECODESC_POSTER={slot='poster'},DECODESC_LEFT_DOLL={slot='leftOrnament',named=true},
  DECODESC_RIGHT_DOLL={slot='rightOrnament',named=true},DECODESC_BIG_DOLL={slot='bigDoll'},
  DECODESC_CONSOLE={slot='console',named=true}}}
for n=1,14 do
 local name=Native.actionName(n);local action=Native.action(name)
 if not action.put then action.put=nil end
 M.ACTIONS[name]=action
end
local bound,edition,epoch=nil,nil,0
local function data()
 return edition==Version.get()and Native.ready(bound)and bound or nil
end
function M.useRegistry(value)
 epoch=epoch+1;bound=nil;edition=nil
 if Native.ready(value)then bound=value;edition=Version.get()end
 return bound~=nil
end
function M.idFor(id)return 'deco:'..tostring(id)end
function M.idForFlag(n)
 n=n==nil and 0 or tonumber(n)
 local d=data();local info=d and Native.pool(d).decorationInfo
 if not(n and n%1==0 and n>=0 and n<=255 and info and info.giftsComplete)then return nil end
 return info.gifts and info.gifts[n+1]
end
function M.attributes(id)return Native.attributes(data(),id)end
function M.state(save)return Native.state(data(),save)end
function M.name(id,monName)return Native.name(data(),id,monName)end
function M.registerInto(registry,source,owner)
 local d=Native.ready(source)and source or data();local count=0
 if not d then return count end
 local seen={}
 for raw in pairs(Native.pool(d).decorations)do
  local id=Native.byte(raw)
  if id and not seen[id]then
   seen[id]=true;registry:register(M.idFor(id),Copy(Native.attributes(d,id)),owner);count=count+1
  end
 end
 return count
end
-- Optional native adapter for callers of the numeric Events protocol. Its
-- get/set operations reach the same canonical flags as scripts and SRAM.
-- A retained adapter expires on rebind/unload; it never captures a new game.
function M.events(save)
 if not data()or type(save)~='table'then return nil end
 local generation=epoch
 local function current(id)
  return generation==epoch and data()and type(id)=='number'and id%1==0 and id>=0 and id<65535
 end
 return{get=function(_,id)
  return current(id)and type(save.flags)=='table'and Flags.get(save,Gen2Flags.eventFlag(id))or false
 end,set=function(_,id,value)
  if not current(id)then return false end
  save.flags=save.flags or{}
  if value then Flags.set(save,Gen2Flags.eventFlag(id))else Flags.clear(save,Gen2Flags.eventFlag(id))end
  return true
 end}
end
local function usable(id)
 id=Native.byte(id)
 local row=M.attributes(id);local action=row and Native.action(row.action)
 return id and id~=0 and action and not action.put and row or nil
end
function M.owns(events,id)
 local row=usable(id);if not row or type(events)~='table'then return false end
 if type(events.get)=='function'then return events:get(row.flag)and true or false end
 return Native.owns(data(),events,id)
end
function M.give(events,id)
 local row=usable(id);if not row or type(events)~='table'then return false end
 if type(events.set)=='function'then return events:set(row.flag,true)~=false end
 return Native.give(data(),events,id)
end
function M.giveFlag(events,n)return M.give(events,M.idForFlag(n))end
function M.ownedCategories(events)
 local out={}
 for _,category in ipairs(Native.categories(data()))do
  for _,id in ipairs(category.members)do
   if M.owns(events,id)then out[#out+1]=category;break end
  end
 end
 return out
end
function M.rows(events,category)
 local out={}
 -- Rebuild membership rather than trusting a category retained across reload.
 for _,current in ipairs(Native.categories(data()))do
  if category and current.id==category.id and(current.slot==category.slot or
    category.slot==nil and category.id~=nil)then
   for _,id in ipairs(current.members)do if M.owns(events,id)then out[#out+1]=id end end
   if #out>0 then
    for _,id in ipairs(current.headers)do out[#out+1]=id end
    out[#out+1]=0
   end
   break
  end
 end
 return out
end
function M.apply(state,id,side,monName)
 local placement=Native.placement(data(),state,id,side,monName)
 if not placement then return false,{}end
 state[placement.slot]=placement.value
 return placement.changed,Native.feedbackPages(data(),placement)
end
function M.clearOtherSide(state,id,side)
 id=Native.byte(id)
 if not data()or type(state)~='table'or not id or id==0 or(side~='left'and side~='right')then return end
 local other=side=='right'and 'leftOrnament'or 'rightOrnament'
 if state[other]==id then state[other]=0 end
end
function M.visibility(state)return data()and Native.layoutVisibility(data(),state)or{}end
function M.tiles(state)return data()and Native.layoutTiles(data(),state)or{}end
function M.posterVisible(state)return data()~=nil and Native.posterVisible(state)end
return setmetatable(M,{__index=function(_,key)
 if key=='CATEGORIES'then return Native.categories(data())end
 if key=='ATTRIBUTES'then
  local out={};local d=data()
  for raw in pairs(d and Native.pool(d).decorations or{})do
   local id=Native.byte(raw);if id then out[id]=Native.attributes(d,id)end
  end
  return out
 end
 if key=='NOTHING_TO_CHOOSE'then
  local pages=Native.feedbackPages(data(),{role='noChoice',buffers={}})
  return pages[1]
 end
end})
