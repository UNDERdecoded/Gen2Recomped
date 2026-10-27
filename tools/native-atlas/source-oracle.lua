-- Run from the pinned reference checkout; writes only synthetic byte fixtures.
local fixturePath,output=assert(arg[1]),assert(arg[2])
local F=assert(loadfile(fixturePath))()
local Pack=require('src.import.gba.native_pack')
local Versions=require('src.import.gba.versions')
local function write(name,data)local f=assert(io.open(output..'/'..name,'wb'));f:write(data);f:close()end
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  require('src.core.GameVersion').set(edition)
  Versions.select(edition)
  local f=F.new(edition)
  local under,over=Pack.buildLayeredIdx(f.bundle,f.mids)
  local palettes=require('src.import.gba.tileset').mergeMapPalettes(f.bankPalettes.primary,f.bankPalettes.secondary)
  local colors=Pack.palsToRgb8(palettes)
  write(edition..'-under.idx',Pack.encodeIdx(under));write(edition..'-over.idx',Pack.encodeIdx(over))
  write(edition..'-under.rgba',Pack.bakeRgba(under,colors))
  write(edition..'-over.rgba',Pack.bakeRgba(over,colors,{transparentZero=true}))
  local base=Pack.bakeRgba(under,colors)
  local function patched(label,slot,words)
    local changed={};for key,value in pairs(palettes)do changed[key]=value end;changed[slot]=words
    local rgb=Pack.palsToRgb8(changed)
    local rgba,w,h=Pack.bakeRgba(under,rgb);local lines={}
    for y=0,h-1 do
      local row={}
      for x=0,w-1 do
        local atlasSlot=math.floor(y/16)*16+math.floor(x/16);local at=(y*w+x)*4+1
        local bytes=atlasSlot>=#f.mids and base or rgba
        row[#row+1]=bytes:sub(at,at+3)
      end
      lines[#lines+1]=table.concat(row)
    end
    write(edition..'-'..label..'-under.rgba',table.concat(lines))
    write(edition..'-'..label..'-over.rgba',Pack.bakeRgba(over,rgb,{transparentZero=true}))
  end
  local red={};for color=0,15 do red[color]=31 end
  patched('palette0',0,red);patched('palette1',1,red)
  if edition=='emerald'then
    for frame=0,1 do
      local words={};for c=0,15 do words[c]=(c*3+frame*7)%32+((c*5+frame*11)%32)*32+((c*9+frame*13)%32)*1024 end
      patched('palette-frame'..frame,8,words)
    end
  end
end
