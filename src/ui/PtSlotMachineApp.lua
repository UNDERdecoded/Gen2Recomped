-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SLOT MACHINE APP (overlay 101: ov101_021D0D80 / 0E40 / 0EE4),
-- the screen around src/script/PtSlotLogic.lua, on the art
-- src/import/Gen4PtSlotArt.lua imports (`gen4_pt_slot_art`).
--
-- THE TWO SCREENS (READ FROM CODE, ov101_021D0F9C: GX_DISP_SELECT_MAIN_SUB,
-- the main engine on top):
--   top     the cabinet. Backdrop, then the reel symbols (OBJ, BG priority 3,
--           five per reel at x 68 / 128 / 188, ov101_021D59AC), the reel
--           glass BG2 blended over them (G2_SetBlendAlpha BG2 over OBJ, 8 / 9
--           -- drawn here at half alpha, INFERRED approximation), the cabinet
--           BG1 with its five lamps and three stop buttons, the credit and
--           payout digits (ov101_021D5AF0 / 5C28, x 108 / 180, y 180), and
--           the message window (BG0, template 2,19 26x4, text bank 544).
--   bottom  the moonlit Poke Ball panel (sub BG3, palette row 1 faded to the
--           bonus colours, ov101_021D542C..54EC), the hint ball, Clefairy,
--           the sparkle and burst, the bonus counters.
-- The 7s that line up fall from the reels down to the bottom screen
-- (ov101_021D7B08, NNS_G2D_VRAM_TYPE_2DBOTH): y >= 192 is the bottom one.
--
-- ONE SCREEN (SecondScreen "swap" / "off"): the top screen is the play
-- surface, and while the bottom screen has something on it (the ball,
-- Clefairy, the falling 7s, the totals) the port shows the two side by
-- side -- the cabinet at 2/3, the bottom screen at 1/3 to its right, so
-- neither covers the other; SELECT turns that off / on. With an inset,
-- a real second panel or the stacked / side-by-side layouts the bottom
-- screen goes where SecondScreen puts it. (A port choice: the cartridge has
-- no one-screen layout.)
--
-- Controls are the cartridge's: X bets, down (or X) spins, Y / B / A stop
-- the reels, START leaves, X speeds up a payout, A / B close a message.

local Assets = require("src.render.Assets")
local SecondScreen = require("src.ui.SecondScreen")
local Logic = require("src.script.PtSlotLogic")

local S = {}; S.__index = S
S.isOpaque = true

local W, H = 256, 192

-- Is the art in this cache?
function S.available(game)
  local art = game and game.data and game.data.gen4_pt_slot_art
  return type(art) == "table" and type(art.bg) == "table" and type(art.groups) == "table"
end

local function se(data, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, data, name) end
end

-- args: { machine, setting, coins } (PtSlotMachine); onDone(result)
function S.new(game, args, onDone)
  local self = setmetatable({ game = game, data = game.data, onDone = onDone, args = args or {} }, S)
  self.art = game.data.gen4_pt_slot_art or {}
  self.images = {}
  self.fade = 16                       -- StartScreenFade(..., 8, 1): in
  self.fadeTarget = 0
  self.phase = "in"
  self.inset = true                    -- one screen: the bottom panel shown
  local seed = love and love.math and love.math.random(0, 2147483646) or os.time()
  self.logic = Logic.new({
    setting = self.args.setting, coins = self.args.coins, seed = seed,
    sound = function(kind, name) self:sound(kind, name) end,
    seqLen = function(group, anim) return self:seqLength(group, anim) end,
  })
  self.fieldSong = nil
  return self
end

function S:uiSize() return W, H end
function S:wantsFillScale() return true end

function S:twoScreens()
  return SecondScreen.separate(self.game)
end

-- --------------------------------------------------------------- sound --

function S:sound(kind, name)
  local data = self.data
  if kind == "se" then se(data, name)
  elseif kind == "cry" then
    pcall(function() require("src.core.Sound").playCry(data, name) end)
  elseif kind == "bgm_stop" then
    local Music = require("src.core.Music")
    if name == 0 then self.fieldSong = Music.current() end   -- the field player paused
    pcall(Music.stop)
  elseif kind == "bgm_start" then
    local Music = require("src.core.Music")
    if name == 0 then
      if self.fieldSong then pcall(Music.play, data, self.fieldSong) end
    elseif name == 1 then pcall(Music.play, data, 1184)       -- SEQ_SLOT_ATARI
    elseif name == 2 then pcall(Music.play, data, 1185) end   -- SEQ_SLOT_OOATARI
  end
