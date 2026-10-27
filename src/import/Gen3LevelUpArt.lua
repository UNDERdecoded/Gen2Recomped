-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- FRLG's additional vertical streaks use their own 8x16 cartridge sprite.
-- Offsets were found by matching every decoded pixel/palette word against
-- pret/pokefirered ce6406d8's level_up.png, then checked on both exact ROMs.
-- Publish hashes and addresses only; artwork remains in the user's cartridge.
local Version=require('src.core.GameVersion')
local M={REVISION=1}
local profiles={firered={gfx=4561032,palette=4561000},leafgreen={gfx=4559528,palette=4559496}}
local gfxDigest='0dbfbcf3f4a3fef33ba7449f89c2e510f780dfc063c4dd631c1715d3848152b5'
local palDigest='fbd58ce9122f0aa5058167d5e185820f19ba95d86f5ed52629d19bf2b0937f9a'
function M.supports(edition)return profiles[edition]~=nil end
local function digest(bytes)
 return love.data.encode('string','hex',love.data.hash('sha256',bytes))
end
function M.read(x)
 local edition=type(x.version)=='table'and x.version.id or x.version
 local profile=profiles[edition]
 if not profile then return nil,'no native vertical-streak profile for this edition'end
 local info=Version.info(edition)
 if not(x.manifest and x.manifest.romSha1==info.sha1)
  or require('src.import.RomVerification').sha1(x.rom.data)~=info.sha1 then
  return nil,'native vertical-streak cartridge fingerprint mismatch'
 end
 local ok,tiles=pcall(x.rom.lz77,x.rom,profile.gfx)
 if not ok or type(tiles)~='table'or #tiles~=64 then return nil,'invalid native vertical-streak tile size'end
 local packed={};for i=1,#tiles do packed[i]=string.char(tiles[i])end
 if digest(table.concat(packed))~=gfxDigest then return nil,'native vertical-streak tile fingerprint mismatch'end
 local palette,raw={},{}
 for index=0,15 do
  local color=x.rom:u16(profile.palette+index*2)
  if color>=32768 then return nil,'invalid native vertical-streak palette'end
  palette[index]=color;raw[#raw+1]=string.char(color%256,math.floor(color/256))
 end
 if digest(table.concat(raw))~=palDigest then return nil,'native vertical-streak palette fingerprint mismatch'end
 return {tiles=tiles,palette=palette,width=8,height=16,edition=edition,
  romSha1=info.sha1,gfxOffset=profile.gfx,paletteOffset=profile.palette}
end
function M.image(record)
 local image=require('src.import.ImageWriter').blank(8,16)
 for y=0,15 do for x=0,7 do
  local byte=record.tiles[y*4+math.floor(x/2)+1]
  local index=math.floor(byte/(x%2==0 and 1 or 16))%16
  local color=record.palette[index]
  image:setPixel(x,y,(color%32)/31,(math.floor(color/32)%32)/31,
   (math.floor(color/1024)%32)/31,index==0 and 0 or 1)
 end end
 return image
end
return M
