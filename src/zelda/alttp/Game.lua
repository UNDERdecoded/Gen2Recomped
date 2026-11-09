-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ALTTP GAME OBJECT handed to ZeldaRuntime: a title card, then Hyrule.
--
-- What is playable (see docs/zelda/PROGRESS-alttp.md for the honest list):
-- the whole Light World and Dark World overworld rendered from the cartridge
-- (both BG layers, per-screen tilesets and palettes), Link walking with the
-- cartridge's speeds, walk cycle and tile collision, ledge hops, the camera
-- clamped to each area with the screen-edge scroll between areas, the
-- overworld music, saving position, and online presence (friends' Links in
-- your Hyrule, see Online.lua).

local Overworld = require("src.zelda.alttp.Overworld")
local Link = require("src.zelda.alttp.Link")
local Palette = require("src.zelda.alttp.Palette")

local G = {}
G.__index = G

G.W, G.H = 240, 160
-- Link's house, outside the door (screen 0x2C), in line with the door tile
-- the cartridge's entrance table names (x 192)
G.START = { world = "lw", x = 4 * 512 + 192, y = 5 * 512 + 280, facing = Link.DOWN }

function G.new(opts)
  local self = setmetatable({}, G)
  self.opts = opts or {}
  self.input = self.opts.input
  self.data = assert(self.opts.data, "ALttP: no imported data")
  self.ow = Overworld.new(self.data)
  self.headless = self.opts.headless or not (love and love.graphics)
  if not self.headless then
    self.view = require("src.zelda.alttp.View").new(self.ow, self.data)
  end
  self.linkPal = Palette.link(self.data)
  -- HUD stats (hearts, magic, counters), the cartridge's new-game values
  local Hud = require("src.zelda.alttp.Hud")
  local sv = type(self.opts.save) == "table" and self.opts.save.alttp
  self.stats = (sv and type(sv.stats) == "table") and sv.stats or Hud.newStats()
  -- a new file starts with the cartridge's opening (startOpening)
  self.newGame = not sv
  self.state = self.opts.skipTitle and "play" or "title"
  self.titleT = 0
  self.titleChoice = 1
  if self.opts.mode == "fs" then self.state = "fs" end
  local save = self.opts.save
  local s = (type(save) == "table" and save.alttp) or G.START
  self.link = Link.new(self.data, { world = s.world or "lw", x = s.x or G.START.x,
                                    y = s.y or G.START.y, facing = s.facing or Link.DOWN })
  self.area = self.ow:area(self:screen())
  self.cam = self:cameraFor(self.area)
  self.scroll = nil
  self.online = require("src.zelda.alttp.Online").new(self)
  self.music = require("src.zelda.alttp.Audio").new(self.data, self.opts)
  self.frame = 0
  if self.state == "fs" then self:enterFs() end
  return self
end

-- Four Swords: the cartridge's other game, on the same data
function G:enterFs()
  if not self.fsMode then
    self.fsMode = require("src.zelda.alttp.FourSwords").new(self, { fs = self.opts.fs })
  end
  self.state = "fs"
  if self.music then self.music:stop() end
end

function G:screen()
  return Overworld.screenAt(self.link.world, self.link.x + 8, self.link.y + 16) or 0
end

-- camera top-left that centres Link, clamped to the area
function G:cameraFor(area)
  local cx = self.link.x + 8 - G.W / 2
  local cy = self.link.y + 12 - G.H / 2
  cx = math.max(area.x, math.min(area.x + area.w - G.W, cx))
  cy = math.max(area.y, math.min(area.y + area.h - G.H, cy))
  return { x = math.floor(cx), y = math.floor(cy) }
end

local function held(input, b) return input and input.isDown(b) end
local function pressed(input, b) return input and input.wasPressed(b) end

