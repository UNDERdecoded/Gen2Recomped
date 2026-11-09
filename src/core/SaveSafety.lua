-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- A SAVE MUST NEVER BE LOST.  The write, keep and find half of SaveData.
--
-- Reported from play (HeartGold, Android): "it kinda froze after
-- encountering a Pidgey and now my save is gone".  Whatever froze, the save
-- path must leave the slot recoverable, and every way it did not is closed
-- here.  docs/save-safety.md lists the paths and where backups live.
--
-- WRITES ARE ATOMIC.  A save is written to <name>.tmp, read back and checked
-- byte for byte, and only then renamed over <name> (os.rename on the real
-- path; on Windows, where rename cannot replace, the old file is removed first
-- and the verified .tmp is the copy in between).  A file system with no real
-- path (an injected test fs) falls back to write-then-verify with the .tmp
-- kept until the main file reads back whole.  An OS kill, a freeze or a crash
-- at any point leaves either the old main file or a complete .tmp.
--
-- THE PREVIOUS COPY IS KEPT, and only a good one.  <name>.bak takes the old
-- main file only when it decodes, so a truncated main file can never rotate
-- the one good backup away; a main file that does not decode is kept aside as
-- <name>.corrupt-<stamp> instead of being written over.
--
-- STAMPED SNAPSHOTS.  <name>.bak-YYYYmmdd-HHMMSS[-tag]: a rolling history (at
-- most one every SNAP_EVERY seconds, KEEP_ROLLING kept) plus tagged copies
-- taken at the moments a save is most at risk -- a different playthrough
-- about to replace it ("replaced"), a file changed on disk by something else
-- ("external"), a restore ("prerestore"), a recovery ("recovered").  Tagged
-- copies have their own, larger cap.  <name>.backups is an index of them, so
-- a file system that cannot list a folder still finds them.
--
-- LOADS FALL BACK.  main, then .tmp, then .bak, then the stamped copies
-- newest first, then whatever extra copies the caller knows of (Pokewalker and
-- cloud backups, the same slot in another storage location).  A candidate
-- counts only when it decodes AND looks like a save.
--
-- Pure Lua over a small fs interface (getInfo/read/write/remove, optionally
-- getDirectoryItems/realPath), so tools/save_safety_check drives it headless.

local SaveSerializer = require("src.core.SaveSerializer")

local S = {}

S.KEEP_ROLLING = 8
S.KEEP_TAGGED = 16
S.SNAP_EVERY = 10 * 60

-- this process, so an in-use marker this process wrote is not mistaken for
-- another instance's
S.session = ("%d-%s"):format(os.time(), tostring({}):match("0x(%x+)") or tostring(math.random(1, 1e9)))

-- ------------------------------------------------------------------ helpers

function S.read(fs, name)
  if not (fs and name and fs.getInfo) then return nil end
  local okI, info = pcall(fs.getInfo, name)
  if not (okI and info) then return nil end
  local ok, body = pcall(fs.read, name)
  if ok and type(body) == "string" then return body end
  return nil
end

local function exists(fs, name)
  local ok, info = pcall(fs.getInfo, name)
  return ok and info ~= nil
end

local function remove(fs, name)
  if fs.remove then pcall(fs.remove, name) end
end

-- a decoded table that is a save, not merely a table: an empty or foreign
-- table must never stand in for a playthrough
function S.looksLikeSave(t)
  -- `zelda` is the stamp src/zelda/ZeldaSaves.lua puts on a Zelda save
  return type(t) == "table" and (type(t.player) == "table" or type(t.party) == "table"
    or type(t.zelda) == "table")
end

function S.decodeSave(bytes)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  local t = SaveSerializer.decode(bytes)
  if S.looksLikeSave(t) then return t end
  return nil
end

function S.decodeAny(bytes)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  return SaveSerializer.decode(bytes)
end

function S.playSeconds(t)
  local p = type(t) == "table" and t.playTime or nil
  local n = tonumber(p)
  if n then return n end
  if type(p) ~= "table" then return 0 end
  return (tonumber(p.hours) or 0) * 3600 + (tonumber(p.minutes) or tonumber(p.mins) or 0) * 60
    + (tonumber(p.seconds) or tonumber(p.secs) or 0)
end

