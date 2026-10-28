-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Find the native pointer table by its typed placeholders, never by English
-- wording or a provenance string. The caller has verified the full ROM hash.
local M={}
function M.profile(edition)
 local family=({firered='frlg',leafgreen='frlg',emerald='emerald',ruby='rs',sapphire='rs'})[edition]
 return family and require('src.import.gba.battle_text.'..family)
end
local function pointer(rom,off)
 if off<0 or off+4>rom.size then return end
 local at=rom:u32(off)-0x08000000
 if at>=0 and at<rom.size then return at end
end
local function phs(x,off,expected)
 if not off then return false end
 local _,_,nodes=x:readText(off,4096,nil,true)
 if not nodes then return false end
 local n=0
 for _,node in ipairs(nodes)do if node.t=='ph'then
  n=n+1;if node.code~=expected[n]then return false end
 end end
 return n==#expected
end
function M.locate(x,profile)
 local codes={};for code,name in pairs(profile.placeholders)do codes[name]=code end
 local signature=string.char(0xFD,assert(codes.B_TRAINER1_LOSE_TEXT),0xFF)
 local targets,at={},1
 while true do
  local found=x.rom.data:find(signature,at,true);if not found then break end
  targets[found-1]=true;at=found+1
 end
 local result
 for off=0,x.rom.size-profile.count*4,4 do
  local first=pointer(x.rom,off)
  if targets[first]and phs(x,pointer(x.rom,off+4),{codes.B_BUFF1,codes.B_BUFF2,codes.B_BUFF3})
    and phs(x,pointer(x.rom,off+8),{codes.B_BUFF1,codes.B_BUFF2})then
   local valid=true
   for index=0,profile.count-1 do
    local where=pointer(x.rom,off+index*4)
    if not where or not x:readText(where,4096,nil,true)then valid=false;break end
   end
   if valid then
    if result then return nil,'ambiguous native battle string table'end
    result=off
   end
  end
 end
 return result,result and nil or 'native battle string table unavailable'
end
function M.append(x,text,catalog)
 local profile=M.profile(catalog.edition);if not profile then return nil,'unknown native battle text edition'end
 local base,why=M.locate(x,profile);if not base then return nil,why end
 local count=0
 for name,index in pairs(profile.ids)do
  if index>=profile.first and index<profile.first+profile.count then
   local off=assert(pointer(x.rom,base+(index-profile.first)*4))
   local id=('TEXT_%06X'):format(off)
   if not catalog.records[id]then
    local plain,used,ir=x:readText(off,4096,nil,true)
    catalog.records[id]={plain=plain,ir=ir,nativePlain=text[id],address=off,bytes=used}
   end
   catalog.named[name]=id
   count=count+1
  end
 end
 catalog.battle={tableOffset=base,first=profile.first,count=profile.count}
 return true,count
end
return M
