-- Synthetic data only: exercise the real ROM reader, LZ decoder, palette
-- nibbles and complete 160x144 image, with no cartridge or GPU requirement.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Extractor = require("src.import.RomExtractorGen2")
local Rom = require("src.import.Rom")
local oldImage = love.image
love.image = love.image or {}
local oldImageData = love.image.newImageData
local tiles, cells, palette, nibbles = {}, {}, {}, {}
for tile=0,47 do
  for y=0,7 do
    -- All four shades, with asymmetric corners/rows to expose shifts/flips.
    local lo, hi = 0,0
    for x=0,7 do
      local shade=(tile+x+2*y)%4
      lo=lo+(shade%2)*2^(7-x)
      hi=hi+math.floor(shade/2)*2^(7-x)
    end
    tiles[#tiles+1]=string.char(lo,hi)
  end
end
tiles=table.concat(tiles)
for i=0,359 do cells[#cells+1]=string.char(i%48) end
cells=table.concat(cells)
for p=0,5 do
  for shade=0,3 do
    local r,g,b=3*p+shade,2*p+2*shade,p+3*shade
    local word=r+g*32+b*1024
    palette[#palette+1]=string.char(word%256,math.floor(word/256))
  end
end
palette=table.concat(palette)
for tile=0,94,2 do
  nibbles[#nibbles+1]=string.char(tile%6+((tile+1)%6)*16)
end
nibbles=table.concat(nibbles)
local symbols={TownMapGFX={1,0x4000},JohtoMap={1,0x5000},
  KantoMap={1,0x5200},["TownMapPals.PalMap"]={1,0x5400},
  MalePokegearPals={1,0x5500}}
local function fixture(version, raw, layout)
  local image
  love.image.newImageData=function(w,h)
    image={width=w,height=h,pixels={}}
    function image:setPixel(x,y,r,g,b,a) self.pixels[y*w+x]={r,g,b,a} end
    return image
  end
  -- A genuine LZ long literal command, not a mocked decompressor. Its two
  -- header bytes used to become the first row of the imported tile sheet.
  local stream=raw and tiles or string.char(0xe2,0xff)..tiles..string.char(0xff)
  local bytes=string.rep("\0",0x4000)..stream
  bytes=bytes..string.rep("\0",0x5000-#bytes)..cells
  bytes=bytes..string.rep("\0",0x5200-#bytes)..cells
  bytes=bytes..string.rep("\0",0x5400-#bytes)..nibbles
  bytes=bytes..string.rep("\0",0x5500-#bytes)..palette
  bytes=bytes..string.rep("\0",0x8000-#bytes)
  local e=setmetatable({version=version,symbols=symbols,
    manifest={layout=layout or {}},rom=Rom.new(bytes)},Extractor)
  e.saveImage=function(_,saved,path) T.eq(saved,image,"real import saves its decoded image") end
  return e,function()return image end
end
for _,version in ipairs({"gold","silver","crystal"}) do
  for _,region in ipairs({"JohtoMap","KantoMap"}) do
    local e,image=fixture(version)
    T.eq(e:gen2TownMapImage(region,"fixture.png"),"assets/generated/fixture.png",version.." "..region.." imports")
    image=image()
    T.eq(image.width,160,"native screen width")
    T.eq(image.height,144,"native screen height")
    local matches=true
    for cell=0,359 do
      local tile=cell%48;local p=tile%6
      for y=0,7 do for x=0,7 do
        local shade=(tile+x+2*y)%4
        local c=image.pixels[(math.floor(cell/20)*8+y)*160+(cell%20)*8+x]
        matches=matches and math.abs(c[1]-(3*p+shade)/31)<1e-9
          and math.abs(c[2]-(2*p+2*shade)/31)<1e-9
          and math.abs(c[3]-(p+3*shade)/31)<1e-9 and c[4]==1
      end end
    end
    T.check(matches,version.." "..region..": all 23040 pixels match independent tile/palette pattern")
  end
end
local e,image=fixture("crystal",true,{townMapGfxCompressed=0})
T.check(e:gen2TownMapImage("JohtoMap","raw.png")~=nil,"explicit raw layout remains authoritative")
T.eq(image().pixels[0][1],0,"raw tile has no compressed-header displacement")
e=fixture("polishedcrystal",false,{townMapGfxCompressed=1})
T.check(e:gen2TownMapImage("JohtoMap","compressed.png")~=nil,"explicit compressed hack remains supported")
e=fixture("crystal")
e.gen2Lz=function()return {0}end
T.eq(e:gen2TownMapImage("JohtoMap","short.png"),nil,"truncated graphics cannot masquerade as a complete image")
love.image.newImageData=oldImageData
love.image=oldImage
T.finish("native GSC town-map pixels")
