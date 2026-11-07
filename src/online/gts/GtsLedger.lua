-- The player's half of GTS escrow (docs/online-design.md 2.7a, WS7).
--
-- Lives in the save (`save.onlineGts`) so it is written by the same atomic
-- save write as the party it changes:
--
--   outbox[token]  a mon on its way to a host: it was taken OUT of the
--                  party / PC and the save was written BEFORE the request
--                  left.  The host's answer settles it: accepted -> the
--                  entry is dropped; refused -> the mon goes back.  After a
--                  crash or a lost reply the same token is resent to the same
--                  host (`dbId`), whose answer for that token never changes.
--   applied[mailId] a mon the host handed over that is already in the save
--                  (written before the host was told).  If the host offers
--                  the same item again (its ack never arrived), it is only
--                  acknowledged, never added twice.
--
-- So at every instant a mon is in exactly one place: the save's party/PC,
-- the save's outbox, the host's deposits, or the host's mail.
--
--   local ledger = GtsLedger.new{ save = save, data = data, persist = fn(save) -> ok }
--   ledger:take(source, kind, fields) -> token, entry | nil, why
--   ledger:finish(token) ; ledger:rollback(token)
--   ledger:pending(dbId) -> { entry... }        (entries for that host)
--   ledger:hasApplied(id) ; ledger:apply(id, mon) -> where | nil, why
--   ledger:forget(id)
--
-- source: { where = "party", index = i } | { where = "box", box = b, slot = s }

local GtsLedger = {}
GtsLedger.__index = GtsLedger

GtsLedger.PARTY_MAX = 6
GtsLedger.APPLIED_KEPT = 64

local function newToken()
  local ok, Util = pcall(require, "src.online.net.Util")
  if ok and Util and Util.rand32 then
    return ("%08x%08x"):format(Util.rand32() % 4294967296, Util.rand32() % 4294967296)
  end
  return ("%08x%08x"):format(math.random(0, 2147483646), math.random(0, 2147483646))
end
GtsLedger.newToken = newToken

function GtsLedger.state(save)
  local st = save.onlineGts
  if type(st) ~= "table" then
    st = {}
    save.onlineGts = st
  end
  st.outbox = st.outbox or {}
  st.applied = st.applied or {}
  return st
end

function GtsLedger.new(opts)
  local self = setmetatable({
    save = assert(opts.save, "GtsLedger needs a save"),
    data = opts.data,
    persist = opts.persist or function() return true end,
    now = opts.now or os.time,
  }, GtsLedger)
  GtsLedger.state(self.save)
  return self
end

function GtsLedger:_persist()
  local ok, res = pcall(self.persist, self.save)
  return ok and res ~= false
end

function GtsLedger:monAt(source)
  local save = self.save
  if type(source) ~= "table" then return nil end
  if source.where == "party" then
    return save.party and save.party[source.index]
  elseif source.where == "box" then
    local boxes = save.boxes
    return boxes and boxes[source.box] and boxes[source.box][source.slot]
  end
  return nil
end

local function removeAt(save, source)
  if source.where == "party" then
    return table.remove(save.party, source.index)
  end
  local mon = save.boxes[source.box][source.slot]
  save.boxes[source.box][source.slot] = nil
  return mon
end

