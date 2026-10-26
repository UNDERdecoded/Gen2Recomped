package.path = "./?.lua;./?/init.lua;" .. package.path
local checks, ticks, workers, queued = 0, 0, {}, {}
local function check(ok, label) checks = checks + 1; assert(ok, label) end
local function channel()
  local q = {}
  function q:push(v) self[#self + 1] = v; if type(v) == "table" and v.stage then queued[v.id] = v end end
  function q:pop() if #self > 0 then return table.remove(self, 1) end end
  function q:peek() return self[1] end
  function q:clear() for i = #self, 1, -1 do self[i] = nil end end
  function q:performAtomic(fn) return fn(self) end
  return q
end
love = {system = {getOS = function() return "Linux" end}, timer = {getTime = function() return ticks end},
  filesystem = {createDirectory = function() return true end, getSaveDirectory = function() return "/owned" end,
    getInfo = function() error("filesystem IO in main-thread poll") end,
    remove = function() return true end}, thread = {newChannel = channel,
    newThread = function()
      local t = {start = function(self, c, r) self.commands, self.results = c, r end,
        getError = function(self) return self.err end, wait = function() end}
      workers[#workers + 1] = t; return t
    end}}
package.loaded["src.core.HostShell"] = {canSpawnProcess = function() return true end}
local rename = os.rename
os.rename = function() error("filesystem publication in main-thread poll") end
local D = require("src.net.AsyncDownload")
local function complete(id, ok, bytes, err)
  check(queued[id] ~= nil, "request queued before worker result")
  workers[#workers].results:push({id = id, ok = ok, bytes = bytes, err = err, httpStatus = ok and 200 or 404})
end
local function claim(id)
  local control = queued[id].control
  return control:performAtomic(function(c)
    if c:peek() ~= "open" then return false end
    c:clear(); c:push("publishing"); return true
  end)
end
for _, dest in ipairs({"", "/absolute", "../escape", "x/../escape", "C:\\escape", "x//file", "x/", "net-download/file"}) do
  check(D.download("https://host/file", dest) == nil, "invalid target refused: " .. dest)
end
check(D.download("file:///private", "out") == nil, "only HTTP transport")
check(D.download("http://host/file", "out", {boundedHttpsGet = 1}) == nil, "HTTPS constraint")
check(D.download("https://host/file", "out", {size = 3, maxBytes = 2}) == nil, "contradictory size limit")
check(D.download("https://host/file", "out", {size = .5}) == nil, "fractional size refused")
check(D.download("https://host/file", "out", {maxBytes = math.huge}) == nil, "infinite limit refused")
check(D.download("https://host/file", "out", {userAgent = "bad\r\nheader"}) == nil, "invalid header refused")
local id = assert(D.download("https://host/file", "nested/out", {size = 6}))
check(#workers == 2, "fixed file worker ceiling")
check(D.download("https://host/file", "nested\\out") == nil, "one active writer per normalized destination")
check(D.poll(id).status == "pending", "poll starts no HTTP or filesystem work")
queued[id].progress:push(3)
local progress = D.poll(id)
check(progress.receivedBytes == 3 and progress.progress == .5, "coalesced progress is available without filesystem IO")
queued[id].progress:clear()
check(D.poll(id).receivedBytes == 3, "progress cannot move backwards between worker updates")
check(claim(id), "worker claims completed transfer")
check(D.cancel(id) == false, "cancellation after publication claim is refused")
check(D.poll(id).phase == "publishing" and D.poll(id).cancellable == false, "publication boundary exposed honestly")
complete(id, true, 6)
local state = D.poll(id)
check(state.status == "ok" and state.receivedBytes == 6 and state.progress == 1, "completed file metadata")
state.status = "modified"; check(D.poll(id).status == "ok", "detached polling state")
check(not D.cancel(id) and D.poll(id).status == "ok", "completed publication is not rolled back")
D.release(id); check(D.poll(id).status == "error", "released handle invalid")
for _, mode in ipairs({"cancel", "release", "timeout"}) do
  id = assert(D.download("https://host/file", "preserved", {size = 6, maxSeconds = 1}))
  if mode == "cancel" then check(D.cancel(id), "pre-publication cancellation accepted")
  elseif mode == "release" then D.release(id)
  else ticks = ticks + 2; check(D.poll(id).status == "error", "queue time counts toward deadline") end
  check(not claim(id), mode .. " cannot permit worker publication")
  complete(id, true, 6) -- adversarial late result must not revive the request
  check(D.poll(id).status == "error", mode .. " remains terminal after late completion")
  D.release(id)
end
for _, err in ipairs({"HTTP 404", "download size mismatch", "could not publish download"}) do
  id = assert(D.download("https://host/file", "retry")); complete(id, false, nil, err)
  state = D.poll(id)
  check(state.status == "error" and state.err == err and state.httpStatus == 404, "worker error preserved: " .. err)
  D.release(id)
end
id = assert(D.download("https://host/empty", "empty", {size = 0})); claim(id); complete(id, true, 0)
check(D.poll(id).status == "ok" and D.poll(id).receivedBytes == 0, "zero-byte success completes")
D.release(id)
id = assert(D.download("https://host/finishing", "released-publish")); check(claim(id), "publication claim before release")
D.release(id)
check(D.download("https://host/retry", "released-publish") == nil, "released publication still owns destination until finished")
complete(id, true, 6)
local replacement = assert(D.download("https://host/retry", "released-publish"))
check(D.poll(id).status == "error", "released completion handle remains invalid")
D.cancel(replacement); complete(replacement, false, nil, "cancelled"); D.poll(replacement); D.release(replacement)
id = assert(D.download("https://host/finishing", "shutdown-publish")); claim(id); complete(id, true, 6)
D.shutdown(); check(D.poll(id).status == "ok", "shutdown drains a completed publication instead of leaving it pending")
D.release(id)
local held = {}
for i = 1, D.MAX_JOBS do held[i] = assert(D.download("https://host/slow", "held" .. i)) end
check(D.download("https://host/slow", "extra") == nil, "bounded active and queued file jobs")
for _, h in ipairs(held) do D.cancel(h); D.release(h) end
check(D.download("https://host/slow", "extra") == nil, "release cannot evade occupied worker budget")
for _, h in ipairs(held) do complete(h, false, nil, "cancelled") end
id = assert(D.download("https://host/new", "reused"))
check(D.poll(held[1]).status == "error", "released request never revived")
workers[#workers].err = "worker stopped"
check(D.poll(id).status == "error", "worker death terminates pending file jobs")
D.shutdown()
id = assert(D.download("https://host/new", "restart")); claim(id); complete(id, true, 5)
check(D.poll(id).status == "ok", "file pool restarts after shutdown")
D.release(id); D.shutdown(); os.rename = rename
print(("async file download queue: %d checks PASS"):format(checks))
