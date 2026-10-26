-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Journal=require('src.core.StepJournal')
local S={}
local owners=setmetatable({},{__mode='k'})
function S.available()
  return Journal.available()
end
function S.sync()
  if not S.available() then return false end
  local ok,started=pcall(love.system.syncHealthSteps)
  return ok and started==true
end
function S.retire(loader,id)
  local bucket=owners[loader]
  if not bucket then return end
  if id then
    if bucket[id] then bucket[id].active=false;bucket[id]=nil end
  else
    for key,state in pairs(bucket)do state.active=false;bucket[key]=nil end
    owners[loader]=nil
  end
end
function S.unloadAll()
  for loader in pairs(owners)do S.retire(loader) end
end
function S.forMod(loader,mod)
  local id=mod.manifest.id
  S.retire(loader,id)
  local state={active=true,loader=loader}
  owners[loader]=owners[loader] or {};owners[loader][id]=state
  local fs=love and love.filesystem
  local function permitted()
    if not mod.manifest.permissionSet.steps then error('mod.steps for '..id..' needs the "steps" permission',3) end
    if not state.active then error('mod.steps for '..id..' belongs to a retired loader',3) end
  end
  local api={}
  function api:available()return state.active and mod.manifest.permissionSet.steps==true and S.available() end
  function api:sync()permitted();return S.sync()end
  function api:poll()
    permitted()
    if not S.available() then return nil end
    local snapshot,why=Journal.read(fs)
    if not snapshot then return nil,why end
    local ledger;ledger,why=Journal.receipts(fs)
    if not ledger then return nil,why end
    local previous=ledger.owners[id]
    if not previous then
      local count=0;for _ in pairs(ledger.owners)do count=count+1 end
      if count>=Journal.MAX_OWNERS then return nil,'step receipt ledger full' end
    end
    local delivery,nextCursor,err=Journal.next(snapshot,previous)
    if not delivery then return nil,err end
    ledger.owners[id]=nextCursor
    local ok;ok,why=Journal.saveReceipts(fs,ledger)
    if not ok then return nil,why end
    return delivery
  end
  return api
end
return S
