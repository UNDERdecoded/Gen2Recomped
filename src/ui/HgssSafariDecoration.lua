-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S SAFARI ZONE DECORATION APP -- ScrCmd_717
-- (sub_02097720 -> SafariDecoration_LaunchApp; pokeheartgold
-- asm/overlay_108_021E8850.s, undecompiled), run by std_safari_place_object
-- (scr_seq_0262 000) after "Place an object?". The rules are
-- src/world/HgssSafariPlace.lua; this is the screen.
--
-- READ FROM THE ASM:
--   * ov108_021E8968: the list (ov108_021EA63C, Baoba's unlocked groups), six
--     a page, the cursor restored from the field's remembered byte
--     (fieldSystem + 0x111, RAM only -- kept on `game`, not the save: page = n / 6, position = n % 6, page 0 when past
--     the last), the area's free count (30 - its objects), the result 255.
--   * THE HITBOXES (ov108_021EABF0): the six objects 2 x 3 at y 40..71,
--     80..111, 120..151, x 0..127 / 128..255; Return y 168..191 x 192..255;
--     the page arrows y 164..187 at x 9..55 / 49..95; the page "n/m"
--     (msg_0430 12).
--   * A on an object (ov108_021E9528 -> ov108_021EA52C): a refusal is shown
--     (msg 4 + n - 1, SE 0x5F3) -- "Cannot place any more." with no room,
--     "Cannot place on land." / "...on the waterside." for the fountain on
--     foot / a land object from the water, "No open spaces left." with no
--     footprint ahead; otherwise "Place the X?" (msg 0) with Yes / No, and
--     Yes commits it (ov108_021E8C64) and ends the app with its id.
--   * Return / B (ov108_021E9528 >= 6): the app ends, result 255.
--   * the top screen: the object's name (msg 13 = msg 14 + id), its line
--     (msg 38 + id) and "There are n left to place." (msg 2).
--
--   * THE D-PAD (ov108_021E95AC): position p = col + 2 row, row 3 the
--     Return row. B -> Return; A -> the entry. RIGHT: nothing on row 3; from
--     col 1 the next page when there is one (row < 3), the position kept
--     (SE 0x5E1 with the arrow's press, ov108_021EA584); from col 0, col 1.
--     LEFT the mirror. UP / DOWN: row (r + 3) % 4 / (r + 1) % 4. Any other
--     move SE 0x5E5. A position past the page's last entry stays reachable
--     and A there does nothing (ov108_021E9528's count test).
--   * THE TOUCH SCREEN (ov108_021E96FC, hitboxes ov108_021EABF0): a slot ->
--     the position, then A on it; 6 Return; 7 the left arrow (y 164..187 x
--     9..54), 8 the right one (x 49..94), each only when there is a page that
--     way.
--   * THE SCREENS (Gen4HgssSafariAppArt): the top is the main engine (POWCNT
--     bit 15 set) -- BG3 member 2's preview frame, BG2 member 3's text bar,
--     BG0 the 3D object (ov108_021E9230: Camera_Init_FromTargetDistanceAndAngle
--     at the origin, distance 0x15B000 = 347, angle ov108_021EA9C4 x =
--     0xDD62 (-48.7 deg), perspective 0x5C1 (half fov 8.09 deg), clip
--     100..1200; the model at the origin, identity rotation, scale 1
--     (ov108_021E9144), its build-model animations playing (ov108_021E9210));
--     the bottom is sub -- BG3 member 6's six slots, each entry's plate from
--     member 8 (the plates sit 40 px above their slots), the confirm page
--     member 7. Windows (ov108_021EAC18): the header (2, 1) 28 x 2 on sub
--     BG0, the refusal (2, 21) 27 x 2, Return (25, 21) 6 x 3, the page "n/m"
--     (13, 21) 6 x 2, the chosen name on the confirm page (9, 8) 14 x 2, the
--     description (2, 18) 28 x 6 on main BG1. The cursor is OBJ sequence 0
--     (128 x 32) at the slot, 1 (64 x 32) on Return; the arrows 5..10; the
--     Return button sequence 2. Yes / No: YesNoPrompt at tile (26, 4) on sub
--     BG0 (ov108_021E9488). The ink: LoadFontPal1.
--   * THE MUSIC: Sound_SetSceneAndPlayBGM(0x43, 0, 0), the field's BGM kept.
--
--   * THE LIST (ov108_021EA040): each entry's plate copied from member 8 at
--     source x 16 tiles (the grey one) when ov108_021EA52C refuses it, else
--     0, to (16 col, 5 (row + 1)) tiles on sub BG2; its name (msg 14 + id,
--     font 4) centred in a 112 px window in MAKE_TEXT_COLOR(1, 2, 0); the
--     page "n/m" (msg 12) in (3, 4, 0). The arrows: left sequence 7 (off) on
--     the first page else 5, right 10 on the last else 8; a turn plays 6 / 9
--     (ov108_021EA584: 3 side + 6).
--   * THE MESSAGES (ov108_021EA418, msg 4 + n; the confirm's msg 0): window
--     (2, 21) 27 x 2 on sub BG0 inside DrawFrameAndWindow2 -- the frame the
--     player chose on the Options screen (LoadUserFrameGfx2 with
--     Options_GetFrame, ov108_021E8968) -- in (1, 2, 15).
--
-- INFERRED: the name window's exact place on its plate (centred on the
-- plate here; the window templates for windows 6..11 are not transcribed).

local S = require("src.ui.HgssSafariScreen")

local D = {}
D.__index = D
D.isOpaque = true

D.BANK = 430
D.PER_PAGE = 6
D.RETURN = 6

function D:uiSize() return S.W, S.H end
function D:wantsFillScale() return true end

function D.new(game, args, onDone)
  local Place = require("src.world.HgssSafariPlace")
  local save = game.save
  local list = Place.objectList(save)
  local pages = math.max(1, math.ceil(#list / D.PER_PAGE))
  -- fieldSystem + 0x111
  local remembered = tonumber(game.hgssSafariDecorationCursor) or 0
  local page, pos = math.floor(remembered / 6), remembered % 6
  if page >= pages then page = 0 end
  local self = setmetatable({
    game = game, args = args or { fits = {} }, onDone = onDone, list = list,
    pages = pages, page = page, pos = pos, result = 255,
    state = "fadein", t = 0, yes = 1,
  }, D)
  if self:entry() == nil and self.pos < D.RETURN then self.pos = 0 end
  return self
end

function D:text(n, fallback, buffers) return S.line(self.game, D.BANK, n, fallback, buffers) end

function D:entry(i)
  i = i or self.pos
  if i >= D.RETURN then return nil end
  return self.list[self.page * D.PER_PAGE + i + 1]
end

function D:name(entry)
  return self:text(14 + entry.id, require("src.world.HgssSafariObjects").objectName(self.game.data, self.game, entry.id))
end

function D:refusalOf(entry)
  return require("src.world.HgssSafariPlace").refusal(self.game.save, self.args, entry)
end

function D:finish()
  if self.finished then return end
  self.finished = true
  -- ov108_021E8A88: the cursor kept (page * 6 + position, position < 6)
  local pos = math.min(5, self.pos)
  self.game.hgssSafariDecorationCursor = self.page * 6 + pos
  local stack = self.game.stack
  if stack and stack.top and stack:top() == self then stack:pop() end
  if self.onDone then self.onDone(self.result) end
end

function D:touchpressed(_, px, py)
  local x, y = S.point(self.game, px, py)
  if not x then return false end
  self.tap = { x = x, y = y }
  return true
end
function D:mousepressed(x, y, button)
  if button == 1 then return self:touchpressed("mouse", x, y) end
end

-- ov108_021EABF0: { top, bottom, left, right }
D.RECTS = {
  { 40, 72, 0, 128 }, { 40, 72, 128, 0 }, { 80, 112, 0, 128 }, { 80, 112, 128, 0 },
  { 120, 152, 0, 128 }, { 120, 152, 128, 0 },
  { 168, 192, 192, 0 }, { 164, 188, 9, 55 }, { 164, 188, 49, 95 },
}
D.YESNO_TILE = { 26, 4 }
-- ov108_021E9230's camera
D.CAMERA = { distance = 347, pitch = -48.69, halfFov = 8.09, near = 100, far = 1200 }

local ROWS = { 40, 80, 120 }
local function slotRect(i)
  local col, row = i % 2, math.floor(i / 2)
  return col * 128, ROWS[row + 1], 128, 32
end
local RETURN_RECT = { 192, 168, 64, 24 }
local PREV_RECT, NEXT_RECT = { 9, 164, 40, 24 }, { 52, 164, 40, 24 }
local function hit(r, x, y) return x >= r[1] and y >= r[2] and x < r[1] + r[3] and y < r[2] + r[4] end

function D:turn(step)
  local p = self.page + step
  if p < 0 or p >= self.pages then return false end
  self.page = p
  S.se(self.game, "page")
  if not self:entry() then
    local n = #self.list - self.page * D.PER_PAGE
    self.pos = math.max(0, math.min(self.pos, n - 1))
  end
  return true
end

-- ov108_021E9528
function D:choose()
  local game = self.game
  if self.pos >= D.RETURN then
    self.pos = D.RETURN
    S.se(game, "select")
    self.state, self.t = "fadeout", 0
    return
  end
  local e = self:entry()
  if not e then return end
  local why = self:refusalOf(e)
  if why then
    S.se(game, "refuse")
    self.state, self.refusal = "refused", why
    return
  end
  S.se(game, "select")
  self.state, self.yes = "confirm", 1
end

function D:update()
  self.t = self.t + 1
  local game = self.game
  local tap = self.tap
  self.tap = nil
  local A, B = S.pressed(game, "a"), S.pressed(game, "b")
  local s = self.state
  if s == "fadein" then
    if self.t >= S.FADE then self.state, self.t = "list", 0 end
  elseif s == "list" then
    -- ov108_021E96FC
    local hitAt = tap and S.hitbox(D.RECTS, tap.x, tap.y)
    if hitAt == 7 then
      if self.page > 0 then self.page = self.page - 1; S.se(game, "page"); self.arrowPress = { 0, self.t } end
    elseif hitAt == 8 then
      if self.page < self.pages - 1 then self.page = self.page + 1; S.se(game, "page"); self.arrowPress = { 1, self.t } end
    elseif hitAt then
      if hitAt ~= self.pos then self.pos = hitAt end
      self:choose()
    elseif B then
      self.pos = D.RETURN
      self:choose()
    elseif A then
      self:choose()
    else
      -- ov108_021E95AC
      local pos = self.pos
      local col, row = pos % 2, math.floor(pos / 2)
      local turned
      if S.pressed(game, "right") then
        if row == 3 then return end
        if col == 1 then
          if self.page < self.pages - 1 and row < 3 then self.page = self.page + 1; turned = 1 else return end
        else col = col + 1 end
      elseif S.pressed(game, "left") then
        if row == 3 then return end
        if col == 0 then
          if self.page > 0 and row < 3 then self.page = self.page - 1; turned = 0 else return end
        else col = col - 1 end
      elseif S.pressed(game, "up") then row = (row + 3) % 4
      elseif S.pressed(game, "down") then row = (row + 1) % 4
      else return end
      self.pos = col + row * 2
      if turned then
        S.se(game, "page"); self.arrowPress = { turned, self.t }
      else
        S.se(game, "cursor")
      end
    end
  elseif s == "refused" then
    if A or B or tap then self.state = "list" end
  elseif s == "confirm" then
    if tap then
      if S.art(game) then
        local hitYes = S.yesNoHit(tap.x, tap.y, D.YESNO_TILE[1], D.YESNO_TILE[2])
        if hitYes then self.yes = hitYes; A = true end
      else
        for i = 1, 2 do
          if hit({ 184, 88 + (i - 1) * 26, 64, 22 }, tap.x, tap.y) then self.yes = i; A = true end
        end
      end
    end
    if S.pressed(game, "up") or S.pressed(game, "down") then self.yes = 3 - self.yes; S.se(game, "cursor") end
    if A and self.yes == 1 then
      S.se(game, "select")
      local e = self:entry()
      if e and require("src.world.HgssSafariPlace").commit(game.save, self.args, e) then
        self.result = e.id
      end
      self.state, self.t = "fadeout", 0
    elseif A or B then
      S.se(game, "select")
      self.state = "list"
    end
  elseif s == "fadeout" then
    if self.t >= S.FADE then self:finish() end
  end
end

-- ----------------------------------------------------------------- drawing

local TYPE_INK = { [0] = { 144, 144, 152 }, { 112, 184, 72 }, { 40, 128, 64 }, { 152, 120, 88 }, { 64, 136, 216 } }

function D:veilAmount()
  if self.state == "fadein" then return 1 - self.t / S.FADE end
  if self.state == "fadeout" then return self.t / S.FADE end
  return 0
end

function D:drawTop()
  S.backdrop({ 200, 224, 248 }, { 128, 176, 224 })
  local g = love.graphics
  local e = self:entry()
  S.box(16, 10, S.W - 32, 26, { 248, 248, 248 }, { 88, 104, 136 })
  local left = math.max(0, require("src.world.HgssSafariPlace").remaining(self.game.save, self.args))
  local line = self:text(2, ("There are %d left to place."):format(left), { left })
  S.centred(line, 16, S.W - 32, 15)
  if e then
    -- the stand-in for the turning model: a card in the object's type colour
    local c = require("src.world.HgssSafariObjects").config(e.id)
    S.color(TYPE_INK[c.type] or TYPE_INK[0])
    g.rectangle("fill", 104, 46, 48, 48, 6, 6)
    S.color({ 248, 248, 248 })
    g.rectangle("line", 104.5, 46.5, 47, 47, 6, 6)
    S.centred(("%dx%d"):format(c.width, c.height), 104, 48, 62, { 248, 248, 248 }, { 40, 40, 40 })
    S.centred(self:name(e), 0, S.W, 100)
    S.box(8, 120, S.W - 16, 64, { 248, 248, 248 }, { 88, 104, 136 })
    S.lines(self:text(38 + e.id, ""), 14, 124)
  else
    S.centred(self:text(8, "Return"), 0, S.W, 100)
  end
  g.setColor(1, 1, 1, 1)
end

function D:drawBottom(single)
  S.backdrop({ 232, 240, 248 }, { 176, 204, 232 })
  local g = love.graphics
  if single then
    local e = self:entry()
    S.box(4, 2, S.W - 8, 34, { 248, 248, 248 }, { 88, 104, 136 })
    if e then
      S.text(self:name(e), 10, 4)
      local left = math.max(0, require("src.world.HgssSafariPlace").remaining(self.game.save, self.args))
      S.text(("%d/30"):format(30 - left), 210, 4)
      local first = (self:text(38 + e.id, "") .. "\n"):match("(.-)\n") or ""
      S.text(first, 10, 19, nil, false)
    end
  end
  for i = 0, 5 do
    local e = self:entry(i)
    if e then
      local x, y, w, h = slotRect(i)
      local sel = self.pos == i
      local refused = self:refusalOf(e) ~= nil
      S.box(x + 4, y, w - 8, h, sel and { 255, 236, 168 } or { 248, 248, 248 },
            sel and { 224, 120, 40 } or { 96, 120, 160 })
      local c = require("src.world.HgssSafariObjects").config(e.id)
      S.color(TYPE_INK[c.type] or TYPE_INK[0]); g.rectangle("fill", x + 10, y + 10, 10, 12)
      S.text(self:name(e), x + 26, y + 8, refused and { 160, 160, 168 } or nil)
    end
  end
  -- the page and its arrows
  S.box(PREV_RECT[1], PREV_RECT[2], PREV_RECT[3], PREV_RECT[4], self.page > 0 and { 240, 240, 240 } or { 200, 200, 200 })
  local function arrow(r, dir)
    local cx, cy = r[1] + r[3] / 2, r[2] + r[4] / 2
    S.color({ 82, 82, 90 })
    g.polygon("fill", cx - 5 * dir, cy - 6, cx - 5 * dir, cy + 6, cx + 5 * dir, cy)
  end
  arrow(PREV_RECT, -1)
  S.box(NEXT_RECT[1], NEXT_RECT[2], NEXT_RECT[3], NEXT_RECT[4], self.page < self.pages - 1 and { 240, 240, 240 } or { 200, 200, 200 })
  arrow(NEXT_RECT, 1)
  S.text(("%d/%d"):format(self.page + 1, self.pages), 104, 170)
  S.box(RETURN_RECT[1], RETURN_RECT[2], RETURN_RECT[3], RETURN_RECT[4],
        self.pos >= D.RETURN and { 255, 236, 168 } or { 240, 240, 240 })
  S.centred(self:text(8, "Return"), RETURN_RECT[1], RETURN_RECT[3], RETURN_RECT[2] + 5)
  if self.state == "refused" then
    S.message(self:text(self.refusal, "Cannot place it."), 120)
  elseif self.state == "confirm" then
    local e = self:entry()
    local name = e and self:name(e) or ""
    local line = self:text(0, ("Place the %s?"):format(name), { name })
    S.message(line, 120)
    S.yesNo(self.yes, 64)
  end
  g.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------- the cartridge's art

-- the object's build model, the way ov108_021E9230 / 9144 show it: drawn
-- through the field's own Gen4Ground (its building set, its animations)
function D:preview()
  local G = package.loaded["src.core.Game"]
  local ow = (self.game and self.game.overworld) or (G and G.overworld)
  local ground = ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground
  local e = self:entry()
  if not (ground and e) then return nil end
  local Props = require("src.world.HgssSafariProps")
  local save = self.game.save or {}
  local girl = (save.player or {}).gender == "girl"
  local index = Props.buildModel(e.id, girl)
  local okB, model = pcall(ground.building, ground, index)
  if not (okB and model) then return nil end
  local Gen4Model = require("src.render.Gen4Model")
  if not self.colour then
    self.colour, self.depth = Gen4Model.newTarget(S.W, S.H)
    if not self.colour then return nil end
  end
  local cam = D.CAMERA
  local rad = math.pi / 180
  local projection = Gen4Model.perspective(cam.halfFov * 2 * rad, S.W / S.H, cam.near, cam.far)
  local view = Gen4Model.orbit({ 0, 0, 0 }, cam.distance, 0, cam.pitch * rad)
  local flipY = { 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
  local vp = Gen4Model.multiply(flipY, Gen4Model.multiply(projection, view))
  -- ov108_021E9210: the animations step one frame a field frame
  local okM, mats = pcall(ground.propMaterials, ground, { model = index }, self.t)
  local g = love.graphics
  g.push("all")
  g.setCanvas({ self.colour, depthstencil = self.depth })
  g.clear(0, 0, 0, 0, true, true)
  pcall(model.draw, model, vp, nil, okM and mats or nil)
  g.pop()
  return self.colour
end

function D:drawTopArt(art)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  S.draw(art.topFrame, 0, 0, 0, 0, 256, 192)
  local canvas = self:preview()
  if canvas then g.setColor(1, 1, 1, 1); g.draw(canvas, 0, 0) end
  S.draw(art.topBar, 0, 0, 0, 0, 256, 192)
  local all = S.art(self.game) or {}
  local fi = all.fontInk or {}
  local e = self:entry()
  if e then
    -- the description, window (2, 18) 28 x 6 on main BG1
    S.lines(self:text(38 + e.id, ""), 16, 18 * 8, fi[1] or S.INK, fi[2] or S.SHADOW)
  end
  g.setColor(1, 1, 1, 1)
end

function D:drawBottomArt(art, single)
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  local all = S.art(self.game) or {}
  local fi = all.fontInk or {}
  local i1, i2 = fi[1] or S.INK, fi[2] or S.SHADOW
  local s = self.state
  local confirm = s == "confirm"
  S.draw(confirm and art.confirm or art.list, 0, 0, 0, 0, 256, 192)
  -- the header, window (2, 1) 28 x 2: the count left to place
  local left = math.max(0, require("src.world.HgssSafariPlace").remaining(self.game.save, self.args))
  S.text(self:text(2, ("There are %d left to place."):format(left), { left }), 16, 8 + 2, i1, i2)
  if confirm then
    local e = self:entry()
    if e then S.centred(self:name(e), 9 * 8, 14 * 8, 8 * 8 + 2, i1, i2) end
  else
    for i = 0, 5 do
      local e = self:entry(i)
      if e then
        local col, row = i % 2, math.floor(i / 2)
        -- member 8's plates sit 40 px above their slots; the grey one for a
        -- refused entry
        local refused = self:refusalOf(e) ~= nil
        local sx = refused and 128 or 0
        S.draw(art.plates, col * 128, 40 + row * 40, sx, 0, 128, 32)
        S.centred(self:name(e), col * 128, 128, 40 + row * 40 + 8, i1, i2)
      end
    end
    -- the cursor: sequence 0 on a slot, 1 on Return
    if self.pos >= D.RETURN then S.sprite(art.sprites, 1, self.t, 224, 180)
    else S.sprite(art.sprites, 0, self.t, (self.pos % 2) * 128, 40 + math.floor(self.pos / 2) * 40) end
  end
  -- Return, the page and its arrows
  S.sprite(art.sprites, 2, 0, 224, 180)
  S.centred(self:text(8, "Return"), 25 * 8, 48, 21 * 8 + 4, i1, i2)
  if not confirm then
    local fc = all.fontColours or {}
    S.centred(self:text(12, ("%d/%d"):format(self.page + 1, self.pages), { self.page + 1, self.pages }),
              13 * 8, 48, 21 * 8 + 2, fc[3] or i1, fc[4] or i2)
    local press = self.arrowPress and (self.t - self.arrowPress[2]) < 8 and self.arrowPress[1] or nil
    if self.page == 0 then S.sprite(art.sprites, 7, 0, 32, 176)
    else S.sprite(art.sprites, press == 0 and 6 or 5, 0, 32, 176) end
    if self.page >= self.pages - 1 then S.sprite(art.sprites, 10, 0, 72, 176)
    else S.sprite(art.sprites, press == 1 and 9 or 8, 0, 72, 176) end
  end
  if s == "refused" then
    S.userFrame(2, 21, 27, 2)
    S.text(self:text(self.refusal, "Cannot place it."), 16, 21 * 8, i1, i2)
  elseif confirm then
    local e = self:entry()
    local name = e and self:name(e) or ""
    S.userFrame(2, 21, 27, 2)
    S.text(self:text(0, ("Place the %s?"):format(name), { name }), 16, 21 * 8, i1, i2)
    S.yesNoArt(all, self.yes, D.YESNO_TILE[1], D.YESNO_TILE[2])
  end
  if single and not confirm then
    local e = self:entry()
    if e then
      -- one screen: the top's description, its first line, over the header
      local first = (self:text(38 + e.id, "") .. "\n"):match("(.-)\n") or ""
      S.box(4, 2, S.W - 8, 34, { 248, 248, 248 }, { 88, 104, 136 })
      S.text(self:name(e) .. "  " .. ("%d/30"):format(30 - left), 10, 4, i1, i2)
      S.text(first, 10, 19, i1, i2)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function D:draw()
  local all = S.art(self.game)
  local art = all and all.decoration
  if art and art.list then
    S.present(self.game, function() self:drawTopArt(art) end,
              function(single) self:drawBottomArt(art, single) end, self:veilAmount())
    return
  end
  S.present(self.game, function() self:drawTop() end,
            function(single) self:drawBottom(single) end, self:veilAmount())
end


return D
