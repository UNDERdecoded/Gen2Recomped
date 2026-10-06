-- THE POFFIN HOUSE'S COOKING, ALONE (`openpoffincooking 0`): choose a Berry,
-- stir it through three phases (src/pokemon/Gen4PoffinStir.lua), read the
-- result (Gen4Poffin.cook), keep cooking or stop. The words are the
-- cartridge's own, bank 464 (TEXT_BANK_POFFIN_MAKING).
--
-- STIRRING: drag around the pot with the touch screen / mouse, as on the DS;
-- or hold RIGHT (clockwise) / LEFT (anticlockwise) to swirl a virtual finger
-- around the rim, which speeds up the longer the key is held and lifts when
-- it is released.
--
-- THE POT IS THE CARTRIDGE'S (src/import/Gen4PoffinArt.lua, overlay083):
-- the tablecloth, the flames for the phase's heat, the batter -- turned by
-- the stir's own angle, swelled by its speed (ov83_0223FB68: 1 + 1/4 of the
-- speed past 910 over 2730) and cross-faded into the next batter over a
-- phase's last 60 frames or last 5 turns (ov83_0223FC58) -- and the rim on
-- top, in ov83_0223E368's order; the spoon at the finger, and the stir arrow
-- whenever the batter turns against the way it should (ov83_0223C558). On
-- a second screen, the top screen's own picture (top_screen_single).
--
-- IN A GROUP (`openpoffincooking 1`, opts.group = 2-4 cooks). On the
-- cartridge the others are other DSes; there are no computer cooks. PORT
-- ADDITION: the other places are filled by local cooks, each bringing a
-- different Berry and stirring the same pot -- the way it should turn, late
-- to notice a change of direction, easing off when the pot runs fast and
-- drifting toward the player's finger. Everything after that is the
-- cartridge's group rules: the arcs averaged (Gen4PoffinStir), the frames
-- stirred in sync sparkling and taken off the smoothness, the same Berry
-- twice making a Foul Poffin, and every cook given one Poffin per cook. The
-- top screen is top_screen_multi with the cooks' names on its plates.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Stir = require("src.pokemon.Gen4PoffinStir")
local P = require("src.pokemon.Gen4Poffin")

local Cook = {}
Cook.__index = Cook
Cook.isOpaque = true
Cook.BANK = 464
Cook.FINGER_RADIUS = 40

function Cook:uiSize() return 256, 192 end
function Cook:wantsFillScale() return true end

local function line(game, n)
  local T = require("src.import.Gen4Text")
  local s = game.data and game.data.text and game.data.text[T.label(Cook.BANK, n)]
  return s
end

-- a cartridge line with its {STRVAR_1 kind slot pad} slots filled: the values
-- are BUFFERED on the game (Gen4Text.buffer, slot by slot, nil as "") and
-- gen4Markup expands them, as every Gen 4 command does -- not a gsub of the
-- token here, which is the hand-rolled expansion the machine check forbids
local function fill(game, text, values)
  values = values or {}
  local n = 0
  for k in pairs(values) do if type(k) == "number" and k > n then n = k end end
  local list = {}
  for i = 1, n do list[i] = values[i] ~= nil and tostring(values[i]) or "" end
  require("src.import.Gen4Text").buffer(game, (table.unpack or unpack)(list, 1, n))
  local s = tostring(text or "")
  local ok, Commands = pcall(require, "src.script.Commands")
  if ok and Commands and Commands.gen4Markup then
    local okM, plain = pcall(Commands.gen4Markup, s, game)
    if okM and type(plain) == "string" then s = plain end
  end
  return s
end

Cook.PARTNER_NAMES = { "ALEX", "MAYA", "KENJI" }

function Cook.new(game, opts)
  local self = setmetatable({ game = game, opts = opts or {}, mode = "choose", made = 0 }, Cook)
  self.group = math.max(1, math.min(4, math.floor(tonumber(self.opts.group) or 1)))
  return self
end

local function random(n) return (love and love.math and love.math.random or math.random)(0, n - 1) end

