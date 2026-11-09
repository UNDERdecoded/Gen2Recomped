-- The Minish Cap runtime: title -> file select -> the field.
--
-- newGame(opts) (init.lua) returns one of these.  The foundation's
-- ZeldaRuntime ticks update() at the GBA frame rate and draws into the
-- 240x160 canvas; input comes through opts.input (isDown / wasPressed with
-- the lower-case GBA button names).

local Assets = require("src.zelda.tmc.Assets")
local Field = require("src.zelda.tmc.Field")
local Script = require("src.zelda.tmc.Script")
local Audio = require("src.zelda.tmc.Audio")
local Net = require("src.zelda.tmc.Net")
local RoomCode = require("src.zelda.tmc.RoomCode")

local Game = {}
Game.__index = Game

local W, H = 240, 160

-- sound / song ids (include/sound.h)
Game.BGM_TITLE_SCREEN = 0x03
Game.BGM_FILE_SELECT = 0x07
Game.SFX_MENU = 0x6A

-- area names for messages and the HUD (our own labels for the areas'
-- enum names in include/area.h; the cartridge's own names are map art)
local AREA_NAMES = {
  [0x00] = "Minish Woods", [0x01] = "Minish Village", [0x02] = "Hyrule Town",
  [0x03] = "Hyrule Field", [0x04] = "Castor Wilds", [0x05] = "Wind Ruins",
  [0x06] = "Mt. Crenel", [0x07] = "Castle Garden", [0x08] = "Cloud Tops",
  [0x09] = "Royal Valley", [0x0A] = "Veil Falls", [0x0B] = "Lake Hylia",
  [0x0C] = "Lake Woods Cave", [0x0D] = "Beanstalks", [0x15] = "Hyrule Town",
  [0x22] = "Hyrule Town", [0x48] = "Deepwood Shrine", [0x50] = "Cave of Flames",
  [0x58] = "Fortress of Winds", [0x60] = "Temple of Droplets", [0x70] = "Palace of Winds",
  [0x80] = "Hyrule Castle", [0x88] = "Dark Hyrule Castle",
}

function Game.new(opts)
  opts = opts or {}
  local self = setmetatable({ opts = opts, frame = 0, logLines = {} }, Game)
  self.input = Game.wrapInput(opts.input)
  self.assets = Assets.new(opts.root or opts.cache)
  local m = self.assets.manifest
  local blob = self.assets.store:read("scripts.bin")
  self.scriptMem = Script.memory(blob, m.scripts and m.scripts.base or 0)
  self.roomCode = RoomCode.table()
  -- the cartridge's own font (Font.lua); LÖVE's as a fallback
  local okCart, cart = pcall(require("src.zelda.tmc.Font").load, self.assets.store)
  local okFont, font = pcall(love.graphics.newFont, 8)
  self.font = (okCart and cart) or (okFont and font) or love.graphics.getFont()
  if self.font.setFilter then self.font:setFilter("nearest", "nearest") end
  if not opts.noAudio then
    local ok, audio = pcall(Audio.new, self.assets.store, m, {
      musicVol = opts.options and opts.options.musicVol, sfxVol = opts.options and opts.options.sfxVol })
    if ok then self.audio = audio else self:log("audio: " .. tostring(audio)) end
  end
  self.saveData = type(opts.save) == "table" and opts.save or nil
  if opts.online then self:netAttached(opts.online) end
  if opts.skipTitle then
    self:startGame(self.saveData or Game.newSave(opts.name))
  else
    self.state = "title"
    if self.audio then self.audio:playBgm(Game.BGM_TITLE_SCREEN) end
  end
  return self
end

function Game:log(s)
  self.logLines[#self.logLines + 1] = s
  if #self.logLines > 50 then table.remove(self.logLines, 1) end
  if os.getenv and os.getenv("TMC_DEBUG") then print("[tmc] " .. s) end
end

-- the input facade: isDown/wasPressed from the runtime, or a test table
function Game.wrapInput(src)
  src = src or {}
  return {
    down = function(b) return src.isDown and src.isDown(b) or false end,
    pressed = function(b) return src.wasPressed and src.wasPressed(b) or false end,
  }
end

-- FinalizeSave (src/playerUtils.c): a fresh file starts in Link's room in
-- Hyrule Town (area $22 room $15) at (0x90, 0x38) with three hearts
function Game.newSave(name)
  return {
    name = name or "Link",
    progress = 1,
    stats = { health = 24, maxHealth = 24, rupees = 0, maxRupees = 100, shells = 0 },
    items = {},
    flags = { global = {} },
    kinstones = { bag = {}, fused = {} },
    status = { area = 0x22, room = 0x15, x = 0x90, y = 0x38, facing = 0, layer = 1 },
    playTime = 0,
  }
end

function Game:areaName(area) return AREA_NAMES[area] end

-- back to the title screen (game over: save and quit)
function Game:toTitle()
  self.field = nil
  self.state = "title"
  if self.audio then self.audio:playBgm(Game.BGM_TITLE_SCREEN) end
end

function Game:startGame(save)
  save.flags = save.flags or { global = {} }
  save.flags.global = save.flags.global or {}
  save.items = save.items or {}
  save.stats = save.stats or Game.newSave().stats
  self.saveData = save
  self.state = "field"
  self.field = Field.new(self, save)
end

function Game:onRoomChanged(area, room)
  if self.saveData then
    self.saveData.summary = { line = (AREA_NAMES[area] or ("Area " .. area)) }
  end
end

-- ---------------------------------------------------------------------------
function Game:update(dt)
  self.frame = self.frame + 1
  if self.audio then self.audio:update() end
  local inp = self.input
  if self.state == "title" then
    if inp.pressed("start") or inp.pressed("a") then
      self.state = "files"
      self.cursor = self.saveData and 1 or 2
      if self.audio then self.audio:playBgm(Game.BGM_FILE_SELECT) end
    end
  elseif self.state == "files" then
    if inp.pressed("up") then self.cursor = 1 end
    if inp.pressed("down") then self.cursor = 2 end
    if not self.saveData then self.cursor = 2 end
    if inp.pressed("a") or inp.pressed("start") then
      if self.audio then self.audio:playSfx(Game.SFX_MENU) end
      if self.cursor == 1 and self.saveData then self:startGame(self.saveData)
      else self:startGame(Game.newSave(self.opts.name)) end
    elseif inp.pressed("b") then
      self.state = "title"
    end
  elseif self.state == "field" then
    if self.saveData then self.saveData.playTime = (self.saveData.playTime or 0) + (dt or 1 / 60) end
    if self.net and inp.pressed("select") then self.net:emote(self.field, (self.frame % 4) + 1) end
    self.field:update(inp)
  end
end

function Game:drawTitle()
  local g = love.graphics
  g.clear(0.02, 0.05, 0.12, 1)
  -- a slow pan over Hyrule Town, rendered from the player's own cartridge
  if not self.titleRoom then
    local ok, Room = pcall(require, "src.zelda.tmc.Room")
    if ok then
      local okr, r = pcall(Room.load, self.assets, 0x02, 0)
      if okr then self.titleRoom = r end
    end
  end
  local r = self.titleRoom
  if r then
    local t = self.frame * 0.25
    local span = math.max(1, r.width - W)
    local x = (t % (2 * span))
    if x > span then x = 2 * span - x end
    local y = math.max(0, (r.height - H) / 2)
    -- the town's tileset manager swaps graphics by camera region, as in
    -- the field (without it the river and houses show the default
    -- tileset's tiles -- the same smear as round 2's Minish Village bug)
    self.titleSwap = self.titleSwap or { assets = self.assets, room = r, swapGroups = {} }
    self.titleSwap.camX, self.titleSwap.camY = math.floor(x), math.floor(y)
    Field.updateTileSwap(self.titleSwap)
    g.setColor(1, 1, 1, 1)
    r:drawLayer("bottom", x, y)
    r:drawLayer("top", x, y)
    g.setColor(0, 0, 0, 0.45)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setFont(self.font)
  g.setColor(0.95, 0.85, 0.35, 1)
  g.printf("THE LEGEND OF ZELDA", 0, 46, W, "center")
  g.setColor(0.5, 1, 0.55, 1)
  g.printf("THE MINISH CAP", 0, 60, W, "center")
  if math.floor(self.frame / 30) % 2 == 0 then
    g.setColor(1, 1, 1, 1)
    g.printf("PRESS START", 0, 112, W, "center")
  end
  g.setColor(1, 1, 1, 1)
end

function Game:drawFiles()
  local g = love.graphics
  g.clear(0.08, 0.16, 0.1, 1)
  g.setFont(self.font)
  g.setColor(1, 0.95, 0.6, 1)
  g.printf("SELECT A FILE", 0, 18, W, "center")
  local rows = {
    self.saveData and string.format("CONTINUE  %s  (%s)", self.saveData.name or "Link",
      self.saveData.summary and self.saveData.summary.line or "") or "CONTINUE  (no file)",
    "NEW GAME",
  }
  for i, text in ipairs(rows) do
    local y = 54 + (i - 1) * 24
    local sel = i == self.cursor
    g.setColor(sel and 0.25 or 0.12, sel and 0.4 or 0.2, sel and 0.3 or 0.15, 1)
    g.rectangle("fill", 24, y - 4, W - 48, 18, 3, 3)
    g.setColor(sel and 1 or 0.7, sel and 1 or 0.7, sel and 1 or 0.7, 1)
    g.print(text, 34, y)
  end
  g.setColor(1, 1, 1, 1)
end

function Game:draw()
  if self.state == "title" then self:drawTitle()
  elseif self.state == "files" then self:drawFiles()
  elseif self.field then self.field:draw(self.font) end
end

-- ---------------------------------------------------------------------------
-- runtime hooks
-- ---------------------------------------------------------------------------
function Game:save()
  if not self.saveData then return nil end
  if self.field then
    local p, st = self.field.player, self.saveData.status
    st.x, st.y, st.facing = math.floor(p.x), math.floor(p.y), p.animationState
  end
  return self.saveData
end

function Game:quit()
  if self.audio then self.audio:quit() end
end

function Game:pause(on)
  if self.audio and self.audio.source then
    if on then self.audio.source:pause() else self.audio.source:play() end
  end
end

function Game:optionsChanged(o)
  if self.audio and o then self.audio:setVolumes(o.musicVol, o.sfxVol) end
end

function Game:netAttached(session)
  self.net = Net.new(self, session)
end

function Game:netDetached()
  if self.field then self.field.ghosts = {} end
  self.net = nil
end

function Game:netSnapshot()
  if self.net and self.field then return self.net:snapshot(self.field) end
  return nil
end

function Game:netApply(peer, snap)
  if self.net and self.field then self.net:apply(peer, snap, self.field) end
end

function Game:netEvent(peer, ev)
  if self.net and self.field then self.net:event(peer, ev, self.field) end
end

-- a friend arrived: wave, so they see us at once (and get an event)
function Game:netPeerJoined(peer)
  if self.net then self.net:send({ t = "emote", e = 1 }, peer) end
end

-- the runtime's system menu / LINK PLAY is up: keep the music fed
function Game:pausedUpdate()
  if self.audio then self.audio:update() end
end

function Game:netPeerLeft(peer)
  if self.net then self.net:peerLeft(peer, self.field) end
end

return Game
