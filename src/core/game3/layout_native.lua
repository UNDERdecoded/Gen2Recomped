-- Native 16px layout handles. A handle reads/writes the actual shared Map;
-- it owns no parallel field simulation, renderer or update clock.
local Map = require('src.world.Map')
local Layout = {}
local Methods = Layout
-- Both sides are weak: the model contains its view and owning Map. A
-- weak-key-only registry would retain that cycle on LuaJIT/Lua 5.1.
local models = setmetatable({}, {__mode='kv'})
local function integer(n, lo, hi)
 return type(n)=='number' and n>=lo and n<=hi and n%1==0
end
local function model(self) return assert(models[self], 'not a native layout handle') end
local function dims(m)
 if m.authored then return m.width,m.height,m.trueWidth,m.trueHeight end
 return m.map.def.width,m.map.def.height,m.map.widthCells,m.map.heightCells
end
local function baseField(m, x, y, field)
 local w = dims(m)
 if m.authored then local c=m.cells[y*w+x+1];return c and c[field]or(field=='coll'and 255 or 0)end
 local def=m.map.def;local i=y*w+x+1;local mid,coll,elev
 if type(def.blocks)=='string' then
  local a,b=def.blocks:byte(i*2-1,i*2)
  if a and b then local v=a+b*256;mid,coll,elev=v%1024,math.floor(v/1024)%4,math.floor(v/4096) end
 else mid=def.blocks and def.blocks[i] end
 if def.collisionCells then coll=def.collisionCells[i] end
 if def.elevationCells then elev=def.elevationCells[i] end
 if field=='mid'then return mid or 0 elseif field=='coll'then return coll==nil and 255 or coll elseif field=='elev'then return elev or 0 end
end
local function borders(m)
 if m.authored then return m.borderWidth,m.borderHeight,m.borderMids end
 local bytes=m.map.def.border
 if m.borderSource==bytes and m.borderFallback==m.map.def.borderBlock and m.borderCache then return m.bw,m.bh,m.borderCache end
 if type(bytes)=='string' and #bytes>=8 then
  local out={};for i=1,4 do local a,b=bytes:byte(i*2-1,i*2);out[i]=(a+b*256)%1024 end
  m.borderSource,m.borderFallback,m.borderCache,m.bw,m.bh=bytes,m.map.def.borderBlock,out,2,2
  return 2,2,out
 end
 local out={m.map.def.borderBlock or 0};m.borderSource,m.borderFallback,m.borderCache,m.bw,m.bh=bytes,m.map.def.borderBlock,out,1,1
 return 1,1,out
end
local function syncOverrides(m)
 local out=m.overrides
 for k in pairs(out) do out[k]=nil end
 local map,w=m.map,m.map.def.width;local selected={}
 for _,patch in ipairs{map.blockPatch,map.collisionPatch,map.elevationPatch}do
  for i in pairs(patch)do selected[i]=true end
 end
 for i in pairs(selected)do
  local x,y=(i-1)%w,math.floor((i-1)/w)
  out[y*1024+x]={mid=map:blockAt(x,y),coll=map:cellCollision(x,y),
   elev=map.elevationPatch[i]~=nil and map.elevationPatch[i]or map:cellElevation(x,y)or 0}
 end
 for key,row in pairs(map.layoutOutside or {})do
  local x,y=key:match('^(-?%d+):(-?%d+)$');x,y=tonumber(x),tonumber(y)
  out[y*1024+x]={mid=row.mid,coll=row.coll,elev=row.elev}
 end
end
local function notify(self, rows, bulk)
 local view=package.loaded['src.core.game3.field_view']
 if not view then return end
 if bulk or not view.invalidateLayoutCell or #rows>64 then view._nativeDirty=true;return end
 for _,r in ipairs(rows)do view.invalidateLayoutCell(self,r.x,r.y)end
