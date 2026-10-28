-- Native imported animation tables -> genuine GSC runtime data.
-- Identifier/command formats derive from Gen1Recomp535a5ec0 under GPLv3
-- plus Additional Terms; see compat/gen1-gsc/. No ROM program is invented.
local Ids=require('src.battle.Gen2AnimObjectIds')
local M={}
M.CACHE_REVISION=3
function M.isNative(anims)
  return anims and anims.generation==2 and type(anims.scripts)=='table'
    and type(anims.moves)=='table'and type(anims.oamsets)=='table'
end
function M.isGen2(anims)
  return anims and (anims.gen2==true or M.isNative(anims))
end
local function order(constants,key)
  return constants and constants[key] or Ids[key]
end
function M.tables(anims,constants,version)
  anims=anims or {}
  local c={}
  for _,key in ipairs({'battleAnimFramesetOrder','battleAnimObjectOrder',
      'battleAnimFuncOrder','battleAnimGfxOrder','battleAnimObPaletteOrder'})do c[key]=order(constants,key)end
  c.battleBgEffectOrder=constants and constants.battleBgEffectOrder
    or require('src.battle.Gen2BgEffectIds').forVersion(version or anims.gameVersion)
  if M.isNative(anims)then return anims,c end
  local data={objects={},framesets={},oamsets={},gfx={},palettes=anims.palettes,
    pictureArt=anims.pictureArt}
  for id,row in pairs(anims.objects or {})do
    local name=c.battleAnimObjectOrder[id+1]or id
    local native=anims.functions and anims.functions[row.fn]
    local fn=constants and constants.battleAnimFuncOrder
      and constants.battleAnimFuncOrder[(row.fn or 0)+1]
      or Ids.nativeFunctions[native] or native
      or c.battleAnimFuncOrder[(row.fn or 0)+1]
    data.objects[name]={flags=row.oamFlags,fixY=row.fixY,
      frameset=c.battleAnimFramesetOrder[row.frameset+1]or row.frameset,
      func=fn,palette=c.battleAnimObPaletteOrder[(row.palette or 0)+1]or row.palette,
      gfx=c.battleAnimGfxOrder[(row.gfx or 0)+1]or row.gfx}
  end
  for id,set in pairs(anims.framesets or {})do
    local rows={}
    for _,frame in ipairs(set.frames or {})do
      rows[#rows+1]=frame.wait and {'wait',frame.duration or 0}
        or {'frame',frame.oam,frame.duration or 0,
          (frame.xflip and 0x20 or 0)+(frame.yflip and 0x40 or 0)}
    end
    rows[#rows+1]={set.loop=='restart'and 'restart'
      or set.loop=='delete'and 'delete'or 'end'}
    data.framesets[c.battleAnimFramesetOrder[id+1]or id]=rows
  end
  for id,row in pairs(anims.oam or {})do
    data.oamsets[id]={vtile=row.tile,sprites=row.sprites}
  end
  for id,sheet in pairs(anims.gfx or {})do
    data.gfx[c.battleAnimGfxOrder[id+1]or id]=sheet
  end
  return data,c
end

local ops={delay='wait',ifvarequal='if_var_equal',
  ifparamequal='if_param_equal',ifparamand='if_param_and'}
function M.row(inst,target)
  local op=ops[inst.op]or inst.op
  local row={op}
  for _,value in ipairs(inst.args or {})do row[#row+1]=type(value)=='number'and value%256 or value end
  if op=='wait'then row[2]=inst.frames or 0
  elseif op=='gfx'then
    row={tostring(#(inst.ids or {}))..'gfx'}
    for _,id in ipairs(inst.ids or {})do row[#row+1]=id end
  elseif op=='jump'or op=='call'or op=='jumpuntil'or op=='ifpmode'then
    row={op,target}
  elseif op=='loop'or op=='if_var_equal'or op=='if_param_equal'or op=='if_param_and'then
    row={op,row[2],target}
  end
  return row
end
-- Native scripts already contain all reached subroutines in one flat ROM
-- walk. A target remains that walk's instruction index; suffix lists let the
-- GSC interpreter fetch it without synthesizing addresses or instructions.
function M.program(tables,script)
  local data={}
  for key,value in pairs(tables)do data[key]=value end
  data.scripts={}
  if not script then return data end
  local rows,targets={},{}
  targets[script.entry or 1]=true
  for i,inst in ipairs(script.code or {})do
    local row=M.row(inst,inst.to)
    if inst.to then targets[inst.to]=true end
    rows[i]=row
  end
  for start in pairs(targets)do
    local suffix={}
    for i=start,#rows do suffix[#suffix+1]=rows[i]end
    data.scripts[start]=suffix
  end
  return data,script.entry or 1
end
return M
