-- Native zukan_data.narc membership/order tables and pokedex_sort.c rules.
-- Pure data operations, also used by the ROM extractor.
local S={}
S.ORDER_KEYS={'numerical','alphabetical','heaviest','lightest','tallest','smallest'}
S.ORDER_LABELS={'NUMERICAL','A TO Z','HEAVIEST','LIGHTEST','TALLEST','SMALLEST'}
S.NAME_KEYS={'none','ABC','DEF','GHI','JKL','MNO','PQR','STU','VWX','YZ'}
S.TYPE_KEYS={'none','NORMAL','FIGHTING','FLYING','POISON','GROUND','ROCK','BUG','GHOST','STEEL','FIRE','WATER','GRASS','ELECTRIC','PSYCHIC','ICE','DRAGON','DARK'}
S.SHAPE_KEYS={'none','QUADRUPED','BIPEDALTAILLESS','BIPEDALTAILED','SERPENTINE','MULTIWINGED','WINGED','INSECTOID','HEADBASE','HEADARMS','HEADLEGS','TENTACLES','FINS','HEAD','MULTIBODY'}
S.DATA_KEYS={'national','sinnoh','alphabetical','heaviest','lightest','tallest','smallest'}
for _,group in ipairs({S.NAME_KEYS,S.TYPE_KEYS,S.SHAPE_KEYS}) do
  for i=2,#group do S.DATA_KEYS[#S.DATA_KEYS+1]=group[i] end
end
S.CHOICES={S.ORDER_KEYS,S.NAME_KEYS,S.TYPE_KEYS,S.TYPE_KEYS,S.SHAPE_KEYS}
S.TYPE_LABEL_IDS={false,64,70,73,71,72,76,75,77,80,65,66,68,67,74,69,78,79}
function S.label(dex,id,fallback)
  local text=((dex.art or {}).labels or {})[id]
  return text and text:find('%S') and text or fallback
end
function S.defaults() return {1,1,1,1,1} end
-- Display order is deliberately separate from the filter enum order.
S.SHAPE_GRID={13,4,12,9,8,3,10,1,6,11,14,2,5,7,0}
S.SHAPE_SPRITES={0,5,10,1,6,11,2,9,12,3,8,13,4,7}
function S.buttons(dex)
  local out={}
  local function button(x,y,w,seq,label,action,value,icon)
    out[#out+1]={x=x,y=y,w=w,h=32,sequence=seq,label=label,action=action,value=value,icon=icon}
  end
  local field=dex.searchField
  local group=field==4 and 3 or field
  button(212,16,48,3,nil,'cancel')
  for i,b in ipairs({{1,'ORDER'},{2,'NAME'},{3,'TYPE'},{5,'FORM'}}) do
    button(224,16+i*32,64,2,S.label(dex,({50,47,48,49})[i],b[2]),'field',b[1])
    out[#out].selected=group==b[1]
  end
  button(212,176,80,1,S.label(dex,51,'OK'),'apply')
  if group==5 then
    for i,value in ipairs(S.SHAPE_GRID) do
      button(28+(i-1)%3*56,16+math.floor((i-1)/3)*32,48,6,nil,'shape',value+1,S.SHAPE_SPRITES[i])
      out[#out].selected=dex.searchSelection[5]==value+1
    end
  else
    local count=group==1 and 6 or group==2 and 10 or ((dex.searchTypePage or 0)==0 and 10 or 9)
    for i=1,count do
      local value,label
      if group==1 then value=i;label=S.label(dex,80+i,S.ORDER_LABELS[i])
      elseif group==2 then value=i==10 and 1 or i+1;label=value==1 and 'NONE' or S.label(dex,52+value,S.NAME_KEYS[value])
      else
        value=i==count and 1 or i+((dex.searchTypePage or 0)==0 and 1 or 10)
        label=value==1 and 'NONE' or S.label(dex,S.TYPE_LABEL_IDS[value],S.TYPE_KEYS[value])
      end
      local x=48+(i-1)%2*80
      if group==3 and (dex.searchTypePage or 0)==1 and i==9 then x=128 end
      local y=(group==1 and 48 or 16)+math.floor((i-1)/2)*32
      button(x,y,80,0,label,group==1 and 'order' or group==2 and 'name' or 'type',value)
      local s=dex.searchSelection
      out[#out].selected=group==3 and (value~=1 and (s[3]==value or s[4]==value)) or (group~=3 and s[group]==value)
    end
    if group==3 then button(24,176,32,(dex.searchTypePage or 0)==0 and 5 or 4,nil,'typePage') end
  end
  return out
end
function S.activate(dex,b)
  if not b then return end
  local s=dex.searchSelection
  dex.searchError=nil
  if b.action=='cancel' then dex:backToList()
  elseif b.action=='apply' then dex:applySearch()
  elseif b.action=='field' then
    dex.searchField=b.value;dex.searchCursor=nil
    if b.value==3 then dex.searchTypeSlot=3 end
  elseif b.action=='order' then s[1]=b.value
  elseif b.action=='name' then s[2]=b.value
  elseif b.action=='shape' then s[5]=b.value
  elseif b.action=='typePage' then dex.searchTypePage=1-(dex.searchTypePage or 0);dex.searchCursor=nil
  elseif b.action=='type' then
    if b.value==1 then
      if s[3]~=1 then s[3]=1 else s[4]=1 end
      dex.searchTypeSlot=3
    elseif s[3]~=b.value and s[4]~=b.value then
      local slot=dex.searchTypeSlot or 3;s[slot]=b.value;dex.searchTypeSlot=slot==3 and 4 or 3
    end
  end
end
function S.navigate(buttons,index,direction)
  local at=buttons[index] or buttons[7];local best,score=index,math.huge
  for i,b in ipairs(buttons) do
    local dx,dy=b.x-at.x,b.y-at.y
    local forward=(direction=='right' and dx) or (direction=='left' and -dx) or (direction=='down' and dy) or -dy
    local perpendicular=(direction=='left' or direction=='right') and math.abs(dy) or math.abs(dx)
    if forward>0 then
      local distance=forward+perpendicular*4
      if distance<score then best,score=i,distance end
    end
  end
  return best
end
local function set(list)
  local out={};for _,id in ipairs(list or {}) do out[id]=true end;return out
end
function S.results(dex,selection)
  local orders=(dex.art or {}).orders or {}
  local region=orders[dex.national and 'national' or 'sinnoh'] or dex.entries
  local allowed=set(region)
  local key=S.ORDER_KEYS[selection[1]]
  local order=key=='numerical' and region or orders[key]
  if not order then return nil,'missing data' end
  local out={}
  for _,id in ipairs(order) do
    local state=dex:status(id)
    if allowed[id] and state and (selection[1]<=2 or state=='owned') then out[#out+1]=id end
  end
  for field=2,5 do
    local filter=S.CHOICES[field][selection[field]]
    if filter~='none' then
      if not orders[filter] then return nil,'missing data' end
      local membership=set(orders[filter]);local filtered={}
      for _,id in ipairs(out) do
        -- FilterByType uses keepUncaught=FALSE; names and shapes use TRUE.
        if membership[id] and ((field~=3 and field~=4) or dex:status(id)=='owned') then filtered[#filtered+1]=id end
      end
      out=filtered
    end
  end
  return out
end
return S
