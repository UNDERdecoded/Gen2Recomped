-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Reuse a static native palette projection only after comparing every RGB
-- input by value. Caller-visible palette tables are never the cache's owner.
local C={};C.__index=C
local function plain(value)return type(value)=='table'and getmetatable(value)==nil end
local function copyRows(rows)
 local out={}
 for slot=0,15 do local row={};out[slot]=row;for color=0,15 do row[color]=rows[slot][color]end end
 return out
end
local function inputs(self,expected,out)
 local decoder,layout=self.decoder,self.layout
 local state=decoder.paletteState
 if not plain(state)or not state.complete or not plain(state.primary)or not plain(state.secondary)then return false end
 for _,bank in ipairs{decoder.primary,decoder.secondary}do
  if not plain(bank)or not plain(bank.paletteCycles)or next(bank.paletteCycles)~=nil then return false end
 end
 local at=0
 for slot=0,15 do
  local reserved=slot>=(layout.palettesTotal or 13)
  local list=reserved and decoder.primary.palettes or(slot<decoder.palettesInPrimary and state.primary or state.secondary)
  if not plain(list)then return false end
  local row=list[reserved and 1 or slot+1];if not plain(row)then return false end
  for color=0,15 do
   local rgb=row[color+1];if not plain(rgb)then return false end
   for channel=1,3 do
    local value=not reserved and slot<decoder.palettesInPrimary and color==0 and 0 or rgb[channel]
    if type(value)~='number'then return false end
    at=at+1
    if expected and expected[at]~=value then return false end
    if out then out[at]=value end
   end
  end
 end
 return true
end
function C.new(decoder,layout)
 return setmetatable({decoder=decoder,layout=layout,hits=0,misses=0},C)
end
local function eligible(overrides)return plain(overrides)and next(overrides)==nil end
function C:read(overrides,rows)
 local d=self.decoder;local saved=self.saved
 if saved and eligible(overrides)and rows
  and saved.primaryBytes==d.primary.sourcePaletteBytes and saved.secondaryBytes==d.secondary.sourcePaletteBytes
  and saved.split==d.palettesInPrimary and saved.total==(self.layout.palettesTotal or 13)
  and inputs(self,saved.rgb)then
  local same=true
  for slot=0,15 do if rows[slot]~=saved.rows[slot]then same=false;break end end
  if same then
   self.hits=self.hits+1
   return saved.lut,copyRows(saved.bgr),saved.key,{}
  end
 end
 self.misses=self.misses+1
end
function C:remember(overrides,rows,lut,bgr,key)
 self.saved=nil
 if not eligible(overrides)then return end
 local rgb={};if not inputs(self,nil,rgb)then return end
 local d=self.decoder;local savedRows,savedLut={},{}
 for slot=0,15 do savedRows[slot]=rows[slot]end
 for i=0,255 do savedLut[i]=lut[i]end
 self.saved={rgb=rgb,primaryBytes=d.primary.sourcePaletteBytes,secondaryBytes=d.secondary.sourcePaletteBytes,
  split=d.palettesInPrimary,total=self.layout.palettesTotal or 13,rows=savedRows,lut=savedLut,bgr=copyRows(bgr),key=key}
end
return C
