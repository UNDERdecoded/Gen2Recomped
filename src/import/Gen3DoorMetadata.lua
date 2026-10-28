-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Read the authenticated cartridge's door graphics descriptors. No pixel
-- copies, animation controller, sound playback or map edits live here.
local M={REVISION=1}
-- pret field_door tables: matching cartridge data symbols and FR/LG's
-- sDoorGraphics. Locations were checked against all five complete ROM hashes.
local profiles={
 firered={'41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc',0x35b5d8,32},
 leafgreen={'574fa542ffebb14be69902d1d36f1ec0a4afd71e',0x35b5b8,32},
 emerald={'f3ae088181bf583e55daf962a92bb46f4f1d07b7',0x497174,53},
 ruby={'f28b6ffc97847e94a6c21a63cacf633ee5c8df1e',0x30f9b4,34},
 sapphire={'3ccbbd45f8553c36463f13b938e833f652b793e4',0x30f944,34},
}
local sounds={[0]='normal',[1]='sliding',[2]='arena'}
function M.read(rom,edition,sha1)
 local p=profiles[edition]
 if not p or p[1]~=sha1 then return nil,'door metadata profile unavailable'end
 if not(rom and type(rom.data)=='string'and#rom.data>=p[2]+p[3]*12)then return nil,'door table outside cartridge'end
 local frlg=edition=='firered'or edition=='leafgreen'
 local out={schema=M.REVISION,edition=edition,romSha1=sha1,family=frlg and'frlg'or'rse',entries={},doors={},by_mid={}}
 for i=0,p[3]-1 do
  local off=p[2]+i*12
  local mid,sound,size=rom:u16(off),rom:u8(off+2),rom:u8(off+3)
  local tiles,pals=rom:pointer(off+4),rom:pointer(off+8)
  local validSize=frlg and(size==0 or size==1)or edition=='emerald'and(size==1 or size==2)
   or(edition=='ruby'or edition=='sapphire')and size==0
  if mid>=1024 or not sounds[sound]or(frlg and sound>1)or not validSize
   or not tiles or not pals or pals+8>#rom.data then return nil,'invalid native door descriptor'end
  local width=size==2 and 32 or 16
  local height=frlg and(size==1 and 32 or 16)or 32
  if tiles+width*height/2>#rom.data then return nil,'door artwork outside cartridge'end
  local name=('native_door_%d'):format(i)
  local row={index=i,mid=mid,tile=name,sound=sounds[sound],sound_type=sound,size_type=size,
   size=(width/16)..'x'..(height/16)}
  out.entries[#out.entries+1]=row
  if not out.by_mid[mid]then out.by_mid[mid]=row end
  local slots={}
  for n=0,7 do
   local slot=rom:u8(pals+n);if slot>15 then return nil,'invalid door palette slot'end
   slots[n+1]=slot
  end
  out.doors[name]={frame_width=width,frame_height=height,nativeTilesOffset=tiles,paletteSlots=slots}
 end
 return out
end
return M
