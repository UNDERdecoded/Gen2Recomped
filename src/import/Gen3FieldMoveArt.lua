-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Digest-bound GBA tilemap artwork. Store compact indices and palette words;
-- compose RGBA only for a consumer, without changing existing native art.
local M={SCHEMA=1,WIDTH=256,HEIGHT=80}
local function integer(n,lo,hi)return type(n)=='number'and n==n and n%1==0 and n>=lo and n<=hi end
local function range(rom,at,n)return integer(at,0,rom.size-n)end
local function strip(rom,spec,checkpoint)
  assert(type(spec)=='table'and integer(spec.tileCount,1,1024),'invalid field streak geometry')
  assert(range(rom,spec.tiles,spec.tileCount*32)and range(rom,spec.palette,32)and range(rom,spec.tilemap,640),'field streak ROM bounds')
  local palette={};for i=1,16 do palette[i]=rom:u16(spec.palette+(i-1)*2)end
  local tiles={}
  for t=0,spec.tileCount-1 do
    local variants={}
    for flip=0,3 do
      local rows={}
      for y=0,7 do
        local row={};local sy=flip>=2 and 7-y or y
        for x=0,7 do
          local sx=flip%2==1 and 7-x or x
          local b=rom:u8(spec.tiles+t*32+sy*4+math.floor(sx/2))
          row[x+1]=string.char(sx%2==0 and b%16 or math.floor(b/16))
        end
        rows[y+1]=table.concat(row)
      end
      variants[flip]=rows
    end
    tiles[t]=variants
  end
  local rows={}
  for ty=0,9 do
    local cells={}
    for tx=0,31 do
      local e=rom:u16(spec.tilemap+(ty*32+tx)*2)
      assert(e%1024<spec.tileCount,'field streak tile outside declared strip')
      cells[tx+1]=tiles[e%1024][math.floor(e/1024)%4]
    end
    for y=1,8 do
      local row={};for x=1,32 do row[x]=cells[x][y]end
      rows[#rows+1]=table.concat(row)
    end
    if checkpoint then checkpoint()end
  end
  return{width=M.WIDTH,height=M.HEIGHT,indexed=table.concat(rows),palette=palette}
end
function M.extract(rom,manifest,sha1,edition,checkpoint)
  local spec=manifest and manifest.fieldMoveStreaks
  if spec==nil then spec=require('src.import.Gen3FieldMoveProfiles').forSha1(sha1,edition)end
  if not(type(spec)=='table'and spec.schema==M.SCHEMA and type(sha1)=='string'and#sha1==40
      and sha1==manifest.romSha1 and sha1==spec.romSha1 and type(spec.strips)=='table')then
    return nil,'field streak profile is not authenticated'
  end
  local ok,rows=pcall(function()
    local out={schema=M.SCHEMA,romSha1=sha1,edition=edition,strips={}}
    for _,name in ipairs({'outdoors','indoors'})do out.strips[name]=strip(rom,spec.strips[name],checkpoint)end
    return out
  end)
  if not ok then return nil,tostring(rows)end
  return rows
end
function M.rgba(row)
  assert(type(row)=='table'and row.width==M.WIDTH and row.height==M.HEIGHT
    and type(row.indexed)=='string'and#row.indexed==M.WIDTH*M.HEIGHT and type(row.palette)=='table','invalid field streak record')
  local colors={[0]='\0\0\0\0'}
  for i=1,15 do
    local word=row.palette[i+1];assert(integer(word,0,65535),'invalid field streak palette')
    local function expand(n)return math.floor(n*255/31+.5)end
    colors[i]=string.char(expand(word%32),expand(math.floor(word/32)%32),expand(math.floor(word/1024)%32),255)
  end
  assert(not row.indexed:find('[\16-\255]'),'invalid field streak palette index')
  return(row.indexed:gsub('.',function(c)return colors[c:byte()]end))
end
return M
