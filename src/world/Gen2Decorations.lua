-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Native ownership flags, placed bytes and callback presentation are distinct.
-- Attribute/name rows come from the current cartridge, never a retail table.
local V=require('src.core.GameVersion')
local Strings=require('src.core.Strings')
local M={}
M.slots={'bed','carpet','plant','poster','console','bigDoll','leftOrnament','rightOrnament'}
M.objectSlots={
 {slot='console',sprite=0,flag=1857},{slot='leftOrnament',sprite=1,flag=1858},
 {slot='rightOrnament',sprite=2,flag=1859},{slot='bigDoll',sprite=3,flag=1860},
}
local groups={
 {'BED','bed'},{'CARPET','carpet'},{'PLANT','plant'},{'POSTER','poster'},
 {'GAME CONSOLE','console'},{'ORNAMENT','ornament'},{'BIG DOLL','bigDoll'},
}
function M.byte(id)
 local n=(type(id)=='number'or type(id)=='string')and tonumber(id)
 return n and n%1==0 and n>=0 and n<=255 and n or nil
end
local kinds={'BED','CARPET','PLANT','POSTER','CONSOLE','BIG_DOLL','DOLL'}
local slotFor={BED='bed',CARPET='carpet',PLANT='plant',POSTER='poster',CONSOLE='console',BIG_DOLL='bigDoll'}
local actions={}
for _,kind in ipairs(kinds)do
 actions[#actions+1]='SET_UP_'..kind;actions[#actions+1]='PUT_AWAY_'..kind
end
function M.actionName(n)return actions[n]end
function M.action(name)
 if type(name)~='string'then return nil end
 local kind=name:match('^SET_UP_(.+)$');local put=false
 if not kind then kind=name:match('^PUT_AWAY_(.+)$');put=true end
 if kind=='DOLL'then return{ornament=true,put=put}end
 return slotFor[kind] and {slot=slotFor[kind],put=put}or nil
end
function M.pool(data)return data and data.map_scripts end
function M.ready(data)
 local p=M.pool(data);local info=p and p.decorationInfo
 return V.generation(V.get())==2 and type(p)=='table' and type(p.decorations)=='table' and
  type(info)=='table' and info.complete==true or false
end
function M.attributes(data,id)
 if not M.ready(data)then return nil end
 id=M.byte(id);if not id then return nil end
 local rows=M.pool(data).decorations
 return rows[id]or rows[tostring(id)]
end
function M.state(data,save)
 if not M.ready(data)or type(save)~='table'then return nil end
 if save.decorations==nil then
  local info=M.pool(data).decorationInfo
  if not info.defaultsComplete then return nil end
  save.decorations=require('src.mods.Merge').deepCopy(info.defaults or{})
 end
 return type(save.decorations)=='table'and save.decorations or nil
end
local names={
 [2]=Strings.source('%s BED'),[3]=Strings.source('%s CARPET'),
 [4]=Strings.source('%s POSTER'),[5]=Strings.source('%s DOLL'),[6]=Strings.source('BIG %s'),
}
function M.name(data,id,monName)
 id=M.byte(id)
 local row=M.attributes(data,id)
 if not row then return ''end
  local name=row.name
  if row.type>=4 then
   if monName then name=monName(name)or name
   else
    local info=M.pool(data).decorationInfo
    local key=info.sourceNames and info.sourceNames[id]==name and info.species and info.species[id]or name
    local mon=data.pokemon and data.pokemon[key]
    name=mon and mon.name or name
   end
  end
  return names[row.type] and Strings(names[row.type],name)or name
end
function M.owns(data,save,id)
 id=M.byte(id)
 local row=M.attributes(data,id);local action=row and M.action(row.action)
 return type(save)=='table' and type(save.flags)=='table' and id~=0 and action and not action.put and require('src.script.Flags').get(save,
  require('src.script.Gen2Flags').eventFlag(row.flag))or false
end
function M.give(data,save,id)
 id=M.byte(id)
 local row=M.attributes(data,id)
 if type(save)~='table' or id==0 or not row or not M.action(row.action)or M.action(row.action).put then return false end
 save.flags=save.flags or{}
 require('src.script.Flags').set(save,require('src.script.Gen2Flags').eventFlag(row.flag));return true
end
function M.giveFlag(data,save,n)
 local info=M.pool(data)and M.pool(data).decorationInfo
 local id=info and info.gifts and info.gifts[(tonumber(n)or -1)+1]
 return id~=nil and M.give(data,save,id)or false
end
function M.choose(data,save,id,side)
 id=M.byte(id)
 local state=M.state(data,save);local row=M.attributes(data,id)
 local action=row and M.action(row.action)
 if id==0 or not(state and action)then return false end
 if not action.put and not M.owns(data,save,id)then return false end
 local slot=action.slot
 if action.ornament then
  if side~='left'and side~='right'then return false end
  slot=side=='left'and 'leftOrnament'or 'rightOrnament'
 end
 local value=action.put and 0 or id
 local changed=(state[slot]or 0)~=value
 state[slot]=value
 if changed and action.ornament and not action.put then
  local other=side=='left'and 'rightOrnament'or 'leftOrnament'
  if state[other]==id then state[other]=0 end
 end
 return changed
end
-- Public menu metadata is derived from the current native rows, including
-- registry additions/removals. No independent retail catalogue is seeded.
function M.categories(data)
 if not M.ready(data)then return{}end
 local indexed={}
 for raw in pairs(M.pool(data).decorations)do
  local id=M.byte(raw);if id and id~=0 then indexed[id]=true end
 end
 local out={}
 for _,group in ipairs(groups)do
  local category={label=group[1],slot=group[2],members={},headers={}}
  for id in pairs(indexed)do
   local row=M.attributes(data,id);local action=row and M.action(row.action)
   if action and(action.slot or 'ornament')==category.slot then
    local list=action.put and category.headers or category.members;list[#list+1]=id
   end
  end
  table.sort(category.members);table.sort(category.headers)
  category.id=category.headers[1];out[#out+1]=category
 end
 return out
end
function M.placement(data,state,id,side,monName)
 id=M.byte(id)
 local row=M.attributes(data,id);local action=row and M.action(row.action)
 if type(state)~='table'or not action or id==0 then return nil end
 local slot=action.slot
 if action.ornament then
  if side~='left'and side~='right'then return nil end
  slot=side=='left'and 'leftOrnament'or 'rightOrnament'
 end
 local old=M.byte(state[slot])or 0
 local value=action.put and 0 or id
 local role=action.put and(old==0 and 'empty'or 'put')or
  old==id and 'same'or old==0 and 'setup'or 'replace'
 return{slot=slot,value=value,changed=old~=value,role=role,
  buffers={[3]=M.name(data,role=='setup'and id or old,monName),[4]=M.name(data,id,monName)}}
end
function M.feedbackPages(data,placement)
 if not placement then return{}end
 local programs=M.pool(data)and M.pool(data).decorationPrograms
 local id=programs and programs.texts and programs.texts[placement.role]
 if not id then return{}end
 local private=data._portableScriptText and data._portableScriptText[id]
 local text=private and private.value or not private and data.text and data.text[id]
 if type(text)~='string'then return{}end
 text=text:gsub('{RAM:wStringBuffer([34])}',function(n)return placement.buffers[tonumber(n)]end)
 text=text:gsub('{DONE}',''):gsub('{PROMPT}',''):gsub('\v','\n')
 local pages={}
 for page in(text..'\f'):gmatch('(.-)\f')do if page~=''then pages[#pages+1]=page end end
 return pages
end
function M.layoutVisibility(data,state)
 local out={}
 for _,binding in ipairs(M.objectSlots)do
  local id=type(state)=='table'and M.byte(state[binding.slot])or 0
  local row=id and id~=0 and M.attributes(data,id)
  out[#out+1]={sprite=binding.sprite,flag=binding.flag,hidden=not row,byte=row and row.sprite or nil}
 end
 return out
end
function M.layoutTiles(data,state)
 local out={}
 local function paint(slot,x,y)
  local id=type(state)=='table'and M.byte(state[slot])or 0
  local row=id and id~=0 and M.attributes(data,id)
  if row then out[#out+1]={x=x,y=y,block=row.sprite};return row.sprite end
 end
 paint('bed',0,2);paint('plant',3,2);paint('poster',3,0)
 local carpet=paint('carpet',0,0)
 if carpet then
  out[#out+1]={x=0,y=1,block=(carpet+1)%256}
  out[#out+1]={x=1,y=1,block=(carpet+2)%256}
  out[#out+1]={x=2,y=1,block=(carpet+1)%256}
 end
 return out
end
function M.posterVisible(state)return((state and state.poster)or 0)~=0 end
-- These callbacks deliberately preserve the VM's current script/check vars.
function M.visibility(ctx)
 local data=ctx.game.data;local state=M.state(data,ctx.save)
 if not state then return end
  ctx.save.flags=ctx.save.flags or{}
 local C=require('src.script.Commands');local Flags=require('src.script.Gen2Flags')
 for _,row in ipairs(M.layoutVisibility(data,state))do
  if not row.hidden then
   C.g2_variablesprite(ctx,row.sprite,row.byte);C.clear_flag(ctx,Flags.eventFlag(row.flag))
  else C.set_flag(ctx,Flags.eventFlag(row.flag))end
 end
end
function M.tiles(ctx)
 local data=ctx.game.data;local state=M.state(data,ctx.save)
 if not state then return end
  ctx.save.flags=ctx.save.flags or{}
 local C=require('src.script.Commands')
 for _,row in ipairs(M.layoutTiles(data,state))do C.replace_block(ctx,row.x,row.y,row.block)end
 local flag=require('src.script.Gen2Flags').eventFlag(716)
 if M.posterVisible(state)then C.set_flag(ctx,flag)else C.clear_flag(ctx,flag)end
end
function M.description(data,save,kind)
 local state=M.state(data,save);local programs=M.pool(data)and M.pool(data).decorationPrograms
 if not state or type(programs)~='table'then return nil end
 if kind==0 then return programs.posters and programs.posters[state.poster or 0]or programs.null end
 if kind==3 then return programs.big end
 local slot=({[1]='leftOrnament',[2]='rightOrnament',[4]='console'})[kind]
 if slot then return programs.ornament,M.name(data,state[slot]or 0)end
end
return M
