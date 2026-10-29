-- GSC GetSubstitutePic / GetMinimizePic, decoded from the mounted ROM.
-- Scratch tiles are column-major on the cartridge; PNG tiles are row-major.
-- No ROM image bytes are shipped with the engine.
local Writer=require('src.import.ImageWriter')
local M={}
local function bytes(e,name,count)
  local p=e:symbol(name)
  if not p or not e.rom then return end
  local ok,raw=pcall(e.rom.bytes,e.rom,p.bank,p.address,count)
  if not ok or type(raw)~='table' or #raw~=count then return end
  for _,value in ipairs(raw)do
    if type(value)~='number' or value%1~=0 or value<0 or value>255 then return end
  end
  return raw
end
local function box(raw,n,placements)
  local out={}
  for i=1,n*n*16 do out[i]=0 end
  for _,p in ipairs(placements)do
    local dest=(p[2]*n+p[1])*16
    for j=1,16 do out[dest+j]=raw[p[3]*16+j]end
  end
  return Writer.decode2bpp(out,n*8,n*8,true)
end
function M.extract(e)
  local doll=bytes(e,'MonsterSpriteGFX',8*16)
  local mini=bytes(e,'MinimizePic',16)
  local staged=e:symbol('BattleAnimCmd_UpdateActorPic')~=nil
  if not(doll or mini or staged)then return end
  local record={version=1,stagedActorPic=staged}
  if doll then
    local front='battle/gen2_substitute_front.png'
    local back='battle/gen2_substitute_back.png'
    local sheet='battle/gen2_substitute_sheet.png'
    e:saveImage(box(doll,7,{{2,5,0},{3,5,1},{2,6,2},{3,6,3}}),front)
    e:saveImage(box(doll,6,{{2,4,4},{3,4,5},{2,5,6},{3,5,7}}),back)
    e:saveImage(Writer.decode2bpp(doll,16,32,true),sheet)
    record.substitute={enemy='assets/generated/'..front,
      player='assets/generated/'..back,sheet='assets/generated/'..sheet}
  end
  if mini then
    local front='battle/gen2_minimize_front.png'
    local back='battle/gen2_minimize_back.png'
    e:saveImage(box(mini,7,{{3,5,0}}),front)
    e:saveImage(box(mini,6,{{3,4,0}}),back)
    record.minimize={enemy='assets/generated/'..front,player='assets/generated/'..back}
    -- GS $e8/$e9 are ret. Crystal stages into vTiles0 before copying to the
    -- actor's BG slot; positive symbols also admit supported renamed editions.
    record.stagedMinimize=e:symbol('BattleAnimCmd_Minimize')~=nil
      and e:symbol('BattleAnimCmd_UpdateActorPic')~=nil
  end
  return record
end
return M