function G:update(dt)
  self.frame = self.frame + 1
  self.music:update()
  if self.state == "title" then
    self.titleT = self.titleT + 1
    if pressed(self.input, "up") or pressed(self.input, "down") then
      self.titleChoice = 3 - self.titleChoice
    end
    if pressed(self.input, "start") or pressed(self.input, "a") then
      if self.titleChoice == 2 then return self:enterFs() end
      self.state = "play"
      if self.newGame and self.data.rooms then return self:startOpening() end
      self.music:playForScreen(self.area.parent, self.link.world)
    end
    return
  end
  if self.state == "fs" then return self.fsMode:update(self.input) end
  if self.textBox then return self:updateText() end
  if self.state == "room" then return self:updateRoom() end
  if self.state ~= "play" then return end
  if not self.musicStarted then
    self.musicStarted = true
    self.music:playForScreen(self.area.parent, self.link.world)
  end

  if self.scroll then return self:updateScroll() end

  local inp = {
    up = held(self.input, "up"), down = held(self.input, "down"),
    left = held(self.input, "left"), right = held(self.input, "right"),
  }
  local ow = self.ow
  self.link:update(inp, function(world, x, y) return ow:attrAt(world, x, y) end)
  -- doors: walking up into an overworld door (the cartridge's entrance
  -- tables, Interior.owEntrance)
  if inp.up and self.link.facing == Link.UP and self.data.rooms then
    local Interior = require("src.zelda.alttp.Interior")
    local e = Interior.owEntrance(self.data, self.ow, self.link.world, self.link.x, self.link.y, 3)
    if e then return self:enterRoom(e) end
  end

  -- leaving the area: scroll to the neighbour
  local s = self:screen()
  local a = self.ow:area(s)
  if a.parent ~= self.area.parent then
    self:beginScroll(a)
  else
    self.cam = self:cameraFor(self.area)
  end
  self.online:update()
end

-- entrance: cartridge entrance number (RomMap.entrances)
function G:enterRoom(entrance)
  local Interior = require("src.zelda.alttp.Interior")
  self.interior = Interior.new(self.data, entrance)
  local sp = self.interior.spawn
  self.link.x, self.link.y, self.link.facing = sp[1], sp[2], sp[3]
  self.link.steps = 0
  self.state = "room"
  self.roomImages = nil
end

function G:updateRoom()
  local inside = self.interior
  local inp = {
    up = held(self.input, "up"), down = held(self.input, "down"),
    left = held(self.input, "left"), right = held(self.input, "right"),
  }
  self.link:update(inp, function(_, x, y) return inside:blocked(x, y) and 0x01 or 0x00 end)
  -- TileBehavior_Entrance (0x8E/0x8F) under Link's feet while he walks down
  local out = inside.outside
  if inp.down and out and inside:isExit(self.link.x + 8, self.link.y + 20) then
    self.link.world, self.link.x, self.link.y, self.link.facing = out.world, out.x, out.y, 2
    self.state = "play"
    self.interior, self.roomImages = nil, nil
    self.area = self.ow:area(self:screen())
    self.cam = self:cameraFor(self.area)
  end
end

function G:drawRoom()
  local inside = self.interior
  if not self.roomImages then
    local View = require("src.zelda.alttp.View")
    local pal = inside:palette()
    self.roomImages = {}
    -- BG2 is the room, BG1 the frame over a transparent fill (drawn above)
    for _, layer in ipairs({ "bg2", "bg1" }) do
      local img = love.image.newImageData(512, 512)
      View.fill(img, 512, 512, inside:decodeLayer(layer), pal, layer == "bg2" and pal[0] or nil)
      local im = love.graphics.newImage(img)
      im:setFilter("nearest", "nearest")
      self.roomImages[layer] = im
    end
  end
  local cx, cy = inside:camera(self.link.x, self.link.y, G.W, G.H)
  love.graphics.draw(self.roomImages.bg2, -cx, -cy)
  love.graphics.draw(self.roomImages.bg1, -cx, -cy)
  local saved = self.cam
  self.cam = { x = cx, y = cy }
  self:drawLink(self.link)
  self.cam = saved
  self:drawHud()
end

function G:beginScroll(newArea)
  local from = self.cam
  local oldArea = self.area
  self.area = newArea
  local to = self:cameraFor(newArea)
  self.scroll = { from = from, to = to, t = 0, frames = 40 }
  self.ow.attrCache = {}   -- keep the collision cache small
  if self.music.screenChanged then self.music:screenChanged(oldArea.parent, newArea.parent, self.link.world) end
end

function G:updateScroll()
  local sc = self.scroll
  sc.t = sc.t + 1
  local p = sc.t / sc.frames
  self.cam = { x = math.floor(sc.from.x + (sc.to.x - sc.from.x) * p + 0.5),
               y = math.floor(sc.from.y + (sc.to.y - sc.from.y) * p + 0.5) }
  if sc.t >= sc.frames then self.scroll = nil end
end

-- ----------------------------------------------------------------- drawing

