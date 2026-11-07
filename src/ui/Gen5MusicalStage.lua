-- src/ui/Gen5MusicalStage.lua -- the Musical's stage and its results
-- (overlays 131 / 132, sta_acting.c and kin).
--
-- Four performers in the lineup the event drew, the show's own song
-- (SEQ_BGM_MSL_01 .. 04 by show), and the appeals: a prop held in a hand is
-- shown off once (ov132 0x021F99F4 -- the prop's worth again, the louder
-- cheer, SE 0x62B, when it is worth 7 or more). The player appeals with A;
-- the others show theirs off on their own. When the song's time is up the
-- curtain falls and the ranking is read out with each one's points
-- (src/script/Gen5Musical.lua scores them).
--
-- THE CHOREOGRAPHY is the show's own script (member 2 of /a/1/1/x, decoded
-- by Gen5MusicalData.decodeScript into constants.gen5Musical.shows[n].script):
-- thread 0 runs the stage and its length is the show's, threads 2..5 move
-- the four performers (placed, slid, hopped, turned, faced) and show off the
-- NPCs' held props when their script says so (op 39); the spotlights follow
-- ops 28 / 29 / 31. The stage's 3D units are laid onto the 256 x 192 screen
-- by a flat projection (INFERRED: x 666 at the centre, 0.85 px a unit, z
-- lifts the far ones a little). THE CAMERA, as far as it was read: the
-- stage scrolls (ov132 0x021F8EE0..0x021F90CA): its target is the focused
-- performer's or light's x - 128, clamped to 0..256, and the scroll walks
-- 4 px a frame toward it; the 3D camera sits at (scroll / 16, 0, 301) from
-- the vector at 0x021FDBEC and BG 2 scrolls with it; ov112 0x021F4A12 turns
-- a point to the screen as (x / 16, 192 - y). The performers' x (561..771)
-- do not fit that 256-px window as plain pixels, so the projection between
-- the two was not settled and the flat layout stays (INFERRED). A
-- cache without the script keeps the old
-- stand-in: a fixed 40 seconds, NPC appeals at random moments.
--
-- Not the cartridge's: the 3D stage, the audience, the effects.

local Font = require("src.render.Font")
local Art = require("src.ui.Gen5MusicalArt")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 256, 192
local SHOW_FRAMES = 40 * 60
local lg = love and love.graphics

function Screen:uiSize() return W, H end
function Screen:wantsFillScale() return true end
function Screen:wantsEdgeBleed() return false end

local function se(self, name) pcall(function() require("src.core.Sound").play(self.game.data, name) end) end

function Screen.new(game, opts)
  local self = setmetatable({}, Screen)
  self.game, self.prog, self.performers, self.onDone = game, opts.prog, opts.performers, opts.onDone
  self.t, self.state, self.pops = 0, "curtain", {}
  self.M = require("src.script.Gen5Musical")
  self.script = opts.prog and opts.prog.show and opts.prog.show.script
  if self.script and not (self.script.threads and self.script.threads[0]) then self.script = nil end
  self.length = self.script and self.script.frames or SHOW_FRAMES
  -- the NPCs' appeals, one per held prop, at random moments of the song
  -- (the stand-in, when the cache has no show script)
  self.plan = {}
  for i, pf in ipairs((not self.script) and self.performers or {}) do
    if not pf.player then
      for _, slot in ipairs({ 7, 8 }) do
        if pf.props[slot] then
          self.plan[#self.plan + 1] = { who = i, slot = slot,
            at = 300 + ((love and love.math and love.math.random(0, SHOW_FRAMES - 600)) or math.random(0, SHOW_FRAMES - 600)) }
        end
      end
    end
  end
  local song = opts.prog and opts.prog.show and opts.prog.show.song
  if song then pcall(function() require("src.core.Music").play(game.data, song) end) end
  return self
end

-- the saved Musical Photo: the player's Pokemon on the stage, still
function Screen.photo(game, photo)
  local self = setmetatable({}, Screen)
  self.game, self.state, self.t, self.pops = game, "photo", 0, {}
  local outfit = {}
  for slot, id in pairs(photo.outfit or {}) do outfit[slot] = { id = id } end
  self.performers = { { player = true, species = photo.species, props = outfit, used = {} } }
  self.photoRec = photo
  return self
end

function Screen:pressed(key)
  local input = self.game.input
  return input and input.wasPressed and input:wasPressed(key)
end