end

-- -------------------------------------------------------------- update --

local KEYS = { "a", "b", "x", "y", "start", "down" }

function S:update()
  local input = self.game.input
  local pressed, held = {}, {}
  if input then
    -- the RAW buttons: Input folds Gen 4's X into START and Y into SELECT
    -- (alsoHeld), and here X bets and Y stops the left reel
    local rawP, rawH = input.pressed, input.state
    for _, k in ipairs(KEYS) do
      if type(rawP) == "table" and type(rawH) == "table" then
        pressed[k] = rawP[k] and true or nil
        held[k] = rawH[k] and true or nil
      else
        pressed[k] = input:wasPressed(k) or nil
        held[k] = input:isDown(k) or nil
      end
    end
    local sel = (type(rawP) == "table") and rawP.select or (rawP == nil and input:wasPressed("select") and not pressed.y)
    if sel and not self:twoScreens() then
      self.inset = not self.inset
      se(self.data, "SEQ_SE_DP_SELECT")
    end
  end
  self:tick(pressed, held)
end

-- one frame (ov101_021D0E40)
function S:tick(pressed, held)
  self.frame = (self.frame or 0) + 1
  local L = self.logic
  if self.fadeTarget then
    local stepv = 16 / 8
    if self.fadeTarget > self.fade then self.fade = math.min(16, self.fade + stepv)
    else self.fade = math.max(0, self.fade - stepv) end
    if self.fade == self.fadeTarget then self.fadeTarget = nil end
  end
  if self.phase == "in" then
    -- case 0: the fade in finishes before the game takes the pad
    L:step({}, {})
    if not self.fadeTarget then self.phase = "play" end
  elseif self.phase == "play" then
    if L:step(pressed, held) then
      self.phase = "out"
      self.fadeTarget = 16
    end
  elseif self.phase == "out" then
    L:step({}, {})
    if not self.fadeTarget and not L:musicBusy() then
      self.phase = "done"
      if self.game.stack then self.game.stack:pop() end
      if self.onDone then self.onDone(L:result()) end
    end
  end
end

-- ------------------------------------------------------------- picture --