function G:drawLink(lk, tint)
  local parts = Link.pose(self.data, lk.facing or lk.f, lk.steps or lk.s or 0)
  local x = (lk.x - self.cam.x)
  local y = (lk.y - self.cam.y) - (lk.z or 0)
  if tint then love.graphics.setColor(tint) end
  for i = #parts, 1, -1 do
    local p = parts[i]
    local im = self.view:linkCell(p.cell, self.linkPal, "green")
    local sx, sy = p.hflip and -1 or 1, p.vflip and -1 or 1
    love.graphics.draw(im, x + p.dx + (p.hflip and 16 or 0), y + p.dy + (p.vflip and 16 or 0), 0, sx, sy)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function G:visibleScreens()
  local list = {}
  local x0, y0 = self.cam.x, self.cam.y
  for sy = math.floor(y0 / 512), math.floor((y0 + G.H - 1) / 512) do
    for sx = math.floor(x0 / 512), math.floor((x0 + G.W - 1) / 512) do
      if sx >= 0 and sy >= 0 and sx < 8 and sy < 8 then
        list[#list + 1] = { s = sy * 8 + sx + (self.link.world == "dw" and 0x40 or 0),
                            x = sx * 512 - x0, y = sy * 512 - y0 }
      end
    end
  end
  return list
end

function G:draw()
  if self.headless then return end
  love.graphics.clear(0, 0, 0, 1)
  if self.state == "title" then return self:drawTitle() end
  if self.state == "fs" then return self.fsMode:draw() end
  if self.state == "room" then return self:drawRoom() end
  local vis = self:visibleScreens()
  for _, v in ipairs(vis) do
    love.graphics.draw(self.view:screen(v.s).bg2, v.x, v.y)
  end
  self.online:drawPeers()
  self:drawLink(self.link)
  for _, v in ipairs(vis) do
    love.graphics.draw(self.view:screen(v.s).bg1, v.x, v.y)
  end
  self:drawHud()
end

-- THE OPENING (round 4b, partial): entrance 0 is Link in bed in his house
-- (room 0x104, from the entrance table). Zelda's telepathy (BMG message 31,
-- no window: its Window command says so) plays over the darkened room, then
-- the uncle's "I'm going out for a bit" (message 13). NOT PORTED: the rain,
-- the night palette, Link's in-bed pose, the uncle's sprite and walk out,
-- the music cue; the room is drawn with its daytime palette.
G.MSG_TELEPATHY = 31
G.MSG_UNCLE_LEAVES = 13
function G:startOpening()
  self.newGame = false
  self:enterRoom(0)
  self.opening = "telepathy"
  self.music:stop()
  self:showMessage(G.MSG_TELEPATHY)
  self.onTextDone = function(g)
    g.opening = "uncle"
    g:showMessage(G.MSG_UNCLE_LEAVES)
    g.onTextDone = function(g2) g2.opening = nil end
  end
end

-- DIALOGUE: a cartridge message (BMG index) in the cartridge's window
function G:showMessage(n)
  if not (self.data.text and self.data.font) then return false end
  local Text = require("src.zelda.alttp.Text")
  local cy = self.cam and self.cam.y or 0
  if self.state == "room" and self.interior then
    local _, ry = self.interior:camera(self.link.x, self.link.y, G.W, G.H)
    cy = ry
  end
  self.textBox = Text.open(self.data, n, { linkScreenY = self.link.y - cy, name = self.playerName })
  return true
end

function G:updateText()
  local box = self.textBox
  box:update(pressed(self.input, "a") or pressed(self.input, "b"))
  if box.done then
    self.textBox = nil
    if self.onTextDone then local f = self.onTextDone; self.onTextDone = nil; f(self) end
  end
end

function G:drawText()
  local box = self.textBox
  if not (box and self.view) then return end
  if self.opening == "telepathy" then
    -- the telepathy plays over a dark room (approximation of the fade)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, G.W, G.H)
    love.graphics.setColor(1, 1, 1, 1)
  end
  local Hud = require("src.zelda.alttp.Hud")
  self.hudPal = self.hudPal or Hud.palette(self.data, 0)
  local wx, wy = box:window()
  if box.border then
    -- the window's inside: the cartridge leaves it clear and darkens the
    -- play field behind it; ours is a half-black fill (approximation)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", wx + 8, wy + 8, 22 * 8, 6 * 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.view:hudImage(box:borderWords(), 24, 8, self.hudPal), wx, wy)
  end
  love.graphics.draw(self.view:textImage(box, self.hudPal), wx + 8, wy + 8)
end

-- the cartridge HUD (Hud.lua) over the play field
function G:drawHud()
  if not (self.data.ui and self.view) then return end
  local Hud = require("src.zelda.alttp.Hud")
  self.hudPal = self.hudPal or Hud.palette(self.data, 0)
  local im = self.view:hudImage(Hud.words(self.data.ui, self.stats), Hud.COLS, Hud.ROWS, self.hudPal)
  love.graphics.draw(im, -Hud.SCROLL_X, 0)
  self:drawText()