function Screen:finish()
  if self.state ~= "photo" then pcall(function() require("src.core.Music").restoreMap(self.game.data) end) end
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Screen:appeal(i, slot)
  local pf = self.performers[i]
  local v = self.M.appeal(self.game.data, self.prog, pf, slot)
  if v and v > 0 then
    self.pops[#self.pops + 1] = { who = i, text = "+" .. v, t = 0 }
    se(self, v >= 7 and "SEQ_SE_MSCL_10" or "SEQ_SE_MSCL_11")   -- 0x62B / 0x62C
  end
end

-- ------------------------------------------------- the show's script --

local function fx(v) return (tonumber(v) or 0) / 4096 end

-- a performer's stage state (k = its lineup slot, 0..3)
function Screen:actor(k)
  self.actors = self.actors or {}
  local a = self.actors[k]
  if not a then
    a = { x = 561 + 70 * k, y = 155, z = 80 + 30 * k, rot = 0, flip = false }
    self.actors[k] = a
  end
  return a
end

-- the performers a command names (-1: the thread's own; 0x021FB1F4)
local function targets(run, who)
  who = tonumber(who) or -1
  if who == -1 then return run.who and { run.who } or {} end
  if who >= 0 and who <= 3 then return { who } end
  return {}
end

local OPS = {}
OPS[11] = function(self, run, c)
  for _, k in ipairs(targets(run, c[2])) do
    local a = self:actor(k)
    a.x, a.y, a.z, a.slide, a.hop = fx(c[4]), fx(c[5]), fx(c[6]), nil, nil
  end
end
-- (12, 16 and 38 end in a wait flag: 1 holds the thread for the move's
-- length -- READ, each handler stores it into the thread's wait, +0x14)
-- 12 <who, frames, dx, dy, dz, wait>: a slide by (dx, dy, dz) (READ: a task
-- off GetPos / SetPos)
OPS[12] = function(self, run, c)
  for _, k in ipairs(targets(run, c[2])) do
    local a = self:actor(k)
    local n = math.max(0, c[3] or 0)
    if n == 0 then a.x, a.y, a.z = a.x + fx(c[4]), a.y + fx(c[5]), a.z + fx(c[6])
    else a.slide = { t = 0, n = n, x = a.x, y = a.y, z = a.z, dx = fx(c[4]), dy = fx(c[5]), dz = fx(c[6]) } end
  end
  if c[7] == 1 then run.wait = math.max(0, c[3] or 0) end
end
-- 16 <who, frames, hops, height, wait>: hops of `frames` each (READ: task
-- 0x021FB8CC sets the draw offset to sin(t * 0x8000 / frames) * height,
-- half a turn of the sine table a hop, through ov112 0x021F8084)
OPS[16] = function(self, run, c)
  local per, hops = math.max(1, c[3] or 1), math.max(1, c[4] or 1)
  for _, k in ipairs(targets(run, c[2])) do
    self:actor(k).hop = { t = 0, n = per * hops, hops = hops, h = fx(c[5]) }
  end
  if c[6] == 1 then run.wait = per * hops end
end
-- 38 <who, frames, start, delta, wait>: a turn from `start` to start +
-- delta degrees (READ: task 0x021FBA14 interpolates and sets the angle,
-- degrees * 65536 / 360, through ov112 0x021F8068)
OPS[38] = function(self, run, c)
  local from, to = c[4] or 0, (c[4] or 0) + (c[5] or 0)
  for _, k in ipairs(targets(run, c[2])) do
    local a = self:actor(k)
    local n = math.max(0, c[3] or 0)
    if n == 0 then a.rot, a.turn = to, nil
    else a.rot, a.turn = from, { t = 0, n = n, from = from, to = to } end
  end
  if c[6] == 1 then run.wait = math.max(0, c[3] or 0) end
end
-- 13 / 14 <who>: the performer's own animation stopped / started (READ:
-- ov112 0x021F80B0 / 0x021F80A0 stop / start its MCSS animation)
OPS[13] = function(self, run, c)
  for _, k in ipairs(targets(run, c[2])) do local a = self:actor(k) a.stillAt = a.stillAt or self.t end
end
OPS[14] = function(self, run, c)
  for _, k in ipairs(targets(run, c[2])) do self:actor(k).stillAt = nil end
end
OPS[10] = function(self, run, c)
  for _, k in ipairs(targets(run, c[2])) do self:actor(k).flip = (c[3] or 0) == 1 end
end
OPS[39] = function(self, run, c)
  -- an NPC shows off the prop in hand 0 / 1 (the player's own appeals are
  -- the player's to make, with A)
  for _, k in ipairs(targets(run, c[2])) do
    local pf = self.performers[k + 1]
    if pf and not pf.player then self:appeal(k + 1, 7 + ((c[3] or 0) == 1 and 1 or 0)) end
  end
end
-- 28 <light, kind> makes a spotlight (READ: 0x021FC1D4 allocates it with
-- ov112 0x021F6E78, colour 0x3FF), 29 <light> removes it (0x021F6EE4), 30
-- <light, frames, x, y, z> moves it to a point (not drawn here)
local function light(self, n)
  self.lights = self.lights or {}
  n = n or 0
  self.lights[n] = self.lights[n] or { on = true }
  return self.lights[n]
end
OPS[28] = function(self, run, c) light(self, c[2]).on = true end
OPS[29] = function(self, run, c) light(self, c[2]).on = false end
-- 31 <light, who, frames, x, y, z>: the light rides the performer(s) for
-- `frames` (0: placed once) at that offset (READ: 0x021FC380 adds the offset
-- to GetPos and sets the light there, or runs task 0x021FC491)
OPS[31] = function(self, run, c)
  local l = light(self, c[2])
  local who = targets(run, c[3])
  l.target = who[1] or l.target
end

-- one frame of every thread; true once thread 0 has ended
function Screen:runScript()
  if not self.runs then
    self.runs = {}
    local seen = {}
    for k = 0, 13 do
      local list = self.script.threads[k]
      if list and not seen[list] then
        seen[list] = true
        self.runs[#self.runs + 1] = { list = list, pc = 1, wait = 0, main = k == 0,
                                      who = (k >= 2 and k <= 5) and k - 2 or nil }
      end
    end
  end
  for _, a in pairs(self.actors or {}) do
    if a.slide then
      local m = a.slide
      m.t = m.t + 1
      local f = math.min(1, m.t / m.n)
      a.x, a.y, a.z = m.x + m.dx * f, m.y + m.dy * f, m.z + m.dz * f
      if m.t >= m.n then a.slide = nil end
    end
    if a.hop then
      a.hop.t = a.hop.t + 1
      if a.hop.t >= a.hop.n then a.hop = nil end
    end
    if a.turn then
      local m = a.turn
      m.t = m.t + 1
      a.rot = m.from + (m.to - m.from) * math.min(1, m.t / m.n)
      if m.t >= m.n then a.turn = nil end
    end
  end
  local mainDone = false
  for _, run in ipairs(self.runs) do
    if run.wait > 0 then run.wait = run.wait - 1 end
    local guard = 0
    while run.wait == 0 and not run.done and guard < 200 do
      guard = guard + 1
      local c = run.list[run.pc]
      if not c or c[1] == 0 then run.done = true break end
      run.pc = run.pc + 1
      local op = c[1]
      if op == 1 then
        run.wait = math.max(0, c[2] or 0)
        if run.wait > 0 then break end
      elseif op == 3 then break
      elseif OPS[op] then OPS[op](self, run, c) end
    end
    if run.main and run.done then mainDone = true end
  end
  return mainDone
end

-- where performer k (lineup slot) stands on the screen, with its turn and
-- facing; nil without a script
function Screen:place(k)
  local a = self.actors and self.actors[k]
  if not (self.script and a) then return nil end
  local lift = 0
  if a.hop then lift = math.abs(math.sin(a.hop.t / a.hop.n * math.pi * a.hop.hops)) * a.hop.h end
  local x = 128 + (a.x - 666) * 0.85
  local y = 150 - (a.y - 155) - lift - (a.z - 125) * 0.15
  return x, y, -math.rad(a.rot or 0), a.flip
end

function Screen:update()
  self.t = self.t + 1
  for k = #self.pops, 1, -1 do
    local p = self.pops[k]
    p.t = p.t + 1
    if p.t > 60 then table.remove(self.pops, k) end
  end
  if self.state == "photo" then
    if self:pressed("a") or self:pressed("b") then self:finish() end
    return
  end
  if self.state == "curtain" then
    if self.t >= 90 then self.state, self.t = "show", 0 end
    return
  end
  if self.state == "show" then
    for _, a in ipairs(self.plan) do
      if not a.done and self.t >= a.at then a.done = true self:appeal(a.who, a.slot) end
    end
    local ended = self.script and self:runScript()
    if self:pressed("a") then
      for i, pf in ipairs(self.performers) do
        if pf.player then
          for _, slot in ipairs({ 7, 8 }) do
            if pf.props[slot] and not pf.used[slot] then self:appeal(i, slot) break end
          end
        end
      end
    end
    if ended or (not self.script and self.t >= SHOW_FRAMES) then
      self.state, self.t = "results", 0
      self.order = self.M.rank(self.performers)
      pcall(function() require("src.core.Music").stop() end)
    end
    return
  end
  if self.state == "results" then
    if self.t > 60 and (self:pressed("a") or self:pressed("b")) then self:finish() end
  end
end

local function title(self)
  local index = self.prog and self.prog.index or (self.photoRec and self.photoRec.show) or 0
  local s = self.game.data.text and self.game.data.text[("TEXT_B%04d_%05d"):format(286, 29 + index)]
  return s or "Musical"
end

local function speciesName(data, sp)
  local def = data.pokemon and data.pokemon[sp]
  return def and def.name or ("#" .. tostring(sp))
end

function Screen:drawStage()
  -- the hall, the curtains, the boards
  lg.setColor(0.12, 0.05, 0.12)
  lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(0.55, 0.08, 0.15)
  local open = (self.state == "curtain") and math.min(1, self.t / 90) or 1
  local cw = 128 * (1 - open) + 18
  lg.rectangle("fill", 0, 0, cw, 150)
  lg.rectangle("fill", W - cw, 0, cw, 150)
  lg.setColor(0.45, 0.28, 0.16)
  lg.rectangle("fill", 0, 140, W, 52)
  lg.setColor(1, 1, 0.8, 0.12)
  lg.polygon("fill", 128, 0, 40, 150, 216, 150)
end

function Screen:draw()
  if not lg then return end
  local data = self.game.data
  lg.push("all")
  self:drawStage()
  local n = #self.performers
  -- the spotlights the script has on
  for _, l in pairs(self.lights or {}) do
    local tx = l.on and l.target and self:place(l.target)
    if tx then
      lg.setColor(1, 1, 0.8, 0.14)
      lg.polygon("fill", tx - 6, 0, tx + 6, 0, tx + 30, 160, tx - 30, 160)
    end
  end
  for i, pf in ipairs(self.performers) do
    local x = (n == 1) and 128 or (32 + (i - 1) * 64)
    local bob = (self.state == "show" and not self.script) and math.floor(math.sin((self.t + i * 13) / 9) * 2) or 0
    lg.setColor(1, 1, 1)
    local sx, sy, rot, flip = self:place(i - 1)
    if sx then
      x = sx
      lg.push()
      lg.translate(sx, sy)
      lg.rotate(rot)
      lg.scale(flip and -1 or 1, 1)
      local a = self.actors and self.actors[i - 1]
      Art.drawMon(data, pf.species, pf.props, 0, 0, 0.62, { tick = ((a and a.stillAt) or self.t) + i * 17 })
      lg.pop()
    else
      Art.drawMon(data, pf.species, pf.props, x, 146 + bob, n == 1 and 1 or 0.62)
    end
    for _, p in ipairs(self.pops) do
      if p.who == i then
        lg.setColor(1, 0.9, 0.3)
        Font.draw(p.text, x - 8, 60 - p.t / 3)
      end
    end
  end
  lg.setColor(1, 1, 1)
  Font.draw(title(self), 6, 4)
  if self.state == "show" then
    local left = math.max(0, math.ceil((self.length - self.t) / 60))
    Font.draw(tostring(left), W - 22, 4)
  elseif self.state == "results" then
    lg.setColor(0, 0, 0, 0.7)
    lg.rectangle("fill", 24, 30, 208, 108, 6, 6)
    lg.setColor(1, 1, 1)
    for k, i in ipairs(self.order or {}) do
      local pf = self.performers[i]
      local mark = pf.player and "*" or " "
      Font.draw(("%d %s%s"):format(k, mark, speciesName(data, pf.species)), 34, 38 + (k - 1) * 22)
      Font.draw(tostring(self.M.total(pf)), 196, 38 + (k - 1) * 22)
    end
  elseif self.state == "photo" then
    lg.setColor(1, 1, 1)
    Font.draw(tostring(self.photoRec and self.photoRec.score or ""), W - 30, 4)
  end
  lg.pop()
end

return Screen
