-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Inspect public Gen2 descriptors without executing another engine's bodies.
package.path='./?.lua;./?/init.lua;'..package.path
local Schemas=require('src.mods.Schemas')
local Json=require('src.link.Json')
local function describe(field)
  local out={kind=field.kind,min=field.min,max=field.max,registry=field.registry}
  if field.inner then out.inner=describe(field.inner)end
  return out
end
local out={}
for _,name in ipairs({'apricorns','decorations','landmarks','phone_contacts','radio_channels'})do
  local spec=assert(Schemas.REGISTRIES[name],name)
  local entry={semantics=spec.semantics,fields={}}
  for key,field in pairs(spec.fields)do entry.fields[key]=describe(field)end
  out[name]=entry
end
print('REGISTRY_CONTRACT '..Json.encode(out))