function S:image(rec)
  local path = type(rec) == "table" and rec.path or rec
  if not path then return nil end
  if self.images[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.images[path] = ok and img or false
    if self.images[path] then self.images[path]:setFilter("nearest", "nearest") end
  end
  return self.images[path] or nil
end

function S:seqLength(group, anim)
  local g = (self.art.groups or {})[group]
  local frames = g and g.seqs and g.seqs[anim]
  if not frames then return nil end
  local n = 0
  for _, f in ipairs(frames) do n = n + (f[2] or 1) end
  return n
end

-- the cell a sequence shows at `tick` (looping, unless `hold`)
local function cellAt(frames, tick, hold)
  if not frames or #frames == 0 then return 0 end
  local total = 0
  for _, f in ipairs(frames) do total = total + math.max(1, f[2] or 1) end
  local t = math.floor(tick or 0)
  if hold then t = math.min(t, total - 1) else t = t % total end
  local acc = 0
  for _, f in ipairs(frames) do
    acc = acc + math.max(1, f[2] or 1)
    if t < acc then return f[1] end
  end
  return frames[#frames][1]
end

-- one sprite: a group's sequence at x, y (the OAM position), scaled /
-- rotated about it (affine double mode)
function S:sprite(group, anim, tick, x, y, scale, rot, flipX, hold)
  local g = (self.art.groups or {})[group]
  if not g then return end
  local cell = cellAt(g.seqs and g.seqs[anim or 0], tick, hold)
  local rec = g.cells and g.cells[cell]
  local img = rec and self:image(rec)
  if not img then return end
  local ox, oy = rec.originX or 0, rec.originY or 0
  local sx = (scale or 1) * (flipX and -1 or 1)
  love.graphics.draw(img, x, y, (rot or 0) * 2 * math.pi / 65536, sx, scale or 1, -ox, -oy)
end

-- 5-bit blend (ov101_021D4EC0), colours as 8-bit triples
local function to5(v) return math.floor(v * 31 / 255 + 0.5) end
local function to8(v) return math.floor(v * 255 / 31 + 0.5) end
local function blendRow(a, b, level)
  local out = {}
  level = math.min(16, math.max(0, math.floor(level or 0)))
  for i = 1, 16 do
    local ca, cb = a[i] or { 0, 0, 0 }, b[i] or { 0, 0, 0 }
    local c = {}
    for k = 1, 3 do
      local x, y = to5(ca[k]), to5(cb[k])
      c[k] = to8(x + math.floor((y - x) * level / 16))
    end
    out[i] = c
  end
  return out
end
local function row(pal, r)
  local out = {}
  for i = 1, 16 do out[i] = pal[r * 16 + i] or { 0, 0, 0 } end
  return out
end

-- the 16 x 16 palette texture for one engine, this frame
function S:paletteTexture(which)
  local pals = self.art.palettes or {}
  local bg = pals.bg or {}
  local L = self.logic
  local rows = {}
  for r = 0, 15 do rows[r] = row(bg, r) end
  local key
  if which == "main" then
    -- the lamps: Unk_ov101_021D4F58 unk_A4 (rows 2 / 3 / 3 / 4 / 4) toward
    -- unk_144 (members 74 / 75 / 75 / 76 / 76) on rows 2, 3, 12, 4, 11
    local from = { [0] = 2, 3, 3, 4, 4 }
    local to = { [0] = "m74", "m75", "m75", "m76", "m76" }
    local parts = {}
    for line = 0, 4 do
      local lv = L.lamp[line] or 0
      rows[Logic.LAMP_ROWS[line]] = blendRow(row(bg, from[line]), pals[to[line]] or row(bg, from[line]), lv)
      parts[#parts + 1] = lv
    end
    key = "main:" .. table.concat(parts, ",")
  else
    local src = { base = row(bg, 1), bonus = pals.m5, flashA = pals.m6, flashB = pals.m7 }
    local sp = L.subPal
    rows[1] = blendRow(src[sp.from] or src.base, src[sp.to] or src.base, sp.level)
    key = ("sub:%s:%s:%d"):format(sp.from, sp.to, sp.level)
  end
  self.palTex = self.palTex or {}
  local cached = self.palTex[which]
  if cached and cached.key == key then return cached.image end
  local data = love.image.newImageData(16, 16)
  for r = 0, 15 do
    for i = 0, 15 do
      local c = rows[r][i + 1] or { 0, 0, 0 }
      data:setPixel(i, r, c[1] / 255, c[2] / 255, c[3] / 255, 1)
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  self.palTex[which] = { key = key, image = img }
  return img
end

local shader
local function indexShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern Image pal;
      extern vec4 rects[3];
      extern float rows[3];
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec4 t = Texel(tex, uv);
        if (t.a < 0.5) return vec4(0.0);
        float idx = floor(t.r * 255.0 / 17.0 + 0.5);
        float r = floor(t.g * 255.0 / 17.0 + 0.5);
        vec2 px = uv * vec2(256.0, 256.0);
        for (int i = 0; i < 3; i++) {
          vec4 q = rects[i];
          if (px.x >= q.x && px.y >= q.y && px.x < q.x + q.z && px.y < q.y + q.w) r = rows[i];
        }
        return Texel(pal, vec2((idx + 0.5) / 16.0, (r + 0.5) / 16.0)) * colour;
      }
    ]])
    shader = ok and sh or false
  end
  return shader or nil
end

-- an index background through the engine's palette
function S:background(key, which, alpha)
  local img = self:image((self.art.bg or {})[key])
  local sh = indexShader()
  if not (img and sh) then return end
  local g = love.graphics
  local prev = g.getShader()
  sh:send("pal", self:paletteTexture(which))
  local rects, rws = {}, {}
  for i = 0, 2 do
    if which == "main" and key == "main1" then
      local t = Logic.BUTTON_RECTS[i]
      rects[i + 1] = { t[1] * 8, t[2] * 8, 24, 16 }
      rws[i + 1] = self.logic.buttons[i]
    else
      rects[i + 1] = { -1, -1, 0, 0 }
      rws[i + 1] = 0
    end
  end
  sh:send("rects", rects[1], rects[2], rects[3])
  sh:send("rows", rws[1], rws[2], rws[3])
  g.setShader(sh)
  g.setColor(1, 1, 1, alpha or 1)
  g.draw(img, 0, 0)
  g.setColor(1, 1, 1, 1)
  g.setShader(prev)
