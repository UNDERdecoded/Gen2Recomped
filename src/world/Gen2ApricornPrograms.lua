-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-apricorn-selection.md.
-- Project recipe records into decoded native Kurt programs. Dialogue,
-- working/day flags, quantity and bag-refusal branches remain native IR.
local Merge=require('src.mods.Merge')
local M={}
local copy=Merge.deepCopy
local function number(value)
  return type(value)=='number' and value%1==0 and value>=0 and value<=65534
end
local function item(key)
  local n=type(key)=='string' and tonumber(key:match('^ITEM_(%d%d%d)$'))
  return n and n>0 and n<255 and n or nil
end
M.item=item
local function selected(row)
  return type(row)=='table' and row[1]=='special' and
    (row[3]=='SelectApricornForKurt' or row[3]=='Special_SelectApricornForKurt' or row[3]=='select_apricorn')
end
local function eventBranch(scripts,label,gave)
  local rows=scripts[label]
  if type(rows)~='table' or #rows~=2 then return nil end
  if type(rows[1])~='table' or type(rows[2])~='table' then return nil end
  if rows[1][1]~='setevent' or not number(rows[1][2]) or
      rows[2][1]~='sjump' or rows[2][2]~=gave then return nil end
  return rows[1][2]
end
local function chain(rows,start,kind,known,count,ask)
  local seen,targets={},{}
  for n=0,count-1 do
    local a,b=rows[start+n*2],rows[start+n*2+1]
    if type(a)~='table' or type(b)~='table' or a[1]~=kind or
        not known[a[2]] or seen[a[2]] or b[1]~='iftrue' or
        type(b[2])~='string' or ask and b[2]~=ask then return nil end
    seen[a[2]]=true;targets[a[2]]=b[2]
  end
  return targets
