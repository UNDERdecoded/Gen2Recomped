-- luajit tools/export_frlg_stage_profile.lua frlg-stage-profile.json
-- Export addresses/layout only; no cartridge or generated asset data.
love = require('tests.love_stub')
-- Required modules may log while loading. The JSON itself goes to a file.
local X = require('src.import.RomExtractorGen3')
local Json = require('src.link.Json')
local function object(value)
  if type(value) ~= 'table' then return value end
  local out = {}
  -- Encoding every key as an object key preserves mixed Lua tables too.
  for k,v in pairs(value) do out[tostring(k)] = object(v) end
  return out
end
local tables = {}
local extra = {TM_CASE_SCREEN=true,BERRY_POUCH_SCREEN=true,TEACHY_TV_SCREEN=true}
for name,t in pairs(X) do
  if type(t)=='table' and (name:find('FRLG') or name:match('^FIRERED_') or extra[name])
     and name~='FRLG_CALLBACK_PATH' and name~='FRLG_TARGET_LOCAL_LINEAR' then
    tables[name]=object(t)
  end
end
local f=assert(io.open(assert(arg[1], 'output JSON path required'),'w'))
f:write(Json.encode(tables));f:close()
