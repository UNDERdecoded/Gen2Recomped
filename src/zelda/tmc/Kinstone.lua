-- Kinstones: the bag, fusions, and fusing with friends online.
--
-- CARTRIDGE RULES (src/common.c, src/menu/kinstoneMenu.c, include/kinstone.h):
--   * piece types live in the bag as ids $65-$75; a fusion is a kinstone id
--     1-100; gKinstoneWorldEvents[id].shape says which half fits it, and a
--     piece fits when gKinstoneWorldEvents[piece].shape equals it
--     (KinstoneMenu_Type3_Overlay1);
--   * fused ids are a bit set (CheckKinstoneFused), read by room code and
--     scripts all over the game;
--   * a fuser offering KINSTONE_RANDOM gets one of the eighteen SharedFusions
--     the player has not fused yet, starting at a random index and walking
--     forward (GetRandomSharedFusion).
--
-- ONLINE: a friend's Link stands in for that fuser.  Both players hold L
-- facing each other; the one who opens offers a piece, the other picks one
-- of theirs.  When the shapes match, the ACCEPTOR draws the fusion the way
-- GetRandomSharedFusion does (restricted to shared fusions of that shape
-- that neither of them has fused) and sends it back, so both cartridges
-- record the same kinstone id, lose one piece each and get the same world
-- event -- exactly the result a fuser NPC with a random fusion would give.

local Kinstone = {}
Kinstone.__index = Kinstone

Kinstone.PIECE_FIRST, Kinstone.PIECE_LAST = 0x65, 0x75

function Kinstone.new(field)
  local self = setmetatable({ field = field, active = false, ui = nil, rng = nil }, Kinstone)
  local save = field.save
  save.kinstones = save.kinstones or { bag = {}, fused = {} }
  save.kinstones.bag = save.kinstones.bag or {}
  save.kinstones.fused = save.kinstones.fused or {}
  self.data = field.assets.manifest.kinstones or { events = {}, shared = {}, world = {} }
  return self
end

function Kinstone:bag() return self.field.save.kinstones.bag end
function Kinstone:fusedSet() return self.field.save.kinstones.fused end

function Kinstone:isFused(id)
  if not id or id < 1 or id > 100 then return false end
  return self:fusedSet()[id] == true
end

function Kinstone:addPiece(t, n)
  if not t or t < Kinstone.PIECE_FIRST or t > Kinstone.PIECE_LAST then return end
  local bag = self:bag()
  bag[t] = math.min(99, (bag[t] or 0) + (n or 1))
end

function Kinstone:count(t) return self:bag()[t] or 0 end

function Kinstone:shape(id)
  local e = self.data.events[id]
  return e and e.shape
end

function Kinstone:fits(piece, id)
  local a, b = self:shape(piece), self:shape(id)
  return a ~= nil and a == b
end