end

-- The cartridge's title screen (RomMap.ui: logo on BG1, castle and lake on
-- BG2, the cartridge's scroll and palettes). The game choice under it is
-- written with the cartridge's menu letters; its place on the screen is ours
-- (the cartridge picks the game on a screen that is not decoded yet).
function G:drawTitle()
  if not (self.data.title and self.data.ui) then return self:drawTitleCard() end
  local Hud = require("src.zelda.alttp.Hud")
  if not self.titlePal then
    local pal = Hud.palette(self.data, 0)
    local ui = self.data.ui
    for i = 0, 127 do pal[32 + i] = ui.titlePal[i + 1] end
    for i = 0, 15 do pal[0xD0 + i] = ui.titlePal2[i + 1] end
    self.titlePal = pal
    self.hudPal = self.hudPal or Hud.palette(self.data, 0)
  end
  local t = self.view:titleImages(self.titlePal)
  local sc = self.data.ui.titleScroll
  love.graphics.clear(t.backdrop[1], t.backdrop[2], t.backdrop[3], 1)
  love.graphics.draw(t.bg2, -sc.bg2x, -sc.y)
  love.graphics.draw(t.bg1, -sc.bg1x, -sc.y)
  local label = self.titleChoice == 1 and "A LINK TO THE PAST" or "FOUR SWORDS"
  local blink = math.floor(self.titleT / 30) % 2 == 0
  local words = Hud.textWords((blink and "- " or "  ") .. label .. (blink and " -" or "  "))
  local im = self.view:hudImage(words, #words, 1, self.hudPal)
  love.graphics.draw(im, math.floor((G.W - #words * 8) / 2), G.H - 8)
end

function G:drawTitleCard()
  -- Our own title card (the cartridge's title sequence is not ported yet):
  -- Hyrule Castle's screen from the ROM behind the text.
  local saved = self.cam
  self.cam = { x = 3 * 512 + 136, y = 3 * 512 + 120 }
  for _, v in ipairs(self:visibleScreens()) do
    love.graphics.draw(self.view:screen(v.s).bg2, v.x, v.y)
    love.graphics.draw(self.view:screen(v.s).bg1, v.x, v.y)
  end
  self.cam = saved
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 44, G.W, 64)
  love.graphics.setColor(1, 1, 1, 1)
  local blink = math.floor(self.titleT / 30) % 2 == 0
  love.graphics.printf((self.titleChoice == 1 and (blink and "> " or "  ") or "  ") .. "A LINK TO THE PAST", 0, 56, G.W, "center")
  love.graphics.printf((self.titleChoice == 2 and (blink and "> " or "  ") or "  ") .. "FOUR SWORDS", 0, 80, G.W, "center")
end

-- ----------------------------------------------------------------- saving

function G:save()
  -- inside a room, save the door outside it (rooms are not restored yet)
  local out = self.interior and self.interior.outside
  return { version = 1, game = "alttp",
           alttp = { world = out and out.world or self.link.world,
                     x = out and out.x or self.link.x, y = out and out.y or self.link.y,
                     facing = out and 2 or self.link.facing, stats = self.stats } }
end

function G:quit()
  self.music:stop()
end

-- online hooks: Four Swords when in that mode (a guest who gets the host's
-- fs_start joins it from anywhere), else ALttP presence (Online.lua)
function G:netSnapshot()
  if self.state == "fs" then return self.fsMode:snapshot() end
  return self.online:snapshot()
end
function G:netApply(peer, snap)
  if type(snap) == "table" and snap.m == "fs" then
    if self.fsMode then return self.fsMode:apply(peer, snap) end
    return
  end
  return self.online:apply(peer, snap)
end
function G:netEvent(peer, ev)
  if type(ev) == "table" and type(ev.t) == "string" and ev.t:sub(1, 3) == "fs_" then
    if ev.t == "fs_start" and self.state ~= "fs" then self:enterFs() end
    if self.fsMode then return self.fsMode:event(peer, ev) end
    return
  end
  return self.online:event(peer, ev)
end
function G:netPeerJoined(peer)
  if self.fsMode then self.fsMode:peerJoined(peer) end
end
function G:netPeerLeft(peer)
  if self.fsMode then self.fsMode:peerLeft(peer) end
  return self.online:left(peer)
end
function G:netAttached(session)
  self.session = session
  if self.fsMode and self.state == "fs" then self.fsMode:peerJoined(nil) end
  return self.online:attached(session)
end
function G:netDetached()
  self.session = nil
  return self.online:detached()
end

return G
