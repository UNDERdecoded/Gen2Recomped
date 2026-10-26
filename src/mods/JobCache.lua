-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Job-private staging, reversible publication and restart recovery. No source
-- media or unrelated cache files are removed. Journal paths are derived again
-- from validated keys before any recovery mutation.
local Storage=require('src.mods.Storage')
local Data=require('src.import.PackData')
local Writer=require('src.import.LuaWriter')
local publish=require('src.import.PackPublish')
local C={MAX_BYTES=64*1024*1024,MAX_TOTAL=256*1024*1024,MAX_KEYS=256}
local PREFIX='.job-transactions'
local function plainPath(path)return type(path)=='string' and path:gsub('\\','/'):gsub('/+$','')end
local function localFile(fs,path)
  if not fs.getRealDirectory or not fs.getWriteRoot then return true end
  local actual=fs.getRealDirectory(path)
  return actual and plainPath(actual)==plainPath(fs.getWriteRoot()) or false
end
local function scope(fs)
  local root=fs.getWriteRoot and fs.getWriteRoot()
  return function()
    if fs.getWriteRoot and fs.getWriteRoot()~=root then error('game-data folder changed during job',0) end
  end
end
local function read(fs,path,maximum,expected)
  local info=fs.getInfo(path,'file');local size=info and info.size
  if not info or info.type~='file' or type(size)~='number' or size<0 or size%1~=0 or size>maximum then return nil,'cache file missing or oversized' end
  if expected and size~=#expected then return nil,'staged cache size mismatch' end
  local chunks,handle={},nil
  local ok,result=pcall(function()
    if fs.newFile then handle=assert(fs.newFile(path));assert(handle:open('r')) end
    for offset=0,size-1,1048576 do
      local count=math.min(1048576,size-offset)
      local chunk
      if handle then chunk=handle:read(count)
      elseif fs.readRange then chunk=fs.readRange(path,offset,count)
      elseif size<=1048576 and fs.read then chunk=fs.read(path,size)
      else error('bounded cache reads unavailable',0) end
      assert(type(chunk)=='string' and #chunk==count,'short cache read')
      if expected then
        assert(chunk==expected:sub(offset+1,offset+count),'staged cache contents mismatch')
      else chunks[#chunks+1]=chunk end
    end
    if expected then return true end
    return table.concat(chunks)
  end)
  if handle then pcall(handle.close,handle) end
  if not ok then return nil,tostring(result) end
  return result
end
local function valid(store,key)
  if type(key)~='string' or key==PREFIX or key:sub(1,#PREFIX+1)==PREFIX..'/' then return nil,'reserved job cache key' end
  local _,code,why=store:stat(nil,key)
  if code=='invalid_key' or code=='storage_unavailable' then return nil,why or code end
  return true
end
local function exists(fs,path)return fs.getInfo(path,'file')~=nil end
local function remove(fs,path)
  if exists(fs,path) then assert(fs.remove(path),'could not remove job-owned file') end
end
local function cleanup(fs,dir,rows,guard)
  for index in ipairs(rows) do
    for _,name in ipairs({'new-'..index..'.part','old-bytes-'..index..'.part','old-record-'..index..'.part'}) do
      if guard then guard() end;remove(fs,dir..'/'..name)
    end
  end
  if guard then guard() end;remove(fs,dir..'/journal.lua')
  if fs.removeDir then pcall(fs.removeDir,dir) end
end
local function restore(fs,store,dir,rows,guard)
  for index,row in ipairs(rows) do
    if guard then guard() end
    local dest=store:_path(row.key,Storage.BYTES_EXT)
    local backup=dir..'/old-bytes-'..index..'.part'
    if exists(fs,backup) then
      if localFile(fs,dest) then remove(fs,dest) end
      assert(fs.rename(backup,dest),'could not restore previous byte cache')
    elseif not row.bytes and not exists(fs,dir..'/new-'..index..'.part') and localFile(fs,dest) then remove(fs,dest) end
    backup=dir..'/old-record-'..index..'.part'
    if exists(fs,backup) then
      local record=store:_path(row.key,Storage.RECORD_EXT)
      if localFile(fs,record) then remove(fs,record) end
      assert(fs.rename(backup,record),'could not restore previous record cache')
    end
  end
  store:_invalidate()
end
function C.recover(store,fs)
  if not fs or not fs.getDirectoryItems then return true end
  local guard=scope(fs);local base=store.root..'/'..PREFIX
  if not fs.getInfo(base,'directory') then return true end
  for _,token in ipairs(fs.getDirectoryItems(base) or {}) do
    if token:match('^[a-f0-9]+$') then
      local dir=base..'/'..token;local path=dir..'/journal.lua'
      if exists(fs,path) and localFile(fs,path) then
        local bytes,why=Data.read(fs,path);if not bytes then return nil,why end
        local j;j,why=Data.decode(bytes)
        if not j or j.format~=1 or j.owner~=store.modId or type(j.rows)~='table' or #j.rows>C.MAX_KEYS
            or (j.state~='publishing' and j.state~='committed') then return nil,'invalid job recovery journal' end
        local seen,count={},0
        for index,row in pairs(j.rows) do
          count=count+1
          if type(index)~='number' or index%1~=0 or index<1 or index>#j.rows or type(row)~='table'
              or not valid(store,row.key) or seen[row.key] or type(row.bytes)~='boolean' or type(row.record)~='boolean' then
            return nil,'invalid job recovery row'
          end
          seen[row.key]=true
        end
        if count~=#j.rows then return nil,'job recovery rows must be a dense array' end
        local ok,err=pcall(function()
          guard()
          if j.state=='publishing' then restore(fs,store,dir,j.rows,guard) end
          guard();cleanup(fs,dir,j.rows,guard)
        end)
        if not ok then return nil,tostring(err) end
      end
    end
  end
  return true
end
function C.new(store,fs,token)
  assert(type(token)=='string' and token:match('^[a-f0-9]+$'),'invalid engine job token')
  local guard=scope(fs);local rows,byKey,total,state={},{},0,'open'
  local dir=store.root..'/'..PREFIX..'/'..token
  local api={}
  local function check(key)
    guard();assert(state=='open','job cache is '..state)
    local ok,why=valid(store,key);assert(ok,why)
  end
  function api:write(key,bytes)
    check(key)
    if type(bytes)~='string' or #bytes>C.MAX_BYTES then return false,'too_large','job cache write exceeds its limit' end
    local index=byKey[key];local old=index and rows[index].size or 0
    if total-old+#bytes>C.MAX_TOTAL or (not index and #rows>=C.MAX_KEYS) then return false,'too_large','job cache budget exceeded' end
    index=index or #rows+1
    assert(fs.createDirectory(dir),'job cache staging unavailable')
    local path=dir..'/new-'..index..'.part'
    rows[index]={key=key,size=#bytes};byKey[key]=index
    local wrote,why=fs.write(path,bytes)
    if not wrote or read(fs,path,C.MAX_BYTES,bytes)~=true then state='failed';return false,'write_failed',why or 'job staging verification failed' end
    guard()
    total=total-old+#bytes
    return true
  end
  function api:read(key)
    check(key);local index=byKey[key]
    if index then return read(fs,dir..'/new-'..index..'.part',C.MAX_BYTES) end
    local info,code,why=store:stat(nil,key)
    if not info then return nil,code,why end
    if info.kind~='bytes' then return nil,'type_mismatch','cache key holds a record' end
    local bytes,err=read(fs,store:_path(key,Storage.BYTES_EXT),C.MAX_BYTES)
    return bytes,not bytes and 'read_failed' or nil,err
  end
  function api:info(key)
    check(key);local index=byKey[key]
    if index then return {key=key,kind='bytes',type='file',size=rows[index].size} end
    local info,code,why=store:stat(nil,key)
    if info then info.type='file' end
    return info,code,why
  end
  function api:exists(key)return self:info(key)~=nil end
  function api:cancel()
    if state=='committed' or state=='cancelled' then return end
    local ok=pcall(guard)
    if ok then pcall(cleanup,fs,dir,rows,guard) end
    state='cancelled'
  end
  function api:commit()
    guard();if state~='open' then return nil,'job cache is '..state end
    if #rows==0 then state='committed';return true end
    local journal={format=1,owner=store.modId,state='publishing',rows=rows}
    for index,row in ipairs(rows) do
      if not exists(fs,dir..'/new-'..index..'.part') then return nil,'missing staged cache file' end
      row.bytes=exists(fs,store:_path(row.key,Storage.BYTES_EXT)) and localFile(fs,store:_path(row.key,Storage.BYTES_EXT)) or false
      row.record=exists(fs,store:_path(row.key,Storage.RECORD_EXT)) and localFile(fs,store:_path(row.key,Storage.RECORD_EXT)) or false
    end
    local ok,err=pcall(function()
      assert(publish(fs,dir..'/journal.lua',Writer.encode(journal)))
      for index,row in ipairs(rows) do
        guard()
        for kind,extension in pairs({bytes=Storage.BYTES_EXT,record=Storage.RECORD_EXT}) do
          if row[kind] then assert(fs.rename(store:_path(row.key,extension),dir..'/old-'..kind..'-'..index..'.part'),'cache backup failed') end
        end
        store:_ensureDir(store:_path(row.key,Storage.BYTES_EXT))
        assert(fs.rename(dir..'/new-'..index..'.part',store:_path(row.key,Storage.BYTES_EXT)),'cache publication failed')
      end
      guard();journal.state='committed'
      assert(publish(fs,dir..'/journal.lua',Writer.encode(journal)))
    end)
    if not ok then
      local restored,why=pcall(function()guard();restore(fs,store,dir,rows,guard);cleanup(fs,dir,rows,guard)end)
      state='failed'
      return nil,tostring(err)..(not restored and '; recovery pending: '..tostring(why) or '')
    end
    state='committed';store:_invalidate();pcall(cleanup,fs,dir,rows,guard)
    return true
  end
  function api:state()return state end
  return api
end
return C
