-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- The PC changes placed bytes. Room callbacks render them after native reload.
local Native=require('src.world.Gen2Decorations')
local Menu=require('src.ui.Menu')
local Runner=require('src.script.ScriptRunner')
local Strings=require('src.core.Strings')
local M={}
function M.new(game,opts)
 opts=opts or{}
 local changed,finished=false,false
 local programs=Native.pool(game.data)and Native.pool(game.data).decorationPrograms
 local texts=programs and programs.texts or{}
 local function finish()
  if finished then return end;finished=true
  if opts.onDone then opts.onDone(changed)end
 end
 local function say(role,onDone,extra)
  local id=texts[role]
  if not id then if onDone then onDone()end;return end
  local r=Runner.new(game,game.overworld)
  r:run({{'show_text',id,nil,extra}}, {onDone=onDone})
  return r
 end
 local function perform(id,side)
  local row=Native.attributes(game.data,id);local action=row and Native.action(row.action)
  local state=Native.state(game.data,game.save)
  if not(state and action)or not action.put and not Native.owns(game.data,game.save,id)then return end
  local placement=Native.placement(game.data,state,id,side)
  if not placement then return end
  game.stringBuffers=game.stringBuffers or{}
  for n,name in pairs(placement.buffers)do game.stringBuffers[n]=name end
  say(placement.role,function()changed=Native.choose(game.data,game.save,id,side)or changed end)
 end
 local function select(id)
  local row=Native.attributes(game.data,id);local action=row and Native.action(row.action)
  if not action then return end
  if not action.ornament then perform(id);return end
  local selected,question
  local function close(side)
   selected=side
   if question then game.stack:pop();question:resume()
   elseif side then perform(id,side)end
  end
  local function sides()
   game.stack:push(Menu.new(game,{
    {label=Strings('RIGHT SIDE'),onSelect=function()close('right')end},
    {label=Strings('LEFT SIDE'),onSelect=function()close('left')end},
    {label=Strings('CANCEL'),onSelect=function()close()end},
   },{tx=6,ty=6,tw=14,th=8,noSound=true,onCancel=function()close()end}))
  end
  local role=action.put and 'sidePut'or 'sideSetup'
  if texts[role]then
   question=say(role,function()if selected then perform(id,selected)end end,{stay={onShown=sides}})
  else sides()end
 end
 local function category(key)
  local items={}
  for _,c in ipairs(Native.categories(game.data))do
   if c.slot==key then
    for _,id in ipairs(c.members)do if Native.owns(game.data,game.save,id)then items[#items+1]=id end end
    return items,c.headers
   end
  end
  return items,{}
 end
 local rows={}
 if Native.ready(game.data)and Native.state(game.data,game.save)then
  for _,c in ipairs(Native.categories(game.data))do
   local key=c.slot;local ids=category(key)
   if #ids>0 then
    rows[#rows+1]={label=Strings(c.label),keepOpen=true,onSelect=function()
     local owned,headers=category(key)
     if #owned==0 then say('noChoice');return end
     local items={}
     for _,id in ipairs(owned)do
      local value=id;items[#items+1]={label=Native.name(game.data,value),onSelect=function()select(value)end}
     end
     for _,id in ipairs(headers)do
      local value=id;items[#items+1]={label=Native.name(game.data,value),onSelect=function()select(value)end}
     end
     items[#items+1]={label=Native.name(game.data,0)~=''and Native.name(game.data,0)or Strings('CANCEL')}
     game.stack:push(Menu.new(game,items,{tx=0,ty=0,tw=20,maxVisible=8,noSound=true}))
    end}
   end
  end
 end
 rows[#rows+1]={label=Strings('EXIT'),onSelect=finish}
 return Menu.new(game,rows,{tx=5,ty=0,tw=15,maxVisible=8,noSound=true,onCancel=finish})
end
return M
