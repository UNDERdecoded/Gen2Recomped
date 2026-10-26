-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native producers own the cumulative journal. Consumers only advance their
-- own receipts, so reading never races a producer's read/merge/delete cycle.
local Json = require('src.link.Json')
local J = { FILE='steps_journal.json', RECEIPTS='steps_receipts.json',
  MAX_BYTES=8192, MAX_RECEIPTS_BYTES=262144, MAX_OWNERS=1024,
  MAX_TOTAL=9007199254740991, MAX_DELIVERY=50000 }
function J.available()
  local system=love and love.system
  if not (system and type(system.syncHealthSteps)=='function' and type(system.stepJournalVersion)=='function') then return false end
  local ok,version=pcall(system.stepJournalVersion)
  return ok and version==1
end
local function integer(n)
  return type(n)=='number' and n>=0 and n<=J.MAX_TOTAL and n%1==0
end
local function epoch(value)
  return type(value)=='string' and #value>=1 and #value<=64 and value:match('^[a-zA-Z0-9_-]+$')~=nil
end
local function date(value)
  return value==nil or (type(value)=='string' and #value<=64 and not value:find('[%z%c]'))
end
function J.cursor(value)
  return type(value)=='table' and epoch(value.epoch) and integer(value.total) and date(value.to)
end
local function read(fs,path,limit)
  if not (fs and fs.getInfo and fs.read) then return nil,'step storage unavailable' end
  local info=fs.getInfo(path,'file')
  if not info then return nil end
  if info.type~='file' or not integer(info.size) or info.size>limit then return nil,'step file oversized or invalid' end
  local bytes=fs.read(path,limit+1)
  if type(bytes)~='string' or #bytes>limit then return nil,'step file unreadable or oversized' end
  local ok,value=pcall(Json.decode,bytes)
  if not ok or type(value)~='table' then return nil,'step file is not valid JSON' end
  return value
end
function J.read(fs)
  local value,why=read(fs,J.FILE,J.MAX_BYTES)
  if not value then return nil,why end
  if value.version~=1 or not J.cursor(value) or not date(value.from)
      or (value.source~='healthkit' and value.source~='android-counter') then
    return nil,'invalid native step journal'
  end
  return value
end
function J.next(snapshot,cursor)
  if not snapshot then return nil end
  if cursor and not J.cursor(cursor) then return nil,nil,'invalid step receipt' end
  local previous=cursor and cursor.epoch==snapshot.epoch and cursor.total or 0
  if previous>snapshot.total then return nil,nil,'native step journal moved backwards' end
  local count=math.min(snapshot.total-previous,J.MAX_DELIVERY)
  if count<=0 then return nil end
  local complete=previous+count==snapshot.total
  local from=cursor and cursor.epoch==snapshot.epoch and cursor.to or snapshot.from
  return {steps=count,from=from,to=snapshot.to},
    {epoch=snapshot.epoch,total=previous+count,to=complete and snapshot.to or from}
end
function J.receipts(fs)
  local value,why=read(fs,J.RECEIPTS,J.MAX_RECEIPTS_BYTES)
  if not value then
    if why then return nil,why end
    return {version=1,owners={}}
  end
  if value.version~=1 or type(value.owners)~='table' then return nil,'invalid step receipt ledger' end
  local count=0
  for owner,cursor in pairs(value.owners)do
    count=count+1
    if type(owner)~='string' or #owner>256 or not J.cursor(cursor) or count>J.MAX_OWNERS then
      return nil,'invalid step receipt owner'
    end
  end
  return value
end
function J.saveReceipts(fs,value)
  local bytes=Json.encode(value)
  if #bytes>J.MAX_RECEIPTS_BYTES then return nil,'step receipt ledger full' end
  local path=J.RECEIPTS..'.tmp'
  local ok,why=fs.write(path,bytes)
  if not ok then return nil,why or 'step receipt write failed' end
  if fs.read(path,#bytes+1)~=bytes then return nil,'step receipt verification failed' end
  local called,published,err=pcall(function()
    if fs.rename then return fs.rename(path,J.RECEIPTS) end
    if not fs.getSaveDirectory then return nil,'atomic step receipt publication unavailable' end
    local root=fs.getSaveDirectory()
    return require('src.net.DownloadPublish')(root..'/'..path,root..'/'..J.RECEIPTS)
  end)
  if not called or not published then
    if fs.remove then pcall(fs.remove,path) end
    return nil,called and err or published
  end
  return true
end
return J