end
local function commit(self, rows, bulk)
 local m=model(self);local map=m.map
 -- Validate every row before changing the one native grid. Sentinels and
 -- authored border overrides are layout values, not packed-ROM bit fields.
 for _,r in ipairs(rows)do
  assert(integer(r.x,-2147483648,2147483647)and integer(r.y,-2147483648,2147483647),'invalid layout coordinates')
  assert(integer(r.mid,0,65535)and integer(r.coll,0,255)and integer(r.elev,0,255),'invalid layout cell')
 end
 for _,r in ipairs(rows)do
  if r.x>=0 and r.y>=0 and r.x<map.def.width and r.y<map.def.height then
   local i=r.y*map.def.width+r.x+1
   map.blockPatch[i],map.collisionPatch[i],map.elevationPatch[i]=r.mid,r.coll,r.elev
   map.shutCells[r.x..':'..r.y]=r.coll~=0 and true or nil
  else
   map.layoutOutside=map.layoutOutside or {}
   map.layoutOutside[r.x..':'..r.y]={mid=r.mid,coll=r.coll,elev=r.elev}
  end
 end
 if #rows>0 then map:noteGridChange();map.blocksDirty=true end
 notify(self,rows,bulk)
 return #rows
end
local nativeCellAt, nativeMidAt
local function sample(self,x,y,field)
 local m=model(self);local map=m.map;local _,_,tw,th=dims(m)
 local i=y*map.def.width+x+1
 local outside=map.layoutOutside and map.layoutOutside[x..':'..y]
 local patched=x>=0 and y>=0 and x<map.def.width and y<map.def.height
  and (map.blockPatch[i]~=nil or map.collisionPatch[i]~=nil or map.elevationPatch[i]~=nil)
 if outside then return outside[field] end
 if patched and field=='elev' and map.elevationPatch[i]~=nil then
  -- A padded source column is outside the walkable crop. Its authored
  -- override still has a height; movement continues to use Map:inBounds.
  return map.elevationPatch[i]
 end
 if patched or x>=0 and y>=0 and x<tw and y<th then
  if field=='mid'then return map:blockAt(x,y)or 0 end
  if field=='coll'then return map:cellCollision(x,y)end
  return map:cellElevation(x,y)or 0
 end
 if field=='coll'then return 255 elseif field=='elev'then return 0 end
 local bw,bh,values=borders(m);return values[(y%bh)*bw+x%bw+1]or 0
end
function Methods:nativeMap()return model(self).map end
function Methods:cellAt(x,y)
 local m=model(self)
 if m.authored and x>=0 and y>=0 and x<m.trueWidth and y<m.trueHeight then
  local i=y*m.width+x+1
  if m.map.blockPatch[i]==nil and m.map.collisionPatch[i]==nil and m.map.elevationPatch[i]==nil then
   return m.cells[i]or {mid=0,coll=255,elev=0}
  end
 end
 return {mid=sample(self,x,y,'mid'),coll=sample(self,x,y,'coll'),elev=sample(self,x,y,'elev')}
end
nativeCellAt=Methods.cellAt
local function field(self,x,y,name)
 if self.cellAt~=nativeCellAt then return self:cellAt(x,y)[name] end
 return sample(self,x,y,name)
end
function Methods:midAt(x,y)return field(self,x,y,'mid')end
function Methods:collAt(x,y)return field(self,x,y,'coll')end
function Methods:elevAt(x,y)return field(self,x,y,'elev')end
nativeMidAt=Methods.midAt
function Methods:collArray()
 local m=model(self);local w,h,tw,th=dims(m);if w*h<=0 then return nil end
 local out={};for y=0,h-1 do for x=0,w-1 do out[y*w+x+1]=x<tw and y<th and sample(self,x,y,'coll')or 255 end end
 return out
end
function Methods:applyOverride(x,y,mid,coll,elev)
 commit(self,{{x=tonumber(x)or 0,y=tonumber(y)or 0,mid=tonumber(mid)or 0,coll=coll==nil and 255 or coll,elev=elev or 0}},false)
