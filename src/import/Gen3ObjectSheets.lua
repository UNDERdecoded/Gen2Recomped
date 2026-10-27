-- Preserve cartridge object sheets in image-table order alongside the native
-- normalized actor sheets. Compact indexed bytes keep all poses without a
-- second renderer or a persistent RGBA copy for every object on the cartridge.
local M={SCHEMA=2}
local dimensions={
  [0]={{8,8},{16,16},{32,32},{64,64}},
  [1]={{16,8},{32,8},{32,16},{64,32}},
  [2]={{8,16},{8,32},{16,32},{32,64}},
}
local pair={}; for n=0,255 do pair[n]=string.char(n%16,math.floor(n/16)) end
local blank=string.rep('\0',8)
local function signed(n,bits) return n>=2^(bits-1) and n-2^bits or n end
local function range(rom,at,n) return type(at)=='number' and at>=0 and at%1==0 and at+n<=rom.size end
local function pointer(rom,at)
  if not range(rom,at,4) then return nil end
  return rom:pointer(at)
end
local function bytes(rom,at,n)
  if not range(rom,at,n) then return nil end
  if rom.sub then return rom:sub(at,n) end
  local out={}; for i=0,n-1 do out[i+1]=string.char(rom:u8(at+i)) end
  return table.concat(out)
end
local function palettes(rom,spec)
  local out={}
  for i=0,math.min(spec.paletteCount or 64,64)-1 do
    local at=spec.paletteTable+i*8
    if not range(rom,at,8) or rom:u32(at)==0 then break end
    local data=pointer(rom,at); local tag=rom:u16(at+4)
    if data and tag~=0 and range(rom,data,32) then
      local p={}; for c=0,15 do p[c]=rom:u16(data+c*2) end
      out[tag]=p
    end
  end
  return out