end
function M.describe(data)
  local pool=data and data.map_scripts
  local roles=pool and pool.apricornPrograms
  local scripts=pool and pool.scripts
  local recipes=pool and pool.apricornBalls
  if type(roles)~='table' or type(scripts)~='table' or type(recipes)~='table' or #recipes==0 then
    return nil,'apricorns: native Kurt programs require a current ROM import'
  end
  for _,role in ipairs({'ask','pending','gave','cancel'})do
    if type(roles[role])~='string' or type(scripts[roles[role]])~='table' then
      return nil,'apricorns: missing native Kurt program '..role
    end
  end
  local ask=scripts[roles.ask];local zero
  for i,row in ipairs(ask)do
    if selected(row)then
      if zero then return nil,'apricorns: ambiguous native selection' end
      local nextRow=ask[i+1]
      if type(nextRow)=='table' and nextRow[1]=='ifequal' and nextRow[2]==0 and nextRow[3]==roles.cancel then zero=i+1 end
    end
  end
  if not zero then return nil,'apricorns: native selection/cancel signature differs' end
  local cases,at={},zero+1
  while type(ask[at])=='table' and ask[at][1]=='ifequal' do
    local row=ask[at];local id=row[2]
    local event=eventBranch(scripts,row[3],roles.gave)
    if type(id)~='number' or id%1~=0 or id<1 or id>254 or cases[id] or not event then
      return nil,'apricorns: invalid native selection branch'
    end
    cases[id]=event;at=at+1
  end
  if #ask~=at+1 or type(ask[at])~='table' or type(ask[at+1])~='table' or
      ask[at][1]~='setevent' or not number(ask[at][2]) or
      ask[at+1][1]~='sjump' or ask[at+1][2]~=roles.gave then
    return nil,'apricorns: native default selection signature differs'
  end
  local base,items,events,default={},{},{},nil
  for i,row in ipairs(recipes)do
    if type(row)~='table'then return nil,'apricorns: invalid native recipe record' end
    local id=item(row.apricorn)
    if not id or not item(row.ball) or items[id] then return nil,'apricorns: invalid native recipe table' end
    local event=cases[id]
    if not event then
      if default then return nil,'apricorns: ambiguous native default recipe' end
      default=id;event=ask[at][2]
    end
    if events[event] then return nil,'apricorns: duplicate native recipe event' end
    items[id]=true;events[event]=true
    base[i]={apricorn=row.apricorn,ball=row.ball,event=event,index=i}
  end
  if not default then return nil,'apricorns: no native default recipe' end
  for id in pairs(cases)do if not items[id] then return nil,'apricorns: native selection is outside recipe table' end end
  local pending=scripts[roles.pending];local targets
  for i=1,#pending do
    local found=chain(pending,i,'checkevent',events,#base)
    if found then
      if targets then return nil,'apricorns: ambiguous native collection chain' end
      targets=found
    end
  end
  if not targets then return nil,'apricorns: native collection chain differs' end
  local template,giftAt,clearAt
  for _,row in ipairs(base)do
    local rows=scripts[targets[row.event]]
    if type(rows)~='table' then return nil,'apricorns: native delivery program is absent' end
    local gift,clear
    for i,op in ipairs(rows)do
      if type(op)~='table'then return nil,'apricorns: invalid native delivery row' end
      if op[1]=='verbosegiveitem' or op[1]=='verbosegiveitemvar' then
        if gift or op[2]~=item(row.ball) then return nil,'apricorns: native ball output differs from recipe' end
        gift=i
      elseif op[1]=='clearevent' and op[2]==row.event then
        if clear then return nil,'apricorns: ambiguous native event clear' end
        clear=i
      end
    end
    if not gift or not clear or clear<=gift then return nil,'apricorns: native delivery/event signature differs' end
    if not template then template,giftAt,clearAt=rows,gift,clear end
  end
  return {roles=copy(roles),base=base,items=items,events=events,template=template,
    giftAt=giftAt,clearAt=clearAt,zero=zero,scripts=scripts,ask=ask}
end
function M.project(description,recipes,retired)
  local d=description;local scripts=d.scripts;local out={}
  for key,value in pairs(scripts)do out[key]=value end
  local choices,deliveries,generated={},{},{}
  local used,generation={},1
  for label in pairs(scripts)do
    if type(label)=='string'then
      local n=tonumber(label:match('^engine:apricorn:(%d+):'))
      if n then used[n]=true end
    end
  end
  while used[generation]do generation=generation+1 end
  local function key(kind,index)
    local id='engine:apricorn:'..generation..':'..kind..':'..index
    assert(scripts[id]==nil,'apricorns: generated script label collision')
    return id
  end
  for i,row in ipairs(recipes)do
    assert(item(row.apricorn) and item(row.ball) and number(row.event),'apricorns: invalid projected recipe')
    local choose=key('choose',i)
    choices[#choices+1]={'ifequal',item(row.apricorn),choose}
    generated[choose]={{'setevent',row.event},{'sjump',d.roles.gave}}
  end
  local deliveryRules,events={},{}
  for _,list in ipairs({recipes,retired or {}})do
    for _,row in ipairs(list)do
      if not events[row.event]then deliveryRules[#deliveryRules+1]=row;events[row.event]=true end
    end
  end
  for i,row in ipairs(deliveryRules)do
    local deliver=key('deliver',i)
    deliveries[#deliveries+1]={'checkevent',row.event};deliveries[#deliveries+1]={'iftrue',deliver}
    local body=copy(d.template);body[d.giftAt][2]=item(row.ball);body[d.clearAt][2]=row.event
    table.insert(body,d.clearAt+1,{'apricornconverted',row.apricorn,row.ball,row.event})
    generated[deliver]=body
  end
  choices[#choices+1]={'sjump',d.roles.cancel}
  local touched,memberCount,pendingCount={ },0,0
  for label,rows in pairs(scripts)do
    if type(rows)=='table'then
      local result,i,changed={},1,false
      while i<=#rows do
        local op=rows[i]
        if chain(rows,i,'checkitem',d.items,#d.base,d.roles.ask) then
          for _,row in ipairs(recipes)do
            result[#result+1]={'checkitem',item(row.apricorn)}
            result[#result+1]={'iftrue',d.roles.ask}
          end
          i=i+#d.base*2;changed=true;memberCount=memberCount+1
        elseif chain(rows,i,'checkevent',d.events,#d.base) then
          for _,row in ipairs(deliveries)do result[#result+1]=copy(row)end
          i=i+#d.base*2;changed=true;pendingCount=pendingCount+1
        else result[#result+1]=op;i=i+1 end
      end
      -- Ask is an actual queued root. Its original prefix includes the real
      -- selected item and native zero/cancel branch; never substitute an ID.
      if label==d.roles.ask then
        result={};for n=1,d.zero do result[n]=copy(rows[n])end
        for _,row in ipairs(choices)do result[#result+1]=copy(row)end
        changed=true
      end
      if changed then out[label]=copy(result);touched[label]=true end
    end
  end
  assert(memberCount>0 and pendingCount>0,'apricorns: native item/event consumers are absent')
  for label,rows in pairs(generated)do out[label]=rows;touched[label]=true end
  return out,touched
end
return M