end
function Methods:setMetatiles(rows)
 local writes={};local staged={}
 for _,r in ipairs(rows or {})do
  local x,y=tonumber(r.x)or 0,tonumber(r.y)or 0;local key=x..':'..y
  local old=staged[key]or self:cellAt(x,y)
  local c={x=x,y=y,mid=tonumber(r.mid)or old.mid or 0,coll=r.coll==nil and old.coll or r.coll,elev=r.elev==nil and(old.elev or 0)or r.elev}
  writes[#writes+1]=c;staged[key]=c
 end
 return commit(self,writes,false)
end
function Methods:stamp(src,ox,oy)
 if type(src)~='table'or type(src.cells)~='table'then return 0 end
 ox,oy=tonumber(ox)or 0,tonumber(oy)or 0
 local rows={};for y=0,(src.trueHeight or src.height or 0)-1 do for x=0,(src.trueWidth or src.width or 0)-1 do
  local c=src.cells[y*src.width+x+1]
  if c then rows[#rows+1]={x=ox+x,y=oy+y,mid=c.mid or 0,coll=c.coll==nil and 255 or c.coll,elev=c.elev or 0}end
 end end
 return commit(self,rows,true)
end
function Methods:clearOverrides()
 local map=model(self).map
 map:clearBlockPatches();map.blocksDirty=true
 notify(self,{},true)
end
-- A supplied SVML blob is an immutable imported source. Never re-encode a
-- mutable grid on a per-frame worker request or claim the native packed GBA
-- map words are SVML. The ordinary native Map renderer needs neither blob.
function Methods:workerPacked()
 if self.cellAt~=nativeCellAt or self.midAt~=nativeMidAt then return nil end
 local assets=package.loaded['src.render.Assets']
 if assets and assets.loader and #assets.loader:overrideOrder()>0 then return nil end
 local m=model(self);local s=m.workerSource
 local w,h,tw,th=dims(m);local bw,bh,values=borders(m)
 if not s or m.cells~=s.cells or w~=s.width or h~=s.height or tw~=s.trueWidth or th~=s.trueHeight then return nil end
 if type(s.blob)~='string'or #s.blob<16 or s.blob:sub(1,4)~='SVML' then return nil end
 local copied={};for i=1,bw*bh do copied[i]=values[i]or 0 end
 syncOverrides(m)
 local overrides={};for key,c in pairs(m.overrides)do overrides[key]={mid=c.mid}end
 return {blob=s.blob,off=17+s.blob:byte(15)*s.blob:byte(16)*2,width=w,trueWidth=tw,trueHeight=th,borderWidth=bw,borderHeight=bh,borderMids=copied,overrides=overrides}
end
local function handle(m)
 local view=setmetatable({}, {
  __index=function(_,key)
   if Methods[key]then return Methods[key]end
   local w,h,tw,th=dims(m)
   if key=='width'then return w elseif key=='height'then return h elseif key=='trueWidth'then return tw elseif key=='trueHeight'then return th end
   if key=='mapId'then return m.mapId elseif key=='pair'then return m.pair elseif key=='_revision'then return m.map.gridRevision end
   if key=='overrides'then return m.overrides end
   if key=='borderWidth'or key=='borderHeight'or key=='borderMids'then local bw,bh,b=borders(m);return key=='borderWidth'and bw or key=='borderHeight'and bh or b end
   if key=='cells'then
    if m.authored then return m.cells end
    if not m.cells or m.cellsWidth~=w or m.cellsHeight~=h then
     local cells={};for y=0,h-1 do for x=0,w-1 do
      local cx,cy=x,y;cells[y*w+x+1]=setmetatable({}, {__index=function(_,name)return baseField(m,cx,cy,name)end,__newindex=function()error('imported layout source is read-only; use cell writes',2)end})
     end end;m.cells,m.cellsWidth,m.cellsHeight=cells,w,h
    end
    return m.cells
   end
  end,
  __newindex=function(t,key,value)
   if m.authored and(key=='cells'or key=='width'or key=='height'or key=='trueWidth'or key=='trueHeight'or key=='borderWidth'or key=='borderHeight'or key=='borderMids')then
    if key=='cells'then assert(type(value)=='table','layout cells must be a table')
    elseif key=='borderMids'then assert(type(value)=='table','layout border must be a table')
    else assert(integer(value,key:find('border')and 1 or 0,key:find('border')and 255 or 65535),'invalid layout dimensions')end
    local map=m.map;local writes
    if key=='width'or key=='height'then
     -- Native patches use the source row stride. Preserve their coordinates
     -- when an authored layout changes shape instead of moving the edits to
     -- whichever cell happens to inherit the old flattened index.
     writes={};local selected={};local oldWidth=map.def.width
     for _,patch in ipairs{map.blockPatch,map.collisionPatch,map.elevationPatch}do for i in pairs(patch)do selected[i]=true end end
     for i in pairs(selected)do
      local x,y=(i-1)%oldWidth,math.floor((i-1)/oldWidth)
      writes[#writes+1]={x=x,y=y,mid=map:blockAt(x,y),coll=map:cellCollision(x,y),elev=map.elevationPatch[i]or map:cellElevation(x,y)or 0}
     end
     for coord,c in pairs(map.layoutOutside or{})do
      local x,y=coord:match('^(-?%d+):(-?%d+)$')
      writes[#writes+1]={x=tonumber(x),y=tonumber(y),mid=c.mid,coll=c.coll,elev=c.elev}
     end
    end
    m[key]=value;map.def.width,map.def.height=m.width,m.height;map.widthCells,map.heightCells=m.trueWidth,m.trueHeight
    if writes then
     map.blockPatch,map.collisionPatch,map.elevationPatch,map.shutCells,map.layoutOutside={},{},{},{},nil
     if #writes>0 then commit(t,writes,true);return end
    end
    map:noteGridChange();map.blocksDirty=true;notify(t,{},true);return
   end
   if key=='pair'then m.pair=value;return elseif key=='mapId'then m.mapId=value;return end
   assert(key~='overrides'and key~='_revision'and key~='cells'and key~='width'and key~='height'and key~='trueWidth'and key~='trueHeight','native layout source fields belong to Map; use cell writes')
   rawset(t,key,value)
  end,
 })
 models[view]=m;m.view=view
 function m:syncOverrides()syncOverrides(self)end
 m.map._layoutProjection=m;syncOverrides(m)
 return view
end
function Layout.fromMap(map,mapId,pair)
 assert(type(map)=='table'and map.blockCells==1 and map.blockTiles==2,'native layout needs a 16px Map')
 if map._layoutProjection then return map._layoutProjection.view end
 return handle{map=map,mapId=mapId or map.id,pair=pair or map.def.tileset or map.tileset.id,overrides={}}
end
function Layout.fromDecoded(decoded,mapId,pair,sourceBlob)
 assert(type(decoded)=='table','decoded layout required')
 local m={authored=true,width=decoded.width or 0,height=decoded.height or 0,trueWidth=decoded.trueWidth or decoded.width or 0,trueHeight=decoded.trueHeight or decoded.height or 0,borderWidth=decoded.borderWidth or 1,borderHeight=decoded.borderHeight or 1,borderMids=decoded.borderMids or{0},cells=decoded.cells or{},mapId=mapId,pair=pair or'sevii_outdoor',overrides={}}
 if sourceBlob then m.workerSource={blob=sourceBlob,cells=m.cells,width=m.width,height=m.height,trueWidth=m.trueWidth,trueHeight=m.trueHeight}end
 for _,key in ipairs{'width','height','trueWidth','trueHeight','borderWidth','borderHeight'}do assert(integer(m[key],key:find('border')and 1 or 0,key:find('border')and 255 or 65535),'invalid decoded layout dimensions')end
 local function source(field,default)
  return setmetatable({}, {__index=function(_,i)local c=m.cells[i];return c and c[field]~=nil and c[field]or default end})
 end
 local def={id=mapId,tileset=m.pair,width=m.width,height=m.height,blocks=source('mid',0),collisionCells=source('coll',255),elevationCells=source('elev',0),borderBlock=m.borderMids[1]or 0}
 m.map=Map.new(def,{id=m.pair,blockCells=1,blockTiles=2,collision={},walkable={}})
 m.map.widthCells,m.map.heightCells=m.trueWidth,m.trueHeight
 return handle(m)
end
return Layout
