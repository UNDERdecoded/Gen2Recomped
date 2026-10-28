-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local M=require('src.import.Gen3DoorMetadata')
local Rom=require('src.import.RomGba');local V=require('src.core.GameVersion')
local function le(n,bytes)local out={}for i=1,bytes do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
for _,p in ipairs{{'firered',0x35b5d8,32},{'leafgreen',0x35b5b8,32},{'emerald',0x497174,53},{'ruby',0x30f9b4,34},{'sapphire',0x30f944,34}}do
 local edition,offset,count=p[1],p[2],p[3];local fr=edition=='firered'or edition=='leafgreen'
 local rows={}
 for i=0,count-1 do
  local size=fr and i%2 or edition=='emerald'and(1+i%2)or 0
  rows[#rows+1]=le(i+1,2)..string.char(i%2,size)..le(0x08000040,4)..le(0x08000020,4)
 end
 -- Synthetic structures exercise the binary reader without ROM assets. The
 -- caller supplies its already-authenticated import manifest's full digest.
 local raw=string.rep('\0',offset)..table.concat(rows);local rom=Rom.new(raw)
 local facts=assert(M.read(rom,edition,V.info(edition).sha1))
 T.eq(#facts.entries,count);T.eq(facts.entries[1].mid,1);T.eq(facts.by_mid[2].sound,'sliding')
 local info=facts.doors[facts.by_mid[2].tile]
 T.eq(info.frame_width,edition=='emerald'and 32 or 16);T.eq(info.frame_height,32)
 T.eq(facts.doors[facts.by_mid[1].tile].frame_height,fr and 16 or 32)
 T.eq(M.read(rom,edition,string.rep('0',40)),nil,'a different cartridge digest cannot borrow a profile')
 T.eq(M.read(Rom.new(raw:sub(1,-2)),edition,V.info(edition).sha1),nil,'truncated descriptor tables are rejected as a whole')
 local function damaged(at,bytes)
  local data=raw:sub(1,at)..bytes..raw:sub(at+#bytes+1)
  T.eq(M.read(Rom.new(data),edition,V.info(edition).sha1),nil,'invalid descriptor cannot publish a partial manifest')
 end
 damaged(offset+3,string.char(9));damaged(offset+2,string.char(9))
 damaged(offset+4,le(0,4));damaged(offset+8,le(0,4));damaged(0x20,string.char(16))
end
T.eq(M.read({},'crystal',V.info('crystal').sha1),nil,'other generations do not enter the reader')
T.finish('native door descriptor shapes, profile gates, bounds and atomic rejection')
