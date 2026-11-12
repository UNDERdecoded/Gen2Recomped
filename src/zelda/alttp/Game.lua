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
  -- round 6: the escape's progress (sword, keys, Zelda) and each room's
  -- memory (opened doors and chests)
  local Actors = require("src.zelda.alttp.Actors")
  self.progress = (sv and type(sv.progress) == "table") and sv.progress or Actors.newProgress()
  self.roomMemory = (sv and type(sv.rooms) == "table") and sv.rooms or {}
  self.actors = Actors.new(self)
  -- a new file starts with the cartridge's opening (startOpening)
  self.newGame = not sv
  -- round 13: the player's name (ENTER A NAME; the launcher shows it)
  self.playerName = type(self.opts.save) == "table" and type(self.opts.save.name) == "string" and self.opts.save.name or nil
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
-- the game starts after the title (and the front end): a new file plays the
-- opening, a saved one continues where the cartridge would
function G:startChosen()
  self.state = "play"
  if self.newGame and self.data.rooms then return self:startOpening() end
  if self:resumeIndoors() then return end
  self.music:playForScreen(self.area.parent, self.link.world)
end

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
  -- r20: the dash's screen shake (Ancilla1D_ScreenShake) counts down
  if (self.tremor or 0) > 0 then self.tremor = self.tremor - 1 end
  -- r21: death puffs, the dash dust, the drawn shake (Effects.lua)
  if not self.textBox then require("src.zelda.alttp.Effects").update(self) end
  require("src.zelda.alttp.AnimTiles").tick(self.frame)   -- r15: water, lava...
  self.music:update()
  -- round 14: the zoom actions (Zoom.lua) and the transitions' crossfade
  if self.zoomInput then self:zoomInput() end
  if self.updateCrossfade then self:updateCrossfade() end
  if self.state == "title" then
    self.titleT = self.titleT + 1
    if pressed(self.input, "up") or pressed(self.input, "down") then
      self.titleChoice = 3 - self.titleChoice
    end
    if pressed(self.input, "start") or pressed(self.input, "a") then
      -- round 13: the cartridge's front end (FrontEnd.lua: CHOOSE A FILE,
      -- ENTER A NAME, CHOOSE A GAME) when the cache has its screens
      local FrontEnd = require("src.zelda.alttp.FrontEnd")
      if FrontEnd.available(self.data) and not self.opts.noFrontEnd then
        self.front = FrontEnd.new(self)
        self.state = "front"
        return
      end
      if self.titleChoice == 2 then return self:enterFs() end
      return self:startChosen()
    end
    return
  end
  if self.state == "front" then
    local pick = self.front:update(self.input)
    if pick then
      self.playerName = self.front:playerName() or self.playerName
      self.front = nil
      if pick == "fs" then return self:enterFs() end
      return self:startChosen()
    end
    return
  end
  if self.state == "fs" then return self.fsMode:update(self.input) end
  if self.gameOver then return self:updateGameOver() end
  if self.textBox then return self:updateText() end
  -- round 8: the item menu (Menu.lua); the GBA opens it with SELECT
  -- (0x0806CE54: newly pressed keys & 4 -> module 0x0E submodule 1)
  if self.menu then return self:updateMenu() end
  if self.owmap then return self:updateOwMap() end
  local want = self:menuWanted()
  if want == "items" then return self:openMenu() end
  if want == "owmap" then return self:openOwMap() end
  if self.state == "room" then return self:updateRoom() end
  if self.state ~= "play" then return end
  if not self.musicStarted then
    self.musicStarted = true
    self.music:playForScreen(self.area.parent, self.link.world)
  end

  if self.scroll then return self:updateScroll() end
  if self.gate then return self:updateGate() end
  if self.exitDoor then
    local d = self.exitDoor
    d.t = d.t + 1
    self.cam = self:cameraFor(self.area)
    if d.t < d.frames then return end
    for k = 0, 3 do self:owSetMap16(d.x + (k % 2) * 16, d.y + math.floor(k / 2) * 16, 0xDBA + k) end
    self.exitDoor = nil
    return
  end
  if self.exitWalk and self.exitWalk > 0 then
    self.exitWalk = self.exitWalk - 1
    self.link.y = self.link.y + 1
    if self.exitWalk == 0 and self.exitWalkTail then
      self.link.y = self.link.y + self.exitWalkTail
      self.exitWalkTail = nil
    end
    self.link.steps = math.floor(self.exitWalk / 4) % 8 + 1
    if self.exitWalk == 0 then self.link.steps = 0 end
    self.cam = self:cameraFor(self.area)
    return
  end

  local inp = {
    up = held(self.input, "up"), down = held(self.input, "down"),
    left = held(self.input, "left"), right = held(self.input, "right"),
  }
  local ow = self.ow
  -- round 6: the sword, bush cutting and pits (Escape.lua)
  -- round 18: the GBA's action button (lift, talk, open) is R and its item
  -- button A (Items.lua: 0x0806995C, the messages' button glyphs)
  inp.a, inp.b = pressed(self.input, "r"), pressed(self.input, "b")
  inp.y = pressed(self.input, "a")
  self.owInp = inp   -- r23: the plaque reads this frame's buttons (Desert.lua)
  self:updateDrops()
  self:updateOwActors()
  if self.gameOver then return end
  if self:escapeOwFrame(inp) then
    if self.state == "play" then self.cam = self:followCam(self.area) end
    return
  end
  -- r20: the Pegasus Boots outdoors (Dash.lua): R with nothing to lift or
  -- talk to; the charge holds Link, the run steers him at speed 16
  local Dash = require("src.zelda.alttp.Dash")
  if inp.a and not self.dash and not self.carry and not self.textBox then Dash.start(self) end
  if self.dash and Dash.before(self, inp, held(self.input, "r")) then
    self.cam = self:followCam(self.area)
    return
  end
  if not self.dash and self.link.speedSetting == Dash.SPEED then self.link.speedSetting = 0 end
  -- round 16: the townsfolk block Link (Sprite_BehaveAsBarrier, Npc.lua)
  local Npc = require("src.zelda.alttp.Npc")
  local oa = self.owActors
  self.link:update(inp, function(world, x, y)
    if oa and Npc.solidAt(oa, x, y) then return 0x01 end
    return ow:attrAt(world, x, y)
  end)
  if self.dash then Dash.owAfter(self) end
  -- r21: the held sword outdoors keeps Link's facing (OwSword.lua)
  require("src.zelda.alttp.OwSword").after(self)
  -- doors: walking up into an overworld door (the cartridge's entrance
  -- tables, Interior.owEntrance)
  -- round 12: the cartridge (0x0808C044 / 0x0808BB88, SNES
  -- Overworld_UseEntrance) tests the 16x16 tile under (link_x, link_y + 7)
  -- each frame, with no facing rule for an ordinary door; Link stands one
  -- tile below a door's tile when its doorstep stops him, so the tile above
  -- (ahead 1) is tested too. OURS: that doorstep allowance (the cartridge's
  -- overworld collision there is not traced); before round 12 the test
  -- reached 3 tiles (48 px) ahead and fired before Link reached the door,
  -- and only while he faced up (a diagonal approach did not enter).
  -- round 17: the entrance tile is the one under (link_x + 16, link_y + 7)
  -- (the GBA's 0x0808BEE0 column rule, Interior.owEntranceAt; it fixes the
  -- Eastern Palace's door). STILL OURS: the test runs while Link walks up
  -- (the GBA runs it every frame -- here an exit's walk-out onto an opened
  -- big door's tiles would re-enter; the GBA exit positions there are not
  -- traced) and the doorstep allowance (ahead 1): house doors have
  -- attribute 0x02 under their door tile and our Link stops one tile short.
  if inp.up and self.data.rooms then
    local Interior = require("src.zelda.alttp.Interior")
    self.progress.gates = self.progress.gates or {}
    local e = Interior.owEntrance(self.data, self.ow, self.link.world, self.link.x, self.link.y, 1, self.progress.gates)
    if not e and self.link.facing == Link.UP then
      -- round 7: a closed big door opens when Link walks up into it
      local bx, by, kind = Interior.owBigDoorAhead(self.data, self.ow, self.link.world, self.link.x,
                                                   self.link.y, 3, not self.progress.escaped)
      if bx then
        self.gate = { t = 0, x = bx, y = by, kind = kind,
                      frames = kind == 0x169 and 9 or 33 }   -- SNES counter 24 / 0 -> 32
        return
      end
    end
    if e then
      -- the SNES Dungeon_LoadEntrance keeps Link's overworld spot for the
      -- way back (link_*_coord_exit); the cartridge's Link is in the door
      -- tile by then (its y + 7 on the door row), ours may stop short
      local door = Interior.doorOf(self.data, e)
      self.enteredFrom = { world = self.link.world, x = self.link.x,
                           y = door and (door.y + 8) or self.link.y }
      return self:enterRoom(e)
    end
  end

  -- leaving the area: scroll to the neighbour
  local s = self:screen()
  local a = self.ow:area(s)
  if a.parent ~= self.area.parent then
    -- round 14: seamless mode switches the area without stopping Link and
    -- the camera glides (Seamless.lua); "Cartridge transitions" scrolls
    if self:seamless() then self:seamlessArea(a) else self:beginScroll(a) end
  else
    self.cam = self:followCam(self.area)
  end
  self.online:update()
end

-- entrance: cartridge entrance number (RomMap.entrances)
function G:enterRoom(entrance)
  local Interior = require("src.zelda.alttp.Interior")
  self:dropCarry()
  self.interior = Interior.new(self.data, entrance, self.roomMemory)
  -- SNES Dungeon_LoadEntrance: link_is_on_lower_level = startingBg >> 4
  self.interior.lower = (self.interior.entrance.plane or 0) >= 16
  self.climb, self.swing, self.recoil, self.dash = nil, nil, nil, nil   -- r19: and the dash
  local sp = self.interior.spawn
  self.link.x, self.link.y, self.link.facing = sp[1], sp[2], sp[3]
  self.link.steps = 0
  self.link.doorway = 0
  self.state = "room"
  self.roomImages = nil
end

-- round 12: enter at a starting point (SNES which_starting_point 0..6,
-- idx.startPoints): game over with Zelda following, and a continue.
-- `entranceId` is kept for a later death in a palace (the SNES keeps the
-- entrance it last used); Link's house (0) is outside when no rooms exist.
function G:enterStart(i, entranceId)
  local sp = self.data.roomIdx and self.data.roomIdx.startPoints and self.data.roomIdx.startPoints[(i or 0) + 1]
  if not sp then return self:enterRoom(entranceId or 0) end
  local Interior = require("src.zelda.alttp.Interior")
  self:dropCarry()
  self.interior = Interior.new(self.data, sp, self.roomMemory)
  self.interior.entranceId = entranceId
  if not self.interior.outside and entranceId then
    local door = Interior.doorOf(self.data, entranceId)
    if door then self.interior.outside = { world = door.world, x = door.x, y = door.y + 20 } end
  end
  self.interior.lower = (sp.plane or 0) >= 16
  self.climb, self.swing, self.recoil, self.dash = nil, nil, nil, nil   -- r19: and the dash
  local s = self.interior.spawn
  self.link.x, self.link.y, self.link.facing = s[1], s[2], 2
  self.link.steps = 0
  self.link.doorway = 0
  self.state = "room"
  self.roomImages = nil
  self.startedAt = i
end

function G:updateRoom()
  local inside = self.interior
  local inp = {
    up = held(self.input, "up"), down = held(self.input, "down"),
    left = held(self.input, "left"), right = held(self.input, "right"),
  }
  if self.roomScroll then return self:updateRoomScroll() end
  self:updateDrops()
  local lk = self.link
  -- round 6: sword, chests, keys, stairs between levels, actors (Escape.lua)
  -- round 18: action R, item A (see update)
  inp.a, inp.b = pressed(self.input, "r"), pressed(self.input, "b")
  inp.y = pressed(self.input, "a")
  -- round 10: walking right (the shelf in the throne room is pushed so)
  self.pushRight = inp.right and not inp.left
  if self:escapeRoomFrame(inp) then return end
  -- r19: walking with the sword held out (Escape.lua): facing locked
  -- r20: at link_speed_setting 12 (set by Escape.lua), every frame
  local hs = self.swing and self.swing.held and self.swing
  if not hs and not self.dash and self.link.speedSetting == 12 then self.link.speedSetting = 0 end
  -- r19: the Pegasus Boots dash (Dash.lua): the charge holds Link, the run
  -- steers him the way he faces at its speed
  local Dash = require("src.zelda.alttp.Dash")
  if self.dash and Dash.before(self, inp, held(self.input, "r")) then return end
  if not self.dash and self.link.speedSetting == Dash.SPEED then self.link.speedSetting = 0 end
  local actors = self.actors
  -- round 11: indoor ledges (SNES TileDetect: 0x28 a vertical ledge, 0x2A /
  -- 0x2B horizontal ones). Walking into one with all three probe points on
  -- it for 20 frames (RunLedgeHopTimer) hops Link over it; on landing
  -- Dungeon_HandleLayerChange puts him on the lower level (unless the room's
  -- in-room stairs are of kind 2). OURS: the hop's arc and length (the first
  -- spot 8-64 px on where he fits on the lower level); kind 0's room + 16 is
  -- not ported (no such room on the escape route).
  local wasHop = lk.hop ~= nil
  if not lk.hop then self:indoorLedge(inp) end
  local hopNow = lk.hop ~= nil
  if lk.hop then
    lk:update(inp, function(_, x, y)
      return (inside:blocked(x, y) or actors:solidAt(x, y)) and 0x01 or 0x00
    end)
  else
    -- round 12: the cartridge's indoor walking, doorways and corner slides
    require("src.zelda.alttp.Doors").move(self, inp)
  end
  if hs and hs.facing then lk.facing = hs.facing end
  if self.dash then Dash.after(self) end
  if (wasHop or hopNow) and not lk.hop and self.ledgeHop then
    self.ledgeHop = nil
    if inside.stairKind ~= 2 then inside.lower = true end
    self.ledgeHops = (self.ledgeHops or 0) + 1
  end
  -- round 12: HandleDoorTransitions (Doors.lua): in a doorway the room
  -- changes at the cartridge's +28 / -18 / +21 / -8 page tests; the
  -- entrance attribute 0x8E under Link (x + 8, y + 20) on that move up or
  -- down is the exit to the overworld (Dungeon_StartInterRoomTrans_*)
  local Doors = require("src.zelda.alttp.Doors")
  local doorDir = (lk.doorway or 0) ~= 0 and Doors.doorTransition(self) or nil
  if (doorDir == "down" or doorDir == "up") and lk.tileBelow == 0x8E then
    lk.doorway = 0
    return self:leaveRoom()
  end
  -- stairs to another room (header travel destinations)
  local dir = (inp.up and "up") or (inp.down and "down") or nil
  local target, stairAt, toLower
  if dir then target, stairAt, toLower = inside:staircase(lk.x, lk.y, dir) end
  if target then
    self.stairAt = stairAt
    self.landLower = nil
    self.stairLower = toLower or false
    self:startRoomScroll(nil, false, target)
    inside.lower = toLower or false
    -- round 10: spiral stairs land on the layer of the destination's stair
    if self.landLower ~= nil then inside.lower = self.landLower; self.landLower = nil end
    return
  end
  if doorDir then
    local x0, y0, x1, y1 = inside:area()
    local leaves = (doorDir == "up" and y0 == 0) or (doorDir == "down" and y1 == 512)
                   or (doorDir == "left" and x0 == 0) or (doorDir == "right" and x1 == 512)
    local sh = Doors.START_SHIFT[doorDir]
    lk.x, lk.y = lk.x + sh[1], lk.y + sh[2]
    self.doorScroll = true
    self:startRoomScroll(doorDir, leaves)
    self.doorScroll = nil
    return
  end
  if (lk.doorway or 0) ~= 0 then return end
  -- round 12: Dungeon_TryScreenEdgeTransition (not in a doorway): an open
  -- room edge is crossed at y & 0x1FF < 4 / >= 476, x < 8 / >= 489 while
  -- Link moves on that axis; the landing is the doorway one (Doors.landing)
  local x0, y0, x1, y1 = inside:area()
  local edgeDir
  if (lk.velY or 0) ~= 0 then
    if lk.y < 4 and y0 == 0 then edgeDir = "up" elseif lk.y >= 476 and y1 == 512 then edgeDir = "down" end
  end
  if not edgeDir and (lk.velX or 0) ~= 0 then
    if lk.x < 8 and x0 == 0 then edgeDir = "left" elseif lk.x >= 489 and x1 == 512 then edgeDir = "right" end
  end
  if edgeDir then
    self.doorScroll = true
    self:startRoomScroll(edgeDir, true)
    self.doorScroll = nil
    return
  end
  -- walking out of the camera area inside the room: a quadrant transition
  local edge, leaves = inside:edge(lk.x, lk.y)
  if edge and not leaves then
    self.doorScroll = true
    self:startRoomScroll(edge, false)
    self.doorScroll = nil
  end
end

-- Round 11: the indoor ledge check (see updateRoom). Probe points as
-- Link.PROBES at the next pixel in the walking direction, on Link's level.
function G:indoorLedge(inp)
  local inside, lk = self.interior, self.link
  local dx = (inp.right and 1 or 0) - (inp.left and 1 or 0)
  local dy = (inp.down and 1 or 0) - (inp.up and 1 or 0)
  local dir, want
  if dy ~= 0 and dx == 0 then dir, want = (dy < 0) and Link.UP or Link.DOWN, { [0x28] = true }
  elseif dx ~= 0 and dy == 0 then dir, want = (dx < 0) and Link.LEFT or Link.RIGHT, { [0x2A] = true, [0x2B] = true }
  end
  if not dir then self.ledgeTimer = nil return end
  local all = true
  for _, p in ipairs(Link.PROBES[dir]) do
    if not want[inside:attrAt(lk.x + dx + p[1], lk.y + dy + p[2]) or -1] then all = false break end
  end
  if not all then self.ledgeTimer = nil return end
  self.ledgeTimer = (self.ledgeTimer or 0) + 1
  if self.ledgeTimer < 20 then return end
  self.ledgeTimer = nil
  -- the landing: the first spot past the ledge where Link fits on the level
  -- he lands on (the lower one unless the room's stairs are of kind 2)
  local saved = inside.lower
  inside.lower = (inside.stairKind ~= 2) or saved
  local dist
  for d = 8, 64, 4 do
    local nx, ny = lk.x + dx * d, lk.y + dy * d
    local fits = true
    for _, p in ipairs({ { 0, 8 }, { 15, 8 }, { 0, 23 }, { 15, 23 }, { 8, 16 } }) do
      if inside:blocked(nx + p[1], ny + p[2]) then fits = false break end
    end
    if fits then dist = d break end
  end
  inside.lower = saved
  if not dist then return end
  local frames = math.max(16, dist)
  lk.hop = { dir = dir, vx = dx * dist / frames, vy = dy * dist / frames, t = 0, frames = frames,
             fx = lk.x, fy = lk.y }
  lk.steps = 0
  self.ledgeHop = true
end

-- leave the room to the overworld, where the cartridge's exit table (or the
-- cached entry spot) puts Link (Interior.exitFor), facing down
function G:leaveRoom()
  local Interior = require("src.zelda.alttp.Interior")
  local inside = self.interior
  local out = Interior.exitFor(self.data, inside.room, self.enteredFrom) or inside.outside
  if not out then return end
  self:dropCarry()
  self.link.world, self.link.x, self.link.y, self.link.facing = out.world, out.x, out.y, 2
  self.state = "play"
  self.interior, self.roomImages, self.roomScroll = nil, nil, nil
  self:syncKeys()
  self.area = self.ow:area(self:screen())
  self.cam = self:cameraFor(self.area)
  self.lastExit = out
  -- the exit spot is inside the doorway (under the roof layer); Link then
  -- walks down out of it. Round 12, the SNES OpenSpotlight_Next2 /
  -- Module09_0A_WalkFromExiting_FacingDown: 16 frames of 1 px, then 3 px
  -- more; an exit with a fancy door (kExitData_FancyDoor, the castle's and
  -- the sanctuary's big doors) first opens that door (Module09_09: the
  -- door counter from 0x18 for a palace door, else 0, to 32, one map16
  -- update every 8 frames) and the walk is 36 frames. OURS: the door's
  -- middle animation step is not drawn (as on the way in, updateGate).
  self.exitWalk = 16
  self.exitWalkTail = 3
  local fd = out.fancyDoor or 0
  if fd ~= 0 and out.screen then
    local Ow, bit = require("src.zelda.alttp.Overworld"), require("bit")
    local ox, oy = Ow.screenOrigin(out.screen)
    local pos = bit.band(fd, 0x7FFF)
    self.exitDoor = { x = ox + bit.rshift(bit.band(pos, 0x7F), 1) * 16, y = oy + bit.rshift(pos, 7) * 16,
                      t = 0, frames = bit.band(fd, 0x8000) ~= 0 and 9 or 33 }
    self.exitWalk = 36
  end
end

-- A transition: the camera pans to the next quadrant or room while Link
-- walks 16 px on (the SNES HandleEdgeTransitionMovement* steps), 1 px a
-- frame; stairs load the destination room in place (no pan).
function G:startRoomScroll(dir, leavesRoom, stairRoom)
  local inside = self.interior
  local lk = self.link
  -- r22: a room change (Dungeon_ResetSprites -> Sprite_DisableAll, and
  -- link_state_bits = 0) ends a lift / carry / throw: the pot is gone
  if (stairRoom or leavesRoom) and self.dropCarry then self:dropCarry() end
  local fromX, fromY = inside:camera(lk.x, lk.y, G.W, G.H)
  if stairRoom then
    lk.doorway = 0   -- round 12: stairs end a doorway (Doors.lua)
    inside:loadRoom(stairRoom, inside.main)
    self.roomImages = nil
    inside.qx, inside.qy = math.floor((lk.x + 8) / 256), math.floor((lk.y + 12) / 256)
    -- round 9: spiral stairs (attributes 0x5E/0x5F) land Link beside the
    -- destination's own spiral stair, walking out of it facing down (SNES
    -- RepositionLinkAfterSpiralStairs + SpiralStairs_FindLandingSpot);
    -- straight stairs step off the stair tile in the walking direction
    local land = (self.stairAt == 0x5E or self.stairAt == 0x5F) and inside:spiralLanding(lk.x, self.stairLower)
    -- round 9: straight stairs 0x38 (up) / 0x39 (down) are an inter-room
    -- transition (SNES Dungeon_StartInterRoomTrans_Up/Down): Link keeps
    -- walking through and comes out past the destination's own stairs
    -- (0x39 at the bottom of the room above, 0x38 at the top of the room below)
    if self.stairAt == 0x38 or self.stairAt == 0x39 then
      land = inside:straightLanding(lk.x, self.stairAt == 0x38 and 0x39 or 0x38)
    end
    if land then
      if land.lower ~= nil then self.landLower = land.lower end
      lk.x, lk.y, lk.facing = land[1], land[2], land[3] or 2
      inside.qx, inside.qy = math.floor((lk.x + 8) / 256), math.floor((lk.y + 12) / 256)
    else
      lk.y = lk.y + ((lk.facing == 0) and -24 or 24)
    end
    self.stairAt = nil
    self.roomChanges = (self.roomChanges or 0) + 1
    return
  end
  local old = self.roomImages
  local oldPr = require("src.zelda.alttp.Layers").roomBg(inside.hdr)   -- round 14
  local oldRoom = inside.room
  -- round 11: a layer-toggle doorway under Link (attributes 0x90-0x9F /
  -- 0xA8-0xAF, SNES room_transitioning_flags & 1) swaps his level as the
  -- room changes (Dungeon_StartInterRoomTrans_*)
  local flip = leavesRoom and inside:layerToggleAt(lk.x, lk.y, dir)
  local dx, dy = inside:cross(dir, leavesRoom, lk.x, lk.y)
  if flip then inside.lower = not inside.lower; self.layerToggles = (self.layerToggles or 0) + 1 end
  -- a short log of transitions (tests and the route bot read it)
  self.roomLog = self.roomLog or {}
  if #self.roomLog >= 64 then table.remove(self.roomLog, 1) end
  self.roomLog[#self.roomLog + 1] = { dir = dir, room = inside.room, leaves = leavesRoom }
  lk.x, lk.y = lk.x + dx, lk.y + dy
  if leavesRoom then
    -- round 10: a trapdoor on the way in starts up (Interior:entryShutters);
    -- Escape closes it once Link is through
    if inside.entryShutters then inside:entryShutters(lk.x, lk.y, dir) end
    self.roomImages = nil
    self.roomChanges = (self.roomChanges or 0) + 1
  end
  local s = require("src.zelda.alttp.Interior").STEP[dir]
  local tx, ty = inside:camera(lk.x + s[1] * 16, lk.y + s[2] * 16, G.W, G.H)
  self.roomScroll = { fromX = fromX + dx, fromY = fromY + dy, toX = tx, toY = ty, t = 0,
                      frames = math.max(16, math.floor(math.max(math.abs(tx - fromX - dx), math.abs(ty - fromY - dy)) / 4)),
                      sx = s[1], sy = s[2], walked = 0,
                      old = leavesRoom and old or nil, oldX = dx, oldY = dy, oldPr = oldPr,
                      oldRoom = leavesRoom and oldRoom or nil }
  -- round 12: through a doorway the cartridge lands Link at kStaircaseTab2's
  -- spot of the new page (Doors.landing) and walks him there 2 px a frame
  if self.doorScroll then
    local axis, from, to, kind = require("src.zelda.alttp.Doors").landing(self, dir)
    self.roomScroll.land = { axis = axis, from = from, to = to, kind = kind }
    self.roomScroll.walked = 16
  end
end

function G:updateRoomScroll()
  local sc = self.roomScroll
  sc.t = sc.t + 1
  local frac = sc.t / sc.frames
  -- Link walks 16 px on over the first 16 frames of the pan
  if sc.walked < 16 then
    self.link.x, self.link.y = self.link.x + sc.sx, self.link.y + sc.sy
    sc.walked = sc.walked + 1
    self.link.steps = (self.link.steps or 0) % 8 + 1
  end
  local ld = sc.land
  if ld and sc.t >= sc.frames then
    -- SubtileTransitionCalculateLanding + DungeonTransition_MoveLinkOutDoor
    local lk = self.link
    if not ld.placed then ld.placed = true; lk[ld.axis] = ld.from end
    if lk[ld.axis] ~= ld.to then
      local st = ld.to > lk[ld.axis] and 2 or -2
      lk[ld.axis] = lk[ld.axis] + st
      if (st > 0 and lk[ld.axis] > ld.to) or (st < 0 and lk[ld.axis] < ld.to) then lk[ld.axis] = ld.to end
      lk.steps = (lk.steps or 0) % 8 + 1
      return frac
    end
    -- Dungeon_IntraRoomTrans_State5: landing kinds 2 and 4 end the doorway
    if ld.kind == 2 or ld.kind == 4 then lk.doorway = 0 end
    lk.steps = 0
    self.roomScroll = nil
    return frac
  end
  if sc.t >= sc.frames then self.roomScroll = nil end
  return frac
end

function G:drawRoom()
  local inside = self.interior
  if not self.roomImages then
    local View = require("src.zelda.alttp.View")
    local pal = inside:palette()
    self.roomImages = {}
    -- BG2 is the room, BG1 the frame over a transparent fill (drawn above);
    -- the third layer (loaded to 0x0201A000) is the lower floor seen through
    -- BG2 in two-level rooms, drawn first over the backdrop
    local layers = inside.bg3 and { "bg3", "bg2", "bg1" } or { "bg2", "bg1" }
    for _, layer in ipairs(layers) do
      local img = love.image.newImageData(512, 512)
      -- round 14: every map transparent; the backdrop is filled under them
      -- (Layers.lua: the lower map is not always the bottom layer)
      local cells = {}
      View.fill(img, 512, 512, inside:decodeLayer(layer, cells), pal, nil)
      local im = love.graphics.newImage(img)
      im:setFilter("nearest", "nearest")
      self.roomImages[layer] = im
      -- r15: animated tiles (AnimTiles.lua)
      local AT = require("src.zelda.alttp.AnimTiles")
      AT.register(im, img, cells, AT.dungFrames(self.data, inside.main), AT.DUNG_BASE, pal, nil)
    end
    self.roomImages.backdrop = pal[0]
  end
  local cx, cy = inside:camera(self.link.x, self.link.y, G.W, G.H)
  local sc = self.roomScroll
  if sc then
    local p = math.min(1, sc.t / sc.frames)
    cx = math.floor(sc.fromX + (sc.toX - sc.fromX) * p + 0.5)
    cy = math.floor(sc.fromY + (sc.toY - sc.fromY) * p + 0.5)
  end
  -- round 14: seamless mode's camera glide (Seamless.lua) and the room
  -- being left, still drawn while the camera passes it
  if self.roomGlide then
    cx, cy = self.roomGlide.x, self.roomGlide.y
    if self.roomGlide.old then sc = self.roomGlide end
  end
  self.roomCam = { x = cx, y = cy }
  -- round 8: the telepathy shows with BG1/BG2 off (DISPCNT & 0xF9FF, the
  -- cartridge's telepathy screen setup 0x081271C8): backdrop, sprites, text
  local bgOff = self.opening == "telepathy" and self.textBox
  -- round 14: the GBA's BG / OBJ priorities (Layers.lua): each priority's
  -- maps, then its sprites -- Link passes under the high-priority map (door
  -- frames). Round 7's dark rooms darken each BG layer (sprites stay lit).
  local Layers = require("src.zelda.alttp.Layers")
  local vx, vy = cx, cy
  if self.viewOrigin then vx, vy = self:viewOrigin(cx, cy) end
  -- r21: the dash's screen shake moves the BGs and the sprites (Effects.lua)
  do local sx, sy = require("src.zelda.alttp.Effects").shakeOffset(self); vx, vy = vx + sx, vy + sy end
  local rooms = {}
  if self.roomNeighbours then self:roomNeighbours(rooms, vx, vy) end
  if sc and sc.old then
    rooms[#rooms + 1] = { im = sc.old, x = sc.oldX - vx, y = sc.oldY - vy, pr = sc.oldPr or Layers.roomBg(nil) }
  end
  rooms[#rooms + 1] = { im = self.roomImages, x = -vx, y = -vy, pr = Layers.roomBg(inside.hdr) }
  local saved = self.cam
  self.cam = { x = vx, y = vy }
  self:drawRoomField(rooms, function(p) self:drawRoomSprites(p, vx, vy) end, bgOff)
  if self.drawCrossfade then self:drawCrossfade() end
  self.cam = saved
  if not self.zoomOverlay then self:drawHud() end
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

-- bug round: the pose row and step for our Link (Weapon.lua): the sword
-- swing, lifting / carrying / throwing (Carry.lua), else walking
function G:linkPose()
  local lk = self.link
  -- r19 (LinkOam_Main): the sword held out (button_b_frames 9) is row 2 at
  -- the walking step, the jerks (10-12) row 3 at frames - 10; an item in
  -- hand is kPlayerOam_Tab2[its bit] at player_handler_timer: the bow
  -- (link_item_in_hand 0x10) row 7 at its step
  -- r20: the spin attack is row 0x0F at state_for_spin_attack
  if self.swing and self.swing.spin then return 0x0F, self.swing.gfx or 0 end
  if self.swing and self.swing.held then
    if self.swing.step == 9 then return 2, lk.steps or 0 end
    return 3, self.swing.step - 10
  end
  if self.swing then return 0x27, math.min(8, self.swing.step) end
  if self.bowUse then return 7, math.min(2, self.bowUse.step or 0) end
  local c = self.carry
  if c then
    if c.phase == "lift" then return 0x10, c.poseStep or 0 end
    if c.phase == "throw" then return 0x0E, c.poseStep or 0 end
    return 0x0D, lk.steps or 0
  end
  return 0, lk.steps or 0
end

-- round 9: the sprite graphics for shadows (the room's, or the overworld's)
function G:shadowSprites()
  if self.state == "room" and self.interior then return self.spriteGfx and self:spriteGfx() end
  local Sprites = require("src.zelda.alttp.Sprites")
  if not Sprites.available(self.data) then return nil end
  self.owSprites = self.owSprites or Sprites.new(self.data)
  self.owSprites:setOverworld(self.link.world == "dw", self:owSpriteSet())
  return self.owSprites
end

function G:drawLink(lk, tint)
  local x = (lk.x - self.cam.x)
  local y = (lk.y - self.cam.y) - (lk.z or 0)
  -- bug round: our own Link with his sword and shield (the cartridge's
  -- LinkOam tables, Weapon.lua)
  if lk == self.link and not tint then
    local Weapon = require("src.zelda.alttp.Weapon")
    if Weapon.available(self.data) then
      self.weapon = self.weapon or Weapon.new(self.data)
      -- round 9: Link's shadow under him (LinkOam shadow, Sprites.drawLinkShadow)
      local spr = self:shadowSprites()
      if spr then spr:drawLinkShadow(x, (lk.y - self.cam.y), lk.facing) end
      local yt, rt = self:linkPose()
      local has = self.progress and self.progress.sword
      local list = self.weapon:pieces(lk.facing, yt, rt, { sword = has and self.swing ~= nil, shield = has,
                                                           item = self.bowUse ~= nil or self.toolUse ~= nil or self.hookUse ~= nil })   -- r26a: Tools.lua
      for _, pc in ipairs(list) do
        if pc.kind == "body" then
          local p = pc.part
          local im = self.view:linkCell(p.cell, self.linkPal, self.linkPalKey or "green")
          love.graphics.draw(im, x + p.dx + (p.hflip and 16 or 0), y + p.dy + (p.vflip and 16 or 0), 0,
                             p.hflip and -1 or 1, p.vflip and -1 or 1)
        elseif pc.kind == "item" then
          -- r21: the bow's own picture (Weapon.drawItem, the item strip)
          self.weapon:drawItem(pc, x, y, spr)
        else
          self.weapon:drawPiece(pc, x, y, self.swordType or 1, self.shieldType or 1)   -- r26a: Gear.lua
        end
      end
      if self.carry then self:drawCarried() end
      self:drawThrown()
      return
    end
  end
  local parts = Link.pose(self.data, lk.facing or lk.f, lk.steps or lk.s or 0)
  if tint then love.graphics.setColor(tint) end
  for i = #parts, 1, -1 do
    local p = parts[i]
    local im = self.view:linkCell(p.cell, self.linkPal, self.linkPalKey or "green")
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
  if self.state == "front" and self.front then return self.front:draw() end
  if self.state == "fs" then return self.fsMode:draw() end
  if self.owmap then return self.owmap:draw() end
  if self.state == "room" then return self:drawRoom() end
  -- round 14: the zoomed view around the cartridge's camera (Zoom.lua);
  -- at the default zoom this is the cartridge's own 240 x 160
  local camSaved = self.cam
  self.coreCam = camSaved
  local vx, vy = self:viewOrigin(camSaved.x, camSaved.y)
  -- r21: the dash's screen shake (Effects.lua); Link is drawn without it
  local Effects = require("src.zelda.alttp.Effects")
  local shx, shy = Effects.shakeOffset(self)
  vx, vy = vx + shx, vy + shy
  self.cam = { x = vx, y = vy }
  local vis = self:viewScreens()
  for _, v in ipairs(vis) do
    love.graphics.draw(self.view:screen(v.s).bg2, v.x, v.y)
  end
  self.online:drawPeers()
  if (self.drops and #self.drops > 0) or (self.debris and #self.debris > 0) or self.owActors
     or (self.anc and #self.anc > 0) then
    local Sprites = require("src.zelda.alttp.Sprites")
    if Sprites.available(self.data) then
      self.owSprites = self.owSprites or Sprites.new(self.data)
      self.owSprites:setOverworld(self.link.world == "dw", self:owSpriteSet())
      self:drawOwActors(self.cam.x, self.cam.y, self.owSprites)
      self:drawDrops(self.cam.x, self.cam.y, self.owSprites)
    end
  end
  -- round 14: Link is OBJ priority 2 under the overlay (GBA BG1, priority
  -- 1: canopies, roofs, door tops), 1 above it while a ledge hop is in the
  -- air (Layers.lua)
  local over = self:linkObjPrio() == 1
  Effects.drawDust(self, self:shadowSprites(), self.cam.x, self.cam.y)
  if not over then
    love.graphics.push(); love.graphics.translate(shx, shy)
    self:drawLink(self.link)
    self:drawSword(self.cam.x, self.cam.y)
    love.graphics.pop()
  end
  for _, v in ipairs(vis) do
    love.graphics.draw(self.view:screen(v.s).bg1, v.x, v.y)
  end
  if over then
    love.graphics.push(); love.graphics.translate(shx, shy)
    self:drawLink(self.link)
    self:drawSword(self.cam.x, self.cam.y)
    love.graphics.pop()
  end
  if self.drawRain then self:drawRain() end
  if self.drawCrossfade then self:drawCrossfade() end
  self.cam = camSaved
  if not self.zoomOverlay then self:drawHud() end
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
  -- r22: up / down move a choice cursor (Text.lua)
  box:update(pressed(self.input, "a") or pressed(self.input, "b"), pressed(self.input, "up"), pressed(self.input, "down"))
  if box.done then
    self.textBox = nil
    self.lastChoice = box.choice   -- r22: choice_in_multiselect_box
    if self.onTextDone then local f = self.onTextDone; self.onTextDone = nil; f(self) end
  end
end

function G:drawText()
  local box = self.textBox
  if not (box and self.view) then return end
  local Hud = require("src.zelda.alttp.Hud")
  self.hudPal = self.hudPal or Hud.palette(self.data, 0)
  local wx, wy = box:window()
  if box.border then
    -- round 8: the window's inside is clear, as on the cartridge: its centre
    -- word (0x107F) is the blank tile, the glyph tiles are cleared to colour
    -- 0 (0x08129BC4) and the outlined letters carry their own dark edge; the
    -- text routines (0x08127E00-0x08129FFF) set no blend or window register
    love.graphics.draw(self.view:hudImage(box:borderWords(), 24, 8, self.hudPal), wx, wy)
  end
  love.graphics.draw(self.view:textImage(box, self.hudPal), wx + 8, wy + 8)
end

-- the item menu (round 8): opened from normal play, not mid-transition
function G:menuWanted()
  local sel = pressed(self.input, "select")
  -- the overworld map: L outside (0x0806CE90 checks newly pressed & 0x200)
  local l = self.state == "play" and pressed(self.input, "l")
  if not (sel or l) then return false end
  if self.state ~= "play" and self.state ~= "room" then return false end
  if self.scroll or self.gate or self.roomScroll or self.opening then return false end
  if self.exitDoor or (self.exitWalk and self.exitWalk > 0) then return false end
  if sel and require("src.zelda.alttp.Menu").available(self.data) then return "items" end
  if l and require("src.zelda.alttp.OwMap").available(self.data) then return "owmap" end
  return false
end

function G:openOwMap()
  self.owmap = require("src.zelda.alttp.OwMap").new(self)
  self.owmap:open()
end

function G:updateOwMap()
  self.owmap:update(self.input)
  if self.owmap.done then self.owmap = nil end
end

function G:openMenu()
  self.menu = require("src.zelda.alttp.Menu").new(self)
  self.menu:open()
end

function G:updateMenu()
  self.menu:update(self.input)
  if self.menu.done then self.menu = nil end
end

-- the cartridge HUD (Hud.lua) over the play field
function G:drawHud()
  if not (self.data.ui and self.view) then return end
  local Hud = require("src.zelda.alttp.Hud")
  self.hudPal = self.hudPal or Hud.palette(self.data, 0)
  -- round 8: the item menu replaces the HUD layer while it is up
  if self.menu and self.menu:draw(self.view, self.hudPal) then return end
  -- r19: the item box shows the chosen item (Hud.itemIcon)
  local st = setmetatable({ itemIcon = Hud.itemIcon(self) }, { __index = self.stats })
  local im = self.view:hudImage(Hud.words(self.data.ui, st), Hud.COLS, Hud.ROWS, self.hudPal)
  love.graphics.draw(im, -Hud.SCROLL_X, 0)
  self:drawText()
  if self.gameOver and self.drawGameOver then self:drawGameOver() end
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
  if require("src.zelda.alttp.FrontEnd").available(self.data) then return end
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
  -- inside a room, save where its exit puts Link (rooms are not restored yet)
  local out = self.interior and (require("src.zelda.alttp.Interior").exitFor(self.data,
    self.interior.room, self.enteredFrom) or self.interior.outside)
  -- round 12: where the cartridge continues a saved file: SAVE AND QUIT
  -- clears death_var4/5 (SNES Death_Func, messaging.c), so the file load
  -- goes to which_starting_point wherever Link saved (the uncle's passage,
  -- the prison or the throne room with Zelda, the sanctuary after the
  -- escape); only CONTINUE after a death in a palace uses its entrance
  -- (updateGameOver). The spot above stays for saves without one.
  local resume
  if self.progress.startPoint then
    resume = { start = self.progress.startPoint }
  end
  return { version = 1, game = "alttp", name = self.playerName,
           alttp = { world = out and out.world or self.link.world,
                     x = out and out.x or self.link.x, y = out and out.y or self.link.y,
                     facing = out and 2 or self.link.facing, stats = self.stats,
                     progress = self.progress, rooms = self.roomMemory, resume = resume } }
end

-- round 12: a continue goes back indoors as the cartridge does (save()'s
-- `resume`). OURS: the post-escape choice of Link's house or the sanctuary
-- (the SNES location menu, kLocationMenuStartPos) is not shown; the last
-- starting point is used.
function G:resumeIndoors()
  local sv = type(self.opts.save) == "table" and self.opts.save.alttp
  local r = sv and type(sv.resume) == "table" and sv.resume
  if not (r and self.data.rooms and self.data.roomIdx) then return false end
  if r.start and self.data.roomIdx.startPoints then
    self:enterStart(r.start, r.entrance)
  elseif r.entrance then
    self:enterRoom(r.entrance)
  else
    return false
  end
  self.music:playForScreen(self.area.parent, self.link.world)
  return true
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

require("src.zelda.alttp.Escape").install(G)
require("src.zelda.alttp.Carry").install(G)   -- bug round: lift / carry / throw
require("src.zelda.alttp.Drops").install(G)   -- round 9: what cut / lifted things drop
require("src.zelda.alttp.OwActors").install(G) -- round 10: enemies a secret holds, outdoors
require("src.zelda.alttp.Npc").install(G)      -- round 16: people (Kakariko, Sahasrahla)
require("src.zelda.alttp.Layers").install(G)   -- round 14: BG / OBJ priority
require("src.zelda.alttp.Zoom").install(G)     -- round 14: zoom and the whole map
require("src.zelda.alttp.Seamless").install(G) -- round 14: seamless transitions
require("src.zelda.alttp.Items").install(G)    -- round 18: item button, bow, bombs, lamp, keys
require("src.zelda.alttp.Desert").install(G)   -- r23: the desert plaque, the prayer, the statues
require("src.zelda.alttp.DesertPalace").install(G)   -- r24: Debirando, wall cannons, Lanmolas, the moving wall
require("src.zelda.alttp.OwEnemies").install(G)   -- r25: the outdoor enemies (area lists, proximity loading)
require("src.zelda.alttp.BigRock").install(G)     -- r25: the 32x32 rocks, the gloves by attribute
require("src.zelda.alttp.OldMan").install(G)      -- r25: the old man on the mountain (follower 4, the mirror)
require("src.zelda.alttp.Gear").install(G)        -- r26a: sword / shield / mail levels, the item receipts
require("src.zelda.alttp.DarkWorld").install(G)   -- r26a: warp tiles, the mirror, the portal, the bunny
require("src.zelda.alttp.Swim").install(G)        -- r26a: deep water, the flippers
require("src.zelda.alttp.Tools").install(G)       -- r26a: rods, hammer, shovel, boomerang, hookshot
require("src.zelda.alttp.OwEvents").install(G)    -- r26a: medallions, tablets, the sealed entrances
require("src.zelda.alttp.Cape").install(G)        -- r26a: the Magic Cape, the bottles
require("src.zelda.alttp.Dungeons26").install(G)  -- r26b: pegs, pits, Hera and the later palaces' sprites
require("src.zelda.alttp.BossHooks").install(G)   -- r26a: the items on the later palaces' bosses
require("src.zelda.alttp.ExtractA27").install(G)  -- r27a: grove, fairy, smiths, flute, canes, people, enemies, map, sound

return G