end

local function backdrop(c)
  local g = love.graphics
  c = c or { 0, 0, 0 }
  g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
end

-- digits as the cartridge lays them (5 OBJs, right to left, 8 px apart)
function S:counter(value, x, y, hideZero)
  local unit = 1
  for k = 0, 4 do
    local hide = (k > 0 and value < unit) or (hideZero and value < unit)
    if not hide then
      local d = math.floor((value % (unit * 10)) / unit)
      self:sprite("credit", d, 0, x - 8 * k, y)
    end
    unit = unit * 10
  end
end

-- THE TOP SCREEN
function S:drawTop()
  local L = self.logic
  local pals = self.art.palettes or {}
  backdrop((pals.bg or {})[1])
  -- the reels (ov101_021D5A70)
  for reel = 0, 2 do
    local x = 68 + 60 * reel
    for k = 0, 4 do
      local v = (L.pos[reel] + 32 * k) % 160
      local y = v + 16 + L.bounce[reel]
      local sym = L:symbolAt(reel, math.floor(v / 32))
      self:sprite("reel", sym, 0, x, y)
    end
  end
  self:background("main2", "main", 8 / 16)
  self:background("main1", "main")
  -- credit (unk_60) and payout (unk_64)
  self:counter(math.min(Logic.MAX, L.credit), 108, 180, false)
  self:counter(L.payout, 180, 180, true)
  -- the 7s on their way down
  for _, o in ipairs(L.objs) do
    if o.kind == "drop" and o.ready and o.visible then
      for i = 0, 2 do
        if o.ys[i] < 192 + 16 then self:sprite(o.group, 0, 0, 68 + 60 * i, o.ys[i]) end
      end
    end
  end
  -- the message window (ov101_021D148C)
  if L.message then
    local Font = require("src.render.Font")
    local Text = require("src.import.Gen4Text")
    local t = (self.data.text or {})[Text.label(544, L.message)] or ""
    Font.drawBox(1, 18, 28, 6)
    local g = love.graphics
    g.setColor(0, 0, 0, 1)
    local y = 19 * 8 + 1
    for line in (t .. "\n"):gmatch("(.-)\n") do
      Font.draw(line, 2 * 8 + 1, y)
      y = y + 16
    end
    g.setColor(1, 1, 1, 1)
  end
end

-- THE BOTTOM SCREEN (sprites at their y - 192)
-- `panel`: drawn in the one-screen corner panel, where a sprite parked off
-- the bottom screen (Clefairy at y 192 + 256, the ball at 192 + 224) would
-- spill over the top one -- those are left out
function S:drawBottom(panel)
  local L = self.logic
  local pals = self.art.palettes or {}
  backdrop((pals.bg or {})[1])
  self:background("sub3", "sub")
  local g = love.graphics
  g.push()
  g.translate(0, -192)
  local hidden = L.anim.hide == 1
  for _, o in ipairs(L.objs) do
    local off = panel and type(o.y) == "number" and (o.y > 192 + 192 + 8 or o.y < 192 - 8)
    if o.ready and o.visible ~= false and not off then
      local k = o.kind
      if k == "ball" or k == "sparkle" or k == "clefairy" then
        self:sprite(o.group, o.anim, o.tick, o.x, o.y, o.scale, o.rot, false, o.manual)
      elseif k == "burst" then
        self:sprite("burst", 0, 0, o.x, o.y)
        self:sprite("burst", 0, 0, o.x2, o.y2, 1, 0, true)
      elseif k == "counter" then
        if not hidden then self:sprite(o.group, 0, o.tick, o.x, o.y) end
      elseif k == "gamesLeft" then
        if not hidden then
          local v, x = math.min(99, L.left), 52
          local tens = math.floor((v % 100) / 10)
          if tens > 0 then self:sprite("digits", tens, 0, x, 192 + 8); x = x + 8 end
          self:sprite("digits", v % 10, 0, x, 192 + 8)
        end
      elseif k == "wonDigits" then
        if not hidden then
          local v, unit = math.min(50000, L.won), 10000
          for i = 0, 4 do
            self:sprite("digits", math.floor((v % (unit * 10)) / unit), 0, 220 + 8 * i, 192 + 184)
            unit = unit / 10
          end
        end
      elseif k == "round" then
        local v = o.value
        local x, unit, n = 128, 1, 1
        if v >= 100 then unit, n, x = 100, 3, x - 16 elseif v >= 10 then unit, n, x = 10, 2, x - 8 end
        for _ = 1, n do
          self:sprite("bigDigits", math.floor((v % (unit * 10)) / unit), 0, x, 192 + 32)
          x, unit = x + 16, unit / 10
        end
      elseif k == "label2x" then
        self:sprite(o.group, 0, 0, o.x, o.y, 2)
      elseif k == "total" then
        local v, unit, x = o.value, 1, 128 + 72
        local n = #tostring(v)
        for _ = 1, n do
          self:sprite("digits", math.floor((v % (unit * 10)) / unit), 0, x, o.y, 2)
          x, unit = x - 16, unit * 10
        end
      elseif k == "drop" then
        for i = 0, 2 do
          if o.ys[i] >= 192 - 16 then self:sprite(o.group, 0, 0, 68 + 60 * i, o.ys[i]) end
        end
      end
    end
  end
  g.pop()
