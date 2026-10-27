-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Identity=require('src.compat.gen1.MapIdentity')
local copy=require('src.mods.Merge').deepCopy
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local name=Identity.lookup(edition,4,1)
 local def={id='MAP_G04_N01',group=4,number=1,blocks={{1,2,3}},scripts={entry={'noop'}}}
 local alias=copy(def);alias.id='MAP_G_04_N_01';alias.sourceId=def.id
 local maps={[def.id]=def,[alias.id]=alias}
 T.eq(Identity.bind(maps,edition):nativeId(name),def.id,'Data spelling copies do not shadow the cartridge room')
 alias.blocks[1][1]=9
 T.eq(Identity.bind(maps,edition):nativeId(name),nil,'authored alternate layouts remain ambiguous')
 alias.blocks[1][1]=1;alias.scripts.entry[1]='changed'
 T.eq(Identity.bind(maps,edition):nativeId(name),nil,'distinct scripts cannot inherit cartridge identity')
 alias.scripts=copy(def.scripts);alias.sourceId=nil
 T.eq(Identity.bind(maps,edition):nativeId(name),nil,'similar spelling without source provenance is insufficient')
 alias.sourceId=def.id;alias.id='OTHER';maps[alias.id]=alias
 T.eq(Identity.bind(maps,edition):nativeId(name),nil,'arbitrary claimed source ids are insufficient')
end
T.finish('native companion map identity with unchanged generated spelling aliases')
