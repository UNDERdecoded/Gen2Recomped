-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native SNES graphics extraction. Only explicitly recognized cartridge
-- revisions are accepted; no copyrighted cartridge bytes are shipped.
local G=require("src.import.snes.Graphics")
local Lz=require("src.import.snes.Lz2")
local MD5=require("src.mods.StreamMD5")
local Producer=require("src.import.PackProducer")
local Importers=require("src.import.Importers")
local Writer=require("src.import.LuaWriter")
local T={IMPORTER="lttp",EXPORT_VERSION="1.1.0",SHEET_COUNT=223,SPRITE_FIRST=115,
  RAW_FIRST=115,RAW_LAST=126,RAW_SIZE=1536,SHEET_TILES_WIDE=16,
  COLORS_3BPP=7,COLORS_4BPP=15}
T.SOURCES={["608c22b8ff930c62dc2de54bcd6eba72"]={name="The Legend of Zelda: A Link to the Past (USA)",size=1048576}}
T.POINTERS={bank=0x4f80,high=0x505f,low=0x513e}
T.PLAYER={offset=0x80000,bytes=0x7000,bits=4,tiles=896}
T.PALETTE_SETS={
  {id="sprites_light",offset=0xdd218,rows=4,perRow=15},
  {id="sprites_dark",offset=0xdd290,rows=4,perRow=15},
  {id="armor",offset=0xdd308,rows=5,perRow=15},
  {id="sprites_aux3",offset=0xdd39e,rows=12,perRow=7},
  {id="bg_dungeon",offset=0xdd734,rows=16,perRow=15},
  {id="bg_overworld_aux3",offset=0xde604,rows=12,perRow=7},
}
T.DEFAULT_PALETTE={sprites={set="sprites_light",row=1},tiles={set="bg_dungeon",row=1}}
function T.identify(bytes)
  if type(bytes)~="string" or (#bytes~=1048576 and #bytes~=1049088) then return nil,"expected a supported 1 MiB SNES cartridge, with optional 512-byte copier header" end
  if #bytes==1049088 then bytes=bytes:sub(513) end
  local hash=MD5.new():update(bytes):final()
  local known=T.SOURCES[hash]
  if not known or known.size~=#bytes then return nil,"unsupported SNES cartridge revision ("..hash..")" end
  return {name=known.name,md5=hash,size=#bytes},bytes
end
function T.sheetOffset(rom,index)
  if type(index)~="number" or index<0 or index>=T.SHEET_COUNT or index%1~=0 then return nil end
  local p=T.POINTERS
  return G.loRomOffset(rom:byte(p.bank+index+1),rom:byte(p.high+index+1),rom:byte(p.low+index+1))
end
function T.isRaw(index)return index>=T.RAW_FIRST and index<=T.RAW_LAST end
function T.readSheet(rom,index)
  local offset=T.sheetOffset(rom,index)
  if not offset or offset>=#rom then return nil,"graphics pointer is outside the cartridge" end
  local bytes,err
  if T.isRaw(index) then
    bytes=rom:sub(offset+1,offset+T.RAW_SIZE)
    if #bytes~=T.RAW_SIZE then return nil,"raw graphics block is truncated" end
  else bytes,err=Lz.decompress(rom,offset) end
  if not bytes then return nil,err end
  return G.decodeSheet(bytes)
end
function T.readPlayer(rom)
  local p=T.PLAYER
  local bytes=rom:sub(p.offset+1,p.offset+p.bytes)
  if #bytes~=p.bytes then return nil,"player graphics are truncated" end
  return G.decodeTiles(bytes,p.bits)
end
function T.readPalettes(rom)
  local all={}
  for _,spec in ipairs(T.PALETTE_SETS) do
    local colors,err=G.readPalette(rom,spec.offset,spec.rows*spec.perRow)
    if not colors then return nil,err end
    local rows={}
    for row=1,spec.rows do
      rows[row]={};for color=1,spec.perRow do rows[row][color]=colors[(row-1)*spec.perRow+color] end
    end
    all[spec.id]=rows
  end
  return all
end
local function png(raster)
  assert(love and love.image,"native image encoding is unavailable")
  local image=love.image.newImageData(raster.width,raster.height,"rgba8",raster.rgba)
  local encoded
  local ok,result=pcall(function()encoded=image:encode("png");return encoded:getString()end)
  if encoded then encoded:release() end
  image:release()
  if not ok then error(result,0) end
  return result
end
local function alreadyInstalled(source,fs)
  local expected={tiles=116,sprites=109,palettes=6}
  for pack,count in pairs(expected) do
    local m=Importers.check({importer=T.IMPORTER,pack=pack,version="="..T.EXPORT_VERSION},fs)
    if not m or m.source.md5:lower()~=source.md5 then return false end
    local n=0;for _ in pairs(m.entries) do n=n+1 end
    if n~=count then return false end
    if pack=="tiles" then
      if not m.entries.kakariko then return false end
      for index=0,T.SPRITE_FIRST-1 do if not m.entries[("sheet_%03d"):format(index)] then return false end end
    elseif pack=="sprites" then
      if not m.entries.player then return false end
      for index=T.SPRITE_FIRST,T.SHEET_COUNT-1 do if not m.entries[("sheet_%03d"):format(index)] then return false end end
    else for _,spec in ipairs(T.PALETTE_SETS) do if not m.entries[spec.id] then return false end end end
  end
  return true
end
function T.job(rom,fs,options)
  options=options or {}
  return coroutine.create(function()
    local source,normalized=T.identify(rom);assert(source,normalized);rom=normalized
    fs=Importers.fs(fs)
    if not options.force and alreadyInstalled(source,fs) then
      return {source=source,packs={tiles=116,sprites=109,palettes=6},skipped={},reused=true}
    end
    local palettes=assert(T.readPalettes(rom))
    local writers={}
    for _,pack in ipairs({"tiles","sprites","palettes"}) do writers[pack]=assert(Producer.new(T.IMPORTER,pack,T.EXPORT_VERSION,source,fs)) end
    for index=0,T.SHEET_COUNT-1 do
      local tiles,bits=T.readSheet(rom,index);assert(tiles,bits)
      local pack=index<T.SPRITE_FIRST and "tiles" or "sprites"
      local pick=T.DEFAULT_PALETTE[pack]
      local raster=G.sheet(tiles,palettes[pick.set][pick.row],T.SHEET_TILES_WIDE)
      assert(writers[pack]:put(("sheet_%03d"):format(index),png(raster),
        {width=raster.width,height=raster.height,frames=#tiles,colors=2^bits,
          palette=pick.set.."/"..pick.row,note="color 0 is transparent"}))
      coroutine.yield({done=index+1,total=231,status="Extracting graphics sheet "..index})
    end
    local player=G.sheet(assert(T.readPlayer(rom)),palettes.armor[1],T.SHEET_TILES_WIDE)
    assert(writers.sprites:put("player",png(player),{width=player.width,height=player.height,frames=T.PLAYER.tiles,
      colors=16,palette="armor/1",note="4bpp player graphics; color 0 is transparent"}))
    coroutine.yield({done=224,total=231,status="Extracting player graphics"})
    local overworld=require("src.import.lttp.Overworld").raster(rom,T.readSheet,function(done,total)
      coroutine.yield({done=224+done/total,total=231,status="Assembling overworld metatiles"})
    end)
    assert(writers.tiles:put("kakariko",png(overworld),{width=1024,height=1024,frames=4096,colors=128,
      note="16-pixel overworld metatiles with their map palettes"}))
    for index,spec in ipairs(T.PALETTE_SETS) do
      assert(writers.palettes:put(spec.id,Writer.encode(palettes[spec.id]),
        {frames=spec.rows,note=spec.rows.." palette rows"},nil,"lua"))
      coroutine.yield({done=225+index,total=231,status="Extracting palette "..spec.id})
    end
    local results={}
    for _,pack in ipairs({"tiles","sprites","palettes"}) do
      local result,err=writers[pack]:finish();assert(result,err);results[pack]=result.entries
    end
    return {source=source,packs=results,skipped={}}
  end)
end
return T