end

-- something on the bottom screen worth a corner panel (one screen only)
function S:bottomBusy()
  for _, o in ipairs(self.logic.objs) do
    if o.ready and o.kind ~= "counter" and o.kind ~= "gamesLeft" and o.kind ~= "wonDigits" then return true end
  end
  return self.logic.bonus == 1
end

function S:drawFade()
  if self.fade > 0 then
    local g = love.graphics
    g.setColor(0, 0, 0, math.min(1, self.fade / 16))
    g.rectangle("fill", 0, 0, W, H)
    g.setColor(1, 1, 1, 1)
  end
end

function S:draw()
  local g = love.graphics
  if self:twoScreens() then
    self:drawTop()
    self:drawFade()
    SecondScreen.draw(self.game, function()
      self:drawBottom()
      self:drawFade()
    end)
    return
  end
  -- the bottom screen wanted: the two side by side, the cabinet at 2/3 and
  -- the bottom screen at 1/3 beside it, so neither covers the other; it
  -- stays up a second after the bottom screen goes quiet (no flicker)
  if self.inset and self:bottomBusy() then self.panelHold = 60
  elseif self.panelHold then self.panelHold = self.panelHold - 1; if self.panelHold <= 0 then self.panelHold = nil end end
  if not (self.inset and self.panelHold) then
    self:drawTop()
    self:drawFade()
    return
  end
  local big, small = 2 / 3, 1 / 3
  local tx, ty = 0, (H - H * big) / 2
  local px, py = W * big, (H - H * small) / 2
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  g.push()
  g.translate(tx, ty)
  g.scale(big, big)
  self:drawTop()
  self:drawFade()
  g.pop()
  g.push()
  g.translate(px, py)
  g.scale(small, small)
  self:drawBottom(true)
  self:drawFade()
  g.pop()
  -- the letterbox: a falling 7 or a parked sprite past either screen's edge
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, ty)
  g.rectangle("fill", 0, ty + H * big, W * big, H - ty - H * big)
  g.rectangle("fill", px, 0, W - px, py)
  g.rectangle("fill", px, py + H * small, W - px, H - py - H * small)
  g.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------- the session's hook --
-- PtSlotMachine.app: push the app, wait for it, hand back what it booked
function S.run(ctx, args)
  local game = ctx and ctx.game
  if not (game and game.stack and S.available(game)) then
    require("src.core.Logger").warn("slot machine: no gen4_pt_slot_art in this cache (re-import)")
    return nil
  end
  local runner = ctx.runner
  local out
  local app = S.new(game, args, function(res)
    out = res
    if runner then runner:resume() end
  end)
  game.stack:push(app)
  if runner then runner:yield() end
  -- ov101_021D0F3C: RECORD_UNK_014 += the bonus rounds played (unk_0C)
  local games = out and tonumber(out.games) or 0
  if games > 0 then
    pcall(function()
      local R = require("src.pokemon.Gen4GameRecords")
      R.add(game.save, R.ID.UNK_014, games)
    end)
  end
  return out
end

return S
