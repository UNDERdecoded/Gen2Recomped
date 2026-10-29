-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native GSC ROM programs in the actual interpreter's complete data schema.
-- Command/identifier provenance: compat/gen1-gsc; no ROM scripts authored here.
local Data=require('src.battle.Gen2AnimData')
local M={}
local function same(a,b)
  if type(a)~=type(b)then return false end
  if type(a)~='table'then return a==b end
  for k,v in pairs(a)do if not same(v,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end
  return true
end
function M.compile(imported,constants,version)
  if Data.isNative(imported)then return imported end
  local catalog=Data.tables(imported,constants,version)
  catalog.gen2,catalog.generation,catalog.format=true,2,'gsc-native-v1'
  catalog.commandFormat=imported.commandFormat
  catalog.source=imported.source or (imported.bank
    and 'ROM:BattleAnimations + data/battle_anims/*'or 'Registered GSC animation programs')
  catalog.bank,catalog.gameVersion=imported.bank,version
  catalog.scripts,catalog.scriptOrder,catalog.moves,catalog.ids,catalog.indices={},{},{},{},{}
  catalog.misc,catalog.moveAnims,catalog.move,catalog.effects={},{},{},{}
  local ids={};for id in pairs(imported.scripts or {})do ids[#ids+1]=id end
  table.sort(ids,function(a,b)if type(a)==type(b)then return a<b end;return tostring(a)<tostring(b)end)
  for _,id in ipairs(ids)do
    local script=imported.scripts[id]
    local code=script.code or {}
    local addresses=script.addresses
    local function key(index)
      if not index or not code[index]then return end
      local address=addresses and addresses[index]
      if address then return ('%04x'):format(address)end
      -- Non-ROM native registrations can supply flat programs too. Keep
      -- their own program/index namespace; never invent cartridge addresses.
      return 'program:'..tostring(id)..':'..tostring(index)
    end
    local localBlocks={}
    local function block(start)
      local name=key(start)
      if not name then return end
      if localBlocks[name]then return name end
      local rows,pending={},{}
      localBlocks[name]=rows
      for i=start,#code do
        local inst=code[i]
        local target=key(inst.to)
        rows[#rows+1]=Data.row(inst,target)
        if inst.to and target then pending[#pending+1]=inst.to end
        if inst.op=='ret'or inst.op=='jump'then break end
      end
      for _,target in ipairs(pending)do block(target)end
      return name
    end
    local entry=block(script.entry or 1)
    if entry then catalog.indices[id]=entry end
    -- Claim order follows the real root then its branch blocks. A shared
    -- ROM address must describe identical command bytes across all roots.
    local visited={}
    local function publish(name)
      if not name or visited[name]then return end
      visited[name]=true
      local rows=localBlocks[name]
      if catalog.scripts[name]then
        assert(same(catalog.scripts[name],rows),'conflicting GSC program at '..name)
      else
        catalog.scripts[name]=rows;catalog.scriptOrder[#catalog.scriptOrder+1]=name
      end
      for _,row in ipairs(rows)do
        for i=2,#row do if localBlocks[row[i]]then publish(row[i])end end
      end
    end
    publish(entry)
  end
  for move,id in pairs(imported.moveAnims or {})do
    local entry=catalog.indices[id]
    if entry then catalog.moves[move],catalog.moveAnims[move]=entry,entry end
  end
  for name,id in pairs(imported.ids or {})do catalog.ids[name]=catalog.indices[id]end
  for name,id in pairs(imported.misc or {})do catalog.misc[name]=catalog.indices[id]end
  return catalog
end
return M