local function putBack(save, source, mon)
  if source.where == "party" and save.party and #save.party < GtsLedger.PARTY_MAX then
    table.insert(save.party, math.min(source.index, #save.party + 1), mon)
    return "party"
  end
  if source.where == "box" and save.boxes and save.boxes[source.box]
     and save.boxes[source.box][source.slot] == nil then
    save.boxes[source.box][source.slot] = mon
    return "box"
  end
  return nil
end

-- the first free home for a mon: the party, else the PC
function GtsLedger:place(mon)
  local save = self.save
  save.party = save.party or {}
  if #save.party < GtsLedger.PARTY_MAX then
    save.party[#save.party + 1] = mon
    return "party"
  end
  local ok, Boxes = pcall(require, "src.pokemon.Boxes")
  if ok and Boxes then
    local okD, box, slot = pcall(Boxes.deposit, save, mon)
    if okD and box then return "box", box, slot end
  end
  return nil
end

-- room for one more mon somewhere?
function GtsLedger:hasRoom()
  local save = self.save
  if #(save.party or {}) < GtsLedger.PARTY_MAX then return true end
  local ok, Boxes = pcall(require, "src.pokemon.Boxes")
  if not ok then return false end
  local okE, boxes = pcall(Boxes.ensure, save)
  if not okE or type(boxes) ~= "table" then return false end
  for i = 1, Boxes.count() do
    if boxes[i] and Boxes.firstFree(boxes[i]) then return true end
  end
  return false
end

-- take the mon at `source` into the outbox and write the save
function GtsLedger:take(source, kind, fields)
  local mon = self:monAt(source)
  if not mon then return nil, "Nothing there." end
  local st = GtsLedger.state(self.save)
  local token = newToken()
  local entry = { token = token, kind = kind, at = self.now(),
                  from = { where = source.where, index = source.index,
                           box = source.box, slot = source.slot } }
  for k, v in pairs(fields or {}) do entry[k] = v end
  removeAt(self.save, source)
  entry.mon = mon
  st.outbox[token] = entry
  if not self:_persist() then
    -- the save could not be written: undo, nothing leaves
    st.outbox[token] = nil
    putBack(self.save, source, mon)
    return nil, "The game could not be saved."
  end
  return token, entry
end

function GtsLedger:entry(token)
  return GtsLedger.state(self.save).outbox[token]
end

-- the host took it: the mon is the host's now
function GtsLedger:finish(token)
  local st = GtsLedger.state(self.save)
  if not st.outbox[token] then return false end
  st.outbox[token] = nil
  self:_persist()
  return true
end

-- the host refused it: the mon comes home
function GtsLedger:rollback(token)
  local st = GtsLedger.state(self.save)
  local entry = st.outbox[token]
  if not entry then return false end
  local where = putBack(self.save, entry.from, entry.mon) or self:place(entry.mon)
  if not where then return false, "No room to return the POKéMON." end
  st.outbox[token] = nil
  self:_persist()
  return true, where
end

-- outbox entries waiting on host `dbId` (nil: every entry), oldest first
function GtsLedger:pending(dbId)
  local out = {}
  for _, e in pairs(GtsLedger.state(self.save).outbox) do
    if dbId == nil or e.dbId == dbId then out[#out + 1] = e end
  end
  table.sort(out, function(a, b)
    if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) < (b.at or 0) end
    return a.token < b.token
  end)
  return out
end

function GtsLedger:hasApplied(id)
  return GtsLedger.state(self.save).applied[id] ~= nil
end

-- file a received mon and write the save; the caller acks after this
function GtsLedger:apply(id, mon)
  local st = GtsLedger.state(self.save)
  if st.applied[id] ~= nil then return "already" end
  local where, box, slot = self:place(mon)
  if not where then return nil, "There's no room for it." end
  st.applied[id] = self.now()
  local dex = self.save.pokedex
  if type(dex) == "table" then
    dex.seen = dex.seen or {}
    dex.owned = dex.owned or {}
    dex.seen[mon.species] = true
    dex.owned[mon.species] = true
  end
  if not self:_persist() then
    -- undo: the host keeps the item, nothing was taken
    st.applied[id] = nil
    if where == "party" then
      table.remove(self.save.party)
    elseif box then
      self.save.boxes[box][slot] = nil
    end
    return nil, "The game could not be saved."
  end
  return where
end

-- the host dropped the item: the guard is no longer needed (the newest
-- few are kept anyway, in case an old copy of the host comes back)
function GtsLedger:forget(id)
  local st = GtsLedger.state(self.save)
  if st.applied[id] == nil then return end
  st.applied[id] = false
  local live = {}
  for k, v in pairs(st.applied) do live[#live + 1] = { k, v } end
  if #live > GtsLedger.APPLIED_KEPT then
    table.sort(live, function(a, b)
      local x = a[2] == false and -1 or a[2]
      local y = b[2] == false and -1 or b[2]
      return x < y
    end)
    for i = 1, #live - GtsLedger.APPLIED_KEPT do st.applied[live[i][1]] = nil end
  end
  self:_persist()
end

return GtsLedger
