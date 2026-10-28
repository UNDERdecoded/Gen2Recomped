-- Synthetic banks shared with an independent source-format pixel oracle.
local F={}
local floor=math.floor
local function le(n,bytes)local out={}for i=1,bytes do out[i]=string.char(n%256);n=floor(n/256)end;return table.concat(out)end
function F.new(edition)
  local fr=edition=='firered'or edition=='leafgreen'
  local seed=({firered=1,leafgreen=2,emerald=3,ruby=4,sapphire=5})[edition]
  local layout={tilesInPrimary=fr and 640 or 512,metatilesInPrimary=fr and 640 or 512,palettesInPrimary=fr and 7 or 6,metatileLayers=2}
  local function bank(secondary,count)
    local tiles,metatiles,attributes,source,paletteBytes,palettes={},{},{},{},{},{}
    for tile=0,31 do for y=0,7 do for x=0,7,2 do
      local a=(tile*3+x+y*5+seed)%16;local b=(tile*3+x+1+y*5+seed)%16
      tiles[#tiles+1]=string.char(a+b*16)
    end end end
    for mid=0,count-1 do
      for q=0,7 do
        local tile=(mid+q*7)%32+(q%2==1 and layout.tilesInPrimary or 0)
        local flip=(mid+q)%4*1024
        local palette=(mid*3+q+seed)%16
        metatiles[#metatiles+1]=le(tile+flip+palette*4096,2)
      end
      local layer=mid%4;attributes[#attributes+1]=le(layer*4096,2)
      source[#source+1]=le(fr and layer*0x20000000 or layer*4096,fr and 4 or 2)
    end
    for slot=0,15 do
      local row={}
      for c=0,15 do
        local offset=secondary and 7 or 0
        local r,g,b=(slot+c+seed+offset)%32,(slot*3+c*5+seed)%32,(slot*7+c+offset)%32
        paletteBytes[#paletteBytes+1]=le(r+g*32+b*1024,2)
        row[c+1]={floor(r*255/31),floor(g*255/31),floor(b*255/31)}
      end
      palettes[slot+1]=row
    end
    return {tiles=table.concat(tiles),tileCount=32,metatiles=table.concat(metatiles),metatileCount=count,
      attributes=table.concat(attributes),sourceAttributes=table.concat(source),sourceAttributeBytes=fr and 4 or 2,
      palettes=palettes,sourcePaletteBytes=table.concat(paletteBytes),paletteCycles={},animations={},secondary=secondary}
  end
  local pair={primary=bank(false,19),secondary=bank(true,12)}
  local function part(record,kind)
    if kind=='tiles'then return {raw=record.tiles,count=record.tileCount}end
    return {data=kind=='mt'and record.metatiles or record.sourceAttributes,count=record.metatileCount}
  end
  local bundle={primaryTiles=part(pair.primary,'tiles'),secondaryTiles=part(pair.secondary,'tiles'),
    primaryMt=part(pair.primary,'mt'),secondaryMt=part(pair.secondary,'mt'),
    primaryAttr=part(pair.primary,'attr'),secondaryAttr=part(pair.secondary,'attr')}
  local mids,palettes={},{}
  local bankPalettes={primary={},secondary={}}
  for name,record in pairs(pair)do
    for slot=0,15 do
      local row={}
      for c=0,15 do local at=(slot*16+c)*2+1;row[c]=record.sourcePaletteBytes:byte(at)+record.sourcePaletteBytes:byte(at+1)*256 end
      bankPalettes[name][slot]=row
    end
  end
  for mid=0,18 do mids[#mids+1]=mid end
  for mid=0,11 do mids[#mids+1]=layout.metatilesInPrimary+mid end
  for slot=0,15 do
    local record=slot<layout.palettesInPrimary and pair.primary or pair.secondary
    local row={};for c=0,15 do local at=(slot*16+c)*2+1;row[c]=record.sourcePaletteBytes:byte(at)+record.sourcePaletteBytes:byte(at+1)*256 end
    palettes[slot]=row
  end
  return {pair=pair,layout=layout,bundle=bundle,mids=mids,palettes=palettes,bankPalettes=bankPalettes}
end
return F
