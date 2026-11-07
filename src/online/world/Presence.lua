-- REMOTE PLAYERS ON THE MAP (docs/online-design.md 2.8 "Rendering remote
-- players").  Each world member standing on the map this player is on
-- becomes a GHOST: a real `src.world.NPC` wearing that player's own trainer
-- sheet (the sprite id their save already uses -- the same game family, so
-- the same sheet exists here), walked cell to cell by interpolation.
--
-- WHERE A GHOST LIVES, and why nothing in single-player can tell it is there:
--
--   * in `overworld.entities` ONLY -- the draw list -- never in
--     `overworld.npcs`.  `npcs` is what talking, trainers' sight, scripted
--     movement (localId lookups), seam pooling and captureSave walk, so a
--     ghost is never saved, never scripted, never spotted by a trainer and
--     never answers a map script.  `rebuildEntities` keeps "extras" it does
--     not own in place (a mod's spawns live there the same way), and a map
--     change starts `entities` afresh, after which the next tick puts the
--     ghosts back for the new map.
--   * `passable = true`: Collision.occupied (the player's steps, NPC
--     wandering, seam proxies, sight lines) walks straight through it.
--   * no localId, no script, movementType 0: nothing drives it but this file.
--   * pressing A at one goes through OverworldState.remotePlayerSeam, the one
--     anchored hook in OverworldController:interact, set only while a world
--     is open (src/ui/online/GhostInteract.lua answers it).
--
-- The overhead bubbles (emotes in the game's own art, a chat line for a few
-- seconds) and the name tag are drawn by the ghost's own draw, so they go
-- through whatever transform the renderer draws the sprite in (flat GB/GBA,
-- Gen 4/5 billboards, the free cameras).

local P = require("src.online.world.WorldProtocol")
local Util = require("src.online.net.Util")

local Presence = {}

Presence.ghosts = {}       -- pid -> ghost
Presence.ow = nil
Presence.EMOTE_SECONDS = 2.2
Presence.CHAT_SECONDS = 5
Presence.NAME_RANGE = 4    -- cells: the name tag shows within this of the player
Presence.MAX_QUEUE = 4     -- steps buffered before a ghost snaps
Presence.INDEX = 900       -- synthetic object index base (no real map has 900)

local function now() return Util.time() end

-- ------------------------------------------------------------ local player

-- the cell this player is at, or stepping to (sent as soon as the step
-- starts, so the ghost elsewhere starts walking at once)
function Presence.localPos(game, ow)
  local p = ow and ow.player
  if not (p and ow.map and ow.map.id) then return nil end
  -- a screen that is a room of its own (the link rooms' Union Room / Wi-Fi
  -- Plaza lobbies set `presenceRoom`): everyone on it stands in that room,
  -- whatever map their game is on, so invites between them are "near"
  -- (anywhere on the stack: an invite window or the link screen over it is
  -- still in the room)
  local states = game and game.stack and game.stack.states
  for i = #(states or {}), 1, -1 do
    local st = states[i]
    if type(st) == "table" and type(st.presenceRoom) == "string" then
      return { m = st.presenceRoom, x = 0, y = 0, f = "down", mv = "walk", d = 16 }
    end
  end
  local x, y = p.cellX, p.cellY
  if p.moving and p.targetX and p.targetY then x, y = p.targetX, p.targetY end
  local save = game and game.save
  local mv = "walk"
  if p.surfing then mv = "surf"
  elseif save and save.onBike then mv = "bike"
  elseif p.running then mv = "run" end
  local d = tonumber(p.stepFramesCur) or tonumber(p.stepFrames) or 16
  if not p.moving then d = tonumber(p.stepFrames) or 16 end
  return { m = tostring(ow.map.id), x = math.floor(x or 0), y = math.floor(y or 0),
           f = P.FACINGS[p.facing] and p.facing or "down", mv = mv,
           d = math.max(1, math.min(64, math.floor(d))) }
end

function Presence.localLook(game, ow)
  local p = ow and ow.player
  local look = {}
  if p then
    look.walk = p.walkId
    look.bike = p.bikeId
    look.surf = p.surfId
  end
  local save = game and game.save
  local g = save and save.player and save.player.gender
  if g == "girl" or g == "boy" then look.gender = g end
  return P.cleanLook(look)
end

-- ------------------------------------------------------------ ghosts

local function spriteKey(data, look, mv)
  local sprites = (data and data.sprites) or {}
  look = look or {}
  local want = (mv == "bike" and look.bike) or (mv == "surf" and look.surf) or look.walk
  if want and sprites[want] then return want end
  if look.walk and sprites[look.walk] then return look.walk end
  -- the sheet is from this player's own game family, so it should exist;
  -- if it does not (a modded sheet), wear this game's own hero
  local ow = package.loaded["src.core.Game"] and package.loaded["src.core.Game"].overworld
  local mine = ow and ow.player and ow.player.walkId
  if mine and sprites[mine] then return mine end
  return want or look.walk or "SPRITE_FALLBACK"
end

local function drawOverhead(ghost, npc, camX, camY)
  local data = Presence.data
  local member = ghost.member
  if not member then return end
  local t = now()
  local sprite = npc.sprite
  local tileH = (sprite and sprite.tileH) or 16
  local cx = (npc.px or 0) + 8 - camX
  local head = (npc.py or 0) - camY + 16 - math.max(tileH, 16) - 4
  if tileH >= 32 then head = (npc.py or 0) - camY - 12 end
  local g = love.graphics
  local emote = member.emote
  if emote and t - emote.at < Presence.EMOTE_SECONDS then
    require("src.online.world.EmoteArt").draw(data, emote.e, cx, head)
    return
  end
  local said = ghost.said
  if said and t - said.at < Presence.CHAT_SECONDS then
    Presence.drawBubbleText(said.text, cx, head)
    return
  end
  local ow = ghost.ow or Presence.ow
  local p = ow and ow.player
  if p and math.abs((p.cellX or 0) - (npc.cellX or 0)) + math.abs((p.cellY or 0) - (npc.cellY or 0))
           <= Presence.NAME_RANGE then
    Presence.drawTag(member.name or "?", cx, head)
  end
  g.setColor(1, 1, 1, 1)
end

-- text in the game's own font when it has one
local function textWidth(text)
  local okF, Font = pcall(require, "src.render.Font")
  if okF and Font and Font.width then
    local ok, w = pcall(Font.width, text)
    if ok and w then return w, Font end
  end
  return love.graphics.getFont():getWidth(text), nil
end

local function textHeight(Font)
  if Font and Font.glyphHeight then
    local ok, h = pcall(Font.glyphHeight)
    if ok and tonumber(h) then return tonumber(h) end
  end
  return love.graphics.getFont():getHeight()
end

local function drawText(Font, text, x, y)
  if Font then
    local ok = pcall(Font.draw, text, math.floor(x), math.floor(y))
    if ok then return end
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.print(text, math.floor(x), math.floor(y))
end

-- the longest line a head bubble shows; the whole line is in the chat log
Presence.BUBBLE_CHARS = 12

function Presence.drawTag(name, cx, bottom)
  local g = love.graphics
  local w, Font = textWidth(name)
  local h = textHeight(Font) + 2
  local x, y = math.floor(cx - w / 2 - 2), math.floor(bottom - h)
  g.setColor(1, 1, 1, 0.78)
  g.rectangle("fill", x, y, w + 4, h)
  g.setColor(1, 1, 1, 1)
  drawText(Font, name, x + 2, y + 1)
  g.setColor(1, 1, 1, 1)
end

function Presence.drawBubbleText(text, cx, bottom)
  local g = love.graphics
  local chars = P.utf8chars(text)
  if #chars > Presence.BUBBLE_CHARS then
    text = table.concat(chars, "", 1, Presence.BUBBLE_CHARS - 2) .. ".."
  end
  local w, Font = textWidth(text)
  local h = textHeight(Font) + 4
  local x, y = math.floor(cx - w / 2 - 3), math.floor(bottom - h - 3)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", x, y, w + 6, h, 2, 2)
  g.polygon("fill", cx - 3, y + h - 1, cx + 3, y + h - 1, cx, y + h + 3)
  g.setColor(0, 0, 0, 1)
  g.setLineWidth(1)
  g.rectangle("line", x + 0.5, y + 0.5, w + 5, h - 1, 2, 2)
  g.setColor(1, 1, 1, 1)
  drawText(Font, text, x + 3, y + 2)
  g.setColor(1, 1, 1, 1)
end

local function makeGhost(game, ow, pid, member)
  local NPC = require("src.world.NPC")
  local pos = member.pos
  local key = spriteKey(game.data, member.look, pos.mv)
  local ok, npc = pcall(NPC.new, game.data, ow.map.id, {
    index = Presence.INDEX + pid, sprite = key, x = pos.x, y = pos.y,
    movementType = 0, direction = 1, remotePlayer = true,
  })
  if not ok or not npc then return nil end
  npc.id = "remote_player_" .. tostring(pid)
  npc.remote = true
  npc.remotePlayer = pid
  npc.passable = true
  npc.frozen = true
  npc.facing = pos.f or "down"
  npc.moving = false
  npc.progress = 0
  local ghost = { pid = pid, npc = npc, member = member, key = key, queue = {} }
  -- the overhead art rides the sprite's own draw (and so its transform)
  local baseDraw = NPC.draw
  npc.draw = function(self, camX, camY)
    baseDraw(self, camX, camY)
    local okO, err = pcall(drawOverhead, ghost, self, camX, camY)
    if not okO and not Presence.warned then
      Presence.warned = true
      require("src.core.Logger").warn("world: overhead draw failed: %s", tostring(err))
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  return ghost
end

local function inList(list, e)
  for _, x in ipairs(list or {}) do if x == e then return true end end
  return false
end

local function removeFrom(list, e)
  if not list then return end
  for i = #list, 1, -1 do if list[i] == e then table.remove(list, i) end end
end

local function dropGhost(ow, pid)
  local g = Presence.ghosts[pid]
  if not g then return end
  Presence.ghosts[pid] = nil
  if ow then
    removeFrom(ow.entities, g.npc)
    removeFrom(ow.npcs, g.npc)   -- never there; belt and braces
  end
end

function Presence.clear(ow)
  ow = ow or Presence.ow
  for pid in pairs(Presence.ghosts) do dropGhost(ow, pid) end
  Presence.ghosts = {}
end

-- start the step at the head of the queue
local function startStep(g, t)
  local nextCell = table.remove(g.queue, 1)
  if not nextCell then return end
  local npc = g.npc
  local dx, dy = nextCell.x - npc.cellX, nextCell.y - npc.cellY
  if dx > 0 then npc.facing = "right" elseif dx < 0 then npc.facing = "left"
  elseif dy > 0 then npc.facing = "down" elseif dy < 0 then npc.facing = "up" end
  npc.targetX, npc.targetY = nextCell.x, nextCell.y
  npc.moving = true
  npc.progress = 0
  g.stepAt = t
  local frames = nextCell.d or 16
  -- a ghost that has fallen behind walks a little faster to catch up
  if #g.queue > 0 then frames = frames * 0.6 end
  g.stepDur = math.max(2, frames) / 60
end

local function land(g)
  local npc = g.npc
  npc.cellX, npc.cellY = npc.targetX or npc.cellX, npc.targetY or npc.cellY
  npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
  npc.targetX, npc.targetY = nil, nil
  npc.moving = false
  npc.progress = 0
end

local function snap(g, pos)
  local npc = g.npc
  g.queue = {}
  npc.cellX, npc.cellY = pos.x, pos.y
  npc.px, npc.py = pos.x * 16, pos.y * 16
  npc.targetX, npc.targetY = nil, nil
  npc.moving = false
  npc.facing = pos.f or npc.facing
end

local function steer(g, pos, t)
  local npc = g.npc
  local last = g.queue[#g.queue] or (npc.moving and { x = npc.targetX, y = npc.targetY })
                or { x = npc.cellX, y = npc.cellY }
  if pos.x ~= last.x or pos.y ~= last.y then
    local dist = math.abs(pos.x - last.x) + math.abs(pos.y - last.y)
    if dist > 3 or #g.queue + dist > Presence.MAX_QUEUE then
      snap(g, pos)
      return
    end
    -- walk the gap one cell at a time: x first, then y
    local x, y = last.x, last.y
    while x ~= pos.x do
      x = x + (pos.x > x and 1 or -1)
      g.queue[#g.queue + 1] = { x = x, y = y, d = pos.d }
    end
    while y ~= pos.y do
      y = y + (pos.y > y and 1 or -1)
      g.queue[#g.queue + 1] = { x = x, y = y, d = pos.d }
    end
  end
  if not npc.moving and #g.queue == 0 then npc.facing = pos.f or npc.facing end
  if not npc.moving and g.queue[1] then startStep(g, t) end
end

local function animate(g, t)
  local npc = g.npc
  if not npc.moving then return end
  local frac = (t - (g.stepAt or t)) / (g.stepDur or 0.27)
  if frac >= 1 then
    land(g)
    if g.queue[1] then
      startStep(g, t)
    elseif g.member and g.member.pos then
      npc.facing = g.member.pos.f or npc.facing
    end
    return
  end
  if frac < 0 then frac = 0 end
  local fx, fy = npc.cellX * 16, npc.cellY * 16
  local tx, ty = (npc.targetX or npc.cellX) * 16, (npc.targetY or npc.cellY) * 16
  npc.px = math.floor(fx + (tx - fx) * frac + 0.5)
  npc.py = math.floor(fy + (ty - fy) * frac + 0.5)
  npc.progress = math.floor(frac * 16)
end

local function refreshSprite(game, g, mv)
  local key = spriteKey(game.data, g.member.look, mv)
  if key ~= g.key then
    local okS, SpriteRenderer = pcall(require, "src.render.SpriteRenderer")
    local def = game.data.sprites and game.data.sprites[key]
    if okS and def then
      g.npc.sprite = SpriteRenderer.new(def, g.npc.id)
      g.key = key
    end
  end
end

-- one tick: publish this player, bring the ghosts in line with the roster
function Presence.update(client, game)
  local ow = game and game.overworld
  if ow ~= Presence.ow then
    Presence.clear(Presence.ow)
    Presence.ow = ow
  end
  Presence.data = game and game.data
  if not (ow and ow.map and ow.player and client and client.state == "in") then
    if Presence.ow then Presence.clear(Presence.ow) end
    return
  end
  local t = now()
  -- publish
  local pos = Presence.localPos(game, ow)
  if pos then client:setPosition(pos) end
  local look = Presence.localLook(game, ow)
  local lk = (look.walk or "") .. "|" .. (look.bike or "") .. "|" .. (look.surf or "")
  if Presence.lastLook ~= lk then
    if Presence.lastLook ~= nil then client:setLook(look) end
    Presence.lastLook = lk
  end
  -- what was said lately, per speaker, for the bubbles
  for _, e in ipairs(client.log:recent(8, t, Presence.CHAT_SECONDS)) do
    if e.kind == "chat" and e.pid and Presence.ghosts[e.pid] then
      local g = Presence.ghosts[e.pid]
      if not g.said or g.said.seq < e.seq then g.said = { text = e.text, at = e.t or t, seq = e.seq } end
    end
  end
  -- ghosts
  local mapId = tostring(ow.map.id)
  for pid, g in pairs(Presence.ghosts) do
    local m = client.members[pid]
    if not m or not m.pos or m.pos.m ~= mapId then dropGhost(ow, pid) end
  end
  ow.entities = ow.entities or {}
  for pid, m in pairs(client.members) do
    if pid ~= client.you and m.pos and m.pos.m == mapId then
      local g = Presence.ghosts[pid]
      if not g then
        g = makeGhost(game, ow, pid, m)
        Presence.ghosts[pid] = g
      end
      if g then
        g.member = m
        refreshSprite(game, g, m.pos.mv)
        steer(g, m.pos, t)
        animate(g, t)
        if not inList(ow.entities, g.npc) then table.insert(ow.entities, g.npc) end
      end
    end
  end
  local OW = package.loaded["src.world.OverworldController"]
  if OW then OW.remotePlayerSeam = Presence.seam end
end

-- the ghost at a cell (where it stands, or the cell it is stepping into)
function Presence.ghostAt(cx, cy)
  for pid, g in pairs(Presence.ghosts) do
    local npc = g.npc
    if not npc.hidden and ((npc.cellX == cx and npc.cellY == cy)
       or (npc.targetX == cx and npc.targetY == cy)) then
      return pid, g
    end
  end
  return nil
end

-- OverworldController:interact's remote-player seam: true when it answered
function Presence.seam(ow, fx, fy)
  local pid, g = Presence.ghostAt(fx, fy)
  if not pid then return false end
  local okG, Game = pcall(require, "src.core.Game")
  if not okG then return false end
  -- the ghost turns to face the player, as a person you walk up to would
  local p = ow and ow.player
  if p and not g.npc.moving and g.npc.facePlayer then pcall(g.npc.facePlayer, g.npc, p) end
  local ok, err = pcall(function()
    require("src.ui.online.GhostInteract").open(Game, pid)
  end)
  if not ok then
    require("src.core.Logger").warn("world: interact failed: %s", tostring(err))
    return false
  end
  return true
end

-- the same ghost for a link room's other player (src/online/LinkRoomPeer.lua):
-- no world, one member; never in Presence.ghosts, so no world seam answers it
function Presence.makeRoomGhost(game, ow, pid, member)
  local g = makeGhost(game, ow, pid, member)
  if g then g.ow = ow end
  return g
end
Presence.steerGhost = steer
Presence.animateGhost = animate

-- leaving the world: everything off the map, the seam unhooked
function Presence.shutdown()
  Presence.clear(Presence.ow)
  Presence.ow = nil
  Presence.lastLook = nil
  local OW = package.loaded["src.world.OverworldController"]
  if OW and OW.remotePlayerSeam == Presence.seam then OW.remotePlayerSeam = nil end
end

return Presence