-- pieces in the bag, sorted
function Kinstone:pieces()
  local out = {}
  for t, n in pairs(self:bag()) do if n > 0 then out[#out + 1] = t end end
  table.sort(out)
  return out
end

-- GetRandomSharedFusion, restricted to `shape` and to ids neither side has
-- fused.  `start` is the random index (0-17) the cartridge would roll.
function Kinstone:sharedFusionFor(shape, otherFused, start)
  local list = self.data.shared or {}
  local n = #list
  if n == 0 then return nil end
  local r = (start or 0) % n
  for _ = 1, n do
    local id = list[r + 1]
    if id and id ~= 0 and not self:isFused(id) and not (otherFused and otherFused[id])
       and (shape == nil or self:shape(id) == shape) then
      return id
    end
    r = (r + 1) % n
  end
  return nil
end

-- record a fusion (both sides call this with the same id)
function Kinstone:fuse(id, piece)
  if piece and self:count(piece) > 0 then
    local bag = self:bag()
    bag[piece] = bag[piece] - 1
    if bag[piece] <= 0 then bag[piece] = nil end
  end
  if id and id >= 1 and id <= 100 then
    self:fusedSet()[id] = true
    require("src.zelda.tmc.Fusers").notifyDone(self.field, id) -- round 6
  end
  local we = self.data.events[id] and self.data.world[self.data.events[id].worldEvent]
  return we
end

-- What a fusion changes in the world (src/kinstone.c sub_080186EC /
-- sub_0801876C), run when a room loads: every Kinstone whose
-- gKinstoneWorldEvents entry is a world event (subtask 8) and whose
-- gWorldEvents entry is in this room.  Ported event types: 1 / 3 (an
-- entity once fused, unless a flag / item is already had), 7 (an entity
-- until fused), 8 (a tile), 9 (an entity plus its tiles), 15, 17, 24, 25.
-- The others (beanstalks, bomb walls, cloud tops...) are listed in
-- docs/zelda/minishcap.md.
local WE_TABLES = { [1] = 0x080FEC28, [3] = 0x080FEBE8, [7] = 0x080FECC8, [9] = 0x080FEE78, [25] = 0x080FED18 }
local TILE_TYPE_360, TILE_TYPE_141, TILE_TYPE_140, TILE_TYPE_142 = 360, 141, 140, 142
function Kinstone:applyWorldEvents()
  local f = self.field
  local room = f.room
  for id = 0, 100 do
    local ev = self.data.events[id]
    local we = ev and ev.subtask == 8 and self.data.world[ev.worldEvent]
    if we and we.area == room.area and we.room == room.room then
      local fused = self:isFused(id)
      local t = we.type
      local function one(base)
        local l = f:entityListAt(base + 16 * we.entity)
        return l and l[1] and f:spawn(l[1])
      end
      local tx, ty = math.floor(we.x / 16) % 64, math.floor(we.y / 16) % 64
      if t == 1 and fused and not f:flag("global", we.flag) then one(WE_TABLES[1])
      elseif t == 3 and fused and f:inventory(we.flag) == 0 then one(WE_TABLES[3])
      elseif t == 7 and not fused and we.entity ~= 0x80 then one(WE_TABLES[7])
      elseif t == 25 then
        local e = one(WE_TABLES[25])
        if e then e.form = fused and 2 or 0 end
      elseif t == 8 and fused then f:objects():setTileType(1, tx, ty, TILE_TYPE_360)
      elseif t == 9 and fused then
        one(WE_TABLES[9])
        if we.entity == 0 then f:objects():setTileType(1, tx, ty, TILE_TYPE_141)
        else
          f:objects():setTileType(1, tx - 1, ty, TILE_TYPE_140)
          f:objects():setTileType(1, tx, ty, TILE_TYPE_142)
        end
      elseif t == 24 and fused then f:loadEntityList(0x080FEE18)
      elseif t == 15 then
        local l = f:entityListAt(fused and 0x080FEE58 or 0x080FEE48)
        if l and l[1] then f:spawn(l[1]) end
      elseif t == 17 and fused then
        f:setFlag("bank", 0x79, true, 0x100) -- SOUGEN_05_BOMB_00 (round 9: USA id)
        f:loadEntityList(0x080FEE38)
      end
    end
  end
end

function Kinstone:fusedList()
  local out = {}
  for id in pairs(self:fusedSet()) do out[#out + 1] = id end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------------------
-- UI: L opens it.  Next to a fuser NPC, the NPC's script gets the FUSE
-- interaction (INTERACTION_FUSE); next to a friend online, the fuse
-- handshake starts; otherwise the bag is shown.
-- ---------------------------------------------------------------------------
function Kinstone:openFuse()
  local f = self.field
  local p = f.player
  -- a friend in front of us?
  local friend = f.game.net and f.game.net:friendInFront(p)
  if friend then
    self.active = true
    self.ui = { mode = "offer", cursor = 1, friend = friend }
    -- round 5: the cartridge's fusion window (KinstoneMenu.lua); our piece
    -- goes to the friend, whose game decides
    local KM = require("src.zelda.tmc.KinstoneMenu")
    if self:useWindow() then self.window = KM.new(f, { name = friend.name or "", entity = nil,
      onPick = function(piece)
        self.ui.mine = piece
        self.ui.mode = "wait"
        f.game.net:send({ t = "fuse_offer", piece = piece, fused = self:fusedList() }, friend.peer)
      end,
      record = function(id, piece) self:fuse(id, piece) end,
      onDone = function() self:close() end }) end
    return
  end
  -- a fuser in front of us? (round 6: the nearest interactable, as
  -- gPossibleInteraction.currentObject; Fusers.lua runs native fusers)
  local fx, fy = p:frontPoint(10)
  local best, bestD
  for _, e in ipairs(f.entities) do
    if e.talkable and not e.hidden and not e.deleted then
      local d = math.abs(e.x - fx) + math.abs(e.y - fy)
      if d < 18 and (not bestD or d < bestD) then best, bestD = e, d end
    end
  end
  if best and require("src.zelda.tmc.Fusers").tryFuse(f, best) then return end
  self.active = true
  self.ui = { mode = "bag", cursor = 1 }
  -- round 5: the fusion window with nothing on offer (browse the bag)
  if self:useWindow() then
    self.window = require("src.zelda.tmc.KinstoneMenu").new(f, { onDone = function() self:close() end })
  end
end

-- the window needs the real field (assets, inventory) and LÖVE; headless
-- logic tests keep the plain flow
function Kinstone:useWindow()
  local f = self.field
  return rawget(_G, "love") ~= nil and love.graphics ~= nil and f.inventory ~= nil and f.assets ~= nil
end

function Kinstone:close()
  self.active = false
  self.ui = nil
  self.window = nil
end

-- a friend asked us to fuse (net event)
function Kinstone:onOffer(peer, ev)
  if self.active and self.ui and self.ui.mode ~= "bag" then
    -- busy: decline
    local net = self.field.game.net
    if net then net:send({ t = "fuse_busy" }, peer) end
    return
  end
  self.active = true
  self.ui = { mode = "answer", cursor = 1, peer = peer, offer = ev }
  -- round 5: the friend's half is the one on offer in the fusion window
  local f = self.field
  local net = f.game.net
  if not self:useWindow() then return end
  local KM = require("src.zelda.tmc.KinstoneMenu")
  local win
  win = KM.new(f, { target = ev.piece, name = ev.name or "",
    onPick = function(piece)
      local ok, id, why = self:answer(piece, ev)
      if net then net:send({ t = "fuse_result", ok = ok, id = id, piece = ev.piece, why = why }, peer) end
      self.ui.mine = piece
      win:resolve(ok, id)
    end,
    record = function(id, piece) self:fuse(id, piece) end,
    onDone = function(state)
      if state ~= 6 and net and not self.ui.mine then
        net:send({ t = "fuse_result", ok = false, why = "Your friend declined." }, peer)
      end
      self:close()
    end })
  self.window = win
end

-- the answering side's rule: the shapes fit, then GetRandomSharedFusion
-- among ids neither side has fused (of that shape first)
function Kinstone:answer(piece, offer)
  if not self:fits(piece, offer.piece) then return false, nil, "The Kinstones did not fit." end
  local other = {}
  for _, x in ipairs(offer.fused or {}) do other[x] = true end
  local start = math.random(0, 17)
  local id = self:sharedFusionFor(self:shape(piece), other, start) or self:sharedFusionFor(nil, other, start)
  if id then return true, id end
  return false, nil, "These halves have nothing left to unlock."
end

function Kinstone:onResult(peer, ev)
  local f = self.field
  -- round 5: the offering side's window plays the fusion (or the bounce)
  if self.window and self.window.waiting then
    self.window:resolve(ev.ok, ev.id)
    if not ev.ok then f:showToast(ev.why or "The Kinstones did not fit.", 120); self.ui.mode = "offer" end
    return
  end
  if ev.ok and ev.id then
    local piece = self.ui and self.ui.mine or ev.piece
    local we = self:fuse(ev.id, piece)
    f:sound(0xFA)
    f:showToast(self:resultText(ev.id, we), 180)
  else
    f:showToast(ev.why or "The Kinstones did not fit.", 120)
  end
  self:close()
end

function Kinstone:resultText(id, we)
  local where = ""
  if we and we.area then
    local loc = self.field.game:areaName(we.area)
    if loc then where = " Something changed in " .. loc .. "!" end
  end
  return string.format("Fused Kinstone #%d!%s", id, where)
end

function Kinstone:update(input)
  if self.npcFuse and not self.window then return end -- round 6: a native fuser's messages
  if self.window then
    -- R in the offer window still gives the friend 10 shells (round 3)
    if not (self.ui and self.ui.mode == "offer" and input.pressed("r")) then
      return self.window:update(input)
    end
  end
  local ui = self.ui
  if not ui then self.active = false return end
  local list = self:pieces()
  if input.pressed("up") then ui.cursor = math.max(1, ui.cursor - 1) end
  if input.pressed("down") then ui.cursor = math.min(math.max(1, #list), ui.cursor + 1) end
  if input.pressed("b") or input.pressed("l") and ui.mode == "bag" then
    if ui.mode == "answer" and self.field.game.net then
      self.field.game.net:send({ t = "fuse_result", ok = false, why = "Your friend declined." }, ui.peer)
    end
    return self:close()
  end
  if ui.mode == "wait" then return end
  -- R in the offer window gives the friend 10 Mysterious Shells (the
  -- figurine currency): our addition, the cartridge has no link trading
  if ui.mode == "offer" and input.pressed("r") then
    local s = self.field.save.stats
    local net = self.field.game.net
    if (s.shells or 0) >= 10 and net then
      s.shells = s.shells - 10
      net:send({ t = "gift_shells", n = 10 }, ui.friend.peer)
      self.field:showToast("Gave 10 shells.", 90)
    else
      self.field:showToast("Not enough shells.", 90)
    end
    return self:close()
  end
  if input.pressed("a") and #list > 0 then
    local piece = list[ui.cursor]
    local net = self.field.game.net
    if ui.mode == "offer" and net then
      ui.mine = piece
      ui.mode = "wait"
      net:send({ t = "fuse_offer", piece = piece, fused = self:fusedList() }, ui.friend.peer)
    elseif ui.mode == "answer" and net then
      local offer = ui.offer
      local ok, id, why = false, nil, nil
      if not self:fits(piece, offer.piece) then
        why = "The Kinstones did not fit."
      else
        local other = {}
        for _, x in ipairs(offer.fused or {}) do other[x] = true end
        local start = math.random(0, 17)
        id = self:sharedFusionFor(self:shape(piece), other, start)
          or self:sharedFusionFor(nil, other, start)
        if id then ok = true else why = "These halves have nothing left to unlock." end
      end
      net:send({ t = "fuse_result", ok = ok, id = id, piece = offer.piece, why = why }, ui.peer)
      ui.mine = piece
      self:onResult(ui.peer, { ok = ok, id = id, why = why })
    end
  end
end

function Kinstone:draw(font)
  if self.window then return self.window:draw() end
  local ui = self.ui
  if not ui then return end
  local g = love.graphics
  g.setColor(0.05, 0.12, 0.08, 0.92)
  g.rectangle("fill", 40, 20, 160, 120, 4, 4)
  g.setColor(0.9, 0.8, 0.4, 1)
  g.rectangle("line", 40.5, 20.5, 159, 119, 4, 4)
  g.setFont(font)
  local title = ({ bag = "Kinstone Bag", offer = "Fuse with friend: pick a piece",
                   answer = "Friend wants to fuse!", wait = "Waiting for your friend..." })[ui.mode]
  g.print(title or "", 46, 24)
  local list = self:pieces()
  if #list == 0 then
    g.setColor(0.8, 0.8, 0.8, 1)
    g.print("No Kinstone pieces.", 50, 48)
  end
  for i, t in ipairs(list) do
    if i > 6 then break end
    local y = 40 + (i - 1) * 14
    local e = self.data.events[t] or {}
    g.setColor(i == ui.cursor and 1 or 0.75, i == ui.cursor and 0.95 or 0.75, 0.6, 1)
    g.print(string.format("%s Piece %02X  (shape %d)  x%d", i == ui.cursor and ">" or " ",
      t - 0x64, e.shape or 0, self:count(t)), 48, y)
  end
  g.setColor(1, 1, 1, 1)
end

return Kinstone
