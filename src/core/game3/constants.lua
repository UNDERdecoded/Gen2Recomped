-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Detached names/indices from the current native import, never another ROM.
local Version=require('src.core.GameVersion')
local Native=require('src.compat.gen1.NativeSession')
local C={}
local function enum(rows,prefix)
 local names,ids={},{}
 for name,id in pairs(rows)do
  if type(name)=='string'and type(id)=='number'then names[(prefix or'')..name]=id;ids[id]=ids[id]or((prefix or'')..name)end
 end
 return{byName=names,byId=ids}
end
function C.of(edition)
 edition=edition or Version.get();assert(edition==Version.get(),'foreign native constant dataset')
 local g=Native.game();assert(g,'no native GBA constant dataset')
 local data=g.data;local rows={}
 local forms=data.field and data.field.playerForms or{}
 for who,r in pairs(forms)do
  if r.picIndex then
   local frlg=edition=='firered'or edition=='leafgreen'
   local name=who=='boy'and(frlg and'TRAINER_PIC_RED'or'TRAINER_PIC_BRENDAN')or who=='girl'and(frlg and'TRAINER_PIC_LEAF'or'TRAINER_PIC_MAY')
   if name then rows[name]=r.picIndex end
  end
 end
 -- Named special partners retain the picture identity on native trainer rows.
 for _,r in pairs(data.trainers or{})do
  if(r.name=='WALLY'or r.name=='STEVEN')and type(r.picIndex)=='number'then
   local key='TRAINER_PIC_'..r.name
   if rows[key]and rows[key]~=r.picIndex then error('ambiguous native trainer identity: '..r.name)end
   rows[key]=r.picIndex
  end
 end
 local sections={}
 for id,name in pairs(data.constants.gen3MapSections or{})do
  if type(name)=='table'then name=name.name end
  if type(name)=='string'then sections['MAPSEC_'..name:upper():gsub('[^%w]+','_')]=id end
 end
 local out={game=edition,trainer_classes=enum(rows),region_map_sections=enum(sections)}
 function out:raw(kind)local row=self[kind];return row and require('src.mods.Merge').deepCopy(row)end
 function out:id(kind,name)local row=self[kind];return row and row.byName[name]end
 function out:name(kind,id)local row=self[kind];return row and row.byId[id]end
 return out
end
C.active=function()return C.of()end
return C