-- "same playthrough": the trainer the save belongs to.  Unknown ids compare
-- equal, so only a provable difference counts as a replacement.
function S.samePlaythrough(a, b)
  local pa = type(a) == "table" and a.player or nil
  local pb = type(b) == "table" and b.player or nil
  if type(pa) ~= "table" or type(pb) ~= "table" then return true end
  if pa.id ~= nil and pb.id ~= nil and pa.id ~= pb.id then return false end
  if pa.name ~= nil and pb.name ~= nil and pa.name ~= pb.name then return false end
  return true
end

function S.stamp(t)
  return os.date("%Y%m%d-%H%M%S", t or os.time())
end

local function stampTime(s)
  local y, mo, d, h, mi, se = tostring(s):match("(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)")
  if not y then return nil end
  return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                   hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) })
end
S.stampTime = stampTime

-- The real path of a file, for os.rename.  love.filesystem writes to the save
-- directory; an injected fs may say where it keeps a file (realPath), or not.
function S.realPath(fs, name)
  if type(fs) == "table" and type(fs.realPath) == "function" then
    local ok, p = pcall(fs.realPath, name)
    return ok and p or nil
  end
  if love and love.filesystem and fs == love.filesystem and love.filesystem.getSaveDirectory then
    local ok, dir = pcall(love.filesystem.getSaveDirectory)
    if ok and type(dir) == "string" and dir ~= "" then return dir .. "/" .. name end
  end
  return nil
end

-- ------------------------------------------------------------- atomic write

-- atomicWrite(fs, name, bytes, opts) -> true | false, why
--   opts.bak     where the previous good copy goes (nil: not kept)
--   opts.decode  validator for the previous copy: a previous file it rejects
--                is kept aside as <name>.corrupt-<stamp>, never rotated into
--                .bak and never simply written over
function S.atomicWrite(fs, name, bytes, opts)
  opts = opts or {}
  if type(bytes) ~= "string" or bytes == "" then return false, "nothing to write" end
  local tmp = name .. ".tmp"
  local ok, err = fs.write(tmp, bytes)
  if not ok then return false, ("could not write %s: %s"):format(tmp, tostring(err)) end
  if S.read(fs, tmp) ~= bytes then
    -- the disk is full or the write was cut short: the main file is untouched
    return false, ("%s did not read back whole (disk full?)"):format(tmp)
  end
  local prev = S.read(fs, name)
  if prev and prev ~= "" and prev ~= bytes then
    local good = (not opts.decode) or opts.decode(prev) ~= nil
    if good then
      if opts.bak then fs.write(opts.bak, prev) end
    else
      fs.write(name .. ".corrupt-" .. S.stamp(), prev)
    end
  end
  local rt, rm = S.realPath(fs, tmp), S.realPath(fs, name)
  if rt and rm then
    local okR = os.rename(rt, rm)
    if not okR and exists(fs, name) then
      -- Windows: rename cannot replace a file.  The verified .tmp is the copy
      -- for the instant between these two calls; a load finds it.
      os.remove(rm)
      okR = os.rename(rt, rm)
    end
    if okR and S.read(fs, name) == bytes then return true end
  end
  ok, err = fs.write(name, bytes)
  if not ok then return false, ("could not write %s: %s"):format(name, tostring(err)) end
  if S.read(fs, name) ~= bytes then
    return false, ("%s did not read back whole; the copy in %s is kept"):format(name, tmp)
  end
  remove(fs, tmp)
  return true
end

-- ---------------------------------------------------------- stamped copies

local function indexName(name) return name .. ".backups" end

