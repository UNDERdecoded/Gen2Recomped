-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local Version=require('src.core.GameVersion')
local layouts={firered='frlg',leafgreen='frlg',emerald='rse',ruby='rse',sapphire='rse'}
local original=Version.get()
for id,info in pairs(Version.VERSIONS)do
  local prefix,suffix,manifest=info.cachePrefix,info.saveSuffix,info.manifest
  T.eq(Version.layout(id),info.layout or layouts[id],id..' metadata layout')
  T.eq(Version:layout(id),info.layout or layouts[id],id..' colon query')
  Version.set(id);T.eq(Version.layout(),info.layout or layouts[id],id..' current query')
  T.eq(Version.get(),id);T.eq(info.cachePrefix,prefix);T.eq(info.saveSuffix,suffix);T.eq(info.manifest,manifest)
end
Version.VERSIONS.QA_LAYOUT={id='QA_LAYOUT',generation=3,layout='custom'}
T.eq(Version.layout('QA_LAYOUT'),'custom','an explicit registered layout takes precedence')
Version.VERSIONS.QA_LAYOUT=nil
T.eq(Version.layout('UNKNOWN'),nil,'unknown IDs cannot inherit the current cartridge layout')
Version.set(original)
T.finish('native registered version layout queries')