end
local function imageStarts(rom,spec)
  local starts,infos={},{}
  local function add(at)
    if not at or infos[at] or not range(rom,at,36) or rom:u16(at)~=65535 then return false end
    local images,anims=pointer(rom,at+28),pointer(rom,at+24)
    if not(images and anims) then return false end
    infos[at]=true; starts[images]=true; return true
  end
  for id=0,spec.count-1 do add(pointer(rom,spec.gfxTable+id*4)) end
  -- Contiguous graphics-info records also name image lists not addressed by
  -- the public graphics table. Their boundaries still end the preceding list.
  local seeds={}; for at in pairs(infos) do seeds[#seeds+1]=at end
  for _,at in ipairs(seeds) do at=at+36; while add(at) do at=at+36 end end
  return starts
end
local function layout(rom,at,w,h,wide)
  if not range(rom,at,8) then return nil end
  local count,subs=rom:u8(at),pointer(rom,at+4)
  local stride=wide and 8 or 4
  if count<1 or count>64 or not subs or not range(rom,subs,count*stride) then return nil end
  local pieces={}; local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
  for i=0,count-1 do
    local off=subs+i*stride
    local x=wide and signed(rom:u16(off),16) or signed(rom:u8(off),8)
    local y=wide and signed(rom:u16(off+2),16) or signed(rom:u8(off+1),8)
    local bits=rom:u16(off+(wide and 4 or 2))
    local row=dimensions[bits%4]; local dim=row and row[math.floor(bits/4)%4+1]
    if not dim then return nil end
    local p={x=x,y=y,w=dim[1],h=dim[2],tile=math.floor(bits/16)%1024}
    pieces[#pieces+1]=p
    minX,minY=math.min(minX,x),math.min(minY,y)
    maxX,maxY=math.max(maxX,x+p.w),math.max(maxY,y+p.h)
  end
  if maxX-minX~=w or maxY-minY~=h then return nil end
  for _,p in ipairs(pieces) do p.x,p.y=p.x-minX,p.y-minY end
  return {pieces=pieces,x=minX+math.floor(w/2),y=minY+math.floor(h/2)}
end
local function tiles(w,h,arrangement)
  local rows={}
  for ty=0,h/8-1 do
    local row={}; rows[ty+1]=row
    for tx=0,w/8-1 do
      local tile=ty*(w/8)+tx
      if arrangement then
        tile=false
        for _,p in ipairs(arrangement.pieces) do
          if tx*8>=p.x and ty*8>=p.y and tx*8<p.x+p.w and ty*8<p.y+p.h then
            tile=p.tile+((ty*8-p.y)/8)*(p.w/8)+(tx*8-p.x)/8; break
          end
        end
      end
      row[tx+1]=tile
    end
  end
  return rows
end
local function decode(raw,w,h,tileRows)
  local lines={}
  for y=0,h-1 do
    local row={}; local tileRow=tileRows[math.floor(y/8)+1]
    for x=1,w/8 do
      local tile=tileRow[x]
      if tile==false then row[x]=blank
      else
        local at=tile*32+(y%8)*4+1
        local a,b,c,d=raw:byte(at,at+3)
        row[x]=(pair[a or 0])..(pair[b or 0])..(pair[c or 0])..(pair[d or 0])
      end
    end
    lines[y+1]=table.concat(row)
  end
  return table.concat(lines)
end
local function avatars(rom,spec)
  if not spec then return nil end
  local out={stateFlags={male={},female={}}}
  local function pair(at)
    if not at then return nil end
    assert(range(rom,at,2),'avatar pair outside cartridge')
    return {male=rom:u8(at),female=rom:u8(at+1)}
  end
  for _,kind in ipairs({'player','rival'}) do
    local count=spec[kind..'_states'] or 0;assert(count<=32,'avatar state limit')
    if spec[kind] then
      out[kind]={}
      for i=0,count-1 do
        local row=pair(spec[kind]+i*2);row.state=assert(spec.stateNames[i+1],'avatar state name unavailable')
        out[kind][i+1]=row
      end
    end
  end
  out.linkFrlg=pair(spec.link_frlg);out.linkRs=pair(spec.link_rs)
  local n=spec.state_flag_count or 0;assert(n<=32,'avatar flag limit')
  for g,key in ipairs({'male','female'}) do
    for i=0,n-1 do
      local at=spec.state_flags+((g-1)*n+i)*2
      assert(range(rom,at,2),'avatar flags outside cartridge')
      out.stateFlags[key][i+1]={gfx=rom:u8(at),flag=rom:u8(at+1)}
    end
  end
  return out
end
function M.extract(rom,spec)
  assert(range(rom,spec.gfxTable,spec.count*4),'invalid object graphics table')
  assert(spec.count>=1 and spec.count<=4096,'invalid object graphics count')
  assert(range(rom,spec.paletteTable,8),'invalid object palette table')
  local starts,pals=imageStarts(rom,spec),palettes(rom,spec)
  local result={schema=M.SCHEMA,count=spec.count,edition=spec.edition,romSha1=spec.romSha1,
    reflectionProfile=spec.reflectionProfile or 'paired',avatars=avatars(rom,spec.avatarTables),objects={},unavailable={}}
  for id=0,spec.count-1 do
    local ok,record=pcall(function()
      local info=pointer(rom,spec.gfxTable+id*4)
      assert(range(rom,info,36),'object info unavailable')
      local w,h=math.abs(rom:s16(info+8)),math.abs(rom:s16(info+10))
      assert(w>=8 and h>=8 and w<=128 and h<=128 and w%8==0 and h%8==0,'invalid object dimensions')
      local images=pointer(rom,info+28); assert(images,'object image table unavailable')
      local rawSize=w*h/2; local n=0
      while n<32 do
        local at=images+n*8
        if n>0 and starts[at] or not range(rom,at,8) then break end
        local size=rom:u16(at+4)
        if not pointer(rom,at) or size<32 or size>32768 or size%32~=0 then break end
        n=n+1
      end
      n=math.max(1,n)
      local flags=rom:u8(info+12); local inanimate=math.floor(flags/64)%2==1
      if inanimate and w==32 and h==16 then w=16 end
      local arrangement=layout(rom,pointer(rom,info+20),w,h,spec.wideSubsprites)
      local tileRows=tiles(w,h,arrangement); local expected=w*h/2; local frames={}
      for i=0,n-1 do
        local at=images+i*8; local data=pointer(rom,at); local size=rom:u16(at+4)
        if size<1 or size>expected*4 then size=expected end
        -- Shared picture tables may contain differently sized stages. They
        -- keep their table slots, but a stage belonging to another graphics
        -- row must not read past its own allocation as this row's image.
        local raw=size==rawSize and data and bytes(rom,data,math.max(size,expected))
        frames[i+1]=raw and decode(raw,w,h,tileRows) or string.rep('\0',w*h)
      end
      local tag,reflectTag=rom:u16(info+2),rom:u16(info+4)
      local palette=pals[tag] or {}; for c=0,15 do palette[c]=palette[c] or 0 end
      local nativeReflect=spec.reflectionFor and spec.reflectionFor(info)
      -- A raw reflection profile publishes the flag/palette but leaves the
      -- optional paired-palette projection absent. Keep the independently
      -- derived native palette under its own name in both profiles.
      local mapped=spec.reflectionProfile~='raw' and pals[reflectTag] and nativeReflect or nil
      return {graphicsId=id,width=w,height=h,frameCount=n,indexed=table.concat(frames),
        paletteTag=tag,palette=palette,paletteSlot=flags%16,inanimate=inanimate,
        reflectionPaletteTag=reflectTag,reflectionPalette=pals[reflectTag],
        reflectionPaletteMappedTag=mapped,mappedReflectionPalette=mapped and pals[mapped] or nil,
        nativeReflectionPaletteTag=nativeReflect,
        drawOffX=arrangement and arrangement.x or 0,drawOffY=arrangement and arrangement.y or 0}
    end)
    if ok then result.objects[id]=record else result.unavailable[id]=tostring(record) end
    if spec.progress and id%16==15 then spec.progress(id+1,spec.count) end
  end
  return result
end
local function color(word)
  return string.char(math.floor((word%32)*255/31+.5),math.floor((math.floor(word/32)%32)*255/31+.5),math.floor((math.floor(word/1024)%32)*255/31+.5),255)
end
function M.rgba(record,palette,checkpoint)
  palette=palette or record.palette
  assert(type(record.indexed)=='string' and #record.indexed==record.width*record.height*record.frameCount,'invalid indexed object sheet')
  local colors={[0]='\0\0\0\0'}; for i=1,15 do colors[i]=color(palette[i] or 0) end
  local rows={}; local stride=record.width
  for at=1,#record.indexed,stride do
    local row={}; for x=0,stride-1 do row[x+1]=assert(colors[record.indexed:byte(at+x)],'invalid sprite palette index') end
    rows[#rows+1]=table.concat(row)
    if checkpoint and #rows%32==0 then checkpoint() end
  end
  return table.concat(rows)
end
return M