-- every stamped copy of `name`, newest first: { file, t, tag }
function S.listBackups(fs, name)
  local out, seen = {}, {}
  local function add(file, t, tag)
    if seen[file] or not exists(fs, file) then return end
    seen[file] = true
    out[#out + 1] = { file = file, t = tonumber(t) or 0, tag = tag }
  end
  local idx = S.decodeAny(S.read(fs, indexName(name)))
  if type(idx) == "table" then
    for _, e in ipairs(idx) do
      if type(e) == "table" and type(e.file) == "string" then add(e.file, e.t, e.tag) end
    end
  end
  if fs.getDirectoryItems then
    local dir, base = name:match("^(.*)/([^/]+)$")
    if not dir then dir, base = "", name end
    local ok, items = pcall(fs.getDirectoryItems, dir)
    if ok and type(items) == "table" then
      local prefix = base .. ".bak-"
      for _, item in ipairs(items) do
        if item:sub(1, #prefix) == prefix and not item:match("%.tmp$") then
          local rest = item:sub(#prefix + 1)
          local tag = rest:match("^%d+%-%d+[_%d]*%-(%a[%w]*)$")
          add((dir ~= "" and (dir .. "/") or "") .. item, stampTime(rest), tag)
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.t ~= b.t then return a.t > b.t end
    return a.file > b.file
  end)
  return out
end

local function writeIndex(fs, name, list)
  local rows = {}
  for _, e in ipairs(list) do rows[#rows + 1] = { file = e.file, t = e.t, tag = e.tag } end
  S.atomicWrite(fs, indexName(name), SaveSerializer.encode(rows))
end

-- snapshot(fs, name, bytes, tag) -> the file written, or nil.  Untagged
-- snapshots are throttled to one per SNAP_EVERY; a copy identical to one of
-- the newest few is not written twice.
function S.snapshot(fs, name, bytes, tag)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  local list = S.listBackups(fs, name)
  for i = 1, math.min(3, #list) do
    if S.read(fs, list[i].file) == bytes then return list[i].file end
  end
  local now = os.time()
  if not tag then
    for _, e in ipairs(list) do
      if not e.tag then
        if now - e.t < S.SNAP_EVERY then return nil end
        break
      end
    end
  end
  local base = name .. ".bak-" .. S.stamp(now)
  local file, n = base .. (tag and ("-" .. tag) or ""), 1
  while exists(fs, file) do
    n = n + 1
    file = base .. "_" .. n .. (tag and ("-" .. tag) or "")
  end
  local ok = fs.write(file, bytes)
  if not ok or S.read(fs, file) ~= bytes then return nil end
  table.insert(list, 1, { file = file, t = now, tag = tag })
  -- prune, oldest first, each kind to its own cap
  local keep, rolling, tagged = {}, 0, 0
  for _, e in ipairs(list) do
    local drop = false
    if e.tag then
      tagged = tagged + 1
      drop = tagged > S.KEEP_TAGGED
    else
      rolling = rolling + 1
      drop = rolling > S.KEEP_ROLLING
    end
    if drop then remove(fs, e.file) else keep[#keep + 1] = e end
  end
  writeIndex(fs, name, keep)
  return file
end

-- ---------------------------------------------------------------- loading

-- Every copy a load may fall back to, in order.  `extra` rows are
-- { label, read = fn -> bytes, t } from outside this file's folder.
function S.candidates(fs, name, bak, extra)
  local out = {
    { label = "tmp", file = name .. ".tmp" },
  }
  if bak then out[#out + 1] = { label = "bak", file = bak } end
  for _, e in ipairs(S.listBackups(fs, name)) do
    out[#out + 1] = { label = e.file:match("%.(bak%-.*)$") or "bak", file = e.file, t = e.t }
  end
  -- `extra` may be a function, so the listing it costs is only paid when
  -- every local copy has already failed
  if type(extra) == "function" then
    local ok, list = pcall(extra)
    extra = ok and list or nil
  end
  for _, e in ipairs(type(extra) == "table" and extra or {}) do out[#out + 1] = e end
  return out
end

local function candBytes(fs, c)
  if c.read then
    local ok, b = pcall(c.read)
    return ok and type(b) == "string" and b or nil
  end
  return S.read(fs, c.file)
end
S.candBytes = candBytes

-- loadBest(fs, name, bak, extra) -> save, recoveredFrom|nil, bytes, state
-- state: "ok" | "recovered" | "unreadable" (files exist, none decode) | "none"
function S.loadBest(fs, name, bak, extra)
  local mainBytes = S.read(fs, name)
  local main = S.decodeSave(mainBytes)
  local tmpBytes = S.read(fs, name .. ".tmp")
  local tmp = S.decodeSave(tmpBytes)
  if main then
    -- a .tmp left by a write that was cut short after it verified holds the
    -- newer save; the further-played of the two wins
    if tmp and tmpBytes ~= mainBytes and S.playSeconds(tmp) > S.playSeconds(main) then
      return tmp, "tmp", tmpBytes, "recovered"
    end
    return main, nil, mainBytes, "ok"
  end
  local anyFile = mainBytes ~= nil or tmpBytes ~= nil
  for _, c in ipairs(S.candidates(fs, name, bak, extra)) do
    local bytes = candBytes(fs, c)
    if bytes then anyFile = true end
    local t = S.decodeSave(bytes)
    if t then return t, c.label, bytes, "recovered", c end
  end
  return nil, nil, nil, anyFile and "unreadable" or "none"
end

-- Is there anything at all for `name` (a file, decodable or not)?
function S.anyFile(fs, name, bak)
  if exists(fs, name) or exists(fs, name .. ".tmp") or (bak and exists(fs, bak)) then return true end
  return #S.listBackups(fs, name) > 0
end

-- ------------------------------------------------- the walker's inbox merge

local function key(v)
  local ok, s = pcall(SaveSerializer.encode, v)
  return ok and s or tostring(v)
end

-- Keys of the walker inbox / event queue entries a save holds, so a later
-- merge can tell what is new on disk from what this process already applied.
function S.walkerKeys(save)
  local keys = {}
  local box = type(save) == "table" and save.walkerInbox
  if type(box) == "table" then
    for _, list in pairs({ box.returning, box.mons, box.items }) do
      for _, e in ipairs(type(list) == "table" and list or {}) do keys[key(e)] = true end
    end
  end
  local ev = type(save) == "table" and save.walkerEvents
  if type(ev) == "table" then
    for _, e in ipairs(type(ev.pending) == "table" and ev.pending or {}) do keys[key(e)] = true end
  end
  return keys
end

-- The file on disk changed under a running game (another process: the
-- launcher's Pokewalker, the Watt Shop, an event).  Carry what it delivered
-- into the save about to be written, so the game's write does not erase it.
-- `seen` is S.walkerKeys of the save as this process loaded it.  Returns the
-- number of entries carried over.
function S.mergeWalker(disk, data, seen)
  if type(disk) ~= "table" or type(data) ~= "table" then return 0 end
  seen = seen or {}
  local n = 0
  local dbox = disk.walkerInbox
  if type(dbox) == "table" then
    data.walkerInbox = type(data.walkerInbox) == "table" and data.walkerInbox or {}
    local box = data.walkerInbox
    box.returning, box.mons, box.items = box.returning or {}, box.mons or {}, box.items or {}
    local have = S.walkerKeys(data)
    for _, field in ipairs({ "returning", "mons", "items" }) do
      for _, e in ipairs(type(dbox[field]) == "table" and dbox[field] or {}) do
        local k = key(e)
        if not seen[k] and not have[k] then
          local copy = e
          if field == "returning" and type(e) == "table" and type(e.raw) ~= "table"
              and type(e.placed) == "table" then
            -- the walker put the Pokemon straight into the PC on disk; the
            -- PC being written does not have it, so it rides as `raw` and the
            -- next load deposits it
            local boxes = type(disk.boxes) == "table" and disk.boxes or {}
            local list = boxes[e.placed.box]
            list = type(list) == "table" and (list.mons or list) or {}
            local mon = list[e.placed.index]
            copy = {}
            for k2, v in pairs(e) do copy[k2] = v end
            copy.placed = nil
            copy.raw = type(mon) == "table" and mon or nil
          end
          box[field][#box[field] + 1] = copy
          n = n + 1
        end
      end
    end
  end
  local dev = disk.walkerEvents
  if type(dev) == "table" then
    data.walkerEvents = type(data.walkerEvents) == "table" and data.walkerEvents or {}
    local ev = data.walkerEvents
    ev.claimed = type(ev.claimed) == "table" and ev.claimed or {}
    ev.pending = type(ev.pending) == "table" and ev.pending or {}
    for id, t in pairs(type(dev.claimed) == "table" and dev.claimed or {}) do
      if ev.claimed[id] == nil then ev.claimed[id] = t end
    end
    local have = S.walkerKeys(data)
    for _, e in ipairs(type(dev.pending) == "table" and dev.pending or {}) do
      local k = key(e)
      if not seen[k] and not have[k] then
        ev.pending[#ev.pending + 1] = e
        n = n + 1
      end
    end
  end
  return n
end

return S