-- the other cooks' Berries: different ones, from the common Berries
function Cook:partnerBerries(own)
  local rec = self.game.data.gen4_berry_flavors or {}
  local pool = {}
  for id = 149, 172 do if rec[id] and id ~= own then pool[#pool + 1] = id end end
  local out = {}
  for _ = 2, self.group do
    if #pool == 0 then break end
    out[#out + 1] = table.remove(pool, random(#pool) + 1)
  end
  return out
end

function Cook:newPartners(own)
  self.partners = {}
  for i, item in ipairs(self:partnerBerries(own)) do
    local p = { name = Cook.PARTNER_NAMES[i], item = item,
      angle = -math.pi / 2 + i * math.pi / 2, speed = 0, radius = 36 + random(16),
      skill = 0.6 + random(40) / 100, react = 0 }
    p.x = Stir.CENTER_X + math.cos(p.angle) * p.radius
    p.y = Stir.CENTER_Y + math.sin(p.angle) * p.radius
    self.partners[i] = p
  end
end

-- one local cook's 30 Hz frame: where its finger goes, and its arc
function Cook:partnerFrame(p, s, lead)
  if p.seenDir ~= s.dir then
    p.seenDir, p.react = s.dir, 6 + random(math.floor(24 * (1.4 - p.skill)))
  end
  local want = 0
  if p.react > 0 then p.react = p.react - 1 else want = s.dir == 0 and 1 or -1 end
  local speed = math.abs(s.velocity)
  local pace = 0.36
  if speed > 2900 then pace = 0.16 elseif speed < 1500 then pace = 0.5 end
  local target = want * pace * (0.85 + 0.3 * p.skill)
  -- keeping up with the player, the better cooks the closer
  if lead and want ~= 0 and speed <= 2900 and self.leadOmega and self.leadOmega * want > 0 then
    target = target + (self.leadOmega - target) * p.skill * 0.8
  end
  p.speed = p.speed + (target - p.speed) * 0.25
  local angle = p.angle + p.speed
  if lead then
    local d = math.atan2(lead[2] - Stir.CENTER_Y, lead[1] - Stir.CENTER_X) - angle
    d = (d + math.pi) % (2 * math.pi) - math.pi
    angle = angle + d * 0.2 * p.skill
  end
  local x0, y0 = p.x, p.y
  p.angle = angle
  p.x = Stir.CENTER_X + math.cos(angle) * p.radius
  p.y = Stir.CENTER_Y + math.sin(angle) * p.radius
  return Stir.arc(x0, y0, p.x, p.y)
end

function Cook:finish()
  self.game.stack:pop()
  if self.opts.onDone then self.opts.onDone(self.made) end
end

-- The Bag's Berries, then the stir.
function Cook:chooseBerry()
  local game = self.game
  local berries = P.berries(game.data, game.save)
  if #berries == 0 then
    self.message, self.mode = line(game, 25) or "There isn't a Berry to cook.", "closing"
    return
  end
  if P.empty(game.save) <= 0 then
    self.message, self.mode = line(game, 24) or "The Poffin Case is full.", "closing"
    return
  end
  local rows = {}
  for _, b in ipairs(berries) do
    local def = game.data.items[b.item]
    rows[#rows + 1] = { label = ("%s x%d"):format(def and def.name or ("BERRY " .. b.item), b.count),
      onSelect = function() self:start(b.item) end }
  end
  self.message = line(game, 23)
  game.stack:push(require("src.ui.Menu").new(game, rows, {
    cancelable = true, maxVisible = math.min(#rows, 7),
    onCancel = function() self:finish() end,
  }))
end

function Cook:start(item)
  local game = self.game
  require("src.inventory.Bag").remove(game.save, item, 1)
  local def = game.data.items[item]
  self.berry = item
  self.message = fill(game, line(game, 1), { def and def.name or "Berry" })
  if self.group > 1 then self:newPartners(item) end
  self.lead = { Stir.CENTER_X, Stir.CENTER_Y }
  self.stir = Stir.new()
  self.mode = "stir"
  self.acc = 0
  self.fingerAngle = -math.pi / 2
  self.fingerSpeed = 0
  self.finger = nil
end

function Cook:update(dt)
  local input = self.game.input
  if self.mode == "choose" then
    self.mode = "waiting"
    return self:chooseBerry()
  end
  if self.mode == "closing" or self.mode == "result" then
    if input:wasPressed("a") or input:wasPressed("b") then
      if self.mode == "closing" then return self:finish() end
      return self:afterResult()
    end
    return
  end
  if self.mode ~= "stir" then return end
  self.acc = self.acc + (dt or 1 / 60) * 30
  while self.acc >= 1 and not self.stir.done do
    self.acc = self.acc - 1
    self:frame(input)
  end
  if self.stir.done then self:result() end
end

-- One 30 Hz frame of finger then batter.
function Cook:frame(input)
  local s = self.stir
  local arcIn, rawArc = 0, 0
  if self.touch then
    local t = self.touch
    if t.prevX then
      rawArc = Stir.arc(t.prevX, t.prevY, t.x, t.y)
      arcIn = Stir.weigh(s, rawArc, Stir.zone(s, t.x, t.y))
    end
    t.prevX, t.prevY = t.x, t.y
    self.lead = { t.x, t.y }
  else
    local cw, ccw = input:isDown("right"), input:isDown("left")
    if cw or ccw then
      local target = cw and 1 or -1
      if self.fingerSpeed * target < 0 then self.fingerSpeed = 0 end
      self.fingerSpeed = math.max(-0.8, math.min(0.8, self.fingerSpeed + target * 0.012))
      local r = Cook.FINGER_RADIUS
      local x0 = Stir.CENTER_X + math.cos(self.fingerAngle) * r
      local y0 = Stir.CENTER_Y + math.sin(self.fingerAngle) * r
      self.fingerAngle = self.fingerAngle + self.fingerSpeed
      local x1 = Stir.CENTER_X + math.cos(self.fingerAngle) * r
      local y1 = Stir.CENTER_Y + math.sin(self.fingerAngle) * r
      rawArc = Stir.arc(x0, y0, x1, y1)
      arcIn = Stir.weigh(s, rawArc, Stir.zone(s, x1, y1))
      self.finger = { x1, y1 }
      self.lead = { x1, y1 }
    else
      self.fingerSpeed, self.finger = 0, nil
    end
  end
  if self.partners and #self.partners > 0 then
    -- ov83_0223F900: every cook's weighted arc, summed, over the cooks
    local lead = self.lead
    local la = math.atan2(lead[2] - Stir.CENTER_Y, lead[1] - Stir.CENTER_X)
    if self.leadAngle and (self.touch or self.finger) then
      self.leadOmega = (la - self.leadAngle + math.pi) % (2 * math.pi) - math.pi
    else
      self.leadOmega = nil
    end
    self.leadAngle = la
    local cooks ={ { x = lead[1], y = lead[2], arc = rawArc, zone = Stir.zone(s, lead[1], lead[2]) } }
    local sum = arcIn
    for _, p in ipairs(self.partners) do
      local arc = self:partnerFrame(p, s, (self.touch or self.finger) and lead or nil)
      local zone = Stir.zone(s, p.x, p.y)
      sum = sum + Stir.weigh(s, arc, zone)
      cooks[#cooks + 1] = { x = p.x, y = p.y, arc = arc, zone = zone }
    end
    local n = #cooks
    Stir.step(s, sum >= 0 and math.floor(sum / n) or -math.floor(-sum / n), cooks)
  else
    Stir.step(s, arcIn)
  end
  local game = self.game
  if s.event == "overflow" then self.message = line(game, 4)
  elseif s.event == "warn" then self.message = line(game, 3)
  elseif s.event == "burn" then self.message = line(game, 5)
  elseif math.abs(s.velocity) >= 3200 and s.phase < 3 then self.message = line(game, 6)
  elseif math.abs(s.velocity) <= 910 and s.phase == 3 then self.message = line(game, 7)
  end
end

function Cook:result()
  local game = self.game
  local f = game.data.gen4_berry_flavors[self.berry]
  local berries = { { item = self.berry, flavors = f.flavors, smoothness = f.smoothness } }
  for _, p in ipairs(self.partners or {}) do
    local pf = game.data.gen4_berry_flavors[p.item]
    if pf then berries[#berries + 1] = { item = p.item, flavors = pf.flavors, smoothness = pf.smoothness } end
  end
  local cooks = #berries
  local poffin = P.cook(berries, self.stir.frames, self.stir.burns, self.stir.spills,
    Stir.syncBonus(self.stir, cooks))
  -- one Poffin for each cook, as far as the case has room
  local given = 0
  for _ = 1, cooks do
    local copy = { type = poffin.type, smoothness = poffin.smoothness, flavors = {} }
    for i = 1, 5 do copy.flavors[i] = poffin.flavors[i] end
    if P.add(game.save, copy) then given = given + 1 end
  end
  self.made = self.made + given
  self.poffin = poffin
  local frames = self.stir.frames
  local mins = math.floor(frames / 1800)
  local secs = math.floor((frames - mins * 1800) / 30)
  local cs = math.floor(100 * (frames - mins * 1800 - secs * 30) / 30)
  self.lines = {
    line(game, 9) or "RESULTS",
    (line(game, 10) or "Time") .. "  " .. ("%d:%02d:%02d"):format(mins, secs, cs),
    (line(game, 12) or "Overflowed") .. "  " .. fill(game, line(game, self.stir.spills == 1 and 13 or 15), { self.stir.spills }),
    (line(game, 14) or "Burned") .. "  " .. fill(game, line(game, self.stir.burns == 1 and 13 or 15), { self.stir.burns }),
    line(game, 16) or "Poffins made:",
    fill(game, line(game, 17), { nil, P.level(poffin), given, P.name(game.data, poffin) }),
  }
  self.mode = "result"
  local player = game.save.player and game.save.player.name or ""
  self.message = fill(game, line(game, 20), { player, nil, nil, P.name(game.data, poffin) })
end

-- "Would you like to keep cooking Poffins?"
function Cook:afterResult()
  local game = self.game
  self.mode = "waiting"
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, line(game, 21) or Strings("Would you like to keep cooking\nPoffins?"), nil, {
    choice = function(yes)
      if yes then self.mode = "choose" else self:finish() end
    end,
  }))
end

function Cook:touchpressed(id, px, py)
  local rect = require("src.render.Renderer").uiPresentation
  if not rect or self.mode ~= "stir" then return false end
  local x, y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY
  self.touch = { id = id, x = x, y = y }
  return true
end

function Cook:touchmoved(id, px, py)
  local rect = require("src.render.Renderer").uiPresentation
  if not (rect and self.touch and self.touch.id == id) then return false end
  self.touch.x, self.touch.y = (px - rect.x) / rect.scaleX, (py - rect.y) / rect.scaleY
  return true
end

function Cook:touchreleased(id)
  if self.touch and self.touch.id == id then self.touch = nil end
  return true
end

-- the cache's poffin pictures
function Cook:art(key)
  local index = self.game.data and self.game.data.gen4_poffin_art
  local rec = index and index[key]
  if not rec then return nil end
  self.images = self.images or {}
  if self.images[rec.path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, rec.path)
    self.images[rec.path] = ok and img or false
  end
  return self.images[rec.path] or nil, rec
end

function Cook:sprite(key, x, y)
  local img, rec = self:art(key)
  if img then love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0)) end
end

-- ov83_0223FC58: how far the batter has gone over into the next one (31 = not
-- at all), from the phase's frames and turns left
local function fade(s)
  local a, b = 31, 31
  local framesLeft = 600 - s.phaseFrames
  if framesLeft <= 60 then a = math.floor(31 * framesLeft / 60) end
  local turnsLeft = 16 - s.turns
  if turnsLeft <= 5 then b = math.floor(31 * turnsLeft / 5) end
  return math.max(0, math.min(a, b)) / 31
end

-- the pot, in ov83_0223E368's order
function Cook:drawPot(s)
  local g = love.graphics
  local phase = math.max(1, math.min(3, s.phase)) - 1
  g.setColor(1, 1, 1, 1)
  local cloth = self:art("cook_cloth")
  if cloth then g.draw(cloth, 0, 0) end
  local flame = self:art("cook_flame_" .. phase)
  if flame then g.draw(flame, 0, 0) end
  -- the batter: this phase's over the next one, fading out into it
  local angle = (s.angle % 65536) / 65536 * math.pi * 2
  local speed = math.abs(s.velocity)
  local scale = 1 + 0.25 * math.max(0, speed - 910) / (3640 - 910)
  local under = phase < 2 and self:art("cook_batter_" .. (phase + 1))
  if under then g.draw(under, 128, 96, angle, scale, scale, 64, 64) end
  local top = self:art("cook_batter_" .. phase)
  if top then
    g.setColor(1, 1, 1, phase < 2 and fade(s) or 1)
    g.draw(top, 128, 96, angle, scale, scale, 64, 64)
    g.setColor(1, 1, 1, 1)
  end
  local pot = self:art("cook_pot")
  if pot then g.draw(pot, 0, 0) end
  -- the arrow, while the batter turns the wrong way (ov83_0223C558)
  local spin = s.velocity >= 0 and 0 or 1
  if s.velocity ~= 0 and spin ~= s.dir then self:sprite("cook_arrow_" .. s.dir, 128, 96) end
  -- the spoon where the finger is
  local finger = self.touch and { self.touch.x, self.touch.y } or self.finger
  for _, p in ipairs(self.partners or {}) do self:sprite("cook_spoon", p.x, p.y) end
  if finger then self:sprite("cook_spoon", finger[1], finger[2]) end
  -- the sparkle on the frames the group stirs in sync
  if s.sparkle then
    self.sparkleFrame = ((self.sparkleFrame or 0) + 1) % 32
    local at = self.lead or { 128, 96 }
    self:sprite("cook_sparkle_" .. math.floor(self.sparkleFrame / 4), at[1], at[2])
  end
end

function Cook:drawTopScreen()
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  if not ok then return end
  local mode = SS.mode(self.game)
  self.topShown = (mode == "display" or mode == "inset") and not SS.stowed(self.game)
  if self.topShown then
    SS.draw(self.game, function()
      local g = love.graphics
      local img = self:art(self.group > 1 and "cook_top_multi" or "cook_top_single")
      if img then g.draw(img, 0, 0) end
      if self.group > 1 then
        -- the plates, two by two: names centred at x 80 / 176, y 112 / 152
        local names = { self.game.save.player and self.game.save.player.name or "" }
        for _, p in ipairs(self.partners or {}) do names[#names + 1] = p.name end
        for i, name in ipairs(names) do
          local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
          -- the cook's plate at tile (5 + col x 12, 13 + row x 5) (ov83_0223DFAC)
          local plate = self:art(("cook_plate_%d_%d"):format(col, row))
          g.setColor(1, 1, 1, 1)
          if plate then g.draw(plate, 40 + col * 96, 104 + row * 40) end
          g.setColor(0.25, 0.25, 0.25, 1)
          Font.draw(name, (col == 0 and 80 or 176) - math.floor(Font.width(name) / 2), row == 0 and 112 or 152)
        end
        g.setColor(1, 1, 1, 1)
      end
      -- the messages are the top screen's: a message box at tile (4, 19),
      -- 23 x 4 (ov83_0223E09C)
      if self.message then self:drawMessage(3, 18, 25, 6, 32) end
    end)
  end
end

function Cook:drawMessage(tx, ty, tw, th, x)
  local g = love.graphics
  if Font.hasDialogueFrame and Font.hasDialogueFrame() then Font.drawDialogueBox(tx, ty, tw, th)
  else Font.drawBox(tx, ty, tw, th) end
  g.setColor(0, 0, 0, 1)
  local y = 152
  for l in (tostring(self.message) .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(l, x, y); y = y + 16
  end
  g.setColor(1, 1, 1, 1)
end

function Cook:draw()
  local g = love.graphics
  g.setColor(0.98, 0.94, 0.86, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  local hasArt = self:art("cook_pot") ~= nil
  if hasArt then self:drawTopScreen() end
  if self.mode == "result" and self.lines then
    Font.drawBox(2, 1, 28, 14)
    g.setColor(0, 0, 0, 1)
    for i, l in ipairs(self.lines) do Font.draw(l, 32, 16 + (i - 1) * 16) end
  elseif self.stir and hasArt then
    self:drawPot(self.stir)
  elseif self.stir then
    local s = self.stir
    -- the pot, the batter thickening phase by phase, and its swirl
    g.setColor(0.35, 0.33, 0.36, 1)
    g.circle("fill", Stir.CENTER_X, Stir.CENTER_Y, 74)
    local batter = ({ { 0.98, 0.9, 0.7 }, { 0.92, 0.74, 0.46 }, { 0.78, 0.52, 0.3 } })[s.phase]
    g.setColor(batter[1], batter[2], batter[3], 1)
    g.circle("fill", Stir.CENTER_X, Stir.CENTER_Y, 68)
    local a = (s.angle % 65536) / 65536 * math.pi * 2
    g.setColor(1, 1, 1, 0.8)
    for k = 0, 2 do
      local ang = a + k * math.pi * 2 / 3
      g.circle("fill", Stir.CENTER_X + math.cos(ang) * 44, Stir.CENTER_Y + math.sin(ang) * 44, 6)
    end
    -- the direction to stir
    g.setColor(0.85, 0.2, 0.2, 1)
    Font.draw(s.dir == 0 and ">>" or "<<", 120, 8)
    local finger = self.touch and { self.touch.x, self.touch.y } or self.finger
    if finger then
      g.setColor(0.2, 0.4, 0.9, 1)
      g.circle("line", finger[1], finger[2], 6)
    end
    -- the phase clock
    g.setColor(0.2, 0.2, 0.2, 1)
    g.rectangle("fill", 8, 8, 8, 160)
    g.setColor(0.4, 0.8, 0.4, 1)
    local left = 1 - math.min(1, math.max(s.phaseFrames / 600, s.turns / 16))
    g.rectangle("fill", 8, 8 + 160 * (1 - left), 8, 160 * left)
  end
  -- with no top screen showing, the messages come down onto this one
  if self.message and not (hasArt and self.topShown) then self:drawMessage(0, 18, 32, 6, 8) end
  g.setColor(1, 1, 1, 1)
end

return Cook
